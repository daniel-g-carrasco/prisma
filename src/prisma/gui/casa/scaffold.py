# SPDX-License-Identifier: GPL-3.0-or-later
"""Host adapters for the window copied from Meridiana's fixed snapshot.

The QML retains its catalogue contracts; document I/O stays in FilesController.
"""
from dataclasses import asdict
from pathlib import Path

from PySide6.QtCore import Property, QObject, Qt, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QFont, QPainterPath
from PySide6.QtQml import QJSValue

from . import arrangement, shortcuts
from .style import icons
from .style.design import Button, Layout, Motion, Size, Space


class Words(QObject):
    changed = Signal()

    def __init__(self, scaffold, **words):
        super().__init__(scaffold)
        self.scaffold, self.copy = scaffold, words

    words = Property('QVariantMap', lambda self: {k: self.scaffold.tr(v) for k, v in self.copy.items()}, notify=changed)


class Closing(Words):
    stateChanged = Signal()
    def __init__(self, scaffold):
        super().__init__(scaffold, title='Save changes?', save='Save', cancel='Cancel', discard="Don't save")
        scaffold.controller.dialogs.changed.connect(self.stateChanged)

    asking = Property(bool, lambda self: self.scaffold.controller.dialogs.current == 'close', notify=stateChanged)
    question = Property(str, lambda self: self.scaffold.tr('Save changes before closing?'), notify=stateChanged)

    @Slot(result=bool)
    def mayClose(self):
        return self.scaffold.controller.request_close()

    @Slot(str)
    def answer(self, choice):
        self.scaffold.controller.resolve_close(choice)


class Recovery(Words):
    stateChanged = Signal()
    def __init__(self, scaffold):
        super().__init__(scaffold, title='Recovery', yes='Recover', no='Cancel')
        offer = scaffold.services.get('recovery_offer', False)
        self._offered = bool(offer() if callable(offer) else offer)

    offered = Property(bool, lambda self: self._offered, notify=stateChanged)
    question = Property(str, lambda self: self.scaffold.tr('Recover the previous session?'), notify=stateChanged)

    @Slot(bool)
    def answer(self, yes):
        self._offered = False
        if yes:
            self.scaffold.controller.files.recover()
        elif callable(self.scaffold.services.get('recovery_decline')):
            self.scaffold.services['recovery_decline']()
        self.stateChanged.emit()


class Work(QObject):
    changed = Signal()
    busyChanged = Signal()      # Meridiana R731: only when the commands in progress change, not at each step of a job
    slotsChanged = Signal()     # Meridiana R731: only when the rows a page shows change (_follow_slots)

    def __init__(self, scaffold, provider):
        super().__init__(scaffold)
        self.scaffold, self.provider = scaffold, provider
        self._busy, self._slots = {}, {}
        if provider and hasattr(provider, 'changed'):
            provider.changed.connect(self.changed)
            provider.changed.connect(self._follow_busy)
            provider.changed.connect(self._follow_slots)
        self._follow_slots()

    rows = Property('QVariantList', lambda self: list(self.provider.rows) if self.provider and hasattr(self.provider, 'rows') else [], notify=changed)
    texts = Property('QVariantMap', lambda self: {'others': self.scaffold.tr('Other jobs')}, notify=changed)
    # Meridiana R731: the row of each job by its slot (a page shows its own job, form B), and the commands whose job is
    # in progress with their tooltip then; the host names them (`provider.slot_commands`: slot -> command ids).
    # `slots` is told again only when a job with a slot comes or goes or the row of a shown slot changes
    # (`provider.shown_slots`, every slot when the host names none): a step of another job re-reads no page
    slots = Property('QVariantMap', lambda self: self._slots, notify=slotsChanged)
    busyCommands = Property('QVariantMap', lambda self: self._busy, notify=busyChanged)

    def _follow_slots(self):
        slots, before = {r['slot']: r for r in self.rows if r.get('slot')}, self._slots
        self._slots = slots
        shown = getattr(self.provider, 'shown_slots', None)
        shown = slots.keys() | before.keys() if shown is None else shown
        if slots.keys() != before.keys() or any(slots.get(k) != before.get(k) for k in shown):
            self.slotsChanged.emit()

    def _follow_busy(self):
        busy = self._busy_commands()
        if busy != self._busy:
            self._busy = busy
            self.busyChanged.emit()

    def _busy_commands(self):
        commands = getattr(self.provider, 'slot_commands', None) or {}
        tip = self.scaffold.tr('{job} in progress: Cancel in the status bar')
        return {c: tip.format(job=r['title']) for r in self.rows for c in commands.get(r.get('slot'), ())}

    @Slot(str)
    def cancel(self, job_id):
        if self.provider and hasattr(self.provider, 'cancel'):
            self.provider.cancel(job_id)


