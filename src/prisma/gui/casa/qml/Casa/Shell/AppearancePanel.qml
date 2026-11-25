import QtQuick
import QtQuick.Layouts
import Casa.Theme
import Casa.Controls as M

Item {
    RowLayout {
        anchors.fill: parent; spacing: Theme.space.XXL
        ColumnLayout {
            Layout.alignment: Qt.AlignTop; Layout.preferredWidth: Theme.size.PANEL_MIN
            Layout.maximumWidth: Theme.size.PANEL_MIN; Layout.fillWidth: false
            M.Button { text: shell.words.appearance; checked: true; flat: true; Layout.fillWidth: true }
            Item { Layout.fillHeight: true }
        }
        ColumnLayout {
            Layout.alignment: Qt.AlignTop; Layout.maximumWidth: Theme.size.READING*2
            Layout.fillWidth: false; spacing: Theme.space.XL
            M.Label { text: shell.words.appearance; textStyle: "heading" }
            GridLayout {
                columns: 2; columnSpacing: Theme.space.XL; rowSpacing: Theme.space.L
                M.Label { text: shell.words.theme }
                M.Segments { id: themeChoice; objectName: "themeChoice"; model: [{text:shell.words.light},{text:shell.words.dark},{text:shell.words.system}]
                    currentIndex: ["light","dark","system"].indexOf(Theme.options.theme)
                    onActivated: index => Theme.configure({theme:["light","dark","system"][index]}) }
                M.Label { text: shell.words.backgrounds }
                M.ComboBox { id: backgroundChoice; objectName: "backgroundChoice"; model: shell.backgrounds; textRole: "text"; valueRole: "id"
                    Binding { target: backgroundChoice; property: "currentIndex"; value: shell.backgrounds.findIndex(v=>v.id===Theme.options.backgrounds) }
                    onActivated: index => Theme.configure({backgrounds:model[index].id}) }
                M.Label { text: shell.words.accent }
                M.ComboBox { id: accentChoice; objectName: "accentChoice"; model: shell.accents; textRole: "text"; valueRole: "id"
                    Binding { target: accentChoice; property: "currentIndex"; value: shell.accents.findIndex(v=>v.id===Theme.options.accent) }
                    onActivated: index => Theme.configure({accent:model[index].id}) }
                M.Label { text: shell.words.font }
                M.ComboBox { id: fontChoice; objectName: "fontChoice"; model: shell.fonts; textRole: "text"; valueRole: "id"
                    Layout.fillWidth: true
                    Binding { target: fontChoice; property: "currentIndex"; value: shell.fonts.findIndex(v=>v.id===Theme.options.font) }
                    onActivated: index => Theme.configure({font:model[index].id}) }
                M.Label { text: shell.words.textSize }
                M.Segments { objectName: "sizeChoice"; model: [{text:shell.words.small},{text:shell.words.medium},{text:shell.words.large}]
                    currentIndex: ["small","medium","large"].indexOf(Theme.textSize)
                    onActivated: index => Theme.configure({textSize:["small","medium","large"][index]}) }
                M.Label { text: shell.words.density }
                M.Segments { objectName: "densityChoice"; model: [{text:shell.words.normal},{text:shell.words.compact}]
                    currentIndex: ["normal","compact"].indexOf(Theme.density)
                    onActivated: index => Theme.configure({density:["normal","compact"][index]}) }
                M.Label { text: shell.words.reducedMotion }
                M.CheckBox { id: motionChoice; objectName: "motionChoice"
                    Binding { target: motionChoice; property: "checked"; value: Theme.reducedMotion }
                    onToggled: Theme.configure({reducedMotion:checked}) }
            }
            Item { Layout.fillHeight: true }
        }
        Item { Layout.fillWidth: true }
    }
}
