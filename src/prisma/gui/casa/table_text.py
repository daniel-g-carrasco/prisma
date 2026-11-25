# SPDX-License-Identifier: GPL-3.0-or-later
"""Map elided plain text hits to full paragraphs, using UTF-16 QML offsets."""
import html

from PySide6.QtCore import Property, QEvent, QObject, Signal, Slot
from PySide6.QtGui import (
    QFont,
    QFontMetricsF,
    QGuiApplication,
    QTextLayout,
    QTextOption,
)
from PySide6.QtQuick import QQuickItem
from shiboken6 import isValid

from .surface import release_when_destroyed


def full_position(full, rendered, offset):
    position = len(rendered.encode('utf-16-le')[:offset*2].decode('utf-16-le', errors='ignore'))
    normalized, locations = [], []
    for n, char in enumerate(full):
        if not char.isspace():
            normalized.append(char)
            locations.append(n)
        elif normalized and normalized[-1] != ' ':
            normalized.append(' ')
            locations.append(n)
    flat = ''.join(normalized).rstrip()
    prefix = 0
    while prefix < min(len(flat), len(rendered)) and flat[prefix] == rendered[prefix]:
        prefix += 1
    suffix = 0
    while suffix < min(len(flat), len(rendered))-prefix and flat[-1-suffix] == rendered[-1-suffix]:
        suffix += 1
    if suffix and position >= len(rendered)-suffix:
        position += len(flat)-len(rendered)
    elif flat != rendered:
        position = min(position, max(0, prefix-1))
    original = locations[min(position, len(locations)-1)] if locations else 0
    return len(full[:original].encode('utf-16-le'))//2


class CellTextGuard(QObject):
    """One passive window filter while the inline field is open."""
    changed = Signal()
    outside = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        release_when_destroyed(self)
        self._window = None
        self._editor = None
        self._enabled = False

    def _set_window(self, value):
        if self._window and isValid(self._window):
            self._window.removeEventFilter(self)
        self._window = value
        if value:
            value.installEventFilter(self)
        self.changed.emit()

    def _set_editor(self, value):
        self._editor = value
        self.changed.emit()

    def _set_enabled(self, value):
        self._enabled = value
        self.changed.emit()

    window = Property(QObject, lambda self: self._window, _set_window, notify=changed)
    editorItem = Property(QQuickItem, lambda self: self._editor, _set_editor, notify=changed)
    enabled = Property(bool, lambda self: self._enabled, _set_enabled, notify=changed)

    def eventFilter(self, watched, event):
        if self._enabled and self._editor and isValid(self._editor):
            kind = event.type()
            if kind in (QEvent.Type.MouseButtonPress, QEvent.Type.MouseButtonDblClick, QEvent.Type.Wheel):
                if not self._editor.contains(self._editor.mapFromScene(event.position())):
                    self.outside.emit()
            elif kind == QEvent.Type.WindowDeactivate:
                self.outside.emit()
        return False


class TableText(QObject):
    def __init__(self, parent=None):
        super().__init__(parent)
        release_when_destroyed(self)
        self._elided = {}

    @Slot()
    def invalidate(self):
        self._elided.clear()

    @Slot(str, result=str)
    def tooltip(self, text):
        return '<span>' + html.escape(text).replace('\n', '<br/>') + '</span>'

    @Slot(str, float, QFont, bool, float, float, bool, result=int)
    def hit(self, text, width, font, wrapped, x, y, numeric):
        offset, top = 0, 0.0
        for paragraph in text.split('\n'):
            layout = QTextLayout(paragraph, font)
            option = QTextOption()
            option.setWrapMode(QTextOption.WrapMode.WrapAtWordBoundaryOrAnywhere if wrapped else QTextOption.WrapMode.NoWrap)
            layout.setTextOption(option)
            layout.beginLayout()
            answer = None
            while True:
                line = layout.createLine()
                if not line.isValid():
                    break
                line.setLineWidth(max(1, width))
                if top <= y < top+line.height():
                    shift = max(0, width-line.naturalTextWidth()) if numeric else 0
                    answer = offset+line.xToCursor(x-shift)
                top += line.height()
            layout.endLayout()
            if answer is not None:
                return answer
            offset += len(paragraph.encode('utf-16-le'))//2+1
        return max(0, offset-1)

    @Slot(str, str, float, QFont, bool, result='QVariantList')
    def spans(self, text, query, width, font, wrapped):
        if not query or query.casefold() not in text.casefold():
            return []
        rectangles, top = [], 0.0
        needle = query.casefold()
        for paragraph in text.split('\n'):
            folded, positions, offset = [], [], 0
            for char in paragraph:
                size = len(char.encode('utf-16-le'))//2
                for value in char.casefold():
                    folded.append(value)
                    positions.append((offset, offset+size))
                offset += size
            folded = ''.join(folded)
            matches, start = [], 0
            while True:
                found = folded.find(needle, start)
                if found < 0:
                    break
                matches.append((positions[found][0], positions[found+len(needle)-1][1]))
                start = found+len(needle)
            layout = QTextLayout(paragraph, font)
            option = QTextOption()
            option.setWrapMode(QTextOption.WrapMode.WrapAtWordBoundaryOrAnywhere if wrapped else QTextOption.WrapMode.NoWrap)
            layout.setTextOption(option)
            layout.beginLayout()
            while True:
                line = layout.createLine()
                if not line.isValid():
                    break
                line.setLineWidth(max(1, width))
                for left, right in matches:
                    a = max(left, line.textStart())
                    b = min(right, line.textStart()+line.textLength())
                    if b > a:
                        x1, x2 = line.cursorToX(a)[0], line.cursorToX(b)[0]
                        rectangles.append({'x': min(x1, x2), 'y': top, 'width': abs(x2-x1), 'height': line.height()})
                top += line.height()
            layout.endLayout()
        return rectangles

    @Slot(str, str, int, result=int)
    def fullPosition(self, full, rendered, offset):
        return full_position(full, rendered, offset)

    @Slot(str, float, QFont, str, result=str)
    def elide(self, text, width, font, mode):
        from PySide6.QtCore import Qt
        if mode == 'none':
            return text
        text = ' '.join(text.split())
        key = (text, round(width, 2), font.toString(), mode)
        if key not in self._elided:
            if len(self._elided) >= 8192:
                self._elided.clear()
            self._elided[key] = QFontMetricsF(font).elidedText(text, Qt.TextElideMode.ElideMiddle if mode == 'middle' else Qt.TextElideMode.ElideRight, max(1, width))
        return self._elided[key]

    @Slot(str)
    def copy(self, text):
        QGuiApplication.clipboard().setText(text)
