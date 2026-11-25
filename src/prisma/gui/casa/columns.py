# SPDX-License-Identifier: GPL-3.0-or-later
"""Keyed column preferences and a flat projection with two hot roles."""
from dataclasses import asdict, dataclass

from PySide6.QtCore import (
    Property,
    QAbstractProxyModel,
    QModelIndex,
    QObject,
    Signal,
    Slot,
)

from .surface import release_when_destroyed


@dataclass
class Column:
    key: str
    title: str
    numeric: bool = False
    minimum: float = 72
    preferred: float = 90
    visible: bool = True
    flexible: bool = False
    elide: str = 'right'
    # a fixed column (e.g. the first, with the arrow that opens a row) is not moved, nor does one land among the
    # fixed ones at the start
    fixed: bool = False
    # the most this column takes when it grows with the room left; None (the default) is no limit: a limit is the
    # host's, declared for its column, never a number of the kit
    max_width: float | None = None


class ColumnsController(QObject):
    changed = Signal()
    structureChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._columns = []
        self._layout = []
        self._viewport = 0
        self._scrollbar = 0
        self._manual = set()
        self._natural = {}

    items = Property('QVariantList', lambda self: self._layout, notify=changed)
    allColumns = Property('QVariantList', lambda self: [asdict(c) for c in self._columns], notify=changed)

    def configure(self, columns):
        values = [Column(**asdict(c)) if isinstance(c, Column) else Column(**c) for c in columns]
        if len({c.key for c in values}) != len(values):
            raise ValueError('Duplicate column key')
        for i, c in enumerate(values):
            if not c.key or c.minimum <= 0 or c.preferred <= 0 or c.elide not in ('middle', 'right', 'none'):
                raise ValueError('Invalid column metadata')
            if c.max_width is not None and c.max_width < c.minimum:
                raise ValueError('Invalid column metadata')
            c.source = i
            if c.key == 'description':
                c.minimum = max(200, c.minimum)
                c.preferred = max(260, c.preferred)
                c.flexible = True
        self._columns = values
        self._manual.clear()
        self._natural.clear()
        self._refresh()
        self.structureChanged.emit()

    def _refresh(self):
        previous = self._layout
        self.layout(self._viewport, self._scrollbar)
        if self._layout is previous:
            self.changed.emit()

    @Slot(float, float, result='QVariantList')
    def layout(self, viewport_width, scrollbar_width=0):
        # Flexible text columns share the spare room up to their caps. Columns sized by hand keep their widths.
        # Unclaimed room stays empty. If the minimums do not fit, the table scrolls sideways.
        self._viewport, self._scrollbar = viewport_width, scrollbar_width
        visible = [c for c in self._columns if c.visible]
        caps = [float('inf') if c.max_width is None else c.max_width for c in visible]
        widths = [max(c.minimum, min(cap, self._natural.get(c.key, c.preferred) if c.key not in self._manual
                                     else c.preferred)) for c, cap in zip(visible, caps, strict=True)]
        available = max(0, viewport_width - scrollbar_width)
        # a width given by hand stays as given, wider or narrower (Daniel 20/11/2026: the edge dragged did not follow
        # the pointer: the Description took back what the spare room lacked)
        sharing = [i for i, c in enumerate(visible) if c.flexible and not c.numeric and c.key not in self._manual]
        spare = available - sum(widths)
        while sharing and abs(spare) > 1e-6:
            share = spare / len(sharing)
            for i in list(sharing):
                wanted = widths[i] + share
                widths[i] = max(visible[i].minimum, min(caps[i], wanted))
                if widths[i] != wanted:
                    sharing.remove(i)
            spare = available - sum(widths)
        widths = [round(w, 2) for w in widths]
        rows = [dict(asdict(c), width=w, source=c.source) for c, w in zip(visible, widths, strict=True)]
        if rows != self._layout:
            self._layout = rows
            self.changed.emit()
        return rows

    @Slot('QVariantMap')
    def set_natural_widths(self, widths):
        """The measured widths of headings and values. Manual widths still take precedence."""
        if self._natural != widths:
            self._natural = widths
            self._refresh()

    def _find(self, key):
        return next((c for c in self._columns if c.key == key), None)

    @Slot(str, float)
    def resize(self, key, width):
        c = self._find(key)
        if c:
            # A flexible column before this one keeps the width it has: if it took up the room this one gives back, or
            # gave the room this one takes, the edge dragged would stay where it is (Daniel 20/11/2026: «il bordo della
            # colonna non segue il movimento del mouse», with Quotario's Description before the numbers)
            shown = {row['key']: row['width'] for row in self._layout}
            for other in self._columns:
                if other is c:
                    break
                if other.visible and other.flexible and other.key not in self._manual and other.key in shown:
                    other.preferred = shown[other.key]
                    self._manual.add(other.key)
            self._manual.add(key)
            c.preferred = max(c.minimum, width)
            self._refresh()

    @Slot(str, str)
    def move(self, key, before_key):
        c, before = self._find(key), self._find(before_key)
        if c and c is not before and not c.fixed:
            self._columns.remove(c)
            at = self._columns.index(before) if before else len(self._columns)
            lead = next((i for i, other in enumerate(self._columns) if not other.fixed), len(self._columns))
            self._columns.insert(max(at, lead), c)
            self._refresh()
            self.structureChanged.emit()

    @Slot(str, bool)
    def set_visible(self, key, visible):
        c = self._find(key)
        if c and c.visible != visible:
            c.visible = visible
            self._refresh()
            self.structureChanged.emit()

    @Slot(result='QVariantMap')
    def capture(self):
        return {'columns': [asdict(c) for c in self._columns], 'manual': sorted(self._manual)}

    @Slot('QVariantMap')
    def restore(self, state):
        self._manual = {key for key in state.get('manual', []) if self._find(key)}
        order = []
        for saved in state.get('columns', []):
            c = self._find(saved.get('key'))
            if c and c not in order:
                c.preferred = max(c.minimum, float(saved.get('preferred', c.preferred)))
                c.visible = bool(saved.get('visible', c.visible))
                order.append(c)
        self._columns = order + [c for c in self._columns if c not in order]
        self._refresh()
        self.structureChanged.emit()


