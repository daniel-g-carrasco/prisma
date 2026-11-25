# SPDX-License-Identifier: GPL-3.0-or-later
"""Opt-in Casa decoration. All move/resize operations use native Qt requests.

The title bar of the system follows the theme (Daniel 21/11/2026: «la barra del titolo di Windows debba seguire il
colore di sfondo dell'applicazione (come ora in Meridiana)»): FrameTheme and its functions are Meridiana's
(gui/backend/window_frame.py, R482, R544, R586), unchanged. Windows 11: bar, border and title in the ground and text of
the background chosen (meridiana, tinted, grey), light or dark, veiled under a modal window; Windows 10: the light or
dark bar alone. Wayland with Qt's own decoration: the application palette's Window and WindowText. A frame drawn by
the window manager (X11, a compositor with server-side decorations, GNOME) stays the system's."""
import ctypes
import os
import sys

from PySide6.QtCore import Property, QEvent, QObject, Qt, Signal, Slot, qVersion
from PySide6.QtGui import QColor, QGuiApplication, QPalette, QWindow

DWMWA_USE_IMMERSIVE_DARK_MODE = 20
DWMWA_BORDER_COLOR, DWMWA_CAPTION_COLOR, DWMWA_TEXT_COLOR = 34, 35, 36


def veiled(colour: QColor, veil: QColor | None) -> QColor:
    """`colour` seen under `veil` (a colour with its alpha), as the veil of a modal window shows it; itself without."""
    if veil is None or not veil.isValid():
        return QColor(colour)
    a = veil.alphaF()
    return QColor.fromRgbF(*(getattr(veil, k)() * a + getattr(colour, k)() * (1 - a) for k in ("redF", "greenF", "blueF")))


def frame_colours(colors, veil: QColor | None = None) -> dict[str, QColor]:
    """The frame's colours from the theme's tokens: bar and border on the window's ground, the title in the text;
    under `veil` while a modal window is shown (R586)."""
    return {"ground": veiled(QColor(colors["window"]), veil), "text": veiled(QColor(colors["text"]), veil),
            "quiet": veiled(QColor(colors.get("muted", colors["text"])), veil)}


def frame_palette(colours: dict[str, QColor], palette: QPalette | None = None) -> QPalette:
    """`palette` (the application's) with Window and WindowText from `colours`: what Qt's Wayland decoration paints."""
    palette = QPalette(palette if palette is not None else QGuiApplication.palette())
    for group in (QPalette.ColorGroup.Active, QPalette.ColorGroup.Inactive, QPalette.ColorGroup.Disabled):
        palette.setColor(group, QPalette.ColorRole.Window, colours["ground"])
        palette.setColor(group, QPalette.ColorRole.WindowText,
                         colours["quiet"] if group == QPalette.ColorGroup.Disabled else colours["text"])
    return palette


def draws_own_frame() -> bool:
    """Whether Qt draws the title bar itself (Wayland, client-side decorations), with the application palette."""
    return QGuiApplication.platformName() == "wayland"


def _colorref(colour: QColor) -> int:
    return colour.red() | colour.green() << 8 | colour.blue() << 16


def set_frame_colours(window: QWindow, colours: dict[str, QColor]) -> bool:
    """Bar, title and border of `window` in `colours` (Windows 11); False where DWM refuses them (Windows 10)."""
    if sys.platform != "win32":
        return False
    try:
        from ctypes import wintypes
        hwnd = wintypes.HWND(int(window.winId()))
        done = True
        for attribute, key in ((DWMWA_CAPTION_COLOR, "ground"), (DWMWA_BORDER_COLOR, "ground"),
                               (DWMWA_TEXT_COLOR, "text")):
            value = wintypes.DWORD(_colorref(colours[key]))
            done = ctypes.windll.dwmapi.DwmSetWindowAttribute(
                hwnd, attribute, ctypes.byref(value), ctypes.sizeof(value)) == 0 and done
        return done          # DWM keeps these three write-only: DwmGetWindowAttribute refuses to give them back
    except (OSError, AttributeError, ValueError):
        return False


def set_dark_frame(window: QWindow, dark: bool) -> bool:
    """The title bar of `window` dark or light (Windows 10 2004 and later); False where there is none to set."""
    if sys.platform != "win32":
        return False
    try:
        from ctypes import wintypes
        hwnd = wintypes.HWND(int(window.winId()))
        value = ctypes.c_int(1 if dark else 0)
        return ctypes.windll.dwmapi.DwmSetWindowAttribute(
            hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, ctypes.byref(value), ctypes.sizeof(value)) == 0
    except (OSError, AttributeError, ValueError):
        return False


def dark_frame(window: QWindow) -> bool | None:
    """What the title bar of `window` is, read back from DWM; None where it cannot be read."""
    if sys.platform != "win32":
        return None
    try:
        from ctypes import wintypes
        hwnd = wintypes.HWND(int(window.winId()))
        value = ctypes.c_int(0)
        if ctypes.windll.dwmapi.DwmGetWindowAttribute(
                hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, ctypes.byref(value), ctypes.sizeof(value)) != 0:
            return None
        return bool(value.value)
    except (OSError, AttributeError, ValueError):
        return None


