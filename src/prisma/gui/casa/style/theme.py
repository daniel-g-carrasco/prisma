# SPDX-License-Identifier: GPL-3.0-or-later
"""The pieces of the look that do not need a widget (r30-struttura: taken out of the Widgets window's theme, which
stays in ui/theme.py until that window goes): the names of the choices of Settings > Appearance, a QPalette from the
roles of theme_colors.derive, the arrows of the fields, the fonts read from their files (data/fonts) and given to the
charts of the report, and what the system says for the look.

- The system's accent: on Windows the Highlight of the platform's palette; on Linux the portal
  (org.freedesktop.appearance, accent-color), read with gdbus because PySide's QtDBus cannot read the (ddd) it
  answers, and read again on SettingChanged. Without one, the default colour."""

from __future__ import annotations

import sys

from PySide6.QtCore import QObject, QProcess, Signal, Slot
from PySide6.QtGui import QColor, QFontDatabase, QGuiApplication, QPalette

from . import theme_colors

PORTAL = ("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop", "org.freedesktop.portal.Settings")
# Inter since 25/10/2026 (R95: Daniel chose it at 14 px on the real window at 200 %; Titillium Web, before it, read
# thin and small)
FONT_DIR = "inter"
FONT_FILES = ("Inter-Regular.ttf", "Inter-SemiBold.ttf", "Inter-Bold.ttf")
FONT_WEIGHTS = dict(zip(FONT_FILES, (400, 600, 700), strict=True))
# The fonts to choose from in Preferences > Appearance (Daniel, 03/11/2026, study 29): each one's folder in data/fonts,
# its files and, where it has one, a condensed cut for where room is short (the words of the phase bars). Static files:
# on Linux a variable font with its width axis loses it, or its weight, when a weight is asked (study 29, section 4).
PLEX_WEIGHTS = ("Regular", "SemiBold", "Bold")
FONTS = {"inter": {"dir": FONT_DIR, "files": FONT_FILES, "tight": ()},
         "plex": {"dir": "ibm-plex", "files": tuple(f"IBMPlexSans-{w}.ttf" for w in PLEX_WEIGHTS),
                  "tight": tuple(f"IBMPlexSansCondensed-{w}.ttf" for w in PLEX_WEIGHTS)}}
FONT_WEIGHTS.update({f: weight for files in (FONTS["plex"]["files"], FONTS["plex"]["tight"])
                     for f, weight in zip(files, (400, 600, 700), strict=True)})
DEFAULT_FONT = 'plex'


def theme_names(translate=str) -> dict:
    return {"system": translate("As the system"), "light": translate("Light"), "dark": translate("Dark")}


def colour_names(translate=str) -> dict:
    """The ready-made colours of section 12.1, in the order of the menu."""
    return {"system": translate("System"), "bronze": translate("Bronze"), "terracotta": translate("Terracotta"), "olive": translate("Olive"),
            "forest": translate("Forest"), "petrol": translate("Petrol"), "blue": translate("Blue"), "indigo": translate("Indigo"),
            "plum": translate("Plum"), "graphite": translate("Graphite")}


def background_names(translate=str) -> dict:
    return {"meridiana": translate("Lime and night"), "tinted": translate("From the colour"), "grey": translate("Grey")}


def qpalette(roles: dict) -> QPalette:
    pal = QPalette()
    for group, colours in roles.items():
        g = getattr(QPalette.ColorGroup, group)
        for role, hex_ in colours.items():
            pal.setColor(g, getattr(QPalette.ColorRole, role), QColor(hex_))
    return pal


ARROWS = {"up": ("M2 9L8 3L14 9", 16, 12), "down": ("M2 3L8 9L14 3", 16, 12), "open": ("M2 4L8 10L14 4", 16, 14)}


