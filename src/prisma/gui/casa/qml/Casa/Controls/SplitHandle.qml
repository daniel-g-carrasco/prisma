import QtQuick
import QtQuick.Templates as T
import Casa.Theme
T.Control {
    property int orientation: Qt.Vertical
    implicitWidth: Theme.space.M
    implicitHeight: Theme.space.M
    HoverHandler { cursorShape: parent.orientation === Qt.Vertical ? Qt.SplitHCursor : Qt.SplitVCursor }
}