class FilePage(Words):
    stateChanged = Signal()
    sectionChanged = Signal()
    closed = Signal()
    fileDialogRequested = Signal(str, str, str, list)

    def __init__(self, scaffold):
        super().__init__(scaffold, back='Back', new='New', open='Open', save='Save and revisions', export='Export',
                         preferences='Settings', help='Help', quit='Quit', appearance='Appearance', keyboard='Keyboard',
                         settingsBack='Back to File', settingsLead='Changes are saved immediately.',
                         elsewhere='Choose a file or a recent item.', recent='Recent', noRecent='No recent files',
                         noRecentWhy='The files you open appear here.',
                         unsaved='Save changes?', saveFirst='Save changes before continuing?',
                         saveChanges='Save', discard="Don't save", cancel='Cancel')
        self._section = 'open'
        self.copy.update({s['id']: s['title'] for s in scaffold.controller.settings.sections})
        scaffold.controller.files.fileDialogRequested.connect(self.fileDialogRequested)
        scaffold.controller.files.changed.connect(self.stateChanged)

    section = Property(str, lambda self: self._section, notify=sectionChanged)
    metrics = Property('QVariantMap', lambda self: {'pageX': Layout.PAGE[0], 'pageY': Layout.PAGE[1]}, constant=True)
    confirmation = Property(bool, lambda self: False, constant=True)
    error = Property(str, lambda self: self.scaffold.controller.files.message, notify=stateChanged)
    status = Property(str, lambda self: '', constant=True)
    recent = Property('QVariantList', lambda self: [dict(p, name=p.get('title', p.get('name', '')), folder=str(Path(p.get('path', '')).parent)) for p in self.scaffold.controller.files.recent], notify=stateChanged)
    canOpen = Property(bool, lambda self: self.scaffold.controller.files.capabilities['open'], notify=stateChanged)

    @Property('QVariantMap', notify=stateChanged)
    def sections(self):
        tr = self.scaffold.tr
        def tile(action, icon, title, description, button):
            return {'action': action, 'icon': icon, 'title': tr(title), 'description': tr(description), 'button': tr(button), 'formats': '', 'group': tr('Files')}
        result = {
            'open': {'title': tr('Open'), 'description': '', 'tiles': [tile('open', 'folder-open', 'Open', 'Choose a file or folder.', 'Choose…')]},
            'save': {'title': tr('Save and revisions'), 'description': '', 'tiles': [self._save_tile(tile('save', 'save', 'Save', 'Save the current document.', 'Save'))]},
            'export': {'title': tr('Export'), 'description': '', 'tiles': []},
            'help': {'title': tr('Help'), 'description': '', 'tiles': []},
        }
        for section in self.scaffold.controller.files.sections:
            key = section.get('id', 'export')
            tiles = section.get('tiles', [])
            for action in section.get('actions', []):
                command = self.scaffold.controller.command(action.get('command', ''))
                tiles = [*tiles, {'action': action.get('command', ''), 'icon': 'folder-open', 'title': action['title'],
                    'button': action['title'], 'description': '', 'formats': '', 'group': section.get('title', ''), 'enabled': bool(command and command.enabled)}]
            result[key] = {'title': section.get('title', ''), 'description': section.get('description', ''), 'tiles': tiles}
            if 'actions' in section:
                result['open']['tiles'].extend(tiles)
        return result

    def _save_tile(self, tile):
        """A viewer's document service says why it does not save: its tile is off, with the reason as description."""
        note = self.scaffold.controller.files.notes.get('save', '')
        return dict(tile, enabled=False, description=note) if note else tile

    @Slot(str)
    def selectSection(self, key):
        self._section = key
        self.sectionChanged.emit()

    @Slot()
    def back(self):
        self.closeFile()

    @Slot()
    def closeFile(self):
        self.scaffold.controller.show_view('pages')
        self.closed.emit()

    @Slot(str)
    def request(self, action):
        ctl = self.scaffold.controller
        if action == 'open':
            ctl.files.choose(self.scaffold.file_kind, self.scaffold.tr('Open'), '', self.scaffold.filters)
        elif action == 'save':
            note = ctl.files.notes.get('save', '')
            if note:
                self.scaffold.show_notice(note, ms=4000)
            else:
                ctl.files.choose('save', self.scaffold.tr('Save'), '', self.scaffold.filters)
        elif action == 'quit':
            ctl.request_close()
        elif action == 'new':
            ctl.files.request('new')
        else:
            ctl.trigger(action)

    @Slot(str, str)
    def fileChosen(self, operation, url):
        path = QUrl(url).toLocalFile()
        self.scaffold.controller.files.fileChosen(operation, path)

    @Slot()
    def cancelFileDialog(self):
        self.scaffold.controller.files.cancelFileDialog()

    @Slot(str)
    def openChosen(self, path):
        self.scaffold.controller.files.request('open', path)


