pragma Singleton
import QtQuick
import Casa.Theme

QtObject {
    readonly property real inset: Theme.space.S
    readonly property var pageSize: ({properties: {width: 380, height: 700}})
    readonly property real pageLeast: Theme.size.READING
    readonly property var dialogSize: ({message: {width: 640}, compare: {width: 900, height: 660},
        file: {shortcuts: [640, 560], update: [520, 0], report_bug: [680, 640], about: [600, 0], other: [560, 0]}})

    // The first line's painted middle, also for a wrapped caption or a replacement contentItem.
    // baselineOffset belongs to the live text, so its padding and vertical alignment are included.
    function firstLineMiddle(words) {
        const width = words.width - (words.leftPadding || 0) - (words.rightPadding || 0)
        const ink = Theme.textBlockInk(words.text, width, words.textStyle, words.condensed || false)
        return words.y + words.baselineOffset + (ink.top + ink.firstBottom) / 2
    }
    function textMiddleOffset(words) {
        const ink = Theme.textBlockInk(words.text, words.width, words.textStyle, words.condensed)
        return words.baselineOffset + (ink.top + ink.bottom) / 2
    }
    readonly property real viewButton: 27
    readonly property real viewArrow: Theme.space.XL
    readonly property real viewPlainWidth: 19 + 2 * Theme.space.S
    readonly property real fieldInset: Theme.space.M + 2
    readonly property int arrowDepth: 4
    readonly property real chevronBox: 20
    readonly property real dialogPad: Theme.space.XL
    readonly property real dialogGap: Theme.space.M
    readonly property real dialogButtonGap: Theme.space.M
    readonly property real dialogEdge: 16
    readonly property real dialogHold: 2 * Theme.size.CONTROL
    readonly property real dialogGrip: Theme.space.S
    readonly property var dialogLeast: ({width: dialogWidth.narrow, body: 3 * Theme.size.CONTROL})
    readonly property real workPhase: 200
    readonly property real progressThread: Theme.line.FOCUS
    readonly property real progressGap: Theme.space.XS
    readonly property var dialogWidth: ({narrow: 420, normal: 560, wide: 720, page: 1200})
    readonly property real scrollLane: Theme.size.SCROLLBAR
    readonly property real scrollGap: Theme.space.XXS
    readonly property real wheelNotch: 72
    readonly property real cardMargin: Theme.space.L + Theme.line.HAIR
    // every bar's thumb (ScrollBar): at rest and under the pointer. GNOME (libadwaita 1.8) has 3 and 8 px: 4 keeps
    // the thumb on whole pixels, the same air at its two sides, in the 10 px lane and in a card's margin (R704)
    readonly property real marginThumb: Theme.space.XS
    readonly property real marginThumbHover: Theme.space.M
    readonly property real panelGap: Theme.space.S
    readonly property real heldShare: 1 / 4
    readonly property real menuPad: Theme.space.XS
    readonly property real menuItemRadius: Theme.radius.INNER
    readonly property real menuItemPadV: Theme.space.S
    readonly property real menuInset: Theme.space.L
    readonly property real menuItemPadH: menuInset - menuPad
    // a row of a tree or a list (20/11/2026): a menu entry's shape, menuPad in from the sides with its radius, chosen
    // in select_bg and lit in hover under the pointer; the tables keep their band across the columns
    readonly property real rowInset: menuPad
    // The edges (Daniel 21/11/2026, Quotario's Categories: «grossi problemi ad avere margini simmetrici e armonizzati...
    // armonizziamoli e centralizziamoli»), one rule for every card, panel and page: what a body holds stands on its two
    // lines, cardMargin in from the border: a field, a button, the lit row of a list or a tree without a frame of its
    // own (rowGround). In a row the words and the marks start rowPad in from its ground, the figures end rowPad before
    // it. A bar scrolls beside what it scrolls, never over it: in the card's margin for a body without a frame
    // (ScrollBar.inMargin), in its lane (scrollLane) inside a frame, scrollBreath past the last column of a table.
    // Every lane of a bar takes the ground of the band beside it (a table's heading, its totals): never a strip of the
    // content's ground inside a band (tests/casa/test_lanes_ground.py).
    readonly property real rowPad: rowInset + Theme.space.S
    // Inner gradients for scrolling edges (EdgeFades). Level 0 keeps the base libadwaita tint and depth.
    // Levels 1 and 2 make the gradient more visible (Daniel 21/11/2026).
    property int shadeLevel: 1
    // an edge of the workbench or a divider is being dragged (Shell/Workbench.qml): what costs and does not follow the
    // width by itself (a DataTable's heights and wrapped texts) waits for the release
    property bool resizing: false
    readonly property real shadeStrength: [1, 1.8, 2.6][shadeLevel]
    readonly property real shadeDepth: [4, 6, 8][shadeLevel]
    readonly property real scrollBreath: Theme.space.S
    function rowGround(framed) { return framed ? rowInset : 0 }
    readonly property real rowRadius: menuItemRadius
    function rowFill(chosen, hovered, enabled) {
        return chosen ? Theme.colors.select_bg : hovered && enabled ? Theme.colors.hover : "transparent"
    }
    readonly property real menuCheck: Theme.space.L
    readonly property real menuColumnGap: Theme.space.XXL
    readonly property real menuWide: 620
    readonly property real menuTall: 420
    readonly property real reboundReach: Theme.space.L
    readonly property int growLines: 6
    readonly property real viewMark: 20
    readonly property real helpMark: 20
    readonly property real focusGrow: 6
    readonly property real pixelEpsilon: 1 / 64
    readonly property real helpBubble: 264
    readonly property real helpFoot: Theme.space.XS
    readonly property int helpLines: 8
    readonly property real pointer: 10
    readonly property real toolPad: Theme.space.XS + 1
    readonly property int menuReveal: 140
    readonly property real menuSlide: 6
    readonly property real menuStepMax: .15
    readonly property int tipEnter: 90
    readonly property int tipExit: 60
    readonly property int tipDelay: 700
    readonly property real tipRight: 2
    readonly property real tipBelow: 21
    readonly property real tipAbove: 4
    readonly property real tipEdge: Theme.space.S
    readonly property real tipGap: Theme.space.XS
    function pixelSnap(scene, local, dpr) {
        return (Math.round((scene + local) * dpr) - scene * dpr) / dpr
    }
    function textBaseline(height, metrics, dpr) {
        const ratio = dpr > 0 ? dpr : 1
        return Math.round((height + metrics.tightBoundingRect("H").height) / 2 * ratio) / ratio
    }
    function besidePointer(at, width, height, room) {
        let x = at.x + tipRight, y = at.y + tipBelow
        if (x + width > room.x + room.width - tipEdge) x = at.x - tipRight - width
        if (y + height > room.y + room.height - tipEdge) y = at.y - tipAbove - height
        x = Math.max(room.x + tipEdge, Math.min(x, room.x + room.width - tipEdge - width))
        y = Math.max(room.y + tipEdge, Math.min(y, room.y + room.height - tipEdge - height))
        return Qt.point(x, y)
    }
    function besideMenu(frameAt, frameWidth, width, height, room) {
        let x = frameAt.x + frameWidth + tipGap
        if (x + width > room.x + room.width - tipEdge) x = frameAt.x - tipGap - width
        x = Math.max(room.x + tipEdge, Math.min(x, room.x + room.width - tipEdge - width))
        const y = Math.max(room.y + tipEdge, Math.min(0, room.y + room.height - tipEdge - height))
        return Qt.point(x, y)
    }
    function roomOf(item, clipped) {
        let room = null
        for (let node = item; node; node = node.parent) {
            if (!(node.parent === null || (clipped && node.clip))) continue
            const corner = item.mapFromItem(node, 0, 0), next = Qt.rect(corner.x, corner.y, node.width, node.height)
            if (!room) { room = next; continue }
            const left = Math.max(room.x, next.x), top = Math.max(room.y, next.y)
            room = Qt.rect(left, top, Math.max(0, Math.min(room.x + room.width, next.x + next.width) - left),
                           Math.max(0, Math.min(room.y + room.height, next.y + next.height) - top))
        }
        return room || Qt.rect(0, 0, item.width, item.height)
    }
    function words(text) {
        return String(text || "").replace(/&(?!&)/g, "").replace(/[\s.…:]+$/u, "").replace(/\s+/g, " ").trim().toLocaleLowerCase()
    }
    function tipAdds(tip, shown, cut) {
        return words(tip) !== "" && (cut === true || words(tip) !== words(shown))
    }
}
