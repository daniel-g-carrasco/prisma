import QtQuick
import QtQml.Models
import Casa.Theme
import Casa.Controls as M

// G5 (Daniel 21/11/2026, docs/28-barra-piccola.md): «More» at the end of the bar of small buttons, when the last groups
// do not fit. Its menu holds every command of those groups, in their order, a line between two groups, with the
// keys, the tick of a command that is on and the reason of one that is off, as the menus of Alt. A press opens it,
// as a split button's arrow.
Item {
    id: root
    property var groups: []
    property string label: ""
    readonly property var entries: {
        const list = []
        groups.forEach((group, index) => {
            if (index > 0) list.push({separator: true})
            for (const tool of group.tools) for (const one of [tool].concat(tool.more || [])) list.push(one)
        })
        return list
    }
    readonly property bool menuOpened: menu.visible
    function dismissMenu() { menu.close() }
    objectName: "phaseMore"
    implicitWidth: button.implicitWidth
    PhaseToolButton {
        id: button
        objectName: "phaseMoreButton"
        anchors.fill: parent
        mode: "under"; text: root.label; iconName: "ellipsis"
        tip: root.groups.map(group => group.title).join(", ")
        menu: menu; menuBelow: true; menuOnPress: true
        Accessible.name: root.label
    }
    M.Menu {
        id: menu
        objectName: "phaseMoreMenu"
        Instantiator {
            model: root.entries
            delegate: M.MenuEntry {
                required property var modelData
                objectName: modelData.separator ? "phaseMoreLine" : "phaseMore_" + modelData.command
                entry: modelData.separator ? ({separator: true})
                    : ({text: modelData.title, icon: shell.commandIcon[modelData.command] || modelData.icon, keys: modelData.keys, tip: "",
                        note: shell.commandNote[modelData.command] || "",
                        checked: shell.commandChecked[modelData.command] === true,
                        enabled: modelData.enabled && shell.commandEnabled[modelData.command] !== false})
                onTriggered: if (!modelData.separator) shell.trigger(modelData.command)
            }
            onObjectAdded: (index, object) => menu.insertItem(index, object)
            onObjectRemoved: (index, object) => menu.removeItem(object)
        }
    }
}
