import QtQuick
import Casa.Theme

// The results at the head of a summary page (docs/27-pagine-di-dati.md, Daniel 21/11/2026: «vai con M1»), in the style
// of Meridiana's results (its tiles of Production and of Economy, Charts/ResultsPage.qml): a tile each on the field's
// ground, the card's radius, Theme.space.M apart. In a tile, Theme.space.L from its sides and Theme.space.M from its
// top and foot: the name (small, second ink) with its qualifier as a badge on the same line; the number large
// (display, figures of one width) with its unit beside it on the same baseline; the detail (small, second ink), with
// room for two lines so that the numbers of a line stay at one height.
// `figures` is [{label, figure, unit, detail, badge}]: the figure is the number alone, ready to read; the unit apart;
// what qualifies it («partial») is the badge, never a word before the number.
// Two, three or four in equal parts of the width; they go on two lines when a part would be narrower than its widest
// number and unit (then two and two, or two and one). The tiles of a line are as tall as the tallest.
Item {
    id: root
    property var figures: []
    readonly property real gap: Theme.space.M
    readonly property real padX: Theme.space.L
    readonly property real padY: Theme.space.M
    // the least a part needs: its widest number and unit, and its margins (Meridiana: at least 165)
    readonly property real least: {
        const revision = Theme.revision
        let widest = 0
        for (const entry of figures)
            widest = Math.max(widest, Theme.measureText(entry.figure || "", "display").width + Theme.space.XS
                                      + Theme.measureText(entry.unit || "", "body").width)
        return Math.ceil(widest) + 2 * padX
    }
    readonly property int fit: Math.max(1, Math.min(figures.length, Math.floor((width + gap) / (least + gap))))
    readonly property int lines: Math.ceil(figures.length / fit)
    readonly property int columns: Math.max(1, Math.ceil(figures.length / lines))
    readonly property real part: Math.floor((width - (columns - 1) * gap) / columns)
    readonly property real partHeight: {
        let tallest = 0
        for (let i = 0; i < parts.count; i++) { const item = parts.itemAt(i); if (item) tallest = Math.max(tallest, item.need) }
        return tallest
    }
    objectName: "summaryFigures"
    implicitHeight: lines * partHeight + (lines - 1) * gap
    height: implicitHeight
    Repeater {
        id: parts
        model: root.figures
        Item {
            id: slot
            required property var modelData
            required property int index
            readonly property int column: index % root.columns
            readonly property int line: Math.floor(index / root.columns)
            readonly property real need: words.height + 2 * root.padY
            objectName: "summaryFigure" + index
            x: column * (root.part + root.gap); y: line * (root.partHeight + root.gap)
            width: root.part; height: root.partHeight
            Accessible.role: Accessible.Grouping
            Accessible.name: modelData.label + ": " + modelData.figure + " " + (modelData.unit || "")
                             + (modelData.badge ? ", " + modelData.badge : "") + (modelData.detail ? ", " + modelData.detail : "")
            // the tile: the kit's one surface (R658), the field's ground, no line
            Surface {
                anchors.fill: parent; color: Theme.colors.field; borderWidth: 0
            }
            Column {
                id: words
                x: root.padX; y: root.padY
                width: Math.max(0, parent.width - 2 * root.padX)
                spacing: Theme.space.XXS
                Item {
                    // as tall as the name alone: the badge stands on the name's line and moves no number
                    width: parent.width; height: name.height
                    Label {
                        id: name
                        width: Math.min(implicitWidth, parent.width - (badge.visible ? badge.width + Theme.space.M : 0))
                        anchors.verticalCenter: parent.verticalCenter
                        text: slot.modelData.label || ""; textStyle: "secondary"; color: Theme.colors.text2; elide: Text.ElideRight
                    }
                    Pill {
                        id: badge
                        visible: !!slot.modelData.badge
                        x: name.width + Theme.space.M; anchors.verticalCenter: parent.verticalCenter
                        variant: "badge"; text: slot.modelData.badge || ""; tone: "text2"
                    }
                }
                Item {
                    width: parent.width; height: figure.implicitHeight
                    CopyLabel {
                        id: figure
                        text: slot.modelData.figure || ""; textStyle: "display"
                        font.features: ({"tnum": 1})
                    }
                    Label {
                        x: figure.width + Theme.space.XS; anchors.baseline: figure.baseline
                        text: slot.modelData.unit || ""; textStyle: "body"
                    }
                }
                Label {
                    id: detail
                    width: parent.width
                    // two lines kept, as Meridiana's tiles: the numbers of a line stay at one height
                    height: Math.max(implicitHeight, 2 * Math.ceil(Theme.measureText("Hg", "secondary").height))
                    text: slot.modelData.detail || ""; textStyle: "secondary"; color: Theme.colors.text2
                    wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; verticalAlignment: Text.AlignTop
                }
            }
        }
    }
}
