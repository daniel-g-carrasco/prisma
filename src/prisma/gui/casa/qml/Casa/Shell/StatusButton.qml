import QtQuick
import Casa.Theme
import Casa.Controls as M

M.Button {
    id: root
    // A card on screen has its icon full, a closed or covered one faint (ui/panel_buttons.py, _show).
    property bool seen: true
    flat: true; focusPolicy: Qt.NoFocus
    implicitWidth: Theme.size.CONTROL; implicitHeight: Theme.size.CONTROL
    padding: 0
    topPadding: 0; bottomPadding: 0
    contentItem: Item {
        M.Icon { anchors.centerIn: parent; iconName: root.iconName; width: Math.min(Theme.icon.CONTROL, parent.width, parent.height); height: width
            color: !root.seen ? Theme.colors.muted : Theme.colors.icon_ink }   // the soft stroke, docs/30-icone.md
    }
}
