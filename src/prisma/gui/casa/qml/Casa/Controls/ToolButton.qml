import QtQuick
import Casa.Theme
Button {
    id: root
    property string mode: "under"
    flat: true
    textShown: !compact && mode !== "icons"
    padding: compact ? 0 : ControlMetrics.toolPad
    topPadding: compact ? 0 : Theme.space.XXS
    bottomPadding: topPadding
    focusPolicy: compact ? Qt.StrongFocus : Qt.NoFocus
    implicitWidth: compact ? ControlMetrics.viewButton : mode === "icons" ? Theme.bar.ICON_WIDTH : mode === "under"
        ? Math.ceil(Math.max(Theme.bar.WORD_MIN, word.implicitWidth + Theme.bar.PAD) / Theme.bar.STEP.under) * Theme.bar.STEP.under
        : Math.ceil((word.implicitWidth + symbol.width + Theme.bar.WORD_GAP + Theme.bar.PAD) / Theme.bar.STEP.beside) * Theme.bar.STEP.beside
    implicitHeight: compact ? ControlMetrics.viewButton : mode === "under" ? symbol.height + word.implicitHeight + Theme.bar.PAD : Theme.bar.HEIGHT
    contentItem: Item {
        Icon { id: symbol; name: root.iconName; width: root.compact ? Theme.icon.CONTROL : Theme.bar.ICON[root.mode]; height: width
            // QToolButton fixes the under-icon top and uses integral icon boxes.
            x: !root.compact && root.mode === "beside" ? 2 : Math.floor((parent.width-width)/2)
            // the kit's soft stroke (Icon's own colour, docs/30-icone.md), also when the button is on or pressed
            y: !root.compact && root.mode === "under" ? 2 : Math.floor((parent.height-height)/2) }
        Label { id: word; text: root.text; textStyle: "secondary"; condensed: true; enabled: root.enabled
            visible: !root.compact && root.mode !== "icons"
            x: root.mode === "beside" ? symbol.width + Theme.bar.WORD_GAP : (parent.width-width)/2
            y: root.mode === "under" ? (parent.height-symbol.height-word.implicitHeight-Theme.space.XXS)/2 + symbol.height + Theme.space.XXS : (parent.height-height)/2 }
    }
}
