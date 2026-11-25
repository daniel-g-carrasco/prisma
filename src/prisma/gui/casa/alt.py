# SPDX-License-Identifier: GPL-3.0-or-later
"""Meridiana Alt tap filter, without the background-work activity observer."""
from PySide6.QtCore import QEvent, QObject, Qt, Signal
from PySide6.QtGui import QGuiApplication, QWindow


class AltTap(QObject):
    """Alt pressed and let go alone, anywhere in `window`: `tapped`. Anything else in between makes it a combination:
    another key, a button of the mouse pressed, moved with or let go (R527: Alt held to carry a card as a tab never
    opens the menu). `held` tells Alt down and up, a combination or not, for whoever reads it while carrying.

    A key that is a shortcut (Alt+Down, Alt+Up, Alt and the letter of a command) never reaches the window: Qt's map of
    shortcuts takes it first and sends ShortcutOverride and Shortcut to other objects (Daniel's Quotario, 21/11/2026:
    Alt+Down moved the item and then the row of the menus opened when Alt was let go). The application's events are
    watched too, for those alone: any key but Alt while Alt is down makes it a combination."""

    tapped = Signal()
    pressed = Signal(float, float)          # a button of the mouse, where in the window (the menu bar hides)
    held = Signal(bool)                     # Alt down or up (R527, the cards carried as tabs)

    def __init__(self, window: QWindow, parent=None):
        super().__init__(parent)
        self.armed = False
        self.buttons = Qt.MouseButton.NoButton
        self.window = window
        # on the application, which sees the window's events first and the shortcuts' too; on the window alone only
        # when there is no application yet
        application = QGuiApplication.instance()
        (application or window).installEventFilter(self)

    def eventFilter(self, obj, event) -> bool:
        kind = event.type()
        if obj is not self.window:
            # the application's events: only the keys taken as shortcuts before the window, which end a tap
            if self.armed and kind in (QEvent.Type.ShortcutOverride, QEvent.Type.Shortcut, QEvent.Type.KeyPress) and (
                    kind == QEvent.Type.Shortcut or event.key() != Qt.Key.Key_Alt):
                self.armed = False
            return False
        if kind == QEvent.Type.KeyPress:
            alone = event.key() == Qt.Key.Key_Alt and not event.isAutoRepeat() and not (
                event.modifiers() & (Qt.KeyboardModifier.ControlModifier | Qt.KeyboardModifier.ShiftModifier
                                     | Qt.KeyboardModifier.MetaModifier)) and self.buttons == Qt.MouseButton.NoButton
            if event.key() == Qt.Key.Key_Alt and event.isAutoRepeat():
                return False
            self.armed = alone
            if event.key() == Qt.Key.Key_Alt:
                self.held.emit(True)
        elif kind == QEvent.Type.KeyRelease:
            if event.key() == Qt.Key.Key_Alt and not event.isAutoRepeat():
                self.held.emit(False)
                if self.armed:
                    self.armed = False
                    self.tapped.emit()
                    return True
        elif kind == QEvent.Type.MouseButtonPress:
            self.armed = False
            self.buttons = event.buttons()
            self.pressed.emit(event.position().x(), event.position().y())
        elif kind == QEvent.Type.MouseButtonRelease:
            self.armed = False
            self.buttons = event.buttons()
        elif kind == QEvent.Type.MouseMove:
            self.buttons = event.buttons()
            if self.buttons != Qt.MouseButton.NoButton:
                self.armed = False
        elif kind in (QEvent.Type.MouseButtonDblClick, QEvent.Type.Wheel,
                      QEvent.Type.FocusOut, QEvent.Type.WindowDeactivate, QEvent.Type.TouchBegin):
            self.armed = False
            if kind in (QEvent.Type.FocusOut, QEvent.Type.WindowDeactivate):
                self.held.emit(False)
        return False
