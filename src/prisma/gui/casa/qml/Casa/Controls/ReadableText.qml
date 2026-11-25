import QtQuick
import Casa.Theme

TextArea {
    property string textStyle: "body"
    readonly property var spec: Theme.text[textStyle] || Theme.text.body
    font.pixelSize: spec.size
    font.weight: spec.weight
    color: Theme.colors[spec.tone]
    property string markdownSource: ""
    textActions.markdown: markdownSource
    bare: true
    readOnly: true
    selectByKeyboard: true
    activeFocusOnTab: true
}
