import QtQuick
import Casa.Theme

// One Text per visible cell. Pointer handling and text selection live in DataTable.
Rectangle {
    id: cell
    // Pooled cells still observe table properties. Defer full text until the
    // view has assigned them a new row and column.
    property bool pooled: false
    TableView.onPooled: pooled = true
    TableView.onReused: pooled = false
    required property int row
    required property int column
    required property var display
    required property int decor
    required property var table
    readonly property var metadata: table.columnMeta[column] || ({key:"", title:"", numeric:false, elide:"right"})
    readonly property bool selected: table.selectedRows[row] === true
    readonly property int depth: (decor >> 1) & 127
    readonly property int kind: (decor >> 8) & 3
    readonly property bool expanded: (decor & 1024) !== 0
    readonly property real lead: column === 0 ? 9 + depth * 14 : 8
    readonly property var textItem: label
    readonly property string contentText: {
        if (pooled) return ""
        const compact = String(display)
        return table.wholeText && table.model ? table.model.fullText(table.model.rowKey(row), metadata.key) : compact
    }
    function renderedText() {
        return table.wholeText || table.elideText ? label.text : table.cutText(String(display), label.width, table.font, metadata.elide)
    }
    objectName: "dataCell-" + row + "-" + column
    implicitWidth: table.columnWidths[column] || 90
    implicitHeight: table.rowHeight
    color: selected ? (table.selectionActive ? table.selectionColor : table.inactiveSelectionColor)
                    : (decor & 1) ? table.bandColor : table.fill
    Accessible.role: Accessible.Cell
    Accessible.name: metadata.title + ": " + String(display)
    Accessible.selected: selected
    Accessible.focused: table.currentRow === row && table.currentColumnIndex === column
    Accessible.description: kind === 1 || kind === 2 ? (expanded ? "expanded" : "collapsed") : ""
    Rectangle { x: table.frameThickness; width: 3; height: parent.height; color: Theme.colors.accent; visible: cell.selected && cell.column === 0 }
    Text {
        id: label
        x: cell.lead
        y: table.wholeText ? 4 : (parent.height - height)/2
        width: Math.max(0, parent.width - x - 8 - (cell.column === 0 && (cell.kind === 1 || cell.kind === 2) ? 14 : 0))
        height: table.wholeText ? parent.height-8 : implicitHeight
        font: table.font
        color: Theme.colors.text
        textFormat: Text.PlainText
        wrapMode: table.wholeText ? Text.Wrap : Text.NoWrap
        horizontalAlignment: cell.metadata.numeric ? Text.AlignRight : Text.AlignLeft
        text: table.wholeText ? cell.contentText : table.elideText
            ? table.cutText(String(cell.display), width, font, cell.metadata.elide) : String(cell.display).replace(/\s+/g, " ").trim()
        elide: table.wholeText || table.elideText || cell.metadata.elide === "none" ? Text.ElideNone
               : cell.metadata.elide === "middle" ? Text.ElideMiddle : Text.ElideRight
    }
    Loader { x: parent.width-20; width: 14; height: 14
        y: table.wholeText ? label.y + (table.fontLineHeight-height)/2 : (parent.height-height)/2
        active: cell.column === 0 && (cell.kind === 1 || cell.kind === 2)
        sourceComponent: Chevron { open: cell.expanded; color: Theme.colors.text }
    }
    // Plain-text spans are painted behind the unchanged Text. No user data is
    // ever interpreted as markup. Build them only while search is active.
    Repeater {
        model: table.highlight && label.text.toLocaleUpperCase().includes(table.highlight.toLocaleUpperCase())
               ? table.highlightSpans(cell.renderedText(), label.width, label.font) : []
        delegate: Rectangle {
            required property var modelData
            x: label.x+modelData.x; y: label.y+modelData.y; width: modelData.width; height: modelData.height
            color: table.highlightColor; opacity: 0.25
        }
    }
}
