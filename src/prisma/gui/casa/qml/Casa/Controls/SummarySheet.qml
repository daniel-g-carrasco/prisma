import QtQuick
import Casa.Theme

// A summary page (docs/27-pagine-di-dati.md): the results at the head (SummaryFigures) and their breakdown under them
// (TotalsTree), in one column two reading columns and their gap wide at most (2 * Theme.size.READING + Theme.space.XL),
// the page's margins from the sides (design.Layout.PAGE), in the middle. The results end where the table's figures
// end, before the scroll bar's lane. The table fills the height left and scrolls by itself, the total in view.
// `figures` as SummaryFigures; `model` and `labels` as TotalsTree; `tree` reaches the table (expandTo, sortByAmount).
Item {
    id: root
    property var figures: []
    property var model: []
    property var labels: ({})
    readonly property alias tree: totals
    // design.Layout.PAGE (28 at the sides, 22 above and below), as DataSheet
    readonly property real sideMargin: Theme.space.XXL + Theme.space.XS
    readonly property real topMargin: Theme.space.XXL - Theme.space.XXS
    readonly property real maxWidth: 2 * Theme.size.READING + Theme.space.XL
    readonly property real sheetWidth: Math.max(0, Math.min(maxWidth, width - 2 * sideMargin))
    objectName: "summarySheet"
    Item {
        objectName: "summaryColumn"
        x: Math.floor((root.width - root.sheetWidth) / 2); y: root.topMargin
        width: root.sheetWidth; height: Math.max(0, root.height - y)
        SummaryFigures {
            id: results
            visible: root.figures.length > 0
            width: parent.width - totals.lane
            figures: root.figures
        }
        TotalsTree {
            id: totals
            y: results.visible ? results.height + Theme.space.XL : 0
            width: parent.width; height: Math.max(0, parent.height - y)
            model: root.model; labels: root.labels
        }
    }
}
