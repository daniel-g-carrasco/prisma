import QtQuick
import Casa.Theme
Item {
    id: root
    property string name: ""
    property alias iconName: root.name
    property bool inactive: false
    property bool dimDisabled: true
    // the provider's light or dark drawing (symbol:); a plan has its own (PlanSymbol), the theme's otherwise
    property bool dark: Theme.dark
    // an extra part of the provider's name: «round» draws a symbol on its enclosing centre (symbol:, R515)
    property string variant: ""
    property color color: enabled ? Theme.colors.icon_ink : Theme.disabledText
    // the second layer of the Phosphor Duotone drawing (docs/30-icone.md): the theme's one colour; the stroke's own at
    // 20 %, as Phosphor draws it, when the icon is off or stands on the accent
    property color duo: root.inactive || (root.dimDisabled && !root.enabled) || Qt.colorEqual(root.color, Theme.colors.accent_fg)
                        ? Qt.alpha(root.color, 0.2) : Theme.colors.icon_duo
    // the stroke chosen in Appearance (docs/30-icone.md): Phosphor's Light ("light"), or from Theme.icon.LIGHT_FROM up
    readonly property string weight: dpr >= Theme.icon.LIGHT_MIN_DPR
        && (Theme.icon.STROKE === "light" || (Theme.icon.STROKE === "auto" && root.width >= Theme.icon.LIGHT_FROM))
        ? "light" : "regular"
    implicitWidth: Theme.icon.CONTROL
    implicitHeight: implicitWidth
    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
    readonly property point scene: {
        // Position changes include scrolling. Ancestor sizes/visibility are not
        // dependencies here: layouts can derive them from their child icons.
        for (let node = root; node; node = node.parent) { node.x; node.y }
        return mapToItem(null, 0, 0)
    }
    Image {
        // sourceSize is an integer logical QSize. Match its rounded device size,
        // then place that raster on device pixels, even in fractional layouts.
        width: Math.round(Math.round(root.width) * root.dpr) / root.dpr
        height: Math.round(Math.round(root.height) * root.dpr) / root.dpr
        x: ControlMetrics.pixelSnap(root.scene.x, (root.width - width) / 2, root.dpr)
        y: ControlMetrics.pixelSnap(root.scene.y, (root.height - height) / 2, root.dpr)
        source: root.name ? "image://casa/" + root.name + "/" + encodeURIComponent(root.color.toString())
                + "/" + (root.dark ? "dark" : "light") + "/" + (root.inactive || (root.dimDisabled && !root.enabled) ? "off" : "on")
                + "/" + root.variant + "/" + encodeURIComponent(root.duo.toString()) + "/" + root.weight : ""
        // Image applies the window DPR before asking the provider for pixels.
        sourceSize: Qt.size(Math.round(root.width), Math.round(root.height))
        smooth: false
        fillMode: Image.PreserveAspectFit
    }
    Accessible.ignored: true
}
