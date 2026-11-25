# SPDX-License-Identifier: GPL-3.0-or-later
"""Lazy accessible rows/cells, independent of recycled visual delegates.

No interfaces are created per rendered cell. A native client requests rows and
cells on demand. Keys survive resets; detached entries become invalid. Each
window owns its interface cache until Qt destroys the underlying object.
"""
import weakref

from PySide6.QtCore import QPointF, QRect
from PySide6.QtGui import QAccessible, QAccessibleInterface, QAccessibleObject
from shiboken6 import isValid

_tables = {}


class _Node(QAccessibleInterface):
    def __init__(self, table, key, column=None):
        super().__init__()
        self.table, self.key, self.column = table, key, column
        self.cells = {}

    def isValid(self):
        return (self.table.isValid() and self.table.model is not None and self.table.model.rowForKey(self.key) >= 0
                and (self.column is None or any(c['key'] == self.column for c in self.table.columns)))

    def object(self):
        return None

    def window(self):
        return self.table.object().window() if self.table.isValid() else None

    def parent(self):
        return self.table if self.column is None else self.table.row(self.key)

    def role(self):
        return QAccessible.Role.Row if self.column is None else QAccessible.Role.Cell

    def childCount(self):
        return len(self.table.columns) if self.column is None and self.isValid() else 0

    def child(self, index):
        if not 0 <= index < self.childCount():
            return None
        key = self.table.columns[index]['key']
        if key not in self.cells:
            self.cells[key] = _Node(self.table, self.key, key)
        return self.cells[key]

    def indexOfChild(self, child):
        return next((i for i, c in enumerate(self.table.columns) if c['key'] == child.column), -1) if isinstance(child, _Node) else -1

    def childAt(self, x, y):
        return next((self.child(i) for i in range(self.childCount()) if self.child(i).rect().contains(x, y)), None)

    def focusChild(self):
        return next((self.child(i) for i in range(self.childCount()) if self.child(i).state().focused), None)

    def text(self, kind):
        if not self.isValid():
            return ''
        if kind not in (QAccessible.Text.Name, QAccessible.Text.Value):
            return ''
        if self.column is None:
            return self.table.model.fullText(self.key, self.table.columns[0]['key']) if self.table.columns else ''
        metadata = next((c for c in self.table.columns if c['key'] == self.column), None)
        value = self.table.model.fullText(self.key, self.column)
        return f'{metadata["title"]}: {value}' if metadata and kind == QAccessible.Text.Name else value

    def setText(self, kind, text):
        # The table is read-only, including its accessibility interface.
        return None

    def rect(self):
        if not self.isValid():
            return QRect()
        return self.table.visual_rect(self.key, self.column)

    def state(self):
        result = QAccessible.State()
        result.readOnly = True
        result.invalid = not self.isValid()
        if not result.invalid:
            state = self.table.object().property('state')
            result.selectable = True
            result.focusable = True
            result.selected = bool(state and self.key in state.selectedKeys)
            result.focused = bool(state and state.currentKey == self.key and
                                  (self.column is None or state.currentColumn == self.column))
            row = self.table.model.rowForKey(self.key)
            decor = self.table.model.data(self.table.model.index(row, 0), 256) or 0
            result.expandable = self.column is None and ((decor >> 8) & 3) in (1, 2)
            result.expanded = result.expandable and bool(decor & 1024)
            result.invisible = self.rect().isEmpty()
        return result


class AccessibleTable(QAccessibleObject):
    def __init__(self, root):
        super().__init__(root)
        self._root_ref = weakref.ref(root)
        self.rows = {}

    @property
    def model(self):
        return self.object().property('model') if self.isValid() else None

    @property
    def columns(self):
        controller = self.object().property('columns') if self.isValid() else None
        return controller.items if controller else []

    def isValid(self):
        root = self._root_ref()
        return root is not None and isValid(root)

    def role(self):
        return QAccessible.Role.Table

    def state(self):
        result = QAccessible.State()
        result.readOnly = True
        result.multiSelectable = True
        return result

    def text(self, kind):
        return self.object().property('accessibilityName') if kind == QAccessible.Text.Name else ''

    def setText(self, kind, text):
        return None

    def parent(self):
        item = self.object().parentItem()
        return QAccessible.queryAccessibleInterface(item) if item else None

    def rect(self):
        root = self.object()
        window = root.window()
        if not window:
            return QRect()
        point = window.mapToGlobal(root.mapToScene(QPointF()).toPoint())
        return QRect(point, root.size().toSize())

    def row(self, key):
        if key not in self.rows:
            self.rows[key] = _Node(self, key)
        return self.rows[key]

    def childCount(self):
        return self.model.rowCount() if self.model else 0

    def child(self, index):
        return self.row(self.model.rowKey(index)) if 0 <= index < self.childCount() else None

    def indexOfChild(self, child):
        return self.model.rowForKey(child.key) if isinstance(child, _Node) and child.table is self and self.model else -1

    def childAt(self, x, y):
        view = self.object().property('view')
        if not view:
            return None
        return next((self.child(i) for i in range(max(0, view.property('topRow')), min(self.childCount(), view.property('bottomRow')+1))
                     if self.child(i).rect().contains(x, y)), None)

    def focusChild(self):
        state = self.object().property('state')
        return self.row(state.currentKey) if state and state.currentKey else None

    def visual_rect(self, key, column):
        row = self.model.rowForKey(key)
        index = next((i for i, c in enumerate(self.columns) if c['key'] == column), -1)
        result = QRect()
        def visit(item):
            nonlocal result
            name = item.objectName()
            if item.isVisible() and name.startswith(f'dataCell-{row}-') and (index < 0 or name == f'dataCell-{row}-{index}'):
                point = item.window().mapToGlobal(item.mapToScene(QPointF()).toPoint())
                cell = QRect(point, item.size().toSize())
                result = result.united(cell)
            for child in item.childItems():
                visit(child)
        visit(self.object())
        view = self.object().property('view')
        if not view or not view.window():
            return QRect()
        origin = view.window().mapToGlobal(view.mapToScene(QPointF()).toPoint())
        return result.intersected(QRect(origin, view.size().toSize()))


def factory(class_name, obj):
    meta = obj.metaObject()
    while meta:
        if meta.className().startswith('DataTable_QMLTYPE_'):
            key = id(obj)
            if key not in _tables:
                _tables[key] = AccessibleTable(obj)
                obj.destroyed.connect(lambda _obj=None, key=key: _tables.pop(key, None))
            return _tables[key]
        meta = meta.superClass()
    return None


def install():
    QAccessible.installFactory(factory)
