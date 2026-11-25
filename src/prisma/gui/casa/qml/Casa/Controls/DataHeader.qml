import QtQuick
import Casa.Theme

Rectangle {
    id: header
    required property var table
    color: Theme.colors.panel
    clip: true
    objectName: "dataHeader"
    // Moving a column by its title (Daniel 21/11/2026, "fatto semplice e visibile"): past the system's drag distance the
    // title follows the pointer as a small label, half seen through; a sharp line in the accent shows, live, where it
    // will land; the release moves it (ColumnsController.move, the order kept with the widths in capture()). Esc, or a
    // release out of the table, leaves everything as it was. Near the heading's edges the table scrolls. A fixed column
    // (Column.fixed, e.g. the first with the arrow that opens a row) does not move, and no line lands among the fixed
    // ones at the start. The other columns do not move until the release, and nothing is animated.
    property string dragKey: ""
    property string dragTitle: ""
    property int dragFrom: -1
    property int dropAt: -1
    property real dragX: 0
    property real dragY: 0
    property bool dragOutside: false
    property bool cancelled: false
    readonly property real threshold: Qt.styleHints.startDragDistance
    readonly property real scrollEdge: Theme.space.XXL
    readonly property int firstFree: {
        const items = table.columnItems
        let i = 0
        while (i < items.length && items[i].fixed) i++
        return i
    }
    readonly property bool dropChanges: dragKey !== "" && dropAt >= firstFree && dropAt !== dragFrom && dropAt !== dragFrom + 1
    function boundary(i) {
        let x = 0
        for (let k = 0; k < i && k < table.columnItems.length; k++) x += table.columnItems[k].width
        return x
    }
    function follow(x, y) {
        dragX = x; dragY = y
        dragOutside = x < 0 || x > table.width || y < 0 || y > table.height
        const content = x + table.view.contentX
        let best = firstFree, distance = Infinity
        for (let i = firstFree; i <= table.columnItems.length; i++) {
            const d = Math.abs(boundary(i) - content)
            if (d < distance) { distance = d; best = i }
        }
        dropAt = best
    }
    function cancelDrag() {
        const had = dragKey !== ""
        dragKey = ""; dragTitle = ""; dragFrom = -1; dropAt = -1; dragOutside = false
        if (had) table.forceActiveFocus()
    }
    function finishDrag() {
        if (dragKey && !dragOutside && dropChanges) {
            const items = table.columnItems
            table.columns.move(dragKey, dropAt < items.length ? items[dropAt].key : "")
        }
        cancelDrag()
    }
    Keys.onShortcutOverride: event => { event.accepted = dragKey !== "" && event.key === Qt.Key_Escape }
    Keys.onEscapePressed: event => {
        if (!dragKey) { event.accepted = false; return }
        cancelled = true
        cancelDrag()
    }
    Timer {
        objectName: "columnDragScroll"; interval: 16; repeat: true
        running: header.dragKey !== "" && (header.dragX < header.scrollEdge || header.dragX > header.width - header.scrollEdge)
        onTriggered: {
            const view = header.table.view
            const step = header.dragX < header.scrollEdge ? -Theme.space.L : Theme.space.L
            view.contentX = Math.max(0, Math.min(Math.max(0, view.contentWidth - view.width), view.contentX + step))
            header.follow(header.dragX, header.dragY)
        }
    }
    // the label at the pointer and the line where the column will land, over the whole table
    Rectangle {
        objectName: "columnDragLabel"; parent: header.table; z: 20
        visible: header.dragKey !== ""
        width: Math.min(dragText.implicitWidth + 2 * Theme.space.M, 2 * Theme.size.READING / 3)
        height: Math.max(0, header.height - 2 * Theme.space.XS)
        x: Math.round(header.dragX - width / 2); y: Math.round((header.height - height) / 2)
        // the ground of a selected row and an edge in the accent: it stands out from the heading's band
        radius: Theme.radius.CARD; color: Theme.colors.select_bg; border.width: 1; border.color: Theme.colors.accent
        opacity: 0.85
        Text { id: dragText; anchors.centerIn: parent; width: parent.width - 2 * Theme.space.M
            text: header.dragTitle; textFormat: Text.PlainText; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
            font.family: header.table.font.family; font.pixelSize: header.table.font.pixelSize; color: Theme.colors.text }
    }
    Rectangle {
        objectName: "columnDropLine"; parent: header.table; z: 21; antialiasing: false
        visible: header.dropChanges && !header.dragOutside
        width: 2; height: header.table.height; y: 0
        x: Math.round(Math.max(0, Math.min(header.width - width, header.boundary(header.dropAt) - header.table.view.contentX - width / 2)))
        color: Theme.colors.accent
    }
    Row {
        id: headings
        x: -header.table.view.contentX
        Repeater {
            model: header.table.columnItems.length
            delegate: Item {
                id: heading
                required property int index
                readonly property var modelData: header.table.columnItems[index]
                width: modelData.width; height: header.height
                // the column carried stays in its place, faded: the label at the pointer is what moves
                opacity: header.dragKey === modelData.key ? 0.45 : 1
                // Daniel 21/11/2026: the order shown on the column ordered, with the full arrow of the kit (up:
                // ascending, down: descending). headerFeedback (off by default, two variants for Daniel to choose):
                // the heading lit under the pointer, the ordered column's title in the accent
                readonly property string order: header.table.sortKey === modelData.key ? header.table.sortOrder : "none"
                readonly property bool lit: header.table.headerFeedback && (sortArea.containsMouse || order !== "none")
                // the ground of a row under the pointer, under the pointer and under the ordered column (Daniel 21/11/2026:
                // «senza il colore d'accento... un fondo leggermente più scuro, come la riga sotto il puntatore»)
                Rectangle { anchors.fill: parent; color: Theme.colors.hover; visible: heading.lit }
                Text { objectName: "headingText"; x: 8; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width-16-(sortArrow.visible ? sortArrow.width+Theme.space.XS : 0)
                    text: heading.modelData.title; textFormat: Text.PlainText; elide: Text.ElideRight
                    font.family: header.table.font.family; font.pixelSize: header.table.font.pixelSize
                    font.weight: header.table.headerFeedback && heading.order !== "none" ? Font.DemiBold : header.table.font.weight
                    color: Theme.colors.text }
                Arrow { id: sortArrow; objectName: "sortArrow"; visible: heading.order !== "none"
                    direction: heading.order === "ascending" ? "up" : "down"; active: true
                    x: parent.width-8-width; anchors.verticalCenter: parent.verticalCenter }
                MouseArea {
                    id: sortArea; hoverEnabled: header.table.headerFeedback
                    anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton; preventStealing: true
                    property real startX: 0
                    onPressed: mouse => { startX = mouse.x; header.cancelled = false }
                    onPositionChanged: mouse => {
                        if (!pressed || header.cancelled || !(pressedButtons & Qt.LeftButton)) return
                        const p = mapToItem(header, mouse.x, mouse.y)
                        if (!header.dragKey) {
                            if (heading.modelData.fixed || Math.abs(mouse.x - startX) < header.threshold) return
                            header.dragKey = heading.modelData.key; header.dragTitle = heading.modelData.title
                            header.dragFrom = heading.index; header.forceActiveFocus()
                        }
                        header.follow(p.x, p.y)
                    }
                    onReleased: mouse => {
                        if (mouse.button === Qt.RightButton) { header.table.openColumnsMenu(); return }
                        if (header.dragKey) {
                            const p = mapToItem(header, mouse.x, mouse.y)
                            header.follow(p.x, p.y)
                            header.finishDrag()
                        } else if (!header.cancelled && Math.abs(mouse.x - startX) < header.threshold)
                            header.table.requestSort(heading.modelData.key)
                        header.cancelled = false
                    }
                    onCanceled: header.cancelDrag()
                }
                Rectangle { x: parent.width-1; width: 1; height: parent.height; color: Theme.colors.line }
                // The edge stays under the pointer (Daniel 20/11/2026): the pointer is taken in the row of the
                // headings, whose coordinates are the table's own and move neither with the edge nor with the
                // horizontal scroll; the width is where the pointer is less where the column starts, less where the
                // pointer took the edge. From the press every time, so past a limit the column stops and, coming back,
                // starts again from the right point. One width for each turn of the events (Qt.callLater); while
                // dragged the rows keep their heights (DataTable.resizingColumn)
                MouseArea {
                    objectName: "columnEdge-" + heading.modelData.key
                    x: parent.width-5; width: 10; height: parent.height; cursorShape: Qt.SplitHCursor
                    property real grip: 0
                    property real wanted: 0
                    property string columnKey: ""
                    property bool moved: false
                    function apply() { if (columnKey && moved) header.table.columns.resize(columnKey, wanted) }
                    onPressed: mouse => { columnKey = heading.modelData.key; moved = false; header.table.resizingColumn = true
                        grip = mapToItem(headings, mouse.x, 0).x - (heading.x + heading.width) }
                    onPositionChanged: mouse => {
                        if (!pressed) return
                        wanted = mapToItem(headings, mouse.x, 0).x - grip - heading.x
                        moved = true
                        Qt.callLater(apply)
                    }
                    onReleased: { apply(); columnKey = ""; header.table.resizingColumn = false }
                    onCanceled: { columnKey = ""; header.table.resizingColumn = false }
                    onDoubleClicked: header.table.fitColumn(heading.modelData.key)
                }
            }
        }
    }
    Rectangle { y: parent.height-1; width: parent.width; height: 1; color: Theme.colors.line }
}