class TableProjection(QAbstractProxyModel):
    """Reorder/hide columns without changing source identity or adding roles."""
    columnsChanged = Signal()
    # Emitted after the rows of a source reset are known, before any cell
    # is notified: the view places itself once, then reads the new data.
    refreshed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        release_when_destroyed(self)
        self._columns = None
        self._mapping = []
        self._connections = []
        self._columns_connection = None
        self._source = None
        self._rows = 0
        self._visible_first = 0
        self._visible_last = -1

    # A projection belongs to one virtualized view. Offscreen cells fetch fresh
    # data when reused; notifying their positional indices would make Quick
    # walk every row in a large source reset.
    firstVisibleRow = Property(int, lambda self: self._visible_first,
                               lambda self, value: setattr(self, '_visible_first', value))
    lastVisibleRow = Property(int, lambda self: self._visible_last,
                              lambda self, value: setattr(self, '_visible_last', value))

    def _set_columns(self, value):
        if self._columns_connection is not None:
            QObject.disconnect(self._columns_connection)
        self._columns = value
        if value:
            self._columns_connection = value.structureChanged.connect(self._rebuild)
        self._rebuild()
        self.columnsChanged.emit()

    columns = Property(QObject, lambda self: self._columns, _set_columns, notify=columnsChanged)

    def _rebuild(self):
        self.beginResetModel()
        self._mapping = [c['source'] for c in self._columns.items] if self._columns else []
        self.endResetModel()

    def setSourceModel(self, model):
        if model is self.sourceModel():
            return
        self.beginResetModel()
        for connection in self._connections:
            QObject.disconnect(connection)
        self._connections.clear()
        super().setSourceModel(model)
        self._source = model
        self._rows = model.rowCount() if model is not None else 0
        if model is not None:
            links = [
                (model.modelReset, self._refresh_rows),
                (model.rowsAboutToBeInserted, self._begin_insert),
                (model.rowsInserted, self._end_insert),
                (model.rowsAboutToBeRemoved, self._begin_remove),
                (model.rowsRemoved, self._end_remove),
                (model.dataChanged, self._data_changed),
            ]
            self._connections = [signal.connect(callback) for signal, callback in links]
        self.endResetModel()

    def _refresh_rows(self):
        # This projection exposes positional cells, not source persistent
        # indices. Keep Quick's delegate pool across a same-document reset.
        # Keyed selection/anchors are restored independently by TableState.
        # The view answers `refreshed`: it either rebuilds its cells at the
        # restored row or asks for the loaded ones with refreshVisible().
        old, new = self._rows, self._source.rowCount()
        if new < old:
            self.beginRemoveRows(QModelIndex(), new, old-1)
            self._rows = new
            self.endRemoveRows()
        elif new > old:
            self.beginInsertRows(QModelIndex(), old, new-1)
            self._rows = new
            self.endInsertRows()
        self.refreshed.emit()

    @Slot()
    def refreshVisible(self):
        first = max(0, self._visible_first)
        last = min(self._rows-1, self._visible_last)
        if first <= last and self._mapping:
            self.dataChanged.emit(self.index(first, 0), self.index(last, len(self._mapping)-1), [0, 256])

    @Slot(QModelIndex, int, int)
    def _begin_insert(self, parent, first, last):
        self.beginInsertRows(QModelIndex(), first, last)

    @Slot(QModelIndex, int, int)
    def _end_insert(self, parent, first, last):
        self._rows += last-first+1
        self.endInsertRows()

    @Slot(QModelIndex, int, int)
    def _begin_remove(self, parent, first, last):
        self.beginRemoveRows(QModelIndex(), first, last)

    @Slot(QModelIndex, int, int)
    def _end_remove(self, parent, first, last):
        self._rows -= last-first+1
        self.endRemoveRows()

    def _data_changed(self, first, last, roles):
        if self._mapping:
            self.dataChanged.emit(self.index(first.row(), 0), self.index(last.row(), len(self._mapping)-1), roles)

    def rowCount(self, parent=QModelIndex()):  # noqa: B008
        return self._rows if not parent.isValid() else 0

    def columnCount(self, parent=QModelIndex()):  # noqa: B008
        return len(self._mapping) if not parent.isValid() else 0

    def index(self, row, column, parent=QModelIndex()):  # noqa: B008
        return self.createIndex(row, column) if not parent.isValid() and 0 <= row < self._rows and 0 <= column < len(self._mapping) else QModelIndex()

    def parent(self, index):
        return QModelIndex()

    def mapToSource(self, index):
        return self._source.index(index.row(), self._mapping[index.column()]) if index.isValid() and self._source is not None else QModelIndex()

    def mapFromSource(self, index):
        if index.isValid() and index.column() in self._mapping:
            return self.index(index.row(), self._mapping.index(index.column()))
        return QModelIndex()

    def roleNames(self):
        return self.sourceModel().roleNames() if self.sourceModel() else {0: b'display', 256: b'decor'}

    def data(self, index, role=0):
        source = self.mapToSource(index)
        return self._source.data(source, role) if source.isValid() else None

    @Slot(int, result=int)
    def rowDecor(self, row):
        return int(self.data(self.index(row, 0), 256) or 0)

    @Slot(result=int)
    def countRows(self):
        return self.rowCount()
