import QtQuick
import Casa.Controls as M

M.CopyLabel {
    id: root
    property string fullText: text
    elide: Text.ElideRight
    HoverHandler { id: hover }
    M.ToolTip { text: root.fullText; visible: hover.hovered && root.truncated }
    Accessible.name: fullText
}
