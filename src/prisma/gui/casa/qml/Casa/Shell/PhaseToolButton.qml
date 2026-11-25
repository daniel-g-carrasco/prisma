import QtQuick
import QtQuick.Shapes
import Casa.Theme
import Casa.Controls as M

M.ToolButton {
    id: root
    property bool primary: false
    // R396 deliberately removes the old primary emphasis from Calculate/Place.
    flat: true
    // G5 (Daniel 21/11/2026, «tipo AutoCAD»): the small form, the icon alone in a square of PhaseHeader.smallSize, the name
    // and the keys in the tooltip, which then always says them (docs/28-barra-piccola.md)
    readonly property bool small: mode === "small"
    textShown: !small
    // Meridiana R731 (Daniel 22/11/2026): the job this command started is in progress (work.busyCommands, its tooltip
    // then). With its word, the job's thread under it; as a sign only (small, icons), the job's ring around the sign
    // (sketch S1: the sign stays, so one sees which command works), inside the button, moving nothing. The command
    // cannot start the job twice (PhaseHeader gives enabled false) and its tooltip says how to stop it.
    property string busyTip: ""
    readonly property bool busy: busyTip !== ""
    readonly property bool ringed: busy && (small || mode === "icons")
    property string faceTip: ""
    tip: busy ? busyTip : faceTip
    // R614: the icon and the word in the middle in every mode, so that the air the width's steps leave is the same on the
    // two sides, before the word as after it (up to a split button's strip: PhaseSplitButton's command is this button)
    contentItem: Item {
        M.Icon { id: symbol; iconName: root.iconName; width: root.small ? Theme.icon.CONTROL : Theme.bar.ICON[root.mode]; height: width
            x: root.mode==="beside" ? Math.round((parent.width-width-Theme.bar.WORD_GAP-word.implicitWidth)/2) : (parent.width-width)/2
            // the kit's soft stroke (Icon's own colour, docs/30-icone.md), also when the command is on or pressed
            y: root.mode==="under" ? (parent.height-height-word.implicitHeight-Theme.space.XXS)/2 : (parent.height-height)/2 }
        M.Label { id: word; text: root.text; textStyle: "secondary"; condensed: true; enabled: root.enabled
            visible: root.mode!=="icons" && !root.small
            x: root.mode==="beside" ? symbol.x+symbol.width+Theme.bar.WORD_GAP : (parent.width-width)/2
            y: root.mode==="under" ? symbol.y+symbol.height+Theme.space.XXS : (parent.height-height)/2 }
        M.ProgressBar { objectName: "toolBusy"; visible: root.busy && !root.ringed; indeterminate: true
            width: visible ? parent.width - 2 * Theme.space.S : 0; x: Theme.space.S; y: parent.height - height }
        // the thread of M.ProgressBar bent into a ring: the same thickness and greys, a quarter turning
        Shape { id: ring; objectName: "toolRing"; visible: root.ringed
            readonly property real thread: M.ControlMetrics.progressThread
            property real angle: 0
            width: visible ? Math.min(symbol.width + 2 * Theme.space.XS, parent.width, parent.height) : 0; height: width
            x: symbol.x + (symbol.width - width) / 2; y: symbol.y + (symbol.height - height) / 2
            preferredRendererType: Shape.CurveRenderer
            ShapePath { strokeColor: Theme.colors.line_soft; strokeWidth: ring.thread; fillColor: "transparent"
                PathAngleArc { centerX: ring.width / 2; centerY: ring.height / 2; radiusX: (ring.width - ring.thread) / 2
                    radiusY: radiusX; startAngle: 0; sweepAngle: 360 } }
            ShapePath { strokeColor: Theme.colors.text2; strokeWidth: ring.thread; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: ring.width / 2; centerY: ring.height / 2; radiusX: (ring.width - ring.thread) / 2
                    radiusY: radiusX; startAngle: -90 + ring.angle; sweepAngle: 90 } }
            NumberAnimation on angle { running: ring.visible && !Theme.reducedMotion; from: 0; to: 360
                duration: Theme.motion.SLOW * 3; loops: Animation.Infinite } }
    }
}
