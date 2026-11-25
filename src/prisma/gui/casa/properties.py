# SPDX-License-Identifier: GPL-3.0-or-later
"""Meridiana's stable PropertyField with host-declared, domain-free sections."""
from PySide6.QtCore import Property, QLocale, QObject, Qt, Signal, Slot
from PySide6.QtGui import QFont, QFontMetrics


class PropertyField(QObject):
    """One persistent field. Value updates never destroy the editor or its draft."""
    changed = Signal()
    outlineChanged = Signal()

    # what the form's layout reads of a field (PropertyForm.qml: the label column, the companion beside it): told
    # apart from the value, so that a value changed lays out only its own editor, not every field of its section
    # (R598: 5-26 ms for one note changed, at every layout that comes)
    OUTLINE = ('id', 'label', 'kind', 'inlineWith', 'minimum', 'maximum', 'decimals', 'unit', 'special')

    def __init__(self, data, parent=None, *, format_number=None):
        super().__init__(parent)
        self._data = data
        self._number = format_number or (lambda value, decimals: QLocale().toString(float(value), "f", decimals))
        self._outline = self._outline_of(data)

    @classmethod
    def _outline_of(cls, data):
        return {key: data.get(key) for key in cls.OUTLINE if key in data}

    @Property('QVariantMap', notify=changed)
    def data(self):
        return self._data

    @Property('QVariantMap', notify=outlineChanged)
    def outline(self):
        return self._outline

    def update(self, data):
        if self._data != data:
            self._data = data
            outline = self._outline_of(data)
            if outline != self._outline:
                self._outline = outline
                self.outlineChanged.emit()
            self.changed.emit()

    @Slot(QFont, result='QVariantMap')
    def labelHint(self, font):
        """QLabel's plain-text size hint, without constructing a QWidget.

        Qt's QLabelPrivate::sizeForWidth tries 80, 40, then 20 average
        characters for a wrapped label. ui/style.py wraps labels over 28.
        This keeps QFormLayout's label column without guessing a fixed width.
        """
        text, metrics = self._data['label'], QFontMetrics(font)
        wrapped = len(text) > 28
        flags = Qt.TextFlag.TextWordWrap if wrapped else Qt.TextFlag.TextSingleLine
        width = metrics.averageCharWidth() * 80 if wrapped else 2000
        rect = metrics.boundingRect(0, 0, width, 2000, flags, text)
        if wrapped and rect.height() < 4 * metrics.lineSpacing() and rect.width() > width / 2:
            rect = metrics.boundingRect(0, 0, width // 2, 2000, flags, text)
        if wrapped and rect.height() < 2 * metrics.lineSpacing() and rect.width() > width / 4:
            rect = metrics.boundingRect(0, 0, width // 4, 2000, flags, text)
        return {'width': rect.width(), 'height': rect.height(), 'wrapped': wrapped}

    @Slot(QFont, result=int)
    def editorMinimum(self, font):
        """Qt's range-dependent minimum, with Meridiana's control style.

        QAbstractSpinBox measures both range ends, not the current value.
        Its two cursor pixels and our styled frame/buttons add 59 px.
        The eight-character combo includes the icon and styled arrow (60 px).
        Differential tests compare these dimensions with the actual Widgets.
        """
        data, metrics = self._data, QFontMetrics(font)
        if data['kind'] == 'choice':
            return 8 * metrics.horizontalAdvance('X') + 60
        if data['kind'] != 'number':
            return 80
        texts = []
        for value in (data['minimum'], data['maximum']):
            unit = data['unit']
            if unit in ('m', '°'):
                text = self._number(value, data['decimals']) + ('' if unit == '°' else ' ') + unit
            else:
                text = QLocale().toString(float(value), 'f', data['decimals'])
            texts.append(text[:18] + ' ')
        texts.append(data.get('special', ''))
        return max(metrics.horizontalAdvance(text) for text in texts) + 59


class PropertyModule(QObject):
    sectionsChanged = Signal()
    formAdded = Signal(str)
    formChanged = Signal()
    epochChanged = Signal()
    actionRequested = Signal(str)
    highlightRequested = Signal(int)

    def __init__(self, sections=(), *, commit=None, translate=str, empty=None, parent=None):
        super().__init__(parent)
        # with no section (nothing selected) the panel shows the empty state: {'title', 'description'} from the host
        self._empty = dict(empty or {})
        self._sections, self._fields, self._epoch = [], {}, 0
        self._forms, self._current_form = {}, ''
        self._commit, self._translate = commit, translate
        self.select(sections)

    sections = Property('QVariantList', lambda self: self._sections, notify=sectionsChanged)
    epoch = Property(int, lambda self: self._epoch, notify=epochChanged)
    labels = Property('QVariantMap', lambda self: {key: self._translate(value) for key, value in
        {'search': 'Search', 'cancel': 'Cancel', 'accept': 'Apply', 'again': 'Again', 'adapt': 'Adapt'}.items()}, constant=True)
    empty = Property('QVariantMap', lambda self: self._empty, constant=True)
    formKeys = Property('QStringList', lambda self: list(self._forms), notify=formChanged)
    currentForm = Property(str, lambda self: self._current_form, notify=formChanged)
    kind = Property(str, lambda self: self._current_form, notify=epochChanged)
    error = Property(str, lambda self: '', constant=True)
    confirmation = Property('QVariantMap', lambda self: {}, constant=True)

    @Slot(str, result='QVariantList')
    def formSections(self, key):
        return self._forms.get(key, [])

    @Slot(str)
    def confirm(self, choice):
        self.actionRequested.emit('confirm:'+choice)

    def select(self, sections):
        result, used = [], set()
        for section in sections:
            fields = []
            for declared in section.get('fields', ()):
                key = declared['id']
                if not key or key in used:
                    raise ValueError('Duplicate or empty property key: '+key)
                used.add(key)
                data = {'label': '', 'kind': 'text', 'value': '', 'tip': '', 'enabled': True, 'inlineWith': '', 'help': '',
                            'unit': '', 'side': -1, 'minimum': 0, 'maximum': 100000, 'decimals': 0, 'step': 1, 'options': []}
                data.update(declared)
                # several rows passed with different values (shared()): the placeholder «Different values», never
                # one of them; a value written goes to all of them, a field left alone changes nothing
                data.setdefault('mixedText', self._translate('Different values'))
                if data.get('mixed') is True:
                    data['display'] = ''
                data.setdefault('display', str(data['value']))
                field = self._fields.get(key)
                if field is None:
                    field = self._fields[key] = PropertyField(data, self)
                else:
                    field.update(data)
                fields.append(field)
            result.append(dict(section, fields=fields, help=section.get('help', ''), framed=section.get('framed', False)))
        self._sections = result
        shape = repr([(s['key'], s['title'], [(f.data['id'], f.data['kind']) for f in s['fields']]) for s in result])
        new = shape not in self._forms
        self._forms[shape] = result
        self._current_form = shape
        self._epoch += 1
        if new:
            self.formAdded.emit(shape)
        self.formChanged.emit()
        self.sectionsChanged.emit()
        self.epochChanged.emit()

    @Slot(str, 'QVariant', int, result=bool)
    def commit(self, key, value, epoch):
        if epoch != self._epoch or key not in self._fields or not callable(self._commit):
            return False
        if not self._commit(key, value):
            return False
        field = self._fields[key]
        field.update(dict(field.data, value=value, display=str(value), mixed=False))
        return True

    @staticmethod
    def shared(values):
        """The value of a field for several rows: `{'value': v}` when they all have `v`, else
        `{'value': '', 'mixed': True}` (the placeholder «Different values»). `dict(field, **shared(values))`."""
        values = list(values)
        if values and all(v == values[0] for v in values):
            return {'value': values[0]}
        return {'value': '', 'mixed': True}

    @Slot(str)
    def trigger(self, key):
        self.actionRequested.emit(key)

    @Slot(int)
    def highlightSide(self, side):
        self.highlightRequested.emit(side)
