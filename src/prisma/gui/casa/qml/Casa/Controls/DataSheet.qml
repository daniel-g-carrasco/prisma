import QtQuick
import Casa.Theme

// A data page (docs/27-pagine-di-dati.md, Daniel 21/11/2026: variant B of the study): names and values to read, in
// groups, each group a tile with its title over it. The page scrolls as a whole (ScrollPage).
//  - `groups` is [{title, rows: [{label, value, kind}]}]. The app gives every value ready to read, in the user's
//    language, and says its kind: "text" (the default), "long", "number", "percent", "money", "date", "bool" (true or
//    false), nothing ("" or undefined) for a value not given.
//  - Measures: a tile is at most Theme.size.READING wide; two columns of tiles, Theme.space.XL apart, as soon as the page
//    holds them (2 * READING + XL), else one; the page never grows past that width. The sheet stands the page's margins
//    from the sides (design.Layout.PAGE), in the middle (`align` "center") or at the left ("start").
//  - Inside a tile everything is Theme.layout.TITLE_X from the four sides; a hair between two rows, Theme.space.M away
//    from both. The group's title starts on the same line as the names (TITLE_X), Theme.space.M over its tile.
//  - The columns are balanced: the groups keep their order and the second column starts where the two come nearest
//    in height, so that two tiles of different heights side by side leave no hole at the foot of one.
//  - A row: the name at the left, the value at the right end of the same line; a value that does not fit beside its
//    name, and every "long" one, goes under the name, from the left, wrapping.
//  - Every value can be selected and copied (ReadableText, Tab reaches it); the reader hears «name: value».
//  - `compact`: the form of a low tile or a narrow panel (docs/27, rule 11): one column, no group titles, no page
//    margins; `rows` alone ([{label, value, kind}]) is the same as one group without a title.
ScrollPage {
    id: root
    property var groups: []
    property var rows: []
    property bool compact: false
    // A sheet inside an existing card uses the card's ground and available width.
    property bool embedded: false
    readonly property var shown: groups.length || !rows.length ? groups : [{title: "", rows: rows}]
    property string align: "center"
    property string yesText: "Yes"
    property string noText: "No"
    property string emptyText: "Not given"
    // design.Layout.PAGE (28 at the sides, 22 above and below): the theme gives QML its numbers, not this pair
    readonly property real sideMargin: compact || embedded ? 0 : Theme.space.XXL + Theme.space.XS
    readonly property real topMargin: compact || embedded ? 0 : Theme.space.XXL - Theme.space.XXS
    readonly property real gap: Theme.space.XL
    readonly property real pad: embedded ? 0 : Theme.layout.TITLE_X
    readonly property real room: Math.max(0, pageWidth - 2 * sideMargin)
    readonly property int columns: !compact && room >= 2 * Theme.size.READING + gap ? 2 : 1
    readonly property real maxWidth: columns * Theme.size.READING + (columns - 1) * gap
    readonly property real sheetWidth: embedded ? room : Math.min(maxWidth, room)
    readonly property real sheetX: sideMargin + (align === "center" ? Math.floor((room - sheetWidth) / 2) : 0)
    readonly property real tileWidth: (sheetWidth - (columns - 1) * gap) / columns
    // the height a group will take, in lines of text, to balance the columns: its title, its rows, the long values'
    // lines at the tile's measure
    function weight(group) {
        const revision = Theme.revision
        const perLine = Math.max(1, tileWidth - 2 * pad)
        let lines = 2
        for (const row of group.rows) {
            const text = String(row.value === undefined || row.value === null ? "" : row.value)
            const long = row.kind === "long" || Theme.measureText(row.label + "  " + text, "body").width > perLine
            lines += 1.4 + (long ? Math.ceil(Theme.measureText(text, "body").width / perLine) : 0)
        }
        return lines
    }
    readonly property var split: {
        const groups = shown
        if (columns < 2 || groups.length < 2) return [groups, []]
        const weights = groups.map(weight)
        const whole = weights.reduce((sum, w) => sum + w, 0)
        let best = 1, bestGap = Infinity, sum = 0
        for (let at = 1; at < groups.length; at++) {
            sum += weights[at - 1]
            const apart = Math.abs(whole - 2 * sum)
            if (apart < bestGap) { bestGap = apart; best = at }
        }
        return [groups.slice(0, best), groups.slice(best)]
    }
    objectName: "dataSheet"
    leftMargin: 0; air: topMargin; airInside: true; spacing: 0
    Row {
        objectName: "dataSheetBody"
        x: root.sheetX
        spacing: root.gap
        Repeater {
            model: root.columns
            Column {
                id: column
                required property int index
                objectName: "dataColumn" + index
                width: root.tileWidth
                spacing: root.gap
                Repeater {
                    model: root.split[column.index]
                    // a group: its title, then its tile
                    Column {
                        id: group
                        required property var modelData
                        objectName: "dataGroup"
                        width: column.width
                        spacing: Theme.space.M
                        Accessible.role: Accessible.Grouping
                        Accessible.name: modelData.title
                        Label {
                            objectName: "dataGroupTitle"
                            visible: text !== "" && !root.compact
                            x: root.pad; width: group.width - 2 * root.pad
                            text: group.modelData.title || ""; textStyle: "title"; wrapMode: Text.Wrap
                            Accessible.role: Accessible.Heading
                        }
                        // the tile: the kit's one surface (R658), the field's ground, no line
                        Surface {
                            objectName: "dataTile"
                            width: group.width; height: lines.height + 2 * root.pad
                            color: root.embedded ? "transparent" : Theme.colors.field; borderWidth: 0
                            Column {
                                id: lines
                                x: root.pad; y: root.pad; width: parent.width - 2 * root.pad
                                spacing: Theme.space.M
                                Repeater {
                                    model: group.modelData.rows
                                    Column {
                                        id: line
                                        required property var modelData
                                        required property int index
                                        width: lines.width
                                        spacing: Theme.space.M
                                        Rectangle {
                                            visible: line.index > 0
                                            width: parent.width; height: Theme.line.HAIR; color: Theme.colors.line_soft
                                        }
                                        DataRow { width: line.width; row: line.modelData; sheet: root }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // A row: the name at the left, the value at the right end of the line, or under the name from the left
    component DataRow: Item {
        id: entry
        property var row: ({})
        property Item sheet
        readonly property real nameNatural: Math.ceil(Theme.measureText(row.label || "", "description").width) + Theme.space.XXS
        readonly property bool stacked: row.kind === "long" || nameNatural + sheet.gap + shown.naturalWidth > width
        objectName: "dataRow"
        implicitHeight: stacked ? name.height + Theme.space.XXS + shown.height : Math.max(name.height, shown.height)
        height: implicitHeight
        Accessible.role: Accessible.Row
        Accessible.name: (row.label || "") + ": " + shown.text
        Label {
            id: name
            objectName: "dataName"
            text: entry.row.label || ""
            textStyle: "description"; color: Theme.colors.text2
            width: entry.stacked ? entry.width : Math.min(entry.nameNatural, Math.max(0, entry.width - entry.sheet.gap - shown.naturalWidth))
            wrapMode: Text.Wrap
            // the value says the name too («name: value»): the reader does not hear it twice
            Accessible.ignored: true
        }
        // the value, drawn by its kind
        Item {
            id: shown
            readonly property var given: entry.row.value
            readonly property string kind: entry.row.kind || "text"
            readonly property bool empty: given === undefined || given === null || given === ""
            readonly property bool flag: kind === "bool" && !empty
            readonly property bool figures: ["number", "percent", "money", "date"].indexOf(kind) >= 0
            readonly property string text: empty ? entry.sheet.emptyText : flag ? (given ? entry.sheet.yesText : entry.sheet.noText) : String(given)
            readonly property bool quiet: empty || (flag && !given)
            readonly property real markRoom: flag ? Theme.icon.CONTROL + Theme.space.XS : 0
            readonly property real naturalWidth: markRoom + Math.ceil(Theme.measureText(text, "body").width) + Theme.space.XXS
            readonly property real start: entry.stacked || entry.sheet.embedded ? 0 : Math.max(0, width - naturalWidth)
            objectName: "dataValue"
            x: entry.stacked ? 0 : name.width + entry.sheet.gap
            y: entry.stacked ? name.height + Theme.space.XXS : 0
            width: Math.max(0, entry.width - x)
            height: words.implicitHeight
            Icon {
                objectName: "dataMark"
                visible: shown.flag
                name: shown.flag ? (shown.given ? "sign:check" : "control:minus") : ""
                x: shown.start
                y: Math.round((Theme.measureText("Hg", "body").height - height) / 2)
                width: Theme.icon.CONTROL; height: width; dimDisabled: false
                color: shown.quiet ? Theme.colors.muted : Theme.colors.icon_ink     // the soft stroke, docs/30-icone.md
            }
            ReadableText {
                id: words
                objectName: "dataWords"
                x: shown.start + shown.markRoom
                width: Math.max(0, shown.width - x)
                text: shown.text
                color: shown.quiet ? Theme.colors.muted : Theme.colors.text
                font.features: shown.figures ? ({"tnum": 1}) : ({})
                wrapMode: Text.Wrap
                Accessible.name: entry.row.label ? entry.row.label + ": " + shown.text : shown.text
            }
        }
        // the keyboard's ring round the value it reached (Theme.focusRing: only when Tab brought the focus there)
        Rectangle {
            objectName: "dataRing"
            visible: Theme.focusRing(words)
            x: shown.x + shown.start - Theme.space.XS; y: shown.y - Theme.space.XXS
            width: Math.min(shown.width, shown.naturalWidth) + 2 * Theme.space.XS; height: shown.height + 2 * Theme.space.XXS
            radius: Theme.radius.INNER; color: "transparent"
            border.width: Theme.line.FOCUS; border.color: Theme.colors.focus
        }
    }
}
