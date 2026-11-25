import QtQuick
import QtQuick.Templates as T
import Casa.Theme

// Exactly one field over the original cell, never a popup: read-only to read and copy a cell's whole text, writable in
// a column the host declares editable (DataTable.editable, 21/11/2026, Quotario modifying a bill): Enter commits, Esc
// cancels, Tab commits and goes to the next editable cell; the host may refuse the value and say why (`reason`).
Flickable {
    id: editor
    property alias text: field.text
    property alias font: field.font
    property alias selectedText: field.selectedText
    property alias field: field
    property color backgroundColor: Theme.colors.card
    property real lead: 8
    property bool litSide: false
    property real litInset: 0
    property bool editing: false
    // the text where the cell had it (Daniel 21/11/2026: opened on a long text the words jumped: 4 px at the top, the
    // whole text wrapped in the row's height and scrolled to the word): the cell's top, its alignment; the field as tall
    // as its text while it is open (DataTable.openText)
    property real textTop: 4
    property bool alignRight: false
    property string reason: ""
    signal dismissed()
    signal committed(bool onward)
    signal focusLeft()
    signal changed()
    onVisibleChanged: changed()
    onContentYChanged: changed()
    clip: true
    contentWidth: width
    contentHeight: Math.max(height, field.contentHeight+2*textTop)
    objectName: "cellText"
    function open(position) {
        field.forceActiveFocus()
        field.cursorPosition = Math.min(position, field.length)
        field.selectWord()
        field.ensureVisible()
    }
    Rectangle { parent: editor; anchors.fill: parent; color: editor.backgroundColor; z: -1 }
    T.TextArea {
        id: field
        objectName: "cellTextField"
        width: editor.width; height: Math.max(editor.height, contentHeight+2*editor.textTop)
        padding: 0; leftPadding: editor.lead; rightPadding: 8; topPadding: editor.textTop; bottomPadding: editor.textTop
        horizontalAlignment: editor.alignRight ? TextEdit.AlignRight : TextEdit.AlignLeft
        readOnly: !editor.editing; selectByMouse: true; persistentSelection: true
        wrapMode: TextEdit.Wrap
        textFormat: TextEdit.PlainText
        color: Theme.colors.text
        selectionColor: Theme.colors.accent
        background: null
        function ensureVisible() {
            if (cursorRectangle.y < editor.contentY) editor.contentY = cursorRectangle.y
            if (cursorRectangle.y+cursorRectangle.height > editor.contentY+editor.height)
                editor.contentY = cursorRectangle.y+cursorRectangle.height-editor.height
        }
        onCursorRectangleChanged: ensureVisible()
        onTextChanged: { editor.changed(); if (editor.editing) editor.reason = "" }
        onSelectionStartChanged: editor.changed()
        onSelectionEndChanged: editor.changed()
        onActiveFocusChanged: if (!activeFocus && editor.visible) editor.focusLeft()
        // Esc and Enter close the field here first, before the window's Esc (as ChecksPage.qml in Meridiana)
        Keys.onShortcutOverride: event => {
            event.accepted = event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || editor.editing && event.key === Qt.Key_Tab
        }
        Keys.onPressed: event => {
            const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            if (editor.editing && (enter && !(event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Tab)) {
                editor.committed(event.key === Qt.Key_Tab); event.accepted = true
            } else if (event.key === Qt.Key_Escape || !editor.editing && enter) {
                editor.dismissed(); event.accepted = true
            }
        }
    }
    // the host's reason for refusing the value, under the field, until the text changes
    ToolTip { parent: editor; objectName: "cellTextReason"; text: editor.reason; visible: editor.visible && editor.reason !== "" }
    Rectangle { parent: editor; x: editor.litInset; width: 3; height: parent.height; color: Theme.colors.accent; visible: editor.litSide; z: 1 }
}
