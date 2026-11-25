# SPDX-License-Identifier: GPL-3.0-or-later
"""Quick row heights: lazy natural measurements and local transient heights."""
import time

from PySide6.QtCore import (
    Property,
    QEasingCurve,
    QObject,
    QVariantAnimation,
    Signal,
    Slot,
)
from PySide6.QtGui import QFont, QTextLayout, QTextOption

from .surface import release_when_destroyed


class RowExtension(QObject):
    changed = Signal()
    finished = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        release_when_destroyed(self)
        self.natural = {}
        self.heights = {}
        self.targets = {}
        self.starts = {}
        self.slow = False
        self.animation = QVariantAnimation(self)
        self.animation.setDuration(120)
        self.animation.setEasingCurve(QEasingCurve.Type.OutCubic)
        self.animation.setStartValue(0.0)
        self.animation.setEndValue(1.0)
        self.animation.valueChanged.connect(self._frame)
        self.animation.finished.connect(self.finish)

    @property
    def running(self):
        return self.animation.state() == QVariantAnimation.State.Running

    busy = Property(bool, lambda self: self.running, notify=changed)
    heightsMap = Property('QVariantMap', lambda self: self.heights, notify=changed)

    @Slot('QVariantMap', 'QVariantMap', bool, float)
    def startTransition(self, starts, targets, reduced, cost):
        self.transition(starts, targets, reduced, cost)

    @Slot()
    def invalidate(self):
        self.finish()
        self.natural.clear()
        self.heights.clear()
        self.targets.clear()
        self.starts.clear()
        self.changed.emit()

    def transition(self, starts, targets, reduced=False, cost_ms=0):
        self.animation.stop()
        self.starts = {key: self.heights.get(key, value) for key, value in starts.items()}
        self.targets = targets.copy()
        if reduced or self.slow or cost_ms > 16 or self.starts == self.targets:
            self.finish()
        else:
            self.animation.start()

    def _frame(self, progress):
        start = time.perf_counter()
        self.heights = {k: self.starts.get(k, v) + (v-self.starts.get(k, v))*progress for k, v in self.targets.items()}
        self.changed.emit()
        if (time.perf_counter()-start)*1000 > 16:
            self.slow = True
            self.finish()

    @Slot()
    def finish(self):
        self.animation.stop()
        self.heights = self.targets.copy()
        self.changed.emit()
        self.finished.emit()

    @Slot(float)
    def observe_cost(self, milliseconds):
        if milliseconds > 16:
            self.slow = True
            self.finish()

    @Slot(str, float, QFont, float, result=float)
    def measure(self, text, width, font, dpr):
        key = (text, font.toString(), dpr, round(width, 2))
        if key not in self.natural:
            height = 0
            # QQuickText does not lay out an extra empty paragraph after the
            # final newline. Interior blank paragraphs still occupy one line.
            paragraphs = text.split('\n')
            if len(paragraphs) > 1 and not paragraphs[-1]:
                paragraphs.pop()
            for paragraph in paragraphs:
                layout = QTextLayout(paragraph or ' ', font)
                option = QTextOption()
                option.setWrapMode(QTextOption.WrapMode.WrapAtWordBoundaryOrAnywhere)
                layout.setTextOption(option)
                layout.beginLayout()
                while True:
                    line = layout.createLine()
                    if not line.isValid():
                        break
                    line.setLineWidth(max(1, width))
                    height += line.height()
                layout.endLayout()
            if len(self.natural) > 4096:
                self.natural.clear()
            self.natural[key] = height + 8
        return self.natural[key]
