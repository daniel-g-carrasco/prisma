import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import Casa.Theme

// The shared path style, also used inside batched Shapes (no Item per segment).
ShapePath {
    property bool dashed: false
    property real viewScale: 1
    property bool halo: false
    property color ink: Theme.colors.overlay.pill_ink
    property Item surface: null
    // Software cosmetic pens use physical pixels; CurveRenderer uses logical pixels.
    readonly property bool software: surface && surface.GraphicsInfo.api === GraphicsInfo.Software
    readonly property real pixelRatio: software ? surface.Screen.devicePixelRatio : 1
    // CurveRenderer keeps the pen cosmetic, but still transforms its dash distances.
    readonly property real dashScale: software ? 1 : Math.max(.00002, Math.abs(viewScale))
    strokeWidth: (Theme.annotation.STROKE + (halo ? Theme.annotation.HALO_EXTRA : 0)) * pixelRatio
    strokeColor: halo ? Qt.rgba(0, 0, 0, ink.a > 0 ? Theme.annotation.HALO_ALPHA : 0) : ink
    fillColor: "transparent"
    cosmeticStroke: true
    capStyle: dashed ? ShapePath.FlatCap : ShapePath.RoundCap
    joinStyle: ShapePath.RoundJoin
    strokeStyle: dashed ? ShapePath.DashLine : ShapePath.SolidLine
    dashPattern: [Theme.annotation.DASH_ON * pixelRatio / (strokeWidth * dashScale),
                  Theme.annotation.DASH_OFF * pixelRatio / (strokeWidth * dashScale)]
}