class Preferences(QObject):
    changed = Signal()

    def __init__(self, scaffold):
        super().__init__(scaffold)
        self.scaffold = scaffold
        self._section, self._undo, self._pending = 'appearance', None, {}
        self._preview = None
        scaffold.controller.settings.changed.connect(self.changed)

    section = Property(str, lambda self: self._section, notify=changed)
    sections = Property('QVariantList', lambda self: self.scaffold.controller.settings.sections, constant=True)

    @Slot(str, result='QUrl')
    def sourceFor(self, key):
        section = next((s for s in self.sections if s['id'] == key), None)
        return QUrl(section['source']) if section else QUrl()
    @Property('QVariantMap', notify=changed)
    def values(self):
        state = self.scaffold.controller.settings.values
        appearance = {'theme': 'light', 'accent': 'indigo', 'backgrounds': 'meridiana', 'font': 'plex', 'textSize': 'medium',
                      'density': 'normal', 'phaseMotion': False, **icons.DEFAULTS}
        appearance.update(state['appearance'])
        appearance.update(text_size=appearance['textSize'], reduced_motion=state['reducedMotion'], language=state['language'])
        window = self.scaffold.controller.window
        mode = window.property('toolbarMode') if window else ''
        appearance.update(toolbar=mode if mode in ('icons', 'small') else 'text',
                          toolbar_place=window.property('toolbarPosition') if window else 'top',
                          menu_bar=window.property('menuAlways') if window else False)
        return appearance
    error = Property(str, lambda self: '', constant=True)
    canUndo = Property(bool, lambda self: self._undo is not None, notify=changed)
    shortcutConflict = Property(bool, lambda self: False, constant=True)
    navigationHelp = Property('QVariantMap', lambda self: {'hint': '', 'audience': '', 'gestures': [], 'note': ''}, constant=True)
    @Property('QVariantMap', notify=changed)
    def appearancePreview(self):
        from PySide6.QtCore import QLocale

        from .style import theme_colors
        value = self.values
        token = self.scaffold.services.get('theme_tokens')
        dark = token.dark if token else value.get('theme') == 'dark'
        key = (value.get('accent', 'indigo'), value.get('backgrounds', 'meridiana'), dark,
               self.scaffold.controller.settings.values['language'])
        if self._preview is None or self._preview[0] != key:
            tr = self.scaffold.tr
            report = theme_colors.derive(theme_colors.seed_for(key[0]), dark, key[1]).report
            locale = QLocale('it_IT' if key[3] == 'it' else 'en_GB')
            self._preview = (key, {'contrast': tr('Text on the colour {a}:1, the colour on the view {b}:1 (at least 4.5:1).').format(
                a=locale.toString(report.on_accent, 'f', 1), b=locale.toString(report.on_view, 'f', 1)),
                'note': theme_colors.retouch_note(report, dark, translate=tr) or tr('The colour is used as it is.')})
        return self._preview[1]
    keyboardLead = Property(str, lambda self: self.scaffold.tr('Change the shortcuts used by menus and commands.'), notify=changed)
    shortcutRows = Property('QVariantList', lambda self: self.scaffold.shortcut_rows(), notify=changed)

    @Property('QVariantMap', notify=changed)
    def text(self):
        source = {'panels': 'Panels', 'layout': 'Restore the default layout', 'additional': 'Additional settings',
                      'custom': 'Use colour', 'icons': 'Icons', 'preview': 'Preview', 'building': 'Item', 'south': 'Selection', 'east': 'Other item',
                      'lay': 'Command', 'warning': 'A warning', 'undo': 'Undo the last change', 'reset': 'Restore defaults for this section',
                      'confirm': 'Restore defaults?', 'restore': 'Restore', 'cancel': 'Cancel', 'command': 'Command', 'keys': 'Keys',
                      'defaults': 'Defaults', 'newKeys': 'New shortcut', 'use': 'Use', 'none': 'None', 'allDefaults': 'Restore all shortcuts',
                      'search': 'Search', 'shortcutSearch': 'Search commands', 'openShortcuts': 'Keyboard shortcuts',
                      'privacyLead': '', 'reportLead': '', 'keyboardNote': 'Click a command to change its shortcut.'}
        return {k: self.scaffold.tr(v) for k, v in source.items()}

    @Property('QVariantMap', notify=changed)
    def allFields(self):
        tr = self.scaffold.tr
        from .style.theme import background_names, colour_names, theme_names
        def choice(key, label, options):
            return {'key': key, 'label': tr(label), 'kind': 'choice', 'enabled': True, 'description': '',
                        'options': [{'value': value, 'label': tr(title)} for value, title in options]}
        return {'appearance': [choice('theme', 'Theme', list(theme_names().items())),
            choice('accent', 'Colour', list(colour_names().items())),
            choice('backgrounds', 'Backgrounds', list(background_names().items())),
            choice('iconStroke', 'Stroke of the icons', [('regular', 'Normal'), ('light', 'Thin'),
                                                         ('auto', 'Automatic: thin from 24 px')]),
            choice('iconInk', 'Colour of the icons', [('soft', 'Soft'), ('full', 'Full, as the text')]),
            choice('iconDuo', 'Second colour of the icons', [('neutral', 'Neutral'), ('warm', 'Warm')]),
            choice('text_size', 'Size of the text', [('small', 'Small (12 px)'), ('medium', 'Medium (13 px)'), ('large', 'Large (14 px)')]),
            choice('font', 'Font', [('inter', 'Inter'), ('plex', 'IBM Plex Sans, condensed in the bar')]),
            choice('density', 'Density of the lists', [('normal', 'Normal'), ('compact', 'Compact')]),
            choice('toolbar', 'Bar of the phase', [('text', 'Words under the icons'), ('icons', 'Icons only'),
                                                   ('small', 'Small buttons on two rows')]),
            choice('toolbar_place', 'Where', [('top', 'Under the row of the phases'), ('left', 'On the left side, icons only')]),
            choice('language', 'Language', [('it', 'Italiano'), ('en', 'English')]),
            {'key': 'menu_bar', 'label': tr('Menu bar'), 'kind': 'bool', 'enabled': True, 'description': ''},
            {'key': 'phaseMotion', 'label': tr('Animations when the phase changes'), 'kind': 'bool', 'enabled': True,
             'description': ''},
            {'key': 'reduced_motion', 'label': tr('Reduce motion'), 'kind': 'bool', 'enabled': True, 'description': ''}], 'keyboard': []}

    @Slot(str)
    def showSection(self, key):
        self._section = key
        self.changed.emit()

    @Slot(str, 'QVariant')
    def setValue(self, key, value):
        ctl = self.scaffold.controller
        if isinstance(value, QJSValue):
            value = value.toVariant()
        self._undo = ctl.settings.values
        if key in ('reduced_motion', 'language'):
            ctl.settings.set_value('reducedMotion' if key == 'reduced_motion' else key, bool(value) if key == 'reduced_motion' else value)
        elif key in ('toolbar', 'toolbar_place', 'menu_bar'):
            if ctl.window:
                prop = {'toolbar': 'toolbarMode', 'toolbar_place': 'toolbarPosition', 'menu_bar': 'menuAlways'}[key]
                ctl.window.setProperty(prop, 'under' if key == 'toolbar' and value == 'text' else value)
                if key == 'menu_bar':
                    ctl.window.setProperty('menuOpen', value)
                ctl.settings.set_value('layout', ctl.capture_layout())
        else:
            appearance = ctl.settings.values['appearance']
            appearance['textSize' if key == 'text_size' else key] = value
            ctl.settings.set_value('appearance', appearance)
        ctl.settings.save()

    @Slot(str, 'QVariant')
    def stageValue(self, key, value):
        self._pending[key] = value

    @Slot()
    def flushPending(self):
        for key, value in self._pending.items():
            self.setValue(key, value)
        self._pending.clear()

    @Slot()
    def undoLast(self):
        if self._undo:
            previous, self._undo = self._undo, None
            for key in ('appearance', 'reducedMotion', 'language', 'layout'):
                self.scaffold.controller.settings.set_value(key, previous[key])
            window = self.scaffold.controller.window
            if window and previous['layout'].get('workbench'):
                window.restoreLayout(previous['layout']['workbench'])
            self.scaffold.controller.settings.save()

    @Slot(str)
    def restoreDefaults(self, section):
        if section == 'appearance':
            ctl = self.scaffold.controller
            self._undo = ctl.settings.values
            ctl.settings.set_value('appearance', {'theme': 'system', 'accent': 'indigo',
                'backgrounds': 'meridiana', 'font': 'plex', 'textSize': 'medium', 'density': 'normal', 'phaseMotion': False,
                **icons.DEFAULTS})
            ctl.settings.set_value('reducedMotion', False)
            if ctl.window:
                ctl.window.setProperty('toolbarMode', 'under')
                ctl.window.setProperty('toolbarPosition', 'top')
                ctl.window.setProperty('menuAlways', False)
                ctl.window.setProperty('menuOpen', False)
            ctl.settings.save()
        else:
            self.scaffold.resetShortcut('')

    @Slot(str)
    def requestCommand(self, key):
        self.scaffold.trigger(key)


