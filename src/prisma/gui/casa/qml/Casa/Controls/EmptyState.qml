import QtQuick
import Casa.Theme
Item {
    id: root
    property string title: ""
    property string description: ""
    property string actionText: ""
    property string iconName: ""
    // Meridiana R731 (form B): the row of the job its action started (a row of work.slots, `({})` when none): the action
    // says it is in progress (`busyText`) and cannot start it twice, and the job's row shows under it
    property var job: ({})
    property string busyText: ""
    readonly property bool busy: !!job && job.id !== undefined
    signal triggered()
    implicitWidth: Theme.size.READING
    implicitHeight: content.implicitHeight + Theme.space.XL * 2
    Column { id: content; anchors.centerIn: parent; width: Math.max(0, Math.min(parent.width - 2 * Theme.space.XL, Theme.size.READING)); spacing: Theme.space.M
        Icon { name: root.iconName; visible: name !== ""; width: Theme.icon.TILE; height: width; anchors.horizontalCenter: parent.horizontalCenter; color: Theme.colors.muted }
        ReadableText { text: root.title; textStyle: "secondary"; color: Theme.colors.text2; width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
        ReadableText { text: root.description; textStyle: "description"; width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; visible: text !== "" }
        Button { objectName: "emptyStateAction"; text: root.busy && root.busyText ? root.busyText : root.actionText
            visible: root.actionText !== ""; enabled: !root.busy; anchors.horizontalCenter: parent.horizontalCenter; onClicked: root.triggered() }
        WorkRow { objectName: "emptyStateJob"; width: parent.width; row: root.busy ? root.job : ({}); visible: root.busy }
    }
}
