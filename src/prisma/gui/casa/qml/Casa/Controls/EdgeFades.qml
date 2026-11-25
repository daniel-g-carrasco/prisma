import QtQuick
import Casa.Theme
// The soft ends of every area that scrolls (R624, Daniel 15/11/2026: «la sfumatura deve essere una trasparenza
// gradiente del contenuto», «mantenerla ben centralizzata»): near an edge with more content beyond it, what scrolls
// becomes transparent and what lies under the area shows through. One rule for any content: the rows on their card,
// the white sheet of the report in the dark theme, a page of text. Until R624 a band of one colour (the ground
// guessed above the area) was painted over the content: a darker strip over the Checks' rows on the card colour and a
// dark band on the report's sheet, cut by the edge in between (edgefade.frag has the curve: smoothstep, no kink).
// Placed by M.ScrollPage, M.List, M.Tree, M.Table, M.Dialog and every vertical M.ScrollBar; never by hand
// (tests/quick/sistema/test_sfumature_r624.py).
// History kept: R161 never over a card's border or bar (the dissolve is inside the viewport, the bar's lane `barRoom`
// left whole), R177 nothing whole at the edge, R192 short, R590 as tall as what has gone past the edge, whole at the
// edge from the first pixel.
// When the backing colour is opaque and uniform, painting that colour with the inverse curve is
// equivalent to dissolving the content over it. Other backings still use the original layer.
Item {
    id: root
    objectName: "edgeFades"
    property Flickable flickable
    // the bar's lane inside the flickable, at its right: left whole
    property real barRoom: 0
    property color ground: "transparent"
    // Daniel 21/11/2026, the final choice: the shadow only where the sides are closed (a table, a list or a tree in its
    // frame: spansSurface false); everywhere else (pages, Settings, panels, columns in the middle) the dissolve. One
    // rule each area that scrolls applies by its nature; the shadow's level stays ControlMetrics.shadeLevel.
    // edgeFades "dissolve" in the appearance makes every area dissolve.
    readonly property bool undershoot: Theme.options.edgeFades === "shadow" && !spansSurface
    property bool spansSurface: true
    // An inset view uses its own content edge. Surface clips the shade with the rest of the viewport.
    property real contentEdge: width - barRoom
    readonly property color tone: Theme.colors.undershoot
    readonly property color shade: Qt.rgba(tone.r, tone.g, tone.b, Math.min(1, tone.a * ControlMetrics.shadeStrength))
    // R633: the heads held at the edges of the area (HeldHeads.qml, M.ScrollPage of a panel): the content under them is
    // not drawn, and it dissolves from their edge (topInset, bottomInset), no taller than they allow (topRoom,
    // bottomRoom: the content gone under them, never over a head in its place)
    property Item held: null
    // Surface keeps only its corner mask. Meridiana's shader owns the dissolve.
    readonly property var surface: {
        for (let up=parent; up; up=up.parent) if (up.surfaceKind !== undefined && up.clippingItem !== undefined) return up
        return null
    }
    Binding { target: root.surface; property: "fade"; value: root; when: root.surface !== null }
    anchors.fill: flickable
    readonly property real band: flickable !== null ? Math.max(0, Math.min(Theme.size.FADE, Math.floor(flickable.height / 5))) : 0
    readonly property real above: flickable !== null ? flickable.contentY - flickable.originY : 0
    readonly property real below: flickable !== null ? flickable.originY + flickable.contentHeight - flickable.contentY - flickable.height : 0
    readonly property real topInset: held !== null ? held.topInset : 0
    readonly property real bottomInset: held !== null ? held.bottomInset : 0
    // the heights of the two dissolves: as tall as the content gone past the edge, up to the band
    readonly property real topBand: Math.max(0, Math.min(band, above, held !== null ? held.topRoom : band))
    readonly property real bottomBand: Math.max(0, Math.min(band, below, held !== null ? held.bottomRoom : band))
    readonly property bool drawn: GraphicsInfo.api !== GraphicsInfo.Software && GraphicsInfo.api !== GraphicsInfo.Unknown
    readonly property bool active: drawn && flickable !== null && band > 0 && (above > 0 || below > 0)
    readonly property bool compact: active && !undershoot && ground.a === 1 && held === null
    Binding { target: root.flickable; property: "layer.effect"; value: dissolve; when: root.flickable !== null }
    Binding { target: root.flickable; property: "layer.enabled"; value: root.active && !root.undershoot && !root.compact; when: root.flickable !== null }
    Loader {
        active: root.compact
        sourceComponent: Item {
            Rectangle { id: backing; width: 1; height: 1; color: root.ground }
            ShaderEffectSource {
                id: groundTexture
                sourceItem: backing; hideSource: true; visible: false
                textureSize: Qt.size(1, 1)
            }
            component DissolveBand: ShaderEffect {
                required property bool atTop
                property var source: groundTexture
                readonly property size area: Qt.size(width, height)
                readonly property real topBand: atTop ? 0 : height
                readonly property real bottomBand: atTop ? height : 0
                readonly property real topInset: 0
                readonly property real bottomInset: 0
                readonly property real room: 0
                width: Math.max(0, root.width - root.barRoom)
                height: atTop ? root.topBand : root.bottomBand
                y: atTop ? 0 : root.height - height
                visible: width > 0 && height > 0
                fragmentShader: "edgefade.frag.qsb"
            }
            DissolveBand { objectName: "topDissolveBand"; atTop: true }
            DissolveBand { objectName: "bottomDissolveBand"; atTop: false }
        }
    }
    component Undershoot: Rectangle {
        id: shadow
        required property bool atTop
        readonly property real room: root.held === null ? root.height : atTop ? root.held.topRoom : root.held.bottomRoom
        readonly property real remaining: atTop ? root.above : root.below
        readonly property real fraction: height > 0 ? Math.min(1, Math.max(0, remaining / height)) : 0
        width: Math.max(0, Math.min(root.width - root.barRoom, root.contentEdge))
        height: Math.max(0, Math.min(ControlMetrics.shadeDepth, root.height / 2, room))
        y: atTop ? root.topInset : root.height - root.bottomInset - height
        opacity: root.undershoot ? fraction * fraction * (3 - 2 * fraction) : 0
        visible: opacity > 0 && width > 0
        gradient: Gradient {
            GradientStop { position: 0; color: shadow.atTop ? root.shade : "transparent" }
            GradientStop { position: 1; color: shadow.atTop ? "transparent" : root.shade }
        }
    }
    Undershoot { objectName: "topUndershoot"; atTop: true }
    Undershoot { objectName: "bottomUndershoot"; atTop: false }
    Component {
        id: dissolve
        ShaderEffect {
            objectName: "edgeDissolve"
            readonly property size area: Qt.size(width, height)
            readonly property real topBand: root.topBand
            readonly property real bottomBand: root.bottomBand
            readonly property real room: root.barRoom
            readonly property real topInset: root.topInset
            readonly property real bottomInset: root.bottomInset
            fragmentShader: "edgefade.frag.qsb"
        }
    }
}
