import QtQuick
import QtQuick.Templates as T
import Casa.Theme

// The totals of a summary page (docs/27-pagine-di-dati.md, Daniel 21/11/2026: variant C of the study): chapters and
// their parts as a table that opens and closes, in a column that never goes from one side of the window to the other
// (its owner limits it: SummarySheet, two reading columns and their gap).
// `model` is one root {id, text, amount, value, children}: `amount` is the text to read, `value` the same as a number
// (the shares and the order need it). `labels` are the words: {title, name, amount, share, parentShare, byAmount,
// byAmountTip, levels, all}. From the top:
//  - the tools: the title, «By amount» (the rows of every level from the largest; off, the document's order) and the
//    levels shown (1, 2, ... down to the deepest, then «All»); `tools` false leaves them to the page;
//  - the names of the columns; the total, always in view over what scrolls, with a line under it;
//  - the rows: the levels told by weight and ink (a chapter strong, a part in the text's weight, deeper in the second
//    ink) as well as by the indent, a soft line over every chapter; the amounts in a column of figures of one width,
//    then the share of the total and the share of the chapter, in the muted ink.
// Keys as Tree: the arrows, Home, End, Return; a double click opens and closes. `activated(node)` on a click.
FocusScope {
    id: root
    property var model: []
    property var expandedIds: []
    property bool tools: true
    property var labels: ({title: "", name: "", amount: "", share: "", parentShare: "", byAmount: "", byAmountTip: "", levels: "", all: ""})
    property bool sortByAmount: false
    property bool condensed: true
    property int currentIndex: -1
    signal activated(var node)
    readonly property var lead: model.length === 1 ? model[0] : null
    readonly property var topNodes: lead ? (lead.children || []) : model
    readonly property real total: lead ? lead.value || 0 : topNodes.reduce((sum, node) => sum + (node.value || 0), 0)
    readonly property var rows: flatten(topNodes, 0, total)
    readonly property int count: rows.length
    readonly property int levels: depthOf(topNodes)
    // the measures, all from the theme
    readonly property real inset: ControlMetrics.rowInset
    // the names of the head and the figures of every line stand a card's title away from the two sides, as the
    // results over the totals do: the scroll bar comes and goes in that margin
    readonly property real side: Theme.layout.TITLE_X
    // the scroll bar's lane at the right, always kept (no jump when the bar comes), and its gap: the rows, the head
    // and the tools end before it (ControlMetrics.scrollLane, scrollGap, as a ScrollPage keeps its bar's room)
    readonly property real lane: ControlMetrics.scrollLane + ControlMetrics.scrollGap
    readonly property real contentRight: width - lane
    readonly property real indentStep: Theme.space.L
    readonly property real columnGap: Theme.space.XL
    readonly property real rowHeight: Math.ceil(Theme.measureText("Ag", "body", condensed).height) + Theme.rowAir + Theme.space.XS
    readonly property real amountWidth: {
        const revision = Theme.revision
        let widest = Theme.measureText(labels.amount || "", "caption").width
        for (const node of (lead ? [lead] : topNodes)) widest = Math.max(widest, Theme.measureText(node.amount || "", "strong", condensed).width)
        return Math.ceil(widest) + Theme.space.XS
    }
    readonly property real shareWidth: {
        const revision = Theme.revision
        return Math.ceil(Math.max(Theme.measureText(percent(1), "secondary").width,
                                  Theme.measureText(labels.share || "", "caption").width,
                                  Theme.measureText(labels.parentShare || "", "caption").width)) + Theme.space.XS
    }
    // what stands at the right of the names: the amount, the share of the total, the share of the chapter
    readonly property real figuresWidth: amountWidth + 2 * (columnGap + shareWidth)
    function percent(part) { return (100 * part).toLocaleString(Qt.locale(), "f", 1) + " %" }
    function depthOf(nodes) {
        let deepest = 0
        for (const node of nodes) deepest = Math.max(deepest, 1 + (node.children ? depthOf(node.children) : 0))
        return deepest
    }
    function flatten(nodes, depth, parentValue) {
        const list = nodes.slice()
        if (sortByAmount) list.sort((a, b) => (b.value || 0) - (a.value || 0))
        let out = []
        for (const node of list) {
            const opens = !!node.children && node.children.length > 0
            const open = opens && expandedIds.indexOf(node.id) >= 0
            out.push({node: node, depth: depth, opens: opens, open: open, parentValue: parentValue})
            if (open) out = out.concat(flatten(node.children, depth + 1, node.value || 0))
        }
        return out
    }
    // the levels open, 0 for all
    property int shownLevels: 0
    function expandTo(level) {
        shownLevels = level
        const ids = []
        const walk = (nodes, depth) => {
            for (const node of Array.from(nodes || [])) if (node.children && node.children.length) {
                if (level === 0 || depth < level - 1) ids.push(node.id)
                walk(node.children, depth + 1)
            }
        }
        // a list from Python is a sequence, not an Array (Quotario 21/11/2026: Array.isArray false, nothing opened)
        walk(topNodes ? Array.from(topNodes) : [], 0)
        expandedIds = ids
        if (currentIndex >= count) currentIndex = count - 1
    }
    function toggle(index) {
        if (index < 0 || index >= count || !rows[index].opens) return
        const next = expandedIds.slice(), at = next.indexOf(rows[index].node.id)
        if (at < 0) next.push(rows[index].node.id); else next.splice(at, 1)
        expandedIds = next
        if (currentIndex >= count) currentIndex = count - 1
    }
    function select(index) { if (index >= 0 && index < count) { currentIndex = index; activated(rows[index].node) } }
    objectName: "totalsTree"
    Component.onCompleted: expandTo(shownLevels)
    onModelChanged: expandTo(shownLevels)
    implicitWidth: Theme.layout.PAGE_WIDTH
    implicitHeight: toolRow.height + head.height + Math.min(12, count) * rowHeight
    activeFocusOnTab: true
    Accessible.role: Accessible.Tree
    Keys.onDownPressed: select(Math.min(count - 1, currentIndex + 1))
    Keys.onUpPressed: select(Math.max(0, currentIndex - 1))
    Keys.onRightPressed: {
        if (currentIndex < 0) return
        if (rows[currentIndex].opens && !rows[currentIndex].open) toggle(currentIndex)
        else if (rows[currentIndex].open) select(currentIndex + 1)
    }
    Keys.onLeftPressed: {
        if (currentIndex < 0) return
        if (rows[currentIndex].open) { toggle(currentIndex); return }
        for (let i = currentIndex - 1; i >= 0; i--) if (rows[i].depth < rows[currentIndex].depth) { select(i); break }
    }
    Keys.onReturnPressed: toggle(currentIndex)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Home) { select(0); event.accepted = true }
        else if (event.key === Qt.Key_End) { select(count - 1); event.accepted = true }
    }

    // The tools: the title, the order, the levels
    Item {
        id: toolRow
        objectName: "totalsTools"
        visible: root.tools
        // the tools under the title when the two do not stand on one line
        readonly property bool stacked: root.side + title.implicitWidth + Theme.space.XL + tools.width > root.contentRight
        width: root.width
        height: visible ? (stacked ? 2 * Theme.size.CONTROL + Theme.space.XS : Theme.size.CONTROL) + Theme.space.M : 0
        Label { id: title; x: root.side; height: Theme.size.CONTROL; text: root.labels.title || ""; textStyle: "title"; verticalAlignment: Text.AlignVCenter }
        Row {
            id: tools
            x: root.contentRight - width; y: toolRow.stacked ? Theme.size.CONTROL + Theme.space.XS : 0
            spacing: Theme.space.M
            Button {
                objectName: "totalsByAmount"
                text: root.labels.byAmount || ""; iconName: "arrow-down"; checkable: true; checked: root.sortByAmount
                // flat: on, it shows pressed (Button: a flat button that is on), as a tool of the bar
                flat: true
                tip: root.labels.byAmountTip || ""
                onToggled: root.sortByAmount = checked
            }
            Label { height: Theme.size.CONTROL; text: root.labels.levels || ""; textStyle: "secondary"; verticalAlignment: Text.AlignVCenter }
            Segments {
                objectName: "totalsLevels"
                model: Array.from({length: Math.max(0, root.levels - 1)}, (_, i) => String(i + 1)).concat([root.labels.all || "*"])
                currentIndex: root.shownLevels === 0 ? model.length - 1 : root.shownLevels - 1
                onActivated: index => root.expandTo(index === model.length - 1 ? 0 : index + 1)
            }
        }
    }
    // The head, over what scrolls: the names of the columns, the total, a line.
    Column {
        id: head
        objectName: "totalsHead"
        y: toolRow.height
        width: root.width
        Item {
            width: parent.width; height: visible ? Math.ceil(Theme.measureText("Ag", "caption").height) + Theme.space.S : 0
            Label { x: root.side; height: parent.height; text: root.labels.name || ""; textStyle: "caption" }
            Figures { tree: root; x: root.contentRight - width - root.side; titles: true }
        }
        Item {
            visible: root.lead !== null
            width: parent.width; height: visible ? root.rowHeight + Theme.space.XS : 0
            Label {
                objectName: "totalsLeadName"
                x: root.side; height: parent.height
                width: Math.max(0, leadFigures.x - x - root.columnGap)
                text: root.lead ? root.lead.text : ""; textStyle: "strong"; condensed: root.condensed; elide: Text.ElideRight
            }
            Figures {
                id: leadFigures
                tree: root
                x: root.contentRight - width - root.side
                amount: root.lead ? root.lead.amount || "" : ""; part: root.total > 0 ? 1 : -1; textStyle: "strong"
            }
        }
        Rectangle { width: root.contentRight; height: Theme.line.HAIR; color: Theme.colors.line }
    }
    ListView {
        id: view
        objectName: "totalsRows"
        y: head.y + head.height; width: root.width; height: Math.max(0, root.height - y)
        clip: true; boundsBehavior: Flickable.StopAtBounds
        model: root.rows; currentIndex: root.currentIndex
        onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
        T.ScrollBar.vertical: ScrollBar { fades: false; parent: root; flickable: view; x: view.width - width; y: view.y; height: view.height }
        delegate: Item {
            id: line
            required property var modelData
            required property int index
            readonly property var node: modelData.node
            readonly property bool chosen: root.currentIndex === index
            // the levels by weight: a chapter strong, its parts in the text's weight, what is deeper in the second ink
            readonly property string textStyle: modelData.depth === 0 ? "strong" : "body"
            readonly property color ink: modelData.depth < 2 ? Theme.colors.text : Theme.colors.text2
            readonly property real part: root.total > 0 ? (node.value || 0) / root.total : -1
            width: view.width; height: root.rowHeight
            Accessible.role: Accessible.TreeItem
            Accessible.name: node.text + ", " + (node.amount || "") + (part >= 0 ? ", " + root.percent(part) : "")
            // a soft line over every chapter but the first: the chapters read as blocks
            Rectangle {
                visible: line.modelData.depth === 0 && line.index > 0
                x: root.inset; width: root.contentRight - 2 * x; height: Theme.line.HAIR; color: Theme.colors.line_soft
            }
            Rectangle {
                x: root.inset; y: Theme.line.HAIR; width: root.contentRight - 2 * x; height: parent.height - 2 * y
                radius: ControlMetrics.rowRadius
                color: ControlMetrics.rowFill(line.chosen, hover.hovered, root.enabled)
            }
            HoverHandler { id: hover }
            TapHandler {
                onTapped: { root.forceActiveFocus(Qt.MouseFocusReason); root.select(line.index) }
                onDoubleTapped: root.toggle(line.index)
            }
            Item {
                id: arrow
                x: root.inset + line.modelData.depth * root.indentStep
                width: ControlMetrics.chevronBox; height: parent.height
                visible: line.modelData.opens
                Chevron { anchors.centerIn: parent; open: line.modelData.open; active: hover.hovered }
                TapHandler { onTapped: { root.forceActiveFocus(Qt.MouseFocusReason); root.currentIndex = line.index; root.toggle(line.index) } }
            }
            Label {
                id: name
                objectName: "totalsName"
                x: arrow.x + arrow.width + Theme.space.XXS; height: parent.height
                width: Math.max(0, rowFigures.x - x - root.columnGap)
                text: line.node.text; textStyle: line.textStyle; color: line.ink
                condensed: root.condensed; elide: Text.ElideRight
            }
            ToolTip { text: line.node.text; visible: hover.hovered && name.truncated }
            Figures {
                id: rowFigures
                tree: root
                x: root.contentRight - width - root.side
                amount: line.node.amount || ""; textStyle: line.textStyle; ink: line.ink
                part: line.part
                ofParent: line.modelData.parentValue > 0 ? (line.node.value || 0) / line.modelData.parentValue : -1
            }
        }
    }
    Rectangle {
        visible: Theme.focusRing(root)
        anchors.fill: parent; anchors.margins: -Theme.space.XXS; radius: Theme.radius.CONTROL; color: "transparent"
        border.width: Theme.line.FOCUS; border.color: Theme.colors.focus
    }

    // One line of figures: the amount, the share of the total, the share of the chapter. The same item for the head and
    // for every row, so that the columns stand one under the other; `titles` makes it the line of the columns' names.
    component Figures: Item {
        id: figures
        property Item tree
        property string amount: ""
        property real part: -1
        property real ofParent: -1
        property string textStyle: "body"
        property color ink: Theme.colors.text
        property bool titles: false
        readonly property string quiet: titles ? "caption" : "secondary"
        width: figures.tree.figuresWidth; height: parent.height
        Label {
            objectName: "totalsAmount"
            width: figures.tree.amountWidth; height: parent.height
            text: figures.titles ? figures.tree.labels.amount || "" : figures.amount
            textStyle: figures.titles ? "caption" : figures.textStyle; condensed: !figures.titles && figures.tree.condensed
            color: figures.titles ? Theme.colors.muted : figures.ink
            font.features: ({"tnum": 1}); horizontalAlignment: Text.AlignRight
        }
        Label {
            objectName: "totalsShare"
            x: figures.tree.amountWidth + figures.tree.columnGap
            width: figures.tree.shareWidth; height: parent.height
            text: figures.titles ? figures.tree.labels.share || "" : figures.part >= 0 ? figures.tree.percent(figures.part) : ""
            textStyle: figures.quiet; color: Theme.colors.muted
            font.features: ({"tnum": 1}); horizontalAlignment: Text.AlignRight
        }
        Label {
            objectName: "totalsParentShare"
            x: figures.tree.figuresWidth - figures.tree.shareWidth; width: figures.tree.shareWidth; height: parent.height
            text: figures.titles ? figures.tree.labels.parentShare || "" : figures.ofParent >= 0 ? figures.tree.percent(figures.ofParent) : ""
            textStyle: figures.quiet; color: Theme.colors.muted
            font.features: ({"tnum": 1}); horizontalAlignment: Text.AlignRight
        }

    }
}
