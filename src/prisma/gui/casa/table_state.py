# SPDX-License-Identifier: GPL-3.0-or-later
"""Per-view, in-memory keyed selection and reset anchors. No persistence."""
from PySide6.QtCore import Property, QObject, Signal, Slot


class TableState(QObject):
    changed = Signal()
    beforeReset = Signal()
    restoreRequested = Signal(int, float)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.model = None
        self._current = ''
        self._column = ''
        self._selected = []
        self._anchor = ''
        self._offset = 0.0
        self._lead = ''
        self._saved = None
        self._order = []
        self._filter_return = None
        self._filter_order = []
        self._filter_active = False

    currentKey = Property(str, lambda self: self._current, notify=changed)
    currentColumn = Property(str, lambda self: self._column, notify=changed)
    selectedKeys = Property('QStringList', lambda self: self._selected, notify=changed)
    anchorKey = Property(str, lambda self: self._anchor, notify=changed)

    @Slot(QObject)
    def bind_model(self, model):
        if self.model is model:
            return
        if self.model:
            self.model.modelAboutToBeReset.disconnect(self._before_reset)
            self.model.modelReset.disconnect(self._after_reset)
            self.model.rowsAboutToBeRemoved.disconnect(self._removing)
            self.model.rowsInserted.disconnect(self._rows_changed)
            self.model.rowsRemoved.disconnect(self._rows_changed)
        self.model = model
        self.clear()
        if model:
            model.modelAboutToBeReset.connect(self._before_reset)
            model.modelReset.connect(self._after_reset)
            model.rowsAboutToBeRemoved.connect(self._removing)
            model.rowsInserted.connect(self._rows_changed)
            model.rowsRemoved.connect(self._rows_changed)

    def _rows_changed(self, *_):
        self.changed.emit()

    @Slot()
    def clear(self):
        self._current = self._column = self._anchor = self._lead = ''
        self._selected = []
        self._offset = 0.0
        self._saved = self._filter_return = None
        self._filter_order = []
        self._filter_active = False
        self._order = []
        self.changed.emit()

    @Slot(str, float)
    def set_anchor(self, key, offset):
        self._anchor, self._offset = key, offset

    @Slot(str)
    def set_column(self, key):
        self._column = key
        self.changed.emit()

    @Slot(str)
    def set_current(self, key):
        self._current = key
        self.changed.emit()

    @Slot(bool)
    def set_filter_active(self, active):
        self._filter_active = active

    @Slot(str, int)
    def choose(self, key, modifiers):
        if not self.model or self.model.rowForKey(key) < 0:
            return
        if modifiers & 0x02000000 and self._lead:
            a, b = self.model.rowForKey(self._lead), self.model.rowForKey(key)
            a = max(0, a)
            interval = [self.model.rowKey(r) for r in range(min(a, b), max(a, b)+1)]
            self._selected = list(dict.fromkeys(self._selected+interval)) if modifiers & 0x04000000 else interval
        elif modifiers & 0x04000000:
            self._selected = [k for k in self._selected if k != key] if key in self._selected else self._selected + [key]
            self._lead = key
        else:
            self._selected = [key]
            self._lead = key
        self._current = key
        self.changed.emit()

    @Slot()
    def select_all(self):
        """Ctrl+A: every row the view shows (after the filters); the current row stays, or the first becomes it."""
        if not self.model or not self.model.rowCount():
            return
        self._selected = [self.model.rowKey(r) for r in range(self.model.rowCount())]
        if self.model.rowForKey(self._current) < 0:
            self._current = self._selected[0]
        self._lead = self._lead if self.model.rowForKey(self._lead) >= 0 else self._current
        self.changed.emit()

    @Slot()
    def clear_selection(self):
        """Esc: no row chosen; the current row stays where it is for the keys."""
        if self._selected:
            self._selected = []
            self.changed.emit()

    def _view_state(self):
        return {'anchor': self._anchor, 'offset': self._offset, 'current': self._current,
                'column': self._column, 'selection': list(self._selected), 'lead': self._lead}

    @Slot(result='QVariantMap')
    def capture_view(self):
        expansions = self.model.capture_expansions() if self.model and hasattr(self.model, 'capture_expansions') else []
        return self._view_state() | {'expansions': expansions}

    def _before_reset(self):
        self.beforeReset.emit()
        self._saved = self._view_state()
        # Only keys up to the anchor are needed for deletion fallback. Model
        # identity queries are reset work, never hot per-cell roles.
        row = self.model.rowForKey(self._anchor)
        self._order = [self.model.rowKey(i) for i in range(row+1)]

    def _after_reset(self):
        saved, self._saved = self._saved or self._view_state(), None
        previous, self._order = self._order, []
        if self._filter_return and not self._filter_active:
            saved, self._filter_return = self._filter_return, None
            previous, self._filter_order = self._filter_order, []
        if saved['anchor'] and self.model.rowForKey(saved['anchor']) < 0:
            if self._filter_active:
                if self._filter_return is None:
                    self._filter_return = saved.copy()
                    self._filter_order = previous
            else:
                saved = saved.copy()
                saved['anchor'] = next((k for k in reversed(previous) if self.model.rowForKey(k) >= 0), self.model.rowKey(0))
        self.restore_view(saved)

    def _removing(self, parent, first, last):
        removed = {self.model.rowKey(i) for i in range(first, last+1)}
        mother = self.model.rowKey(first-1)
        if self._current in removed:
            self._current = mother
        if self._lead in removed:
            self._lead = mother
        if removed.intersection(self._selected):
            self._selected = [k for k in self._selected if k not in removed]
            if mother and mother not in self._selected:
                self._selected.append(mother)
        self.changed.emit()

    @Slot('QVariantMap')
    def restore_view(self, state):
        self._anchor = state.get('anchor', '')
        self._offset = float(state.get('offset', 0))
        self._column = state.get('column', '')
        self._lead = state.get('lead', '')
        self._current = state.get('current', '')
        self._selected = list(state.get('selection', []))
        if self.model:
            row = self.model.rowForKey(self._anchor)
            row = max(row, 0)
            if self.model.rowForKey(self._current) < 0:
                self._current = self.model.rowKey(row)
            self._selected = [k for k in self._selected if self.model.rowForKey(k) >= 0]
            self.restoreRequested.emit(row, self._offset if self.model.rowForKey(self._anchor) >= 0 else 0)
        self.changed.emit()