class Properties(QObject):
    changed = Signal()
    formAdded = Signal(str)
    formChanged = Signal()
    epochChanged = Signal()

    def __init__(self, scaffold, host):
        super().__init__(scaffold)
        self.host, self._closed = host, set()
        if host and hasattr(host, 'sectionsChanged'):
            host.sectionsChanged.connect(self.changed)
        if host and hasattr(host, 'epochChanged'):
            host.epochChanged.connect(self.epochChanged)

    sections = Property('QVariantList', lambda self: self.host.sections if self.host else [], notify=changed)
    formKeys = Property('QStringList', lambda self: [], constant=True)
    currentForm = Property(str, lambda self: '', constant=True)
    kind = Property(str, lambda self: '', constant=True)
    error = Property(str, lambda self: '', constant=True)
    confirmation = Property('QVariantMap', lambda self: {}, constant=True)
    epoch = Property(int, lambda self: self.host.epoch if self.host else 0, notify=epochChanged)
    labels = Property('QVariantMap', lambda self: self.host.labels if self.host else {
        'cancel': 'Cancel', 'accept': 'Apply', 'again': 'Again', 'adapt': 'Adapt'}, notify=changed)

    @Slot(int)
    def highlightSide(self, side):
        if self.host and hasattr(self.host, 'highlightSide'):
            self.host.highlightSide(side)

    @Slot(str)
    def trigger(self, key):
        if self.host and hasattr(self.host, 'trigger'):
            self.host.trigger(key)

    @Slot(str, result=bool)
    def closed(self, key):
        return key in self._closed

    @Slot(str)
    def toggle(self, key):
        self._closed.symmetric_difference_update({key})
        self.changed.emit()

    @Slot(str, 'QVariant', int, result=bool)
    def commit(self, key, value, epoch):
        return bool(self.host and self.host.commit(key, value, epoch))


class Tasks(QObject):
    changed = Signal()
    showDialog = Signal(str)

    def __init__(self, scaffold):
        super().__init__(scaffold)
        self.scaffold = scaffold
        self._draft = {}
        self._seen = ''
        self._bindings = {}
        scaffold.controller.dialogs.changed.connect(self.follow)

    @Slot()
    def follow(self):
        current = self.scaffold.controller.dialogs.current
        if current == 'shortcuts' and self._seen != current:
            self._bindings = {c.id: [c.shortcut] if c.shortcut else [] for c in self.scaffold.controller._commands.values()}
        self._seen = current
        self.changed.emit()
        if current and current != 'close':
            self.showDialog.emit(current)

    kind = Property(str, lambda self: self.scaffold.controller.dialogs.current, notify=changed)
    source = Property('QUrl', lambda self: QUrl(self.scaffold.controller.dialogs.content.get('source', '')), notify=changed)
    state = Property('QVariantMap', lambda self: dict(self.scaffold.controller.dialogs.content,
        valid=self.scaffold.controller.dialogs.content.get('valid', True), shortcuts=[dict(row, keys=', '.join(self._bindings.get(row['id'], []))) for row in self.scaffold.shortcut_rows()]), notify=changed)
    busy = Property(bool, lambda self: False, constant=True)
    canShare = Property(bool, lambda self: callable(self.scaffold.services.get('feedback')), constant=True)
    message = Property(str, lambda self: self.scaffold.controller.dialogs.content.get('message', ''), notify=changed)
    rows = Property('QVariantList', lambda self: [], constant=True)
    columns = Property('QVariantList', lambda self: [], constant=True)
    labels = Property('QVariantMap', lambda self: dict(self.scaffold.preferences.text,
        shortcutsSearch=self.scaffold.tr('Search commands'), accept=self.scaffold.tr('OK'),
        close=self.scaffold.tr('Close'), shortcuts=self.scaffold.tr('Keyboard shortcuts'),
        intro=self.scaffold.tr('Describe what happened.'), title=self.scaffold.tr('Title'), description=self.scaffold.tr('Description'),
        environment=self.scaffold.tr('Include environment'), preview=self.scaffold.tr('Preview'),
        copyDraft=self.scaffold.tr('Copy draft'), openDraft=self.scaffold.tr('Open draft'),
        copy=self.scaffold.tr('Copy'), command=self.scaffold.tr('Command'),
        defaults=self.scaffold.tr('Defaults'), keyboardNote=self.scaffold.tr('Click a command to change its shortcut.')),
        notify=changed)

    @Slot(result=str)
    def about(self):
        return self.scaffold.services.get('about_text', lambda: '')()

    @Slot(str, str, bool, result=str)
    def preview(self, title, description, environment):
        return title + '\n\n' + description

    @Slot(str, str, bool, bool)
    def shareDraft(self, title, description, environment, open_draft):
        callback = self.scaffold.services.get('feedback')
        if callback:
            callback(title, description, environment, open_draft)
        elif not open_draft:
            from PySide6.QtGui import QGuiApplication
            QGuiApplication.clipboard().setText(self.preview(title, description, environment))

    @Slot()
    def cancel(self):
        self.scaffold.controller.dialogs.dismiss()

    @Slot()
    def accept(self):
        if self.kind == 'shortcuts':
            ctl = self.scaffold.controller
            for key, keys in self._bindings.items():
                ctl.command(key).set_state(shortcut=', '.join(keys))
            values = ctl.settings.values['layout']
            values['shortcuts'] = {c.id: c.shortcut for c in ctl._commands.values()}
            ctl.settings.set_value('layout', values)
            ctl.settings.save()
        callback = self.scaffold.controller.dialogs.content.get('accept')
        if callable(callback):
            callback()
        self.cancel()

    @Slot(int, int, result=str)
    def captureKey(self, key, modifiers):
        from PySide6.QtGui import QKeySequence
        return QKeySequence(Qt.KeyboardModifier(modifiers) | Qt.Key(key)).toString()

    @Slot(str, str)
    def assignShortcut(self, key, shortcut):
        if key not in self._bindings or shortcut and shortcuts.problem(shortcut, self.scaffold.tr):
            return
        normalized = shortcuts.normalize(shortcut) if shortcut else ''
        if normalized:
            for other in shortcuts.clashes(self._bindings, key, normalized):
                self._bindings[other] = [value for value in self._bindings[other] if value != normalized]
        self._bindings[key] = [normalized] if normalized else []
        self.changed.emit()

    @Slot(str)
    def resetShortcut(self, key):
        for command in self.scaffold.controller._commands.values():
            if not key or key == command.id:
                default = self.scaffold.defaults[command.id]
                self._bindings[command.id] = [default] if default else []
        self.changed.emit()

    @Slot(str, str, result=str)
    def shortcutVerdict(self, key, shortcut):
        why = shortcuts.problem(shortcut, self.scaffold.tr)
        if why:
            return why
        others = shortcuts.clashes(self._bindings, key, shortcut)
        return self.scaffold.tr('{keys} is used by {what}: there it would stop working.').format(
            keys=shortcut, what=', '.join(self.scaffold.controller.command(cid).text for cid in others)) if others else ''


