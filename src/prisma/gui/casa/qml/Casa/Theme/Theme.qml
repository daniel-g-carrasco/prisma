pragma Singleton
import QtQuick

QtObject {
    id: root
    readonly property color disabledText: _casa_tokens.disabledText
    readonly property var colors: _casa_tokens.colors
    readonly property var options: _casa_tokens.options
    readonly property var status: _casa_tokens.status
    readonly property var space: _casa_tokens.space
    readonly property var radius: _casa_tokens.radius
    readonly property var type: _casa_tokens.type
    readonly property var size: _casa_tokens.size
    readonly property var line: _casa_tokens.line
    readonly property var motion: _casa_tokens.motion
    readonly property var layout: _casa_tokens.layout
    readonly property var bar: _casa_tokens.bar
    readonly property var icon: _casa_tokens.icon
    readonly property var stack: _casa_tokens.stack       // R616: what stands over what (design.Stack)
    readonly property var highlight: _casa_tokens.highlight      // R617: every highlight's one scale (design.Highlight)
    readonly property var annotation: _casa_tokens.annotation
    readonly property var text: _casa_tokens.text
    readonly property var tokens: _casa_tokens.tokens
    readonly property string fontFamily: _casa_tokens.fontFamily
    readonly property string barFontFamily: _casa_tokens.barFontFamily
    readonly property bool dark: _casa_tokens.dark
    readonly property bool reducedMotion: _casa_tokens.reducedMotion
    readonly property bool phaseMotion: _casa_tokens.phaseMotion
    readonly property string textSize: _casa_tokens.textSize
    readonly property string density: _casa_tokens.density
    readonly property real rowAir: _casa_tokens.rowAir
    readonly property int revision: _casa_tokens.revision

    function configure(options) {
        _casa_tokens.configure(options)
    }

    // tr(text), tr(text, context), tr(one, many, n): the forms of qsTr (casa/translator.py)
    function tr(message, disambiguation, n) {
        const revision = root.revision
        if (disambiguation === undefined && n === undefined)
            return _casa_tokens.translate(message)
        return _casa_tokens.translateWith(message, disambiguation || "", n === undefined ? -1 : n)
    }

    // R586 (c): a modal window's veil shown or gone (Controls/ModalVeil.qml), for the title bar
    function veil(on, colour) {
        if (_casa_tokens.veil !== undefined) _casa_tokens.veil(on, colour)
    }

    function tooltipLayout(text) {
        const currentRevision = root.revision
        return _casa_tokens.tooltipLayout(text)
    }

    function mix(a, b, share) {
        return Qt.rgba(a.r + (b.r-a.r)*share, a.g + (b.g-a.g)*share,
                       a.b + (b.b-a.b)*share, a.a + (b.a-a.a)*share)
    }

    // The one rule of the focus ring (Daniel 14/11/2026: «compare solo quando ci si arriva con la tastiera»): shown only
    // while the keyboard brought the focus there (Tab, Shift+Tab, a shortcut), never after a click, which leaves a
    // control told by its own state (pressed, checked, chosen, the caret). Every ring and field border in
    // Theme.colors.focus asks here, with the focusReason of a Control or a field, or the one an item declares
    // (PlantInverterCard); guard: tests/quick/controlli/test_anello_tastiera.py.
    function focusRing(item) {
        if (!item || !item.enabled || !item.activeFocus) return false
        const reason = item.focusReason
        return reason === Qt.TabFocusReason || reason === Qt.BacktabFocusReason || reason === Qt.ShortcutFocusReason
    }

    // R596: where a sign's ink stands in the font (ThemeTokens.glyphAxis): the middle of its lowest piece, its top, its bottom
    function glyphAxis(text, size, weight) {
        const currentRevision = root.revision
        return _casa_tokens.glyphAxis(text, size, weight)
    }

    function textBlockInk(text, width, style, condensed) {
        const revision = root.revision
        return _casa_tokens.textBlockInk(text, width, style || "body", condensed || false)
    }
    function measureText(text, style, condensed) {
        // Reading revision makes callers' bindings follow font and size changes.
        const currentRevision = root.revision
        return _casa_tokens.measureText(text, style || "body", condensed || false)
    }
}
