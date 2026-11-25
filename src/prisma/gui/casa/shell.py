# SPDX-License-Identifier: GPL-3.0-or-later
"""Window-scoped composition root, independent of any document domain."""
from copy import deepcopy

from PySide6.QtCore import Property, QObject, QRect, Signal, Slot
from PySide6.QtGui import QGuiApplication

from .alt import AltTap
from .dialogs import DialogsController, rectangle
from .files import FilesController
from .pages import indexed
from .parts import Parts
from .scaffold import Scaffold
from .settings import SettingsController
from .window_frame import FrameTheme, WindowFrame


class ShellController(QObject):
    changed = Signal()
    closed = Signal()
    closeAsked = Signal()

    def __init__(self, pages=(), commands=(), services=None, initial_state=None,
                 *, factories=(), sections=(), decoration_mode='native', parent=None):
        super().__init__(parent)
        self._pages, self._commands = indexed(pages), indexed(commands)
        for command in self._commands.values():
            if command.parent() is not None:
                raise ValueError('Commands must belong to one window')
            command.setParent(self)
        for command in self._commands.values():
            for other in command.more:
                if other == command.id or other not in self._commands:
                    raise ValueError('Unknown command in more of ' + command.id + ': ' + str(other))
        self._current = next((key for key, page in self._pages.items() if page.enabled), '')
        # pages the open document has not (set_page_shown): out of the tabs, their numbers taken by the others
        self._hidden = set()
        self._view, self._closed, self._closing_save = 'pages', False, False
        self.window, self._initial = None, deepcopy(initial_state or {})
        services = services or {}
        self._panels = {}
        self._panel_layouts = {}
        for panel in services.get('panels', ()):
            key = panel.get('id')
            if not key or key in self._panels:
                raise ValueError('Empty or duplicate panel: ' + str(key))
            self._panels[key] = dict(panel)
            self._panel_layouts[key] = {'zone': panel.get('zone', 'right'), 'geometry': [20, 20, 300, 300]}
        self.files = FilesController(services.get('files'), recent=services.get('recent', ()),
                                     sections=services.get('file_sections', ()), recovery=services.get('recovery'), parent=self)
        self.settings = SettingsController(services.get('load', dict), services.get('save', lambda v: None), sections, self)
        self._preferences_changed = services.get('preferences_changed')
        if self._preferences_changed:
            self.settings.changed.connect(self._apply_preferences)
            self._apply_preferences()
        self.dialogs = DialogsController(self)
        self.frame = WindowFrame(decoration_mode=decoration_mode, parent=self)
        self.parts = Parts(self, factories)
        self.files.finished.connect(self._file_finished)
        self.dialogs.register('close', lambda: {'title': 'Save changes?'})
        self._scaffold = Scaffold(self, services)

    pages = Property('QVariantList', lambda self: [{'id': p.id, 'title': p.title, 'source': p.source, 'enabled': p.enabled,
                                                    'reason': p.reason, 'numbered': p.numbered, 'framed': p.framed} for p in self._pages.values()], constant=True)
    commands = Property('QVariantList', lambda self: list(self._commands.values()), constant=True)
    currentPage = Property(str, lambda self: self._current, notify=changed)
    activeView = Property(str, lambda self: self._view, notify=changed)
    isClosed = Property(bool, lambda self: self._closed, notify=changed)
    fileController = Property(QObject, lambda self: self.files, constant=True)
    settingsController = Property(QObject, lambda self: self.settings, constant=True)
    dialogController = Property(QObject, lambda self: self.dialogs, constant=True)
    frameController = Property(QObject, lambda self: self.frame, constant=True)
    partProperties = Property('QVariantMap', lambda self: dict(self.parts.properties), constant=True)
    panels = Property('QVariantList', lambda self: [dict(p, **self._panel_layouts[key]) for key, p in self._panels.items()], notify=changed)
    scaffold = Property(QObject, lambda self: self._scaffold, constant=True)

    @Slot(str, str, 'QVariantList')
    def set_panel_layout(self, key, zone, geometry):
        if key not in self._panels or zone not in ('left', 'right', 'bottom', 'floating'):
            return
        bounds = [0, 0, self.window.width(), self.window.height()] if self.window else [0, 0, 1000, 700]
        valid = rectangle(geometry, bounds)
        if valid:
            self._panel_layouts[key] = {'zone': zone, 'geometry': valid}
            self.changed.emit()

    @Slot(str, result=QObject)
    def command(self, command_id):
        return self._commands.get(command_id)

    def _apply_preferences(self):
        self._preferences_changed(self.settings.values)

    @Slot(str, bool, result=bool)
    def set_page_shown(self, key, shown):
        """A page that comes and goes with the document (Daniel 21/11/2026: Quotario's «Contabilità» only for a SAL): its
        tab and its number go, the others count again; the current page, hidden, gives way to the first page shown."""
        if key not in self._pages or (key not in self._hidden) == shown:
            return False
        if shown:
            self._hidden.discard(key)
        else:
            self._hidden.add(key)
            if self._current == key:
                self._current = next((k for k, p in self._pages.items() if p.enabled and k not in self._hidden), '')
        self.changed.emit()
        self._scaffold.catalogChanged.emit()
        return True

    pagesShown = Property('QVariantList', lambda self: [k for k in self._pages if k not in self._hidden], notify=changed)

    @Slot(str, result=bool)
    def select_page(self, key):
        if self._closed or key not in self._pages or not self._pages[key].enabled or key in self._hidden:
            return False
        self._current, self._view = key, 'pages'
        self.changed.emit()
        return True

    @Slot(str)
    def show_view(self, key):
        if not self._closed and key in ('pages', 'file', 'settings'):
            self._view = key
            self.changed.emit()

    @Slot(str, result=bool)
    def trigger(self, command_id):
        command = self._commands.get(command_id)
        return bool(not self._closed and command and command.trigger())

    def bind(self, window):
        if self.window is not None:
            if self.window is not window:
                raise ValueError('Shell already bound to another window')
            return
        self.window = window
        from PySide6.QtCore import Q_ARG, QMetaObject
        self._alt_tap = AltTap(window, self)
        self._alt_tap.tapped.connect(lambda: QMetaObject.invokeMethod(window, 'altTapped'))
        window.setProperty('altFilter', True)        # the tap is the filter's alone (Workbench.altReleased)
        self._alt_tap.held.connect(lambda down: QMetaObject.invokeMethod(window, 'setAltHeld', Q_ARG('QVariant', down)))
        self._alt_tap.pressed.connect(lambda x, y: QMetaObject.invokeMethod(window, 'pointerPressedAt', Q_ARG('QVariant', x), Q_ARG('QVariant', y)))
        self.frame.bind(window)
        # the system's title bar in the theme's background, light or dark (window_frame.FrameTheme, as Meridiana)
        # services['help']: the texts of the «?» of this window's fields and sections (scaffold.HelpBook)
        if self._scaffold.services.get('help'):
            from PySide6.QtQml import QQmlEngine

            from .scaffold import HelpBook
            self._help_book = HelpBook(self._scaffold.services['help'], self)
            # the engine is the controller's parent (the hosts make it so): a wrapper of the window's engine asked here
            # was Python's, and took the engine and the window with it when it went
            engine = self.parent()
            if isinstance(engine, QQmlEngine):
                engine.rootContext().setContextProperty('helpBook', self._help_book)
        theme = self._scaffold.services.get('theme_tokens')
        if theme is not None and getattr(self, '_frame_theme', None) is None:
            self._frame_theme = FrameTheme(theme, self)
        window.setProperty('toolbarMode', 'under')
        self.parts.bind(window)
        self.restore_layout(self._initial or self.settings.values.get('layout', {}))

    @Slot(result='QVariantMap')
    def capture_layout(self):
        geometry = self.window.geometry().getRect() if self.window else (0, 0, 1000, 700)
        state = {'version': 1, 'page': self._current, 'geometry': list(geometry),
                'dialogs': self.dialogs.geometries, 'panels': deepcopy(self._panel_layouts)}
        if self.window and hasattr(self.window, 'savedLayout'):
            state['workbench'] = self.window.savedLayout().toVariant()
        return state

    @Slot('QVariantMap')
    def restore_layout(self, state):
        if not isinstance(state, dict):
            return
        self.select_page(state.get('page', self._current))
        if self.window:
            screens = QGuiApplication.screens()
            screen = next((s for s in screens if s.name() == state.get('screen')), QGuiApplication.primaryScreen())
            if screen:
                valid = rectangle(state.get('geometry'), screen.availableGeometry().getRect())
                if valid:
                    self.window.setGeometry(QRect(*(round(v) for v in valid)))
            self.dialogs.bounds = [0, 0, self.window.width(), self.window.height()]
        self.dialogs.restore(state.get('dialogs', {}))
        if self.window and state.get('workbench') and hasattr(self.window, 'restoreLayout'):
            self.window.restoreLayout(state['workbench'])
        panels = state.get('panels', {})
        if isinstance(panels, dict):
            for key, value in panels.items():
                if isinstance(value, dict):
                    self.set_panel_layout(key, value.get('zone'), value.get('geometry'))

    @Slot(result=bool)
    def request_close(self):
        if self._closed:
            return True
        if self.files.busy:
            return False
        if self.files.dirty:
            self.dialogs.open('close')
            self.closeAsked.emit()
            return False
        self.close()
        return True

    @Slot(str, str, result=bool)
    def resolve_close(self, choice, path=''):
        if self._closed:
            return True
        if self.files.busy:
            return False
        if choice == 'discard':
            self.close()
        elif choice == 'save':
            self._closing_save = True
            if not self.files.request('save', path):
                self._closing_save = False
        elif choice == 'cancel':
            self._closing_save = False
            self.dialogs.dismiss()
        return self._closed

    def _file_finished(self, status, message):
        pending, self._closing_save = self._closing_save, False
        if pending and status == 'success' and not self.files.dirty:
            self.close()

    @Slot()
    def close(self):
        if self._closed:
            return
        self._closed = True
        if self.window is not None and getattr(self, '_alt_tap', None) is not None:
            # A window being destroyed still sends focus events: its Alt filter must not answer them any more
            self.window.removeEventFilter(self._alt_tap)
        self.files.close()
        self.frame.close()
        if getattr(self, '_frame_theme', None) is not None:
            try:
                QGuiApplication.instance().focusWindowChanged.disconnect(self._frame_theme._focused)
            except (RuntimeError, TypeError):
                pass
        try:
            self.parts.close()
        finally:
            self.dialogs.dismiss()
            self.changed.emit()
            self.closed.emit()