# services['workspaces'] (Scaffold._checked_workspaces): what a page may declare, and where the panels of the kit stand
WORKSPACE_KEYS = frozenset({'panels', 'zones', 'open', 'sizes', 'bottom_span'})
HOME_ZONES = {'project': 'left', 'properties': 'right', 'checks': 'bottom'}


class HelpBook(QObject):
    """The texts of the help next to things (Controls/Help.qml, HelpBubble.qml, a field's «?»: TextField.helpKey), from
    services['help'] = {key: {'text': ..., 'tip': ..., 'source': ...}}: Meridiana's helpBook backend without its manual
    and its assistant (Daniel 21/11/2026: the help of Quotario's search, «disegnamolo allo stile Meridiana»)."""

    def __init__(self, entries, parent=None):
        super().__init__(parent)
        self._entries = {key: dict(value) for key, value in dict(entries or {}).items()}

    labels = Property('QVariantMap', lambda self: {'manual': '', 'ask': ''}, constant=True)
    canAsk = Property(bool, lambda self: False, constant=True)

    @Slot(str, result='QVariantMap')
    def entry(self, key):
        found = self._entries.get(key, {})
        return {'key': key, 'text': found.get('text', ''), 'source': found.get('source', ''), 'manual': ''}

    @Slot(str, result=str)
    def tip(self, key):
        return self._entries.get(key, {}).get('tip', '')

    @Slot(str)
    def openManual(self, _manual):
        return

    @Slot(str)
    def ask(self, _key):
        return