class SystemAccent(QObject):
    """What the system says for the look, one reader for the application (a child of it): the accent and whether
    it asks for less motion. On Windows the Highlight of the platform's palette, read before Meridiana sets its own
    (#0078d4 on Daniel's PC), and SPI_GETCLIENTAREAANIMATION; on Linux the portal's accent-color and
    reduced-motion, read with gdbus (PySide's QtDBus cannot read the (ddd) the portal answers) without waiting,
    and again on SettingChanged."""

    changed = Signal(str)
    motion = Signal(bool)            # True: less motion, please

    def __init__(self, app):
        if not isinstance(app, QGuiApplication):    # its palette() on a QCoreApplication is an access violation
            raise RuntimeError(f"SystemAccent needs a QGuiApplication, not {type(app).__name__}")  # noqa: TRY004 (source API)
        super().__init__(app)
        self.value = ""
        self.reduced_motion = False
        self._processes: dict = {}
        if sys.platform == "win32":
            self.value = QGuiApplication.palette().color(QPalette.ColorRole.Highlight).name()
            self.reduced_motion = _windows_reduced_motion()
        elif sys.platform.startswith("linux") and QGuiApplication.platformName() != 'offscreen':
            self._listen()
            self.read()
            self.read("reduced-motion")

    @classmethod
    def of(cls, app) -> SystemAccent:
        found = next((child for child in app.children() if isinstance(child, cls)), None)   # made with app as parent
        return found if found is not None else cls(app)

    def _listen(self) -> None:
        try:
            from PySide6.QtCore import SLOT
            from PySide6.QtDBus import QDBusConnection
        except ImportError:
            return
        bus = QDBusConnection.sessionBus()
        if bus.isConnected():
            bus.connect("", PORTAL[1], PORTAL[2], "SettingChanged", self, SLOT("_setting_changed(QDBusMessage)"))

    @Slot("QDBusMessage")
    def _setting_changed(self, message) -> None:
        args = message.arguments()
        if len(args) >= 2 and args[0] == "org.freedesktop.appearance" and args[1] in ("accent-color", "reduced-motion"):
            self.read(args[1])

    def read(self, key: str = "accent-color") -> None:
        if key in self._processes:
            return
        process = QProcess(self)
        process.finished.connect(lambda _code, _status: self._answered(key, process))
        process.errorOccurred.connect(lambda _e: self._answered(key, process))
        self._processes[key] = process
        process.start("gdbus", ["call", "--session", "--dest", PORTAL[0], "--object-path", PORTAL[1], "--method",
                                PORTAL[2] + ".ReadOne", "org.freedesktop.appearance", key])

    def _answered(self, key: str, process: QProcess) -> None:
        if self._processes.get(key) is not process:
            return                                  # an answer already taken (an error, then the end)
        del self._processes[key]
        from shiboken6 import isValid
        if not isValid(process):
            return          # the program quitting while gdbus still ran: Qt ends it and says so (seen on Linux)
        text = bytes(process.readAllStandardOutput()).decode("utf-8", "replace")
        process.deleteLater()
        if key == "reduced-motion":
            reduced = theme_colors.gdbus_number(text) == 1
            if reduced != self.reduced_motion:
                self.reduced_motion = reduced
                self.motion.emit(reduced)
            return
        accent = theme_colors.gdbus_accent(text)
        if accent != self.value:
            self.value = accent
            self.changed.emit(accent)


def _windows_reduced_motion() -> bool:
    """Windows' «Animation effects» switched off (SPI_GETCLIENTAREAANIMATION): less motion."""
    try:
        import ctypes
        on = ctypes.c_int(1)
        if ctypes.windll.user32.SystemParametersInfoW(0x1042, 0, ctypes.byref(on), 0):
            return not on.value
    except (AttributeError, OSError):
        pass
    return False


def _font_families(choice, resources):
    """Load the chosen shipped family, including its condensed cut."""
    entry = FONTS[choice]
    families = []
    for names in (entry['files'], entry['tight']):
        family = ''
        for name in names:
            path = resources.fonts / entry['dir'] / name
            if not path.is_file():
                raise FileNotFoundError(path)
            # Some Windows font backends cannot open a non-ANSI path.
            # Read with Python's Unicode filesystem API, then give Qt bytes.
            fid = QFontDatabase.addApplicationFontFromData(path.read_bytes())
            loaded = QFontDatabase.applicationFontFamilies(fid) if fid >= 0 else []
            if not loaded:
                raise RuntimeError(f'Cannot load font: {path}')
            family = family or loaded[0]
        families.append(family)
    return tuple(families)
