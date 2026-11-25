# SPDX-License-Identifier: GPL-3.0-or-later
"""Alpha-preserving raster compositor for the Qt Quick Software backend."""
from functools import partial

from PySide6.QtCore import Property, QRectF, QTimer, Signal
from PySide6.QtGui import QColor, QImage, QPainter, QPainterPath
from PySide6.QtQuick import QQuickItem, QQuickPaintedItem
from shiboken6 import isValid


def release_when_destroyed(obj):
    """PySide 6.12 keeps the Python object of a type the QML engine made (qmlRegisterType) after the engine destroyed
    it: the garbage collector never frees it, one per element of every window closed (Quotario P10c: 92 a window,
    more at each window, then QML errors or a crash in the next window of the same process). The kit cannot give that
    object back, but after the destruction it lets go of what the object holds (timers, watched items, images, models),
    so only the empty Python object stays. Not during the destruction: letting go there of what Qt is still destroying
    made the process fall (one run in two of the shell's tests); at the next turn of the events the window is gone.
    Called in the __init__ of every type registered in controls.py."""
    obj.destroyed.connect(partial(_release, obj.__dict__))


def _release(attributes, *_args):
    QTimer.singleShot(0, attributes.clear)


class RasterSurface(QQuickPaintedItem):
    """Capture only on content changes, preserving the live item's input tree.

    grabToImage ignores the source's own opacity. Its descendants retain their
    opacity and input geometry. No guessed background is painted at the corners.
    """
    sourceChanged = Signal()
    revisionChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        release_when_destroyed(self)
        self._source = None
        self._image = QImage()
        self._grab = None
        self._revision = 0
        self._watched = set()
        self._dirty = False
        self._timer = QTimer(self)
        self._timer.setSingleShot(True)
        self._timer.timeout.connect(self._capture)
        self.widthChanged.connect(self.invalidate)
        self.heightChanged.connect(self.invalidate)
        self.visibleChanged.connect(self.invalidate)
        self._window_connection = None
        self.windowChanged.connect(self._window_changed)

    def _window_changed(self, window):
        if self._window_connection:
            from PySide6.QtCore import QObject
            QObject.disconnect(self._window_connection)
        self._window_connection = window.visibleChanged.connect(self.invalidate) if window else None
        self.invalidate()

    @Property(QQuickItem, notify=sourceChanged)
    def source(self):
        return self._source

    @source.setter
    def source(self, value):
        self._source = value
        self.sourceChanged.emit()
        self.invalidate()

    @Property(int, notify=revisionChanged)
    def revision(self):
        return self._revision

    @Property(bool, notify=revisionChanged)
    def settled(self):
        return self._revision > 0 and not self._dirty and self._grab is None

    def invalidate(self, *args):
        if not isValid(self):
            return
        self._dirty = True
        self.revisionChanged.emit()
        if self._grab is None and not self._timer.isActive():
            self._timer.start(0)

    def _watch(self, item):
        if item not in self._watched:
            self._watched.add(item)
            meta = item.metaObject()
            signals = set()
            for index in range(meta.propertyCount()):
                prop = meta.property(index)
                if prop.hasNotifySignal():
                    name = bytes(prop.notifySignal().name()).decode()
                    if name not in signals:
                        signal = getattr(item, name, None)
                        if signal is not None:
                            signal.connect(lambda: self.invalidate())
                        signals.add(name)
            watched = self._watched     # not through self: after its destruction the surface holds nothing
            item.destroyed.connect(lambda: watched.discard(item))
        for child in item.childItems():
            self._watch(child)

    def _capture(self):
        source = self._source
        if (source is None or not self.window() or not self.window().isVisible() or not self.isVisible()
                or not source.isVisible() or source.width() <= 0 or source.height() <= 0):
            return
        revision_source = self.parentItem().property('revisionSource')
        if revision_source is None:
            self._watch(source)
        elif revision_source not in self._watched:
            self._watched.add(revision_source)
            revision_source.changed.connect(self.invalidate)
        # Surface's parameters (theme, insets and scrolling) also invalidate it.
        self._watch_parameters()
        self._dirty = False
        self._grab = source.grabToImage()
        if self._grab:
            self._grab.ready.connect(self._ready)
        else:
            self._grab = None

    def _watch_parameters(self):
        owner = self.parentItem()
        if owner not in self._watched:
            self._watched.add(owner)
            for name in ('radiusChanged', 'fadeChanged', 'topBandChanged', 'bottomBandChanged',
                         'topInsetChanged', 'bottomInsetChanged', 'fadeRectChanged'):
                getattr(owner, name).connect(self.invalidate)

    def _ready(self):
        if not isValid(self):
            return
        self._image = self._grab.image()
        self._grab = None
        self._revision += 1
        self.revisionChanged.emit()
        self.update()
        if self._dirty:
            self._timer.start(0)

    def paint(self, painter):
        if self._image.isNull():
            return
        owner = self.parentItem()
        radius = owner.property('radius')
        rect = QRectF(0, 0, self.width(), self.height())
        path = QPainterPath()
        path.addRoundedRect(rect, radius, radius)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        painter.setClipPath(path)
        image = self._image
        fade = owner.property('fade')
        if fade is not None:
            # The same smoothstep alpha as surface.frag, in physical pixels.
            image = image.copy()
            scale = image.width() / max(1, self.width())
            area = owner.property('fadeRect')
            top = float(owner.property('topBand'))
            bottom = float(owner.property('bottomBand'))
            ti = float(owner.property('topInset'))
            bi = float(owner.property('bottomInset'))
            room = float(fade.property('barRoom'))
            p = QPainter(image)
            p.setCompositionMode(QPainter.CompositionMode.CompositionMode_DestinationIn)
            left = round(area.x() * scale)
            width = round(max(0, area.width() - room) * scale)
            for row in range(round(area.y()*scale), round((area.y()+area.height())*scale)):
                y = (row + .5) / scale - area.y()
                a, b = y - ti, area.height() - bi - y
                # HeldHeads has already painted these bands above the viewport.
                # Its own head pixels must survive the viewport's dissolve.
                if a < 0 or b < 0:
                    continue
                k = 1
                for band, distance in ((top, a), (bottom, b)):
                    if band > 0:
                        t = max(0, min(1, distance / band))
                        k *= t*t*(3-2*t)
                p.fillRect(left, row, width, 1, QColor(0, 0, 0, round(255*k)))
            p.end()
        painter.drawImage(rect, image)
