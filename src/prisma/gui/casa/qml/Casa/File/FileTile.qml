import QtQuick
import Casa.Theme
import Casa.Controls as M

Rectangle {
    id: root
    required property var tile
    signal triggered(string action)
    property real descriptionHeight: Math.max(description.implicitHeight, Theme.text.description.size * 2.5)
    implicitHeight: Theme.space.L * 2 + title.implicitHeight + descriptionHeight + Theme.space.S * 3 + action.height
    color: Theme.colors.field
    radius: Theme.radius.CARD
    M.Icon { id: mark; x: Theme.space.XL; y: M.ControlMetrics.firstLineMiddle(title) - height / 2
        width: Theme.icon.TILE; height: width; iconName: root.tile.icon }
    M.ReadableText {
        id: title
        x: mark.x + mark.width + Theme.space.L; y: Theme.space.L
        width: root.width - x - Theme.space.XL
        text: root.tile.title; textStyle: "title"; wrapMode: Text.WordWrap
    }
    M.ReadableText {
        id: description
        x: title.x; y: title.y + title.height + Theme.space.S; width: title.width
        text: root.tile.description; textStyle: "description"; wrapMode: Text.WordWrap
    }
    Row {
        x: title.x; anchors.verticalCenter: action.verticalCenter
        spacing: Theme.space.S
        Repeater {
            model: root.tile.formats ? root.tile.formats.split(" · ") : []
            Rectangle {
                required property string modelData
                width: formatLabel.implicitWidth + 2 * Theme.space.S + 2
                height: action.height
                color: "transparent"; radius: Theme.radius.CONTROL
                border.width: Theme.line.HAIR; border.color: Theme.colors.line
                M.CopyLabel { id: formatLabel; anchors.centerIn: parent; text: modelData; textStyle: "caption"; color: Theme.colors.text2 }
            }
        }
    }
    M.Button {
        id: action
        objectName: "fileAction_" + root.tile.action
        anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.rightMargin: Theme.space.XL; anchors.bottomMargin: Theme.space.L
        text: root.tile.button
        enabled: root.tile.enabled !== false
        background: Rectangle {
            radius: Theme.radius.CONTROL
            color: Theme.colors.panel
            border.width: Theme.focusRing(action) ? Theme.line.FOCUS : 0
            border.color: Theme.colors.focus
            Rectangle { anchors.fill: parent; radius: parent.radius; color: action.down ? Theme.colors.press : action.hovered ? Theme.colors.hover : "transparent" }
        }
        onClicked: root.triggered(root.tile.action)
    }
}
