import QtQuick
import Casa.Theme
import Casa.Raster

// R658: the only owner of content masking and R624's transparency compositor.
Item {
    id: root
    property string surfaceKind: "card"
    property string surfaceId: ""
    property color fill: Theme.colors.card
    property alias color: root.fill
    property color borderColor: Theme.colors.line
    property real borderWidth: Theme.line.HAIR
    property alias border: frame.border
    readonly property color frameInk: frame.border.color
    readonly property real frameThickness: frame.border.width
    property bool frameVisible: true
    property bool rounded: true
    readonly property real radius: !rounded ? 0 : surfaceKind === "card" ? Theme.radius.CARD
                                  : surfaceKind === "view" ? Theme.radius.CONTROL : Theme.radius.CONTROL
    default property alias surfaceData: contents.data
    property Item contentItem: contents
    // A card can prepare its body at the destination size inside this mask.
    property Item contentHost: contents
    property Item headerItem: null
    property Item footerItem: null
    property Item barItem: null
    readonly property Item clippingItem: contents
    property var fade: null
    // The viewport owns Meridiana's unchanged dissolve shader. The outer mask
    // must not dissolve it a second time; software keeps the content whole.
    readonly property real topBand: 0
    readonly property real bottomBand: 0
    readonly property real topInset: 0
    readonly property real bottomInset: 0
    readonly property rect fadeRect: {
        if (!fade || !fade.flickable) return Qt.rect(0, 0, 0, 0)
        const f = fade.flickable, p = f.mapToItem(contents, 0, 0)
        return Qt.rect(p.x, p.y, f.width, f.height)
    }
    readonly property bool software: GraphicsInfo.api === GraphicsInfo.Software
    readonly property var ancestorSurface: {
        // deckOwner: out of a popup's frame, the deck still belongs to its surface (adoptSiblings)
        for (let up = parent; up; up = up.deckOwner || up.parent)
            if (up.clippingItem !== undefined && up.surfaceKind !== undefined) return up
        return null
    }
    // Only a sole page in a card shares its compositor. Sibling viewports must
    // keep independent fade parameters, even when their background is clear.
    property bool shareMask: false
    readonly property bool sharesSurface: shareMask && fill.a === 0 && frame.border.width === 0
        && ancestorSurface !== null && ancestorSurface.contentItem !== null
        && ancestorSurface.contentItem.children.length === 1 && ancestorSurface.contentItem.children[0] === root
    readonly property int rasterRevision: raster ? raster.revision : 0
    readonly property bool rasterReady: !software || sharesSurface || (raster !== null && raster.settled)
    property Item nativeOwner: null
    // Virtualized views can publish one explicit changed() signal instead of
    // observing every transient cell property. Composition stays identical.
    property QtObject revisionSource: null
    function placeSlot(item, level) { if (item) { item.parent = item === contentItem ? contentHost : contents; item.z = level } }
    // A popup's own items (a menu's list, a dialog's body, its grips) are drawn in this surface's mask. The deck that
    // holds them stands beside the popup's frame, at z 0, never inside the frame nor at its z (-1): there Qt Quick
    // Controls delivers no press and no wheel (21/11/2026: no entry of a menu answered a click, no list in a dialog
    // scrolled, since 16/11 and 61113f9; tests/casa/test_menu_clicks.py)
    readonly property Item frameLayer: deck
    function adoptSiblings(owner) {
        if (!owner) return
        nativeOwner = owner
        if (deck.parent !== owner) {
            const moves = []
            for (let i = 0; i < root.transform.length; i++) moves.push(root.transform[i])
            deck.parent = owner
            deck.transform = moves
        }
        const siblings = Array.from(owner.children)
        for (const item of siblings) if (item !== root && item !== deck) item.parent = contents
    }
    // a later adoption reaches a surface already destroyed when its popup goes at once (Quotario 21/11/2026: TypeError in
    // the logs): the closure keeps `life`, which says whether the surface is still there
    property var life: ({alive: true})
    Component.onDestruction: life.alive = false
    Connections { target: root.nativeOwner
        function onChildrenChanged() { const life = root.life; Qt.callLater(() => { if (life.alive) root.adoptSiblings(root.nativeOwner) }) }
    }
    onContentItemChanged: if (contentItem !== contents) placeSlot(contentItem, 0)
    onContentHostChanged: if (contentItem !== contents) placeSlot(contentItem, 0)
    onHeaderItemChanged: placeSlot(headerItem, 2)
    onFooterItemChanged: placeSlot(footerItem, 2)
    onBarItemChanged: placeSlot(barItem, 3)
    Rectangle { anchors.fill: parent; color: root.fill; radius: root.radius }
    Item {
        id: deck
        objectName: "surfaceDeck"
        readonly property Item deckOwner: root
        readonly property bool adopted: parent !== root
        x: adopted ? root.x : 0; y: adopted ? root.y : 0
        width: root.width; height: root.height; visible: root.visible
        // what the raster compositor reads from its parent (surface.py), the surface's own
        readonly property real radius: root.radius
        readonly property var fade: root.fade
        readonly property rect fadeRect: root.fadeRect
        readonly property real topBand: root.topBand
        readonly property real bottomBand: root.bottomBand
        readonly property real topInset: root.topInset
        readonly property real bottomInset: root.bottomInset
        readonly property QtObject revisionSource: root.revisionSource
        Item {
            id: contents
            anchors.fill: parent
            opacity: root.software && !root.sharesSurface ? 0 : 1
            // while a border is dragged the mask's texture is not made again at every width (as large as the surface,
            // twice at scale 2): the frame covers the corners until the release (21/11/2026, measured on the Dell)
            layer.enabled: !root.software && !root.sharesSurface && !ControlMetrics.resizing
            layer.effect: ShaderEffect {
                readonly property size area: Qt.size(width, height)
                readonly property real radius: root.radius
                readonly property rect fadeRect: root.fadeRect
                readonly property real topBand: root.topBand
                readonly property real bottomBand: root.bottomBand
                readonly property real topInset: root.topInset
                readonly property real bottomInset: root.bottomInset
                readonly property real room: root.fade ? root.fade.barRoom : 0
                fragmentShader: "surface.frag.qsb"
            }
        }
        RasterSurface { id: raster; anchors.fill: parent; visible: root.software && !root.sharesSurface
            source: visible ? contents : null }
        // The frame is a sibling above the entire content, including opaque slots.
        Rectangle { id: frame; anchors.fill: parent; color: "transparent"; radius: root.radius; visible: root.frameVisible
            border.color: root.borderColor; border.width: root.borderWidth; z: 1000000 }
    }
}