class Scaffold(QObject):
    changed = Signal()
    catalogChanged = Signal()
    enabledChanged = Signal()
    commandRequested = Signal(str)

    def __init__(self, controller, services):
        super().__init__(controller)
        self.controller, self.services = controller, services
        self.tr = services.get('translate', lambda text: text)
        self.file_kind = services.get('file_kind', 'open')
        self.filters = services.get('file_filters', ['All files (*)'])
        # services['bottom_span']: 'wide' (the default, as Meridiana) the bottom panel under the left one and the
        # centre; 'center' only under the centre, with the left panel down to the foot as the right one
        self._bottom_span = services.get('bottom_span', 'wide')
        if self._bottom_span not in ('wide', 'center'):
            raise ValueError('Unknown bottom_span: ' + str(self._bottom_span))
        self._workspaces = self._checked_workspaces(services.get('workspaces'))
        self.defaults = {key: c.shortcut for key, c in controller._commands.items()}
        self._notice, self._notice_kind, self._notice_fading = '', '', False
        self._notice_of = ''
        self._catalog = {key: (c.text, c.label, c.shortcut, c.tip) for key, c in controller._commands.items()}
        self._closing, self._recovery = Closing(self), Recovery(self)
        self._work, self._properties = Work(self, services.get('work')), Properties(self, services.get('properties'))
        self._file, self._preferences = FilePage(self), Preferences(self)
        self._tasks = Tasks(self)
        controller.changed.connect(self.changed)
        for command in controller._commands.values():
            command.changed.connect(self._command_changed)
            command.changed.connect(self._file.stateChanged)
        controller.settings.changed.connect(self.changed)
        controller.files.changed.connect(self.changed)
        controller.files.finished.connect(self._file_finished)
        controller.changed.connect(self._follow_view)

    filePage = Property(QObject, lambda self: self._file, constant=True)
    preferences = Property(QObject, lambda self: self._preferences, constant=True)
    closing = Property(QObject, lambda self: self._closing, constant=True)
    recovery = Property(QObject, lambda self: self._recovery, constant=True)
    work = Property(QObject, lambda self: self._work, constant=True)
    properties = Property(QObject, lambda self: self._properties.host or self._properties, constant=True)
    tasks = Property(QObject, lambda self: self._tasks, constant=True)
    partSources = Property('QVariantMap', lambda self: {'file': '../File/WorkbenchFile.qml'}, constant=True)
    stalePhases = Property('QVariantList', lambda self: [], constant=True)
    staleTip = Property(str, lambda self: '', constant=True)
    # R564: why a command is off, beside it in the menus and under its name in the tooltip; nothing while it is on
    commandNote = Property('QVariantMap', lambda self: {c.id: c.note for c in self.controller._commands.values() if c.note}, notify=enabledChanged)
    commandEnabled = Property('QVariantMap', lambda self: {c.id: c.enabled for c in self.controller._commands.values()}, notify=enabledChanged)
    # A command with two states (Command.checked) is lit in the bar, in its side form and in the menus
    commandChecked = Property('QVariantMap', lambda self: {c.id: c.checked for c in self.controller._commands.values()}, notify=enabledChanged)
    # the sign of each command's state (Command.icon_on, icon_off): the bar, the side and the menus follow it live
    commandIcon = Property('QVariantMap', lambda self: {c.id: c.currentIcon for c in self.controller._commands.values()}, notify=enabledChanged)
    # services['page_tabs']: 'always' (the default) or 'several': the row of the tabs only when there is more than one page
    pageTabs = Property(bool, lambda self: self.services.get('page_tabs', 'always') != 'several' or len(self.controller._pages) > 1, constant=True)
    bottomSpan = Property(str, lambda self: self._bottom_span, constant=True)
    # services['workspaces']: one workspace for each page instead of one for the window (Meridiana)
    panelMemory = Property(str, lambda self: 'page' if self._workspaces is not None else 'window', constant=True)
    pagePanels = Property('QVariantMap', lambda self: {page: spec['panels'] for page, spec in (self._workspaces or {}).items()}, constant=True)
    pageSpans = Property('QVariantMap', lambda self: {page: spec['bottom_span'] for page, spec in (self._workspaces or {}).items()}, constant=True)
    summary = Property(str, lambda self: self.services.get('summary', lambda: '')(), notify=changed)
    notice = Property(str, lambda self: self._notice, notify=changed)
    noticeKind = Property(str, lambda self: 'busy' if self.controller.files._busy else self._kind(), notify=changed)
    noticeFading = Property(bool, lambda self: self._notice_fading and bool(self._kind()), notify=changed)
    metrics = Property('QVariantMap', lambda self: {'tall': 72, 'low': 44, 'lowWindow': arrangement.LOW_WINDOW,
        'tabHeight': Size.CONTROL+Space.XS, 'badge': Button.SMALL[0], 'cardPad': [Space.L-2, Space.S, Space.L-2, Space.S-1],
        'leftWidth': 310, 'rightWidth': 370, 'checksHeight': 230}, constant=True)

    @Property('QVariantMap', notify=changed)
    def words(self):
        source = {'title': 'Casa', 'file': 'File', 'properties': 'Properties', 'project': 'Project', 'checks': 'Details',
                      'close': 'Close', 'closeCard': 'Close the panel; View > Panels brings it back', 'tools': 'Tools',
                      'altTabs': 'Alt: as tabs', 'unsaved': 'Changes not saved yet: Ctrl+S saves them',
                      'dock': 'Dock', 'float': 'Float', 'group': 'Group', 'ungroup': 'Ungroup', 'cancel': 'Cancel', 'undo': 'Undo', 'saveAs': 'Save as…',
                      'appearance': 'Appearance', 'theme': 'Theme', 'light': 'Light', 'dark': 'Dark', 'system': 'System',
                      'backgrounds': 'Backgrounds', 'accent': 'Accent colour', 'font': 'Font', 'textSize': 'Size of the text',
                      'small': 'Small (12 px)', 'medium': 'Medium (13 px)', 'large': 'Large (14 px)', 'reducedMotion': 'Less motion',
                      'density': 'Density of the lists', 'normal': 'Normal', 'compact': 'Compact', 'more': 'More'}
        return {k: self.tr(v) for k, v in source.items()}

    def tool(self, command, family=True):
        """Meridiana's ShellBackend._tool: the name and the keys in the tooltip, the host's explanation under them; the
        alternatives of Command.more on the arrow of a split button, said on its face and on its strip. The bar shows
        Command.label (Meridiana's Tool.label), the tooltip and the menus the whole Command.text."""
        label = command.label
        tip = command.text + (' (' + command.shortcut + ')' if command.shortcut else '')
        if command.tip:
            tip += '\n' + command.tip
        more = [self.tool(self.controller.command(key), False) for key in command.more] if family else []
        strip = self.tr('All of them: {names} (the right button too)').format(names=', '.join([label, *(t['label'] for t in more)]))
        face_tip = tip
        if more:
            head, separator, rest = tip.partition('\n')
            face_tip = head + '. ' + self.tr('{n} more in the arrow').format(n=len(more)) + (separator + rest if rest else '')
        return {'command': command.id, 'title': command.text, 'label': label, 'icon': getattr(command, 'currentIcon', getattr(command, 'icon', 'folder-open')),
                    'tip': tip, 'faceTip': face_tip, 'stripTip': strip if more else '', 'keys': [command.shortcut] if command.shortcut else [],
                    'enabled': True, 'primary': False, 'fixed': False, 'danger': False, 'more': more}

    @Property('QVariantList', notify=catalogChanged)
    def phases(self):
        groups = self.services.get('toolbar_groups')
        default = [{'title': self.tr('Commands'), 'tools': [self.tool(c) for c in self.controller._commands.values()]}]
        def resolve(page):
            if not groups:
                return default
            return [dict(group, tools=[self.tool(self.controller.command(key)) for key in group['commands']])
                    if 'commands' in group else group for group in groups.get(page, default)]
        result, number = [], 0
        for p in self.controller._pages.values():
            if p.id in self.controller._hidden:
                continue
            number += bool(p.numbered)
            result.append({'id': p.id, 'title': p.title, 'number': str(number) if p.numbered else '',
                           'enabled': p.enabled, 'reason': p.reason, 'groups': resolve(p.id)})
        return result

    @Property('QVariantList', notify=catalogChanged)
    def keyCommands(self):
        return [{'id': c.id, 'keys': [c.shortcut]} for c in self.controller._commands.values() if c.shortcut]

    @Property('QVariantList', notify=catalogChanged)
    def menus(self):
        groups = self.services.get('menus') or [{'title': self.tr('File'),
            'commands': list(self.controller._commands), 'mnemonic': 'F'}]
        def command(key):
            c = self.controller.command(key)
            return {'id': c.id, 'text': c.text, 'keys': [c.shortcut] if c.shortcut else [], 'tip': c.tip, 'enabled': True}
        return [dict(group, commands=[command(key) for key in group['commands'] if self.controller.command(key)],
            submenus=group.get('submenus', []), mnemonic=group.get('mnemonic', '')) for group in groups]

    def _command_changed(self):
        catalog = {key: (c.text, c.label, c.shortcut, c.tip) for key, c in self.controller._commands.items()}
        if catalog != self._catalog:
            self._catalog = catalog
            self.catalogChanged.emit()
        self.enabledChanged.emit()

    def _follow_view(self):
        if self.controller.activeView == 'settings':
            self._file.selectSection('preferences:appearance')

    @Property('QVariantList', notify=catalogChanged)
    def backgrounds(self):
        from .style.theme import background_names
        return [{'id': key, 'text': value} for key, value in background_names(self.tr).items()]

    @Property('QVariantList', notify=catalogChanged)
    def accents(self):
        from .style.theme import colour_names
        return [{'id': key, 'text': value} for key, value in colour_names(self.tr).items()]

    fonts = Property('QVariantList', lambda self: [{'id': 'inter', 'text': 'Inter'}, {'id': 'plex', 'text': 'IBM Plex Sans'}], constant=True)

    def shortcut_rows(self):
        return [{'id': c.id, 'label': c.text, 'keys': c.shortcut, 'defaults': self.defaults[c.id]}
                for c in self.controller._commands.values()]

    def shortcutVerdict(self, key, shortcut):
        return self.tr('Shortcut already in use') if any(c.id != key and c.shortcut == shortcut for c in self.controller._commands.values()) else ''

    def assignShortcut(self, key, shortcut):
        if self.shortcutVerdict(key, shortcut):
            return
        command = self.controller.command(key)
        if command:
            command.set_state(shortcut=shortcut)
            values = self.controller.settings.values['layout']
            values['shortcuts'] = {c.id: c.shortcut for c in self.controller._commands.values()}
            self.controller.settings.set_value('layout', values)
            self.controller.settings.save()

    def resetShortcut(self, key):
        for command in self.controller._commands.values():
            if not key or command.id == key:
                self.assignShortcut(command.id, self.defaults[command.id])

    @Slot(str)
    def trigger(self, command):
        if not self.controller.trigger(command):
            if command in ('save', 'save_as'):
                self._file.request('save')
            else:
                self.commandRequested.emit(command)

    def _file_finished(self, status, message):
        # Save as is offered after a failed save only ('error'); a failed Open or New has the cross alone ('error-open')
        failed = 'error' if self.controller.files.operation == 'save' else 'error-open'
        kind = failed if status == 'error' else 'done' if status == 'success' else ''
        self.show_notice(message or (self.tr('Done') if status == 'success' else ''),
            ms=4000 if status == 'success' else 0, kind=kind)

    @Slot()
    def dismissNotice(self):
        """The cross of a notice that stays (R537: an error of a save)."""
        self._notice, self._notice_kind, self._notice_fading = '', '', False
        self.changed.emit()

    def _checked_workspaces(self, value):
        """services['workspaces'] = {page: {'panels': [ids], 'zones': {id: zone}, 'open': {id: bool},
        'sizes': {'left'|'right'|'bottom': px}, 'bottom_span': 'wide'|'center'}}: each page has its own panels and
        remembers its own arrangement (Daniel 21/11/2026: «in ogni fase dev'essere possibile creare un workspace
        indipendente»). A page left out has every panel. Without it the window has one workspace, as Meridiana."""
        if value is None:
            return None
        known = set(self.controller._panels) | {'properties'}
        pages = set(self.controller._pages)
        result = {}
        for page, spec in dict(value).items():
            if page not in pages or not isinstance(spec, dict) or set(spec) - WORKSPACE_KEYS:
                raise ValueError('Invalid workspace for page: ' + str(page))
            panels = list(spec.get('panels', sorted(known)))
            zones, opened, sizes = dict(spec.get('zones', {})), dict(spec.get('open', {})), dict(spec.get('sizes', {}))
            span = spec.get('bottom_span', self._bottom_span)
            if (set(panels) - known or set(zones) - known or set(opened) - known
                    or set(zones.values()) - {'left', 'right', 'bottom', 'floating'}
                    or set(sizes) - {'left', 'right', 'bottom'} or span not in ('wide', 'center')):
                raise ValueError('Invalid workspace for page: ' + str(page))
            result[page] = {'panels': panels, 'zones': zones, 'open': opened, 'sizes': sizes, 'bottom_span': span}
        return result

    @Slot(str, str, result=bool)
    def panelOnPage(self, key, page):
        spec = (self._workspaces or {}).get(page)
        return spec is None or key in spec['panels']

    @Slot(str, result='QVariantMap')
    def workspaceFor(self, page):
        """The page's workspace at its first visit: whether each panel is open, the zones and sizes the page declares
        (the others stay as the window has them), and the zones and sizes of the first start (Restore the layout)."""
        spec = (self._workspaces or {}).get(page, {})
        keys = list(self.controller._panels) + ['properties']
        homes = {key: HOME_ZONES.get(key, self.controller._panels.get(key, {}).get('zone', 'right')) for key in keys}
        opened = {key: self.hasPanel(key) and self.panelOnPage(key, page) and spec.get('open', {}).get(key, True)
                  for key in keys}
        metrics = self.metrics
        return {'zones': dict(spec.get('zones', {})), 'open': opened, 'sizes': dict(spec.get('sizes', {})),
                'homes': homes, 'firstSizes': {'left': metrics['leftWidth'], 'right': metrics['rightWidth'],
                                               'bottom': metrics['checksHeight']}}

    @Slot(str, result=bool)
    def hasPanel(self, key):
        return key in self.controller._panels or key == 'properties' and self._properties.host is not None

    @Slot(str, result=str)
    def panelTitle(self, key):
        return self.controller._panels.get(key, {}).get('title', self.words.get(key, key))

    @Slot(str, result=str)
    def panelSource(self, key):
        source = self.controller._panels.get(key, {}).get('source', '')
        return source.toString() if isinstance(source, QUrl) else str(source)

    @Slot(str, 'QVariant', result=str)
    def sideTip(self, edge, cards):
        """R549: a side's button says the side and what stands there now («Left side: Project»), or, hidden, what a
        click brings back; the left side with its key (Ctrl+B, as in VS Code)."""
        cards = cards.toVariant() if hasattr(cards, 'toVariant') else dict(cards or {})
        side = {'left': self.tr('Left side'), 'bottom': self.tr('Bottom side'), 'right': self.tr('Right side')}[edge]
        names = ', '.join(cards.get('titles') or ())
        what = (self.tr('{side}: {cards}') if cards.get('shown') else self.tr('{side}, hidden: {cards}')).format(side=side, cards=names)
        keys = [c.shortcut for c in self.controller._commands.values() if c.id == 'side_left' and c.shortcut] if edge == 'left' else ()
        return f'{what} ({keys[0]})' if keys else what

    @Slot(bool)
    def layoutRestored(self, previous):
        self._notice = (self.tr('The panels are back as they were before.') if previous else
                        self.tr('The panels are back as at the first start. {keys} again within {seconds} seconds brings back the arrangement before.').format(
                            keys=self.tr('Restore the default layout'), seconds=15))
        self.changed.emit()
        notice = self._notice

        def clear():
            if self._notice == notice:
                self._notice = ''
                self.changed.emit()
        QTimer.singleShot(15000, self, clear)

    @Slot(int, int, str, 'QVariantMap', result='QVariantMap')
    def layoutFor(self, width, height, phase, options):
        previous = arrangement.from_dict(options.get('previous', {}))
        choices = arrangement.Choices(previous=previous, pins=dict(self.services.get('layout_pins', {}), **options.get('pins', {})),
            toolbar=options.get('toolbar', 'text'), needs=options.get('needs', {}),
            bar_sides=2 * (Layout.EDGE + Space.L - 2), columns=tuple(options.get('columns', [310, 370])),
            checks=options.get('checks', 220))
        return asdict(arrangement.arrangement(width, height, phase, choices))

    @Slot('QVariantMap', 'QVariantMap', bool, result='QVariantMap')
    def arrangedSay(self, was, new, remembered):
        """ui/window.py _say_arranged: a line with what changed. The fields, for its Undo."""
        before, now = arrangement.from_dict(was), arrangement.from_dict(new)
        if before is None or now is None:
            return {'fields': []}
        fields = arrangement.changes(before, now)
        if remembered:
            self._tell(self.tr('The arrangement you left for this shape of the window is back.'))
        elif fields:
            what = {'checks_open': self.tr('Bottom panel closed') if not now.checks_open else self.tr('Bottom panel open again'),
                    'views': {'side': self.tr('views side by side'), 'stacked': self.tr('views one above the other'),
                              'one': self.tr('one view at a time')}[now.views],
                    'panels': self.tr('the side panels together') if now.panels == 'together' else self.tr('the side panels apart'),
                    'bar': {'under': self.tr('the words under the icons'), 'beside': self.tr('the words beside the icons'),
                            'icons': self.tr('the icons alone')}[now.bar]}
            self._tell(self.tr('The window changed shape: {what}.').format(what=', '.join(what[f] for f in fields)))
        return {'fields': list(fields)}

    @Slot('QVariantMap', 'QVariantMap', 'QVariantList', result='QVariantMap')
    def arrangePinned(self, pins, was, fields):
        return arrangement.pinned(pins, arrangement.from_dict(was), tuple(fields))

    @Slot()
    def arrangeBack(self):
        self._tell(self.tr('Back as it was: this shape of the window stays so until «Restore the default layout».'))

    @Slot(str, int, int, str, float, result=str)
    def glyphPath(self, family, size, weight, text, disc):
        """The same unhinted outline the Widgets phase disc fills."""
        font = QFont(family)
        font.setPixelSize(size)
        font.setWeight(QFont.Weight(weight))
        path = QPainterPath()
        path.addText(0, 0, font, text)
        center = path.boundingRect().center()
        path.translate(disc/2-center.x(), disc/2-center.y())
        commands, index = [], 0
        while index < path.elementCount():
            element = path.elementAt(index)
            if element.isCurveTo():
                points = [path.elementAt(index+i) for i in range(3)]
                commands.append('C'+' '.join(f'{p.x:.4f},{p.y:.4f}' for p in points))
                index += 3
            else:
                commands.append(('M' if element.isMoveTo() else 'L')+f'{element.x:.4f},{element.y:.4f}')
                index += 1
        return ' '.join(commands)

    def _tell(self, text, ms=15000):
        self._notice = text
        self.changed.emit()

        def clear():
            if self._notice == text:
                self._notice = ''
                self.changed.emit()
        QTimer.singleShot(ms, self, clear)

    @Slot(str)
    def show_notice(self, text, ms=15000, kind=''):
        """A sentence of a part in the status bar for a while (QStatusBar.showMessage): one line. R537: `kind`
        'busy' (a save going on), 'done' (the save done: it fades out at its end, Theme.motion.SLOW), 'error' or
        'error-open' (they stay until closed, a plain sentence of another part does not cover them); `ms` 0: until
        replaced. The kind belongs to its sentence: another one written in its place (_tell) has none."""
        if self._kind().startswith('error') and not kind:
            return
        self._notice = self._notice_of = ' · '.join(line for line in str(text).splitlines() if line)
        self._notice_kind = kind
        self._notice_fading = False
        self.changed.emit()
        notice = self._notice
        if not ms:
            return
        fade = Motion.SLOW if kind == 'done' else 0

        def fading():
            if self._notice == notice:
                self._notice_fading = True
                self.changed.emit()

        def clear():
            if self._notice == notice:
                self._notice, self._notice_kind, self._notice_fading = '', '', False
                self.changed.emit()
        if fade:
            QTimer.singleShot(max(0, ms - fade), self, fading)
        QTimer.singleShot(ms, self, clear)

    def _kind(self):
        return self._notice_kind if self._notice and self._notice == self._notice_of else ''
