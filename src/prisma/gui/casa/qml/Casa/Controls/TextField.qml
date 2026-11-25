import QtQuick
import QtQuick.Controls as C
import QtQuick.Templates as T
import Casa.Theme
T.TextField {
    id: root
    property alias textActions: textCommands
    signal commitRequested()
    TextActions {
        id: textCommands; editor: root; focusExit: () => root.commitRequested()
        numericPolicy: root.validator && root.validator.bottom !== undefined && root.validator.top !== undefined
            ? ({unit: "", kind: "", minimum: root.validator.bottom, maximum: root.validator.top,
                decimals: root.validator.decimals === undefined ? 0 : root.validator.decimals < 0 ? 15 : root.validator.decimals,
                locale: Qt.locale(root.validator.locale || Qt.locale().name)}) : null
    }
    onEditingFinished: {
        if (textCommands.menuActive) textCommands.pendingExit = true
        else { textCommands.pendingExit = false; commitRequested() }
    }
    function handleTextKey(event) { if (textKeys.handle(event)) C.ContextMenu.menu.popup(root, 0, root.height) }
    TextKeys { id: textKeys; editor: root; actions: textCommands; enabled: root.textKeysEnabled }
    property bool textKeysEnabled: true
    Keys.forwardTo: [textKeys]

    C.ContextMenu.menu: TextMenu { actions: textCommands }
    function openTextMenu(x, y) { const menu = C.ContextMenu.menu; if (!menu.visible) menu.popup(root, x, y) }
    onPressAndHold: event => root.openTextMenu(event.x, event.y)

    Loader { active: textCommands.pasteError !== ""
        sourceComponent: ToolTip { parent: root; text: textCommands.pasteError; visible: root.hovered } }
    clip: true
    // the field's «?» at its right end (Daniel 21/11/2026, the help of a search, as Meridiana's): the help of `helpKey`
    // (Help.show, services['help'] or the host's helpBook) in its bubble beside the field
    property string helpKey: ""
    HelpMark { id: fieldHelp; objectName: "fieldHelp"; helpKey: root.helpKey; helpPlace: "field"; visible: root.helpKey !== ""
        anchors.right: parent.right; anchors.rightMargin: Theme.space.XS; anchors.verticalCenter: parent.verticalCenter }
    property bool invalid: false
    implicitWidth: Theme.size.READING / 2
    implicitHeight: Math.max(Theme.size.CONTROL, contentHeight + 2 * Theme.space.XS)
    padding: Theme.space.M
    leftPadding: ControlMetrics.fieldInset
    rightPadding: ControlMetrics.fieldInset + (fieldHelp.visible ? fieldHelp.width : 0)
    // R582: the line on the field's middle by its capitals (ControlMetrics.textBaseline), the hint on the same baseline
    FontMetrics { id: metrics; font: root.font }
    topPadding: ControlMetrics.textBaseline(height, metrics, Screen.devicePixelRatio) - metrics.ascent
    bottomPadding: Theme.space.XS
    font.family: Theme.fontFamily
    font.pixelSize: Theme.text.body.size
    color: enabled ? Theme.colors.text : Theme.disabledText
    selectionColor: Theme.colors.select_bg
    selectedTextColor: Theme.colors.select_fg
    placeholderTextColor: Theme.colors.muted
    verticalAlignment: TextInput.AlignTop
    Label { x: root.leftPadding; anchors.baseline: parent.baseline
        width: Math.max(0, root.width - root.leftPadding - root.rightPadding); verticalAlignment: Text.AlignTop
        text: root.placeholderText; color: root.placeholderTextColor; visible: !root.length && !root.preeditText; elide: Text.ElideRight }
    selectByMouse: true
    autoScroll: activeFocus
    focusPolicy: Qt.StrongFocus
    onActiveFocusChanged: if (activeFocus && (focusReason === Qt.TabFocusReason || focusReason === Qt.BacktabFocusReason)) selectAll()
    hoverEnabled: true
    renderType: TextInput.NativeRendering
    persistentSelection: textCommands.menuActive || textCommands.closingMenu
    background: Rectangle { color: Theme.colors.field; radius: Theme.radius.CONTROL
        border.width: Theme.focusRing(root) ? Theme.line.FOCUS : Theme.line.HAIR
        border.color: !root.enabled ? "transparent" : (root.invalid || textCommands.pasteError !== "") ? Theme.colors.danger : Theme.focusRing(root) ? Theme.colors.focus : root.hovered ? Theme.colors.field_line : "transparent" }
}
