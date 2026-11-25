import QtQuick
import QtQuick.Controls as QQC
import Casa.Theme
import Casa.Tables 1.0

Surface {
    id: root
    property var model: null
    property var columns: null
    property var state: null
    property bool wholeText: false
    property bool reducedMotion: Theme.reducedMotion
    property var measureText: null
    property var elideText: null
    property var fitText: null
    // A host may supply representative longest strings for each numeric column.
    property var numericSamples: null
    onNumericSamplesChanged: Qt.callLater(updateNumericWidths)
    function updateNumericWidths() {
        if (!columns || !numericSamples) return
        const widths = {}
        for (const column of columns.allColumns) {
            if (!column.numeric) continue
            const title = fontMetrics.advanceWidth(column.title) + 2 * Theme.space.M + Theme.icon.CONTROL + Theme.space.XS
            const value = fontMetrics.advanceWidth(numericSamples[column.key] || "") + 2 * Theme.space.M
            widths[column.key] = Math.ceil(Math.max(title, value))
        }
        columns.set_natural_widths(widths)
    }
    property string highlight: ""
    property bool filterActive: false
    property string accessibilityName: Theme.tr("Data table")
    onFilterActiveChanged: if (state) state.set_filter_active(filterActive)
    property var totals: ({})
    property font font: Qt.font({family: Theme.fontFamily, pixelSize: Theme.type.BODY})
    readonly property real fontLineHeight: fontMetrics.height
    property real rowHeight: Math.max(28, Math.ceil(fontLineHeight)+8)
    property real headerHeight: Math.max(32, rowHeight)
    // the bar's lane and the air before it (the edges' rule, ControlMetrics): the last column never touches the bar
    property real scrollbarWidth: ControlMetrics.scrollLane + ControlMetrics.scrollBreath
    property real footerHeight: Object.keys(totals).length ? rowHeight : 0
    property bool selectionActive: root.Window.window ? root.Window.window.active : activeFocus
    onActiveFocusChanged: if (activeFocus && rows) rows.forceActiveFocus()
    readonly property color accent: Theme.colors.accent
    readonly property color foreground: Theme.colors.text
    readonly property color selectionColor: Theme.mix(fill, accent, 0.24)
    readonly property color inactiveSelectionColor: Theme.mix(fill, accent, 0.13)
    readonly property color bandColor: Theme.mix(fill, foreground, 0.04)
    property color highlightColor: "#ffe170"
    readonly property var columnItems: columns ? columns.items : []
    // The columns without their widths, and the widths alone: a column dragged wider changes the widths only, and a
    // cell reads the rest from columnMeta, which stays the same object, so it is not evaluated again (Daniel
    // 20/11/2026: «il ridimensionamento delle colonne è molto lento e scattante»: every visible cell, its text and
    // its Python calls, ran again at each move of the mouse)
    property var columnMeta: []
    readonly property var columnWidths: columnItems.map(c => c.width)
    // The columns menu likewise: its items were made again at every move (one MenuItem for each of the columns)
    property var columnChoices: []
    function refreshMeta() {
        const next = columnItems.map(c => { const m = Object.assign({}, c); delete m.width; return m })
        if (JSON.stringify(next) !== JSON.stringify(columnMeta)) columnMeta = next
        const choices = columns ? columns.allColumns.map(c => ({key: c.key, title: c.title, visible: c.visible})) : []
        if (JSON.stringify(choices) !== JSON.stringify(columnChoices)) columnChoices = choices
    }
    // While a column is dragged (DataHeader) the rows are only laid out again (the elisions are kept by width) and keep
    // their heights; everything is measured again once, at the release
    property bool resizingColumn: false
    onResizingColumnChanged: if (!resizingColumn) invalidateHeights()
    onColumnItemsChanged: {
        // while a border is dragged only the widths change: the columns' names and kinds (a conversion from Python and
        // two JSON comparisons at every step) wait for the release
        if (!ControlMetrics.resizing) refreshMeta()
        if (!extension || !rows || !textTools) return
        if (resizingColumn || ControlMetrics.resizing) rows.forceLayout(); else invalidateHeights()
    }
    readonly property var view: rows
    readonly property var header: heading
    readonly property var extension: extension
    readonly property real dpr: Screen.devicePixelRatio
    onDprChanged: invalidateHeights()
    readonly property bool editing: editor.visible
    readonly property int currentRow: state && model ? model.rowForKey(state.currentKey) : -1
    readonly property int currentColumnIndex: {
        const key = state ? state.currentColumn : ""
        const found = columnItems.findIndex(c => c.key === key)
        return Math.max(0, found)
    }
    readonly property var selectedRows: {
        const result = ({})
        if (state && model) for (const key of state.selectedKeys) {
            const row = model.rowForKey(key)
            if (row >= 0) result[row] = true
        }
        return result
    }
    property string sortKey: ""
    property string sortOrder: "none"
    // the headings lit under the pointer and the ordered one marked in a neutral tone (DataHeader): Daniel's choice of
    // 21/11/2026, on by default (no accent colour)
    property bool headerFeedback: true
    property int editRow: -1
    property int editColumn: -1
    property var pendingOpen: null
    property int polishCount: 0
    property int liveDelegates: 0
    property int createdDelegates: 0
    property int destroyedDelegates: 0
    property int doubleClicks: 0
    property int restoreRow: -1
    property real restoreOffset: 0
    property bool restoring: false
    property bool sourceSettled: true
    property var naturalHeights: ({})
    property var rowHeights: ({})
    property bool changingHeights: false
    // the empty state (docs/22, row 9): shown when no row is left, with the reason and, if any, the action that
    // fills the table again (for a filtered one, «Remove the filters»)
    property string emptyTitle: ""
    property string emptyDescription: ""
    property string emptyActionText: ""
    property string emptyIcon: ""
    signal emptyTriggered()
    signal toggleRequested(string key)
    signal sortRequested(string columnKey, string order)
    signal copyRequested(var keys, var columnKeys, string mode)
    signal activateRequested(string key, int modifiers)
    // The rows chosen (21/11/2026, Daniel on Quotario: «con tasto destro mi toglie la selezione complessiva e mi
    // seleziona solo una voce e non mi dà grandi capacità di controllo»): the right button on a row already chosen keeps
    // the group, on another row it chooses that row alone; Ctrl+A chooses every row shown (after the filters), Esc none.
    // The menu of the right button ends with the host's commands for the rows chosen: `contextCommands`, Command
    // objects of the catalogue (commands.py), each with its text for the number of rows (Command.counted, «Elimina 7
    // voci») and, while off, its reason beside it; contextRequested(keys) comes just before the menu opens.
    property var contextCommands: []
    signal contextRequested(var keys)
    readonly property var chosenKeys: state && model
        ? state.selectedKeys.slice().sort((a, b) => model.rowForKey(a) - model.rowForKey(b)) : []
    // Moving rows by dragging them (rowsMovable, the host's choice): past the system's drag distance the row's label (or
    // «7 rows») follows the pointer, a sharp line in the accent shows where they will land, near the top and the foot
    // the rows scroll, Esc or a release out of the table leave everything as it was; the release asks the host
    // (rowsMoveRequested: the keys in their order, the row they land before, "" at the end, and its group, the
    // nearest row above it less deep, "" at the top level). The host decides, and may ask first. The look of the
    // columns moved by their titles (DataHeader).
    property bool rowsMovable: false
    signal rowsMoveRequested(var keys, string beforeKey, string parentKey)
    property var dragKeys: []
    property int dropRow: -1
    property real dragX: 0
    property real dragY: 0
    property bool dragOutside: false
    readonly property bool dropChanges: {
        if (!dragKeys.length || dropRow < 0 || !model) return false
        const rowsOf = dragKeys.map(k => model.rowForKey(k)).sort((a, b) => a - b)
        const contiguous = rowsOf[rowsOf.length - 1] - rowsOf[0] === rowsOf.length - 1
        return !(contiguous && dropRow >= rowsOf[0] && dropRow <= rowsOf[rowsOf.length - 1] + 1)
    }
    function rowParent(row) {
        if (!model || row < 0 || row >= rows.rows) return ""
        const depth = (projection.rowDecor(row) >> 1) & 127
        let mother = row - 1
        while (mother >= 0 && ((projection.rowDecor(mother) >> 1) & 127) >= depth) mother--
        return depth > 0 && mother >= 0 ? model.rowKey(mother) : ""
    }
    function rowTop(row) {
        if (row <= 0) return 0
        const cell = rows.itemAtCell(Qt.point(Math.max(0, rows.leftColumn), Math.min(row, rows.rows - 1)))
        if (!cell) return row * rowHeight
        return row < rows.rows ? cell.y : cell.y + cell.height
    }
    function followRows(x, y) {
        // x, y in the table's coordinates
        dragX = x; dragY = y
        dragOutside = x < 0 || x > width || y < 0 || y > height
        const at = y - rows.y + rows.contentY
        const found = rows.cellAtPosition(Qt.point(rows.contentX + 1, Math.max(0, Math.min(rows.contentHeight - 1, at))), false)
        if (found.y < 0) { dropRow = at <= 0 ? 0 : rows.rows; redraw(); return }
        const cell = rows.itemAtCell(found)
        dropRow = cell && at > cell.y + cell.height / 2 ? found.y + 1 : found.y
        redraw()          // the label and the line drawn again by the software compositor as well
    }
    function cancelRowDrag() { const had = dragKeys.length > 0; dragKeys = []; dropRow = -1; dragOutside = false; if (had) redraw() }
    function finishRowDrag() {
        if (dragKeys.length && !dragOutside && dropChanges) {
            const before = dropRow < rows.rows ? model.rowKey(dropRow) : ""
            rowsMoveRequested(dragKeys.slice(), before, dropRow < rows.rows ? rowParent(dropRow) : "")
        }
        cancelRowDrag()
    }
    // Editing in a cell (21/11/2026, Quotario's study: «DataTable.editable(row, column) e un segnale cellEdited»): the
    // host says which cells may be written (`editable(key, column)`), may refuse a value with its reason
    // (`commitEdit(key, column, text)` returns "" or the reason) and hears the value accepted (cellEdited). F2, a double
    // click or the cell's menu open the field; the other columns keep the read-only field of the whole text.
    property var editable: null
    property var commitEdit: null
    signal cellEdited(string key, string column, string text)
    function cellEditable(row, column) {
        return !!editable && row >= 0 && column >= 0 && column < columnItems.length
            && editable(model.rowKey(row), columnItems[column].key) === true
    }
    function commitText(onward) {
        if (!editor.visible || !editor.editing) return
        const key = model.rowKey(editRow), column = columnItems[editColumn].key, text = editor.text
        const reason = commitEdit ? String(commitEdit(key, column, text) || "") : ""
        if (reason) { editor.reason = reason; return }
        const row = editRow, at = editColumn
        closeText()
        cellEdited(key, column, text)
        if (onward) for (let c = at + 1; c < columnItems.length; c++) if (cellEditable(row, c)) { openText(row, c, 0); break }
    }
    QtObject { id: revision; signal changed() }
    revisionSource: revision
    function redraw() { revision.changed() }
    onHighlightChanged: redraw()
    onTotalsChanged: redraw()
    onReducedMotionChanged: if (reducedMotion) extension.finish()
    surfaceKind: "view"
    surfaceId: "data-table"
    activeFocusOnTab: true
    Accessible.role: Accessible.Table
    Accessible.name: root.accessibilityName
    headerItem: heading
    footerItem: totalRow
    barItem: verticalBar

    TableProjection {
        id: projection; sourceModel: root.model; columns: root.columns
        firstVisibleRow: Math.max(0, rows.topRow-1)
        lastVisibleRow: rows.bottomRow+1
    }
    FontMetrics { id: fontMetrics; font: root.font }
    TableText { id: textTools }
    RowExtension { id: extension; onChanged: {
        if (root.changingHeights) { root.rowHeights = extension.heightsMap; return }
        root.changingHeights = true
        root.rowHeights = extension.heightsMap; rows.forceLayout()
        root.changingHeights = false
        root.redraw()
    } }
    function cutText(text, width, font, mode) {
        return elideText ? elideText(text, width, font, mode) : textTools.elide(text, width, font, mode)
    }
    function highlightSpans(text, width, font) { return textTools.spans(text, highlight, width, font, wholeText) }
    function columnAt(x) {
        let end = 0
        for (let i=0; i<columnItems.length; i++) { end += columnItems[i].width; if (x < end) return i }
        return -1
    }
    function updateColumns() {
        if (columns) columns.layout(width, scrollbarWidth)
        rows.forceLayout()
    }
    // while a border is dragged the columns follow at every frame and the rows keep their heights (ControlMetrics.resizing,
    // as a column dragged: resizingColumn); the heights and the wrapped texts once at the release
    onWidthChanged: { closeText(); if (!ControlMetrics.resizing) { extension.invalidate(); naturalHeights = ({}) } updateColumns() }
    Connections { target: ControlMetrics; function onResizingChanged() { if (!ControlMetrics.resizing) { root.refreshMeta(); root.invalidateHeights() } } }
    onHeightChanged: rows.forceLayout()
    onRowHeightChanged: if (rows) rows.forceLayout()
    onColumnsChanged: { updateColumns(); Qt.callLater(updateNumericWidths) }
    onModelChanged: {
        restoreRow = -1; pendingOpen = null
        sortKey = ""; sortOrder = "none"
        naturalHeights = ({})
        if (extension) extension.invalidate()
        if (editor) closeText()
        if (tip) tip.visible = false
        if (state) state.bind_model(model)
    }
    onStateChanged: if (state) { state.bind_model(model); state.set_filter_active(filterActive) }
    onFontChanged: { invalidateHeights(); Qt.callLater(updateNumericWidths) }
    function invalidateHeights() { closeText(); textTools.invalidate(); naturalHeights = ({}); extension.invalidate(); rows.forceLayout() }
    onWholeTextChanged: changeWholeText()
    function measureRow(row) {
        if (!wholeText || !model || row < 0 || row >= rows.rows) return rowHeight
        const key = model.rowKey(row)
        if (naturalHeights[key] !== undefined) return naturalHeights[key]
        let height = rowHeight
        const decor = projection.rowDecor(row), depth = (decor >> 1) & 127, kind = (decor >> 8) & 3
        for (let i=0; i<columnItems.length; i++) {
            const col = columnItems[i]
            const lead = i === 0 ? 9 + depth*14 : 8
            const arrow = i === 0 && (kind === 1 || kind === 2) ? 14 : 0
            const room = Math.max(1, col.width-lead-8-arrow)
            const text = model.fullText(key, col.key)
            const measured = measureText ? measureText(text, room, font, dpr)
                                         : extension.measure(text, room, font, dpr)
            height = Math.max(height, measured)
        }
        naturalHeights[key] = height
        return height
    }
    function changeWholeText() {
        if (!rows || !model) return
        closeText()
        const start = Date.now(), starts = ({}), targets = ({})
        const top = Math.max(0, rows.topRow), bottom = Math.min(rows.rows-1, rows.bottomRow)
        for (let r=top; r<=bottom; r++) {
            const key = model.rowKey(r)
            starts[key] = rowHeights[key] !== undefined ? rowHeights[key] : (wholeText ? rowHeight : naturalHeights[key] || rowHeight)
            targets[key] = wholeText ? measureRow(r) : rowHeight
        }
        extension.startTransition(starts, targets, reducedMotion, Date.now()-start)
        rows.forceLayout()
    }
    function hideText() {
        pendingOpen = null
        editor.visible = false; editRow = -1; editColumn = -1
    }
    function closeText() {
        if (!editor.visible) return
        hideText(); rows.forceActiveFocus()
    }
    function openPendingText() {
        if (!pendingOpen) return
        const saved = pendingOpen
        pendingOpen = null
        if (model === saved.source && rows.activeFocus)
            openText(model.rowForKey(saved.key), columnItems.findIndex(c=>c.key === saved.column), saved.position)
    }
    function openText(row, column, position) {
        if (!model || !state || row < 0 || column < 0 || column >= columnItems.length) return
        let cell = rows.itemAtCell(Qt.point(column, row))
        if (!cell) {
            rows.positionViewAtCell(Qt.point(column,row), TableView.Contain)
            rows.forceLayout()
            cell = rows.itemAtCell(Qt.point(column,row))
            if (!cell) {
                pendingOpen = ({source:model, key:model.rowKey(row), column:columnItems[column].key, position:position})
                Qt.callLater(root.openPendingText)
                return
            }
        }
        editRow = row; editColumn = column
        const point = cell.mapToItem(root.clippingItem, 0, 0)
        editor.x = point.x; editor.y = point.y; editor.width = cell.width; editor.height = cell.height
        editor.textTop = wholeText ? 4 : (cell.height - fontMetrics.height) / 2
        editor.alignRight = !!columnItems[column].numeric
        editor.text = model.fullText(model.rowKey(row), columnItems[column].key)
        // as tall as its whole text while it is open, down to the foot of the rows at most
        const room = rows.y + rows.height - point.y, base = cell.height
        editor.height = Qt.binding(() => Math.max(base, Math.min(room, editor.field.contentHeight + 2 * editor.textTop)))
        editor.backgroundColor = cell.color
        editor.lead = cell.lead
        editor.litSide = column === 0 && cell.selected
        editor.litInset = frameThickness
        editor.editing = cellEditable(row, column); editor.reason = ""
        editor.visible = true; editor.open(position || 0)
    }
    function requestSort(key) {
        sortOrder = sortKey !== key ? "ascending" : sortOrder === "none" ? "ascending" : sortOrder === "ascending" ? "descending" : "none"
        sortKey = key; sortRequested(key, sortOrder)
    }
    function fitColumn(key) {
        if (!columns) return
        columns.resize(key, fitText ? fitText(key) : key === "description" ? 260 : 90)
    }
    function openColumnsMenu() { columnMenu.popup() }
    function showTooltip(row, column) {
        if (model && columnItems[column]) {
            tip.text = textTools.tooltip(model.fullText(model.rowKey(row), columnItems[column].key))
            tip.shownAt = pointer.mapToItem(root.clippingItem, pointer.hoverPoint.x, pointer.hoverPoint.y)
            tip.visible = true
        }
    }
    function copy(mode) {
        if (!model || !state || !columnItems.length) return
        const keys = mode === "cell" ? [state.currentKey] : state.selectedKeys.slice().sort((a,b)=>model.rowForKey(a)-model.rowForKey(b))
        const cols = mode === "cell" ? [columnItems[currentColumnIndex].key]
                   : mode === "description" ? ["description"] : columnItems.map(c=>c.key)
        copyRequested(keys, cols, mode)
    }
    function captureAnchor() {
        if (!state || !model) return
        const row = Math.max(0, rows.topRow)
        const cell = rows.itemAtCell(Qt.point(Math.max(0, rows.leftColumn), row))
        state.set_anchor(model.rowKey(row), cell ? rows.contentY-cell.y : 0)
    }
    // After a source reset the view goes straight to the saved row and loads
    // its visible cells once, in the same call that follows the reset. Before
    // P1b3 the next frame drew the top of the table, then the saved row.
    function aimRestore(count) {
        const uniform = !wholeText && !extension.busy
        const step = uniform || rows.rows <= 0 || rows.contentHeight <= 0 ? rowHeight : rows.contentHeight/rows.rows
        const end = Math.max(0, count*step-rows.height)
        const target = Math.min(end, Math.min(restoreRow, count-1)*step+(uniform ? restoreOffset : 0))
        changingHeights = true
        // TableView rebuilds at the viewport only after a move longer than a
        // page: a shorter one would refill around the rows of the old source.
        rows.contentY = rows.contentY+2*rows.height+1
        rows.contentY = Math.max(0, target)
        changingHeights = false
    }
    // True when the visible cells were rebuilt and hold the new data.
    function settleRestore() {
        if (restoring || restoreRow < 0) return false
        const count = projection.countRows()
        if (count === 0 || rows.columns === 0) { restoreRow = -1; return false }
        restoring = true
        const left = Math.max(0, rows.leftColumn), wanted = Math.min(restoreRow, count-1)
        // The projection changes rows at its tail only, so a loaded row
        // below both counts keeps its place. When the saved row is still at
        // the top the cells are refreshed where they are. A longer move
        // would load the rows in between one by one: rebuild instead.
        let cell = wanted < rows.rows ? rows.itemAtCell(Qt.point(left, wanted)) : null
        if (cell && Math.abs(cell.y+Math.max(0, Math.min(restoreOffset, cell.height-1))-rows.contentY) > rowHeight) cell = null
        const rebuilt = !cell
        if (rebuilt) {
            aimRestore(count)
            rows.forceLayout()
            if (rows.rows !== count) { restoring = false; return true }
            cell = rows.itemAtCell(Qt.point(left, wanted))
            if (!cell) {
                rows.positionViewAtRow(wanted, TableView.AlignTop)
                rows.forceLayout()
                cell = rows.itemAtCell(Qt.point(left, wanted))
            }
        }
        if (cell) {
            const uniform = !wholeText && !extension.busy
            const end = rows.rows === count ? Math.max(0, rows.contentHeight-rows.height)
                      : uniform ? Math.max(0, count*rowHeight-rows.height) : Infinity
            // Never past the last row: the saved row can be on the last page.
            rows.contentY = Math.min(end, cell.y+Math.max(0, Math.min(restoreOffset, cell.height-1)))
            restoreRow = -1
        }
        restoring = false
        return rebuilt
    }
    Connections { target: root.state
        function onChanged() { root.redraw() }
        function onBeforeReset() {
            root.captureAnchor(); root.closeText()
            // Do not lay out the old rows while the source is resetting. The
            // view stays where it is until the reset has settled its row.
            root.changingHeights = true
            extension.invalidate()
            root.changingHeights = false
            root.sourceSettled = false
        }
        function onRestoreRequested(row, offset) {
            root.restoreRow = row; root.restoreOffset = offset; root.naturalHeights = ({})
            // Place the view before the next frame, or Quick first draws
            // the top of the table and loads every visible cell twice.
            if (root.sourceSettled) root.settleRestore()
            Qt.callLater(root.settleRestore)
        }
    }
    Connections { target: projection
        function onRefreshed() {
            root.sourceSettled = true
            if (!root.settleRestore()) projection.refreshVisible()
        }
    }
    Connections { target: root.model
        function onDataChanged() { root.invalidateHeights() }
        function onRowsInserted() { root.redraw() }
        function onRowsRemoved() { root.redraw() }
    }
    DataHeader { id: heading; table: root; width: root.width; height: root.headerHeight }
    Item {
        id: totalRow; y: root.height-height-(horizontalBar.visible ? horizontalBar.height : 0); height: root.footerHeight; width: root.width; clip: true
        // the band of the totals to the table's right edge, under the bar's lane (Daniel 21/11/2026); the bar over it
        Rectangle { anchors.fill: parent; color: Theme.colors.panel; z: -1 }
        Row { x: -rows.contentX
            Repeater { model: root.columnItems
                delegate: Rectangle { required property var modelData; width: modelData.width; height: totalRow.height; color: Theme.colors.panel
                    Text { x: 8; width: parent.width-16; text: root.totals[modelData.key] || ""; textFormat: Text.PlainText
                        font: root.font; color: Theme.colors.text; anchors.verticalCenter: parent.verticalCenter }
                }
            }
        }
    }
    // the horizontal bar's lane takes the ground of the band beside it (the totals', the heading's), to the table's
    // edges and into its rounded corners: no strip of the rows' ground under a band (Daniel 21/11/2026; the rule in
    // ControlMetrics, «The edges»)
    Rectangle {
        objectName: "horizontalLane"; parent: root.clippingItem; z: 2
        x: 0; y: root.height-height; width: root.width; height: horizontalBar.visible ? horizontalBar.height : 0
        visible: horizontalBar.visible; color: Theme.colors.panel
    }
    TableView {
        id: rows; objectName: "dataViewport"
        x: 0; y: root.headerHeight; width: Math.max(0, root.width)
        height: Math.max(0, root.height-y-root.footerHeight-(horizontalBar.visible ? horizontalBar.height : 0))
        // The Surface carries this bar out of the view to draw it above the cells (barItem); out of its Flickable Qt
        // no longer places an attached bar (it stayed 0 px high, Daniel 20/11/2026: «non ci sono barre di
        // scorrimento»), so it follows the view here
        QQC.ScrollBar.vertical: ScrollBar { id: verticalBar; objectName: "dataVerticalBar"; fades: false
            x: rows.x+rows.width-width; y: rows.y; height: rows.height }
        // In its Flickable Qt lays the bar over the last row (Daniel 20/11/2026, the bar covered the last visible
        // row): out of it, at the table's foot, in the room the view and the totals leave it, as the vertical one
        QQC.ScrollBar.horizontal: ScrollBar { id: horizontalBar; objectName: "dataHorizontalBar"; fades: false
            parent: root.clippingItem; z: 3; x: rows.x; y: root.height-height; width: rows.width }
        model: projection
        clip: true; reuseItems: true; boundsBehavior: Flickable.StopAtBounds
        animate: false
        editTriggers: TableView.NoEditTriggers
        pointerNavigationEnabled: false
        keyNavigationEnabled: false
        columnSpacing: 0; rowSpacing: 0
        columnWidthProvider: column => root.columnItems[column] ? root.columnItems[column].width : 0
        rowHeightProvider: row => {
            if (!root.wholeText && !extension.busy) return root.rowHeight
            if (!root.model) return root.rowHeight
            const key = root.model.rowKey(row)
            return root.rowHeights[key] !== undefined ? root.rowHeights[key] : root.measureRow(row)
        }
        delegate: DataCell { table: root
            Component.onCompleted: { root.liveDelegates++; root.createdDelegates++ }
            Component.onDestruction: { root.liveDelegates--; root.destroyedDelegates++ }
        }
        onLayoutChanged: { root.polishCount++; root.redraw(); if (root.restoreRow >= 0) Qt.callLater(root.settleRestore) }
        onContentYChanged: {
            root.closeText(); tipTimer.stop(); tip.visible = false
            if (extension.busy && !root.changingHeights) Qt.callLater(extension.finish)
            root.redraw()
        }
        onMovementStarted: extension.finish()
        onContentXChanged: { root.closeText(); tipTimer.stop(); tip.visible = false; root.redraw() }
        Keys.onPressed: event => root.handleKey(event)
        // the table's Esc and Ctrl+A before the window's shortcuts, while they have something to do here
        Keys.onShortcutOverride: event => {
            event.accepted = event.key === Qt.Key_Escape && root.state && (root.dragKeys.length > 0 || root.state.selectedKeys.length > 0)
                || event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.ShiftModifier)
        }
        MouseArea {
            id: pointer
            objectName: "dataPointer"
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            propagateComposedEvents: true
            hoverEnabled: true
            property point hoverPoint: Qt.point(0,0)
            onExited: { tipTimer.stop(); tip.visible = false }
            // a drag of rows is the table's, not the view's flick
            preventStealing: root.rowsMovable
            property point pressPoint: Qt.point(0, 0)
            property string pressKey: ""
            // a press on a row of a group already chosen: the group stays for a drag, the row alone at the release
            property string deferredKey: ""
            onPressed: mouse => {
                tipTimer.stop(); tip.visible = false; root.pendingOpen = null
                root.closeText(); rows.forceActiveFocus()
                pressKey = ""; deferredKey = ""; root.cancelRowDrag()
                const point = Qt.point(mouse.x, mouse.y)
                const at = rows.cellAtPosition(point, false)
                if (at.y < 0 || at.x < 0 || !root.state || !root.model) return
                const cell = rows.itemAtCell(at)
                const key = root.model.rowKey(at.y), chosen = root.selectedRows[at.y] === true
                if (mouse.button === Qt.RightButton && chosen) root.state.set_current(key)
                else if (root.rowsMovable && mouse.button === Qt.LeftButton && chosen && !mouse.modifiers
                         && root.state.selectedKeys.length > 1) { deferredKey = key; root.state.set_current(key) }
                else root.state.choose(key, mouse.modifiers)
                root.state.set_column(root.columnItems[at.x].key)
                if (mouse.button === Qt.RightButton) { root.contextRequested(root.chosenKeys); contextMenu.popup() }
                else if (at.x === 0 && cell && (cell.kind === 1 || cell.kind === 2) && mouse.x-cell.x >= cell.width-22)
                    root.toggleRequested(key)
                else if (mouse.button === Qt.LeftButton && !mouse.modifiers) { pressKey = key; pressPoint = point }
            }
            onPositionChanged: mouse => {
                hoverPoint = Qt.point(mouse.x,mouse.y)
                if (!pressed && !editor.visible) { tip.visible = false; tipTimer.restart() }
                if (!pressed || !root.rowsMovable || !pressKey || !(pressedButtons & Qt.LeftButton)) return
                const p = mapToItem(root, mouse.x, mouse.y)
                if (!root.dragKeys.length) {
                    if (Math.abs(mouse.y - pressPoint.y) < Qt.styleHints.startDragDistance
                        && Math.abs(mouse.x - pressPoint.x) < Qt.styleHints.startDragDistance) return
                    root.dragKeys = root.chosenKeys.indexOf(pressKey) >= 0 ? root.chosenKeys : [pressKey]
                    deferredKey = ""
                }
                root.followRows(p.x, p.y)
            }
            onReleased: mouse => {
                if (root.dragKeys.length) {
                    const p = mapToItem(root, mouse.x, mouse.y)
                    root.followRows(p.x, p.y)
                    root.finishRowDrag()
                } else if (deferredKey && root.state) root.state.choose(deferredKey, 0)
                pressKey = ""; deferredKey = ""
            }
            onCanceled: { root.cancelRowDrag(); pressKey = ""; deferredKey = "" }
            onDoubleClicked: mouse => {
                root.doubleClicks++
                const at = rows.cellAtPosition(Qt.point(mouse.x, mouse.y), false)
                const cell = rows.itemAtCell(at)
                if (!cell || !root.model) return
                const p = cell.textItem.mapFromItem(rows.contentItem, mouse.x, mouse.y)
                const rendered = cell.renderedText()
                const hit = textTools.hit(rendered, cell.textItem.width, root.font, root.wholeText, p.x, p.y, cell.metadata.numeric)
                const full = root.model.fullText(root.model.rowKey(at.y), root.columnItems[at.x].key)
                root.openText(at.y, at.x, root.wholeText ? hit : textTools.fullPosition(full, rendered, hit))
            }
        }
    }
    // Past the last column Tab goes on to the next control of the window, before the first one
    // Shift+Tab to the previous: the table's own parts (the rows, the header) are skipped.
    function leaveTable(forward) {
        const inside = item => { for (let p = item; p; p = p.parent) if (p === root) return true; return false }
        let next = root.nextItemInFocusChain(forward)
        for (let guard = 0; next && inside(next) && guard < 200; guard++) next = next.nextItemInFocusChain(forward)
        if (next && !inside(next)) next.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason)
    }
    function handleKey(event) {
        if (!model || !state || !rows.rows) return
        const control = event.modifiers & Qt.ControlModifier
        const shift = event.modifiers & Qt.ShiftModifier
        const hadCurrent = currentRow >= 0
        let row = hadCurrent ? currentRow : 0
        let col = currentColumnIndex
        if (event.key === Qt.Key_C && control) { copy(shift ? "with_headers" : "rows"); event.accepted = true; return }
        if (event.key === Qt.Key_Escape) {
            if (dragKeys.length) { cancelRowDrag(); pointer.pressKey = ""; event.accepted = true }
            else if (state.selectedKeys.length) { state.clear_selection(); event.accepted = true }
            return
        }
        if (event.key === Qt.Key_A && control && !shift) { state.select_all(); event.accepted = true; return }
        if (event.key === Qt.Key_F2) { openText(row, col, 0); event.accepted = true; return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right || event.key === Qt.Key_Left) {
            const decor = projection.rowDecor(row)
            const kind = (decor >> 8) & 3, expanded = (decor & 1024) !== 0
            const depth = (decor >> 1) & 127
            const key = model.rowKey(row)
            if (control && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) activateRequested(key,event.modifiers)
            else if (event.key === Qt.Key_Left && depth > 0 && !expanded) {
                let mother = row-1
                while (mother >= 0 && ((projection.rowDecor(mother) >> 1) & 127) >= depth) mother--
                if (mother >= 0) { state.choose(model.rowKey(mother), event.modifiers); rows.positionViewAtRow(mother, TableView.Contain) }
            } else if (kind === 1 || kind === 2) {
                if (event.key !== Qt.Key_Right && event.key !== Qt.Key_Left || event.key === Qt.Key_Right && !expanded || event.key === Qt.Key_Left && expanded) toggleRequested(key)
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) activateRequested(key,event.modifiers)
            event.accepted = true; return
        }
        if (event.key === Qt.Key_Up) { if (hadCurrent) row-- }
        else if (event.key === Qt.Key_Down) { if (hadCurrent) row++ }
        else if (event.key === Qt.Key_Home) row=0
        else if (event.key === Qt.Key_End) row=rows.rows-1
        else if (event.key === Qt.Key_PageUp) row-=Math.max(1, rows.bottomRow-rows.topRow)
        else if (event.key === Qt.Key_PageDown) row+=Math.max(1, rows.bottomRow-rows.topRow)
        else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            col += shift || event.key === Qt.Key_Backtab ? -1 : 1
            if (col < 0 || col >= columnItems.length) { leaveTable(col >= 0); event.accepted=true; return }
        } else return
        row=Math.max(0, Math.min(rows.rows-1,row))
        if (!control || shift) state.choose(model.rowKey(row),event.modifiers)
        else state.set_current(model.rowKey(row))
        if (columnItems[col]) state.set_column(columnItems[col].key)
        rows.positionViewAtRow(row,TableView.Contain)
        event.accepted=true
    }
    // Keep the shade over the visible cells when the last column leaves spare room.
    readonly property real rowsEnd: columnItems.reduce((sum, column) => sum+column.width, 0)-rows.contentX
    EdgeFades { flickable: rows; spansSurface: false; contentEdge: root.rowsEnd; ground: root.fill; z: 1 }
    // The bars' states (thin, wide with the lane, dragged) drawn again by the software compositor as well
    Connections { target: verticalBar; function onAppearanceChanged() { root.redraw() } }
    Connections { target: horizontalBar; function onAppearanceChanged() { root.redraw() } }
    CellText { id: editor; visible: false; z: 10; font: root.font; onDismissed: root.closeText(); onFocusLeft: root.hideText()
        onCommitted: onward => root.commitText(onward) }
    CellTextGuard {
        window: root.Window.window
        editorItem: editor
        enabled: editor.visible
        onOutside: root.hideText()
    }
    Connections { target: editor; function onChanged() { root.redraw() } }
    onSelectionActiveChanged: redraw()
    onAccentChanged: redraw()
    onForegroundChanged: redraw()
    onFillChanged: redraw()
    Timer { id: tipTimer; interval: ControlMetrics.tipDelay; onTriggered: {
        const cell = rows.cellAtPosition(pointer.hoverPoint,false)
        if (!editor.visible && pointer.containsMouse && cell.y >= 0) root.showTooltip(cell.y,cell.x)
    } }
    ToolTip { id: tip; visible: false; delay: 0; placed: true }
    Menu { id: contextMenu; objectName: "dataContextMenu"
        MenuItem { text: Theme.tr("Cell text"); onTriggered: root.openText(root.currentRow,root.currentColumnIndex,0) }
        MenuItem { text: Theme.tr("Copy cell"); onTriggered: root.copy("cell") }
        MenuItem { text: Theme.tr("Copy rows"); onTriggered: root.copy("rows") }
        MenuItem { text: Theme.tr("Copy description"); onTriggered: root.copy("description") }
        MenuItem { text: Theme.tr("Copy with headers"); onTriggered: root.copy("with_headers") }
        // the host's commands for the rows chosen, with their number; off, the reason in the column of the keys
        MenuItem { rule: true; shown: root.contextCommands.length > 0 }
        Repeater { model: root.contextCommands
            delegate: MenuEntry { required property var modelData
                objectName: "contextCommand-" + modelData.id
                entry: ({text: modelData.textFor(root.chosenKeys.length), enabled: modelData.enabled, note: modelData.note,
                         keys: modelData.shortcut ? [modelData.shortcut] : []})
                onTriggered: modelData.trigger()
            }
        }
    }
    // the rows carried: the label at the pointer and the line where they will land, as the columns' (DataHeader)
    Timer {
        objectName: "rowDragScroll"; interval: 16; repeat: true
        running: root.dragKeys.length > 0 && (root.dragY < rows.y + Theme.space.XXL || root.dragY > rows.y + rows.height - Theme.space.XXL)
        onTriggered: {
            const step = root.dragY < rows.y + Theme.space.XXL ? -Theme.space.L : Theme.space.L
            rows.contentY = Math.max(0, Math.min(Math.max(0, rows.contentHeight - rows.height), rows.contentY + step))
            root.followRows(root.dragX, root.dragY)
        }
    }
    Rectangle {
        objectName: "rowDragLabel"; z: 20
        visible: root.dragKeys.length > 0
        width: Math.min(rowDragText.implicitWidth + 2 * Theme.space.M, 2 * Theme.size.READING / 3)
        height: Math.max(0, root.rowHeight - 2 * Theme.space.XS)
        x: Math.round(Math.max(0, Math.min(root.width - width, root.dragX + Theme.space.L)))
        y: Math.round(root.dragY - height / 2)
        radius: Theme.radius.CARD; color: Theme.colors.select_bg; border.width: 1; border.color: Theme.colors.accent
        opacity: 0.85
        Text { id: rowDragText; anchors.centerIn: parent; width: parent.width - 2 * Theme.space.M
            text: root.dragKeys.length === 1 && root.model && root.columnItems.length
                ? root.model.fullText(root.dragKeys[0], root.columnItems[Math.max(0, root.columnItems.findIndex(c => c.key === "description"))].key).split("\n")[0]
                : Theme.tr("%n row", "%n rows", root.dragKeys.length)
            textFormat: Text.PlainText; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
            font.family: root.font.family; font.pixelSize: root.font.pixelSize; color: Theme.colors.text }
    }
    Rectangle {
        objectName: "rowDropLine"; z: 21; antialiasing: false
        visible: root.dropChanges && !root.dragOutside
        x: 0; width: Math.min(root.width - root.scrollbarWidth, root.rowsEnd); height: 2
        y: Math.round(Math.max(rows.y, Math.min(rows.y + rows.height - height, rows.y + root.rowTop(root.dropRow) - rows.contentY - height / 2)))
        color: Theme.colors.accent
    }
    Menu { id: columnMenu
        Repeater { model: root.columnChoices
            delegate: MenuItem { required property var modelData; text: modelData.title
                checkable: true; checked: modelData.visible
                onTriggered: root.columns.set_visible(modelData.key, !modelData.visible)
            }
        }
    }
    EmptyState {
        objectName: "dataEmpty"; z: 4
        x: 0; y: root.headerHeight; width: root.width; height: Math.max(0, root.height - y - root.footerHeight)
        visible: rows.rows === 0 && root.emptyTitle !== ""
        title: root.emptyTitle; description: root.emptyDescription; actionText: root.emptyActionText
        iconName: root.emptyIcon; onTriggered: root.emptyTriggered()
    }
    Component.onCompleted: { refreshMeta(); updateColumns(); if (state) state.bind_model(model) }
}
