# SPDX-License-Identifier: GPL-3.0-or-later
"""Casa section v1, no persistence. Load/save functions belong to the host."""
from copy import deepcopy
from dataclasses import dataclass

from PySide6.QtCore import Property, QObject, Signal, Slot

from .pages import indexed

VERSION = 1


@dataclass(frozen=True)
class Section:
    id: str
    title: str
    source: object = ''


class SettingsController(QObject):
    changed = Signal()

    def __init__(self, load=dict, save=lambda value: None, sections=(), parent=None):
        super().__init__(parent)
        self._save = save
        self._values = {'version': VERSION, 'appearance': {}, 'language': 'en',
                        'reducedMotion': False, 'geometry': {}, 'layout': {}}
        value = load()
        if isinstance(value, dict):
            self._values.update(deepcopy(value))
        self._sections = indexed(sections)

    values = Property('QVariantMap', lambda self: deepcopy(self._values), notify=changed)
    sections = Property('QVariantList', lambda self: [{'id': s.id, 'title': s.title, 'source': s.source}
                                                     for s in self._sections.values()], constant=True)

    @Slot(str, 'QVariant')
    def set_value(self, key, value):
        if key not in ('appearance', 'language', 'reducedMotion', 'geometry', 'layout'):
            return
        valid = {'appearance': dict, 'language': str, 'reducedMotion': bool, 'geometry': dict, 'layout': dict}
        if not isinstance(value, valid[key]):
            raise TypeError('Invalid Casa preference: ' + key)
        if key == 'language' and not value:
            raise ValueError('Empty language')
        self._values[key] = deepcopy(value)
        self.changed.emit()

    @Slot()
    def save(self):
        self._save(deepcopy(self._values))