class FrameTheme(QObject):
    """Keeps the title bars of the program's windows in the theme of `theme` (backend.tokens.ThemeTokens)."""

    def __init__(self, theme, parent=None):
        super().__init__(parent)
        self.theme = theme
        app = QGuiApplication.instance()
        theme.changed.connect(self.apply)
        if hasattr(theme, "veiled"):
            theme.veiled.connect(self.apply)                                   # R586 (c)
        # a method of this object, not a lambda: the application outlives the window, and a lambda kept framing new
        # windows with the theme of a window already closed (its colours read as the bare Property: TypeError, r24-unita)
        app.focusWindowChanged.connect(self._focused)
        self.apply()

    def _focused(self, window) -> None:
        if window is not None:
            self.frame(window)

    def frame(self, window: QWindow) -> None:
        if not isinstance(self.theme.colors, dict):                            # the theme's window already taken apart
            return
        if window.type() in (Qt.WindowType.Window, Qt.WindowType.Dialog):        # not a popup, not a tooltip
            set_dark_frame(window, bool(self.theme.dark))
            set_frame_colours(window, self.colours())                         # R544, R586, Windows 11

    def colours(self) -> dict[str, QColor]:
        veil = self.theme.veil_colour() if hasattr(self.theme, "veil_colour") else None
        return frame_colours(self.theme.colors, veil)

    def apply(self) -> None:
        if not isinstance(self.theme.colors, dict):                            # the theme's window already taken apart
            return
        if draws_own_frame():                                                  # R544: Qt's own decoration
            palette = frame_palette(self.colours())
            if palette != QGuiApplication.palette():
                QGuiApplication.setPalette(palette)
        if sys.platform == "win32":
            wanted = {"light": Qt.ColorScheme.Light, "dark": Qt.ColorScheme.Dark}.get(
                self.theme.options.get("theme"), Qt.ColorScheme.Unknown)
            hints = QGuiApplication.styleHints()
            if getattr(QGuiApplication.instance(), "_meridiana_scheme", None) != wanted:
                QGuiApplication.instance()._meridiana_scheme = wanted
                hints.setColorScheme(wanted)
        for window in QGuiApplication.topLevelWindows():
            self.frame(window)


class WindowFrame(QObject):
    changed = Signal()

    def __init__(self, *, decoration_mode='native', parent=None):
        super().__init__(parent)
        self.window, self._mode, self._previous = None, 'native', None
        self.set_mode(decoration_mode)

    mode = Property(str, lambda self: self._mode, notify=changed)
    diagnostics = Property('QVariantMap', lambda self: {
        'platformName': QGuiApplication.platformName(), 'qt': qVersion(),
        'qpa': QGuiApplication.platformName(), 'qpaEnvironment': os.environ.get('QT_QPA_PLATFORM', ''),
        'requested': self._mode,
        'applied': ('casa' if self.window.flags() & Qt.WindowType.FramelessWindowHint else 'native')
        if self.window else 'unbound'}, notify=changed)

    def bind(self, window):
        self.window = window
        window.installEventFilter(self)
        self.set_mode(self._mode)

    @Slot(str)
    def set_mode(self, mode):
        if mode not in ('native', 'casa'):
            raise ValueError('decoration_mode must be native or casa')
        self._mode = mode
        if self.window:
            visible = self.window.isVisible()
            self.window.setFlag(Qt.WindowType.FramelessWindowHint, mode == 'casa')
            if visible:
                self.window.show()
        self.changed.emit()

    @Slot(result=bool)
    def start_move(self):
        return bool(self.window and self.window.startSystemMove())

    @Slot(int, result=bool)
    def start_resize(self, edges):
        valid = int(Qt.Edge.TopEdge.value | Qt.Edge.BottomEdge.value | Qt.Edge.LeftEdge.value | Qt.Edge.RightEdge.value)
        if not self.window or not edges or edges & ~valid:
            return False
        return bool(self.window.startSystemResize(Qt.Edge(edges)))

    @Slot()
    def minimize(self):
        if self.window:
            self.window.showMinimized()

    @Slot()
    def maximize(self):
        if self.window:
            self.window.showNormal() if self.window.visibility() == self.window.Visibility.Maximized else self.window.showMaximized()

    @Slot()
    def toggle_fullscreen(self):
        if not self.window:
            return
        if self._previous is None:
            self._previous = (self.window.visibility(), self.window.geometry())
            self.window.showFullScreen()
        else:
            visibility, geometry = self._previous
            self._previous = None
            self.window.setVisibility(visibility)
            if visibility == self.window.Visibility.Windowed:
                self.window.setGeometry(geometry)

    def eventFilter(self, obj, event):
        if event.type() == QEvent.Type.KeyPress and event.key() == Qt.Key.Key_F11:
            if not event.isAutoRepeat():
                self.toggle_fullscreen()
            return True
        return False

    def close(self):
        if self.window:
            self.window.removeEventFilter(self)
            self.window = None
