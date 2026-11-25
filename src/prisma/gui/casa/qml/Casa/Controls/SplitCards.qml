import QtQuick
import Casa.Theme
// A page made of two or more cards, one above the other (or side by side with orientation Qt.Horizontal), and between
// two of them a divider that the pointer and the keys move (Daniel 21/11/2026, Quotario's price list: two tables with a
// fixed line between them, «avrebbe senso renderle due schede separate»). The cards are its children; each keeps at
// least `least`; the shares are kept with the window's arrangement under `memoryKey` (M.DialogSizes, «split:» and the
// key: one for each page that gives one). The divider is the gap between the panels of the workbench (Theme.layout.GAP),
// drawn as SplitHandle, with the accent line of the workbench's handles while it is held. Up and Down (Left and Right)
// on a divider with the focus move it by a step; a double click shares the room out evenly again.
Item {
    id: root
    property int orientation: Qt.Vertical
    property string memoryKey: ""
    property real least: Theme.size.PANEL_MIN
    readonly property real gap: Theme.layout.GAP
    readonly property real step: Theme.space.XL
    default property alias cards: holder.data
    readonly property var shown: { const list = []; for (const c of holder.children) if (c.visible) list.push(c); return list }
    readonly property bool across: orientation === Qt.Horizontal
    readonly property real room: Math.max(0, (across ? width : height) - gap * Math.max(0, shown.length - 1))
    property var shares: []
    readonly property string sizeKey: memoryKey ? "split:" + memoryKey : ""
    function weights() {
        const kept = DialogSizes.sizes[sizeKey]
        const list = shares.length === shown.length ? shares : kept && kept.length === shown.length ? kept : []
        return list.length ? list : shown.map(() => 1)
    }
    function extents() {
        const w = weights(), sum = w.reduce((a, b) => a + b, 0) || 1
        const out = w.map(v => Math.max(root.least, Math.round(room * v / sum)))
        if (out.length) out[out.length - 1] = Math.max(0, room - out.slice(0, -1).reduce((a, b) => a + b, 0))
        return out
    }
    function place() {
        const sizes = extents()
        let at = 0
        shown.forEach((card, i) => {
            if (across) { card.x = at; card.y = 0; card.width = sizes[i]; card.height = root.height }
            else { card.x = 0; card.y = at; card.width = root.width; card.height = sizes[i] }
            at += sizes[i] + root.gap
        })
        handles.model = Math.max(0, shown.length - 1)
    }
    // a divider moved: the two cards it parts share their room, each never under `least`
    function move(index, by) {
        const sizes = extents(), pair = sizes[index] + sizes[index + 1]
        const first = Math.max(root.least, Math.min(pair - root.least, sizes[index] + by))
        const next = sizes.slice(); next[index] = first; next[index + 1] = pair - first
        shares = next
    }
    function keep() {
        if (!sizeKey) return
        const next = Object.assign({}, DialogSizes.sizes); next[sizeKey] = extents(); DialogSizes.sizes = next
    }
    function even() { shares = shown.map(() => 1); keep() }
    function dividerAt(index) {
        const sizes = extents()
        let at = 0
        for (let i = 0; i <= index; i++) at += sizes[i] + (i < index ? gap : 0)
        return at
    }
    onWidthChanged: place()
    onHeightChanged: place()
    onSharesChanged: place()
    onShownChanged: place()
    Connections { target: DialogSizes; function onSizesChanged() { if (!root.shares.length) root.place() } }
    Component.onCompleted: place()
    Item { id: holder; anchors.fill: parent }
    Repeater {
        id: handles
        SplitHandle {
            id: divider
            required property int index
            objectName: "splitDivider" + index
            orientation: root.across ? Qt.Vertical : Qt.Horizontal
            x: root.across ? root.dividerAt(index) : 0
            y: root.across ? 0 : root.dividerAt(index)
            width: root.across ? root.gap : root.width
            height: root.across ? root.height : root.gap
            activeFocusOnTab: true
            Accessible.role: Accessible.Separator
            Keys.onUpPressed: { root.move(index, -root.step); root.keep() }
            Keys.onLeftPressed: { root.move(index, -root.step); root.keep() }
            Keys.onDownPressed: { root.move(index, root.step); root.keep() }
            Keys.onRightPressed: { root.move(index, root.step); root.keep() }
            Rectangle { objectName: "splitDividerLine"; anchors.centerIn: parent; color: Theme.colors.accent
                width: root.across ? Theme.line.HAIR : parent.width; height: root.across ? parent.height : Theme.line.HAIR
                visible: drag.pressed || Theme.focusRing(divider) }
            MouseArea {
                id: drag
                anchors.fill: parent
                cursorShape: root.across ? Qt.SplitHCursor : Qt.SplitVCursor
                property real start
                property real first
                onPressed: mouse => { const p = mapToItem(root, mouse.x, mouse.y); start = root.across ? p.x : p.y
                    first = root.extents()[divider.index]; divider.forceActiveFocus(Qt.MouseFocusReason) }
                onPositionChanged: mouse => {
                    if (!pressed) return
                    const p = mapToItem(root, mouse.x, mouse.y)
                    root.move(divider.index, first + (root.across ? p.x : p.y) - start - root.extents()[divider.index])
                }
                onReleased: root.keep()
                onDoubleClicked: root.even()
            }
        }
    }
}
