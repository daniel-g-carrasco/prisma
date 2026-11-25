# SPDX-License-Identifier: GPL-3.0-or-later
"""Dialog factories and geometry owned by one window, never a singleton."""
import math
from copy import deepcopy

from PySide6.QtCore import Property, QObject, QUrl, Signal, Slot


def content_copy(value):
    """Qt URLs need their copy constructor, not their locale-dependent pickle."""
    if isinstance(value, QUrl):
        return QUrl(value)
    if isinstance(value, dict):
        return {key: content_copy(item) for key, item in value.items()}
    if isinstance(value, list):
        return [content_copy(item) for item in value]
    if isinstance(value, tuple):
        return tuple(content_copy(item) for item in value)
    return deepcopy(value)


def rectangle(value, bounds):
    if (not isinstance(value, (list, tuple)) or len(value) != 4 or
            not all(type(n) in (int, float) and math.isfinite(n) for n in value)):
        return None
    bx, by, bw, bh = bounds
    x, y, w, h = value
    w, h = max(1, min(max(1, w), bw)), max(1, min(max(1, h), bh))
    return [max(bx, min(x, bx + bw - w)), max(by, min(y, by + bh - h)), w, h]


class DialogsController(QObject):
    changed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._factories, self._geometries = {}, {}
        self._current, self._content = '', {}
        self.bounds = [0, 0, 1000, 700]

    current = Property(str, lambda self: self._current, notify=changed)
    content = Property('QVariantMap', lambda self: content_copy(self._content), notify=changed)
    geometries = Property('QVariantMap', lambda self: deepcopy(self._geometries), notify=changed)
    currentGeometry = Property('QVariantList', lambda self: self.geometry(self._current), notify=changed)

    def register(self, key, factory):
        if not key or key in self._factories or not callable(factory):
            raise ValueError('Invalid or duplicate dialog: ' + key)
        self._factories[key] = factory

    @Slot(float, float)
    def set_bounds(self, width, height):
        self.bounds = [0, 0, max(1, width), max(1, height)]
        self.changed.emit()

    @Slot(str, result=bool)
    def open(self, key):
        if key not in self._factories:
            return False
        content = self._factories[key]()
        if not isinstance(content, dict):
            raise TypeError('Dialog factory must return a content dictionary')
        self._content, self._current = content, key
        self.changed.emit()
        return True

    @Slot()
    def dismiss(self):
        self._current, self._content = '', {}
        self.changed.emit()

    @Slot(str, 'QVariantList')
    def set_geometry(self, key, value):
        if key not in self._factories:
            return
        valid = rectangle(value, self.bounds)
        if valid:
            self._geometries[key] = valid
            self.changed.emit()

    def geometry(self, key):
        return rectangle(self._geometries.get(key, [40, 40, 480, 320]), self.bounds)

    def restore(self, values):
        if isinstance(values, dict):
            for key, value in values.items():
                self.set_geometry(key, value)
