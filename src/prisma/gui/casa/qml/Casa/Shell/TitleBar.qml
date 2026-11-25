import QtQuick
import QtQuick.Layouts
import Casa.Controls as C
import Casa.Theme
RowLayout {
    id: root
    property var controller: null
    spacing: Theme.space.S
    Item {
        Layout.fillWidth: true; implicitHeight: 36
        C.Label { anchors.centerIn: parent; text: root.Window.window ? root.Window.window.title : "" }
        MouseArea {
            anchors.fill: parent
            onPressed: { if (root.controller) root.controller.frameController.start_move() }
            onDoubleClicked: { if (root.controller) root.controller.frameController.maximize() }
        }
    }
    Repeater {
        model: ["minimize", "maximize", "close"]
        C.Button {
            required property string modelData
            objectName: "frame_" + modelData
            readonly property string accessibleName: Theme.tr(modelData === "minimize" ? "Minimize" : modelData === "maximize" ? "Maximize or restore" : "Close")
            text: accessibleName
            Accessible.name: accessibleName
            onClicked: {
                if (!root.controller) return
                if (modelData === "close") root.controller.request_close()
                else if (modelData === "minimize") root.controller.frameController.minimize()
                else root.controller.frameController.maximize()
            }
        }
    }
}
