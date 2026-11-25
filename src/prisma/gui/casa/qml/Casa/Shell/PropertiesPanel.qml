import QtQuick
import Casa.Controls as M
import Casa.Properties
import Casa.Theme
// nothing selected (no section): the empty state the host words (docs/22, row 9)
Rectangle {
    readonly property bool nothing: propertiesBackend.sections.length === 0
    anchors.fill: parent; color: Theme.colors.panel
    PropertiesPage { anchors.fill: parent; backend: propertiesBackend; visible: !parent.nothing }
    M.EmptyState {
        objectName: "propertiesEmpty"; anchors.fill: parent; visible: parent.nothing
        iconName: "mouse-pointer-2"; title: (propertiesBackend.empty || {}).title || ""
        description: (propertiesBackend.empty || {}).description || ""
    }
}
