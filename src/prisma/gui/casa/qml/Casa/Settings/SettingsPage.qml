import QtQuick
import QtQuick.Controls.Basic as C
import QtQuick.Layouts
import Casa.Theme
import Casa.Controls as M

// R630: one page per section, made once and kept by File (FilePage.qml): the section is the page's own, its fields
// and values read once for the page and handed to its rows (before, every row asked Python the fields of the section
// and measured all their labels: a change of section was 0.3-1.7 s of the window's thread). The names the tests and
// Meridio look for are on the page shown only.
Item {
    id: root
    property var backend
    property string section: backend ? backend.section : ""
    property bool shown: true
    readonly property var fields: backend ? (backend.allFields[section] || []) : []
    readonly property var iconKeys: ["iconStroke", "iconInk", "iconDuo"]
    readonly property var values: backend ? backend.values : ({})
    readonly property real labelWidth: Math.max(section === "navigation" ? 104 : 116,
        ...fields.filter(f => f.kind !== "bool").map(f => Theme.measureText(f.label).width))
    property bool confirmReset: false
    property url hostSource: ""
    objectName: shown ? "settingsPage" : ""
    onVisibleChanged: { if (!visible && backend) backend.flushPending() }
    // a section shown again starts at its top, as a page made new did
    onShownChanged: if (shown) { confirmReset = false; scroll.contentItem.contentY = 0 }
    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.space.M
        M.ScrollPage {
            id: scroll
            objectName: root.shown ? "settingsScroll" : ""
            Layout.fillWidth: true
            Layout.fillHeight: true
            leftMargin: 0; rightMargin: Theme.space.XS; air: 0
            Column {
                // R501: the bar's room kept at the right, as ScrollPage keeps it (R100): the bar never lies on a row
                // and a long text wraps short of it.
                objectName: root.shown ? "settingsColumn" : ""
                width: scroll.pageWidth
                spacing: Theme.space.S
                Loader { width: parent.width; source: root.hostSource }
                M.ReadableText {
                    width: parent.width; wrapMode: Text.WordWrap
                    visible: root.backend && ["privacy", "report"].includes(root.section)
                    text: !root.backend ? "" : root.section === "privacy" ? root.backend.text.privacyLead : root.backend.text.reportLead
                }
                Repeater {
                    model: root.fields.filter(f => root.section !== "appearance" || ["theme", "accent", "backgrounds", "text_size", "font", "density", "toolbar", "toolbar_place"].includes(f.key))
                    delegate: SettingField {
                        required property var modelData
                        width: parent.width
                        backend: root.backend; field: modelData
                        section: root.section; values: root.values; labelWidth: root.labelWidth
                        shown: root.shown
                    }
                }
                // what belongs to one section made only in its page (R630: each section has a page of its own)
                Loader {
                    width: parent.width
                    active: root.backend && root.section === "appearance"
                    visible: active
                    sourceComponent: appearance
                }
                Loader {
                    width: parent.width
                    active: root.backend && root.section === "navigation"
                    visible: active
                    sourceComponent: navigationHelp
                }

                Loader {
                    width: parent.width
                    active: root.backend && root.section === "keyboard"
                    visible: active
                    sourceComponent: keyboard
                }


            }
        }
        M.ReadableText {
            objectName: root.shown ? "settingsError" : ""
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.backend ? root.backend.error : ""
            color: Theme.colors.danger
            wrapMode: Text.WordWrap
        }
        M.Button {
            objectName: root.shown ? "settingsTakeShortcut" : ""
            visible: root.backend && root.section === "keyboard" && root.backend.shortcutConflict
            text: root.backend ? root.backend.text.takeShortcut : ""
            onClicked: root.backend.takeShortcut()
        }
        Flow {
            Layout.fillWidth: true
            visible: root.confirmReset
            spacing: Theme.space.S
            M.CopyLabel { text: root.backend ? root.backend.text.confirm : "" }
            M.Button { objectName: root.shown ? "settingsConfirmReset" : ""; text: root.backend ? root.backend.text.restore : ""; onClicked: { root.backend.restoreDefaults(root.section); root.confirmReset = false } }
            M.Button { text: root.backend ? root.backend.text.cancel : ""; onClicked: root.confirmReset = false }
        }
        Flow {
            Layout.fillWidth: true
            spacing: Theme.space.S
            M.Button {
                objectName: root.shown ? "settingsUndo" : ""
                text: root.backend ? root.backend.text.undo : ""
                enabled: root.backend && root.backend.canUndo
                onClicked: root.backend.undoLast()
            }
            M.Button {
                objectName: root.shown ? "settingsReset" : ""
                text: root.backend ? root.backend.text.reset : ""
                onClicked: root.confirmReset = true
            }
        }
    }
    Component {
        id: appearance
                Column {
                    spacing: Theme.space.S
                    RowLayout {
                        width: parent.width
                        spacing: Theme.space.L
                        M.CopyLabel { text: root.backend ? root.backend.text.panels : ""; Layout.preferredWidth: 116 }
                        M.Button { Layout.fillWidth: true; text: root.backend ? root.backend.text.layout : ""; onClicked: root.backend.requestCommand("default_layout") }
                    }
                    AppearancePreview { width: parent.width; backend: root.backend }
                    // the icons' group (docs/30-icone.md): six icons drawn as the window draws them, so a choice shows
                    // at once, and the icons' fields
                    M.Section {
                        objectName: root.shown ? "settingsIcons" : ""
                        width: parent.width
                        title: root.backend ? root.backend.text.icons : ""
                        Row {
                            objectName: root.shown ? "settingsIconsPreview" : ""
                            spacing: Theme.space.L
                            Repeater {
                                model: ["folder-open", "save", "search", "settings", "trash", "printer"]
                                M.Icon { required property string modelData; name: modelData; width: Theme.icon.BAR; height: width }
                            }
                        }
                        Repeater {
                            model: root.fields.filter(f => root.iconKeys.includes(f.key))
                            delegate: SettingField { required property var modelData; width: parent.width; backend: root.backend; field: modelData
                                                     section: root.section; values: root.values; labelWidth: root.labelWidth }
                        }
                    }
                    M.Section {
                        width: parent.width
                        title: root.backend ? root.backend.text.additional : ""
                        _open: false
                        RowLayout {
                            width: parent.width
                            M.TextField { id: custom; objectName: "settingsCustomAccent"; Layout.fillWidth: true; placeholderText: "#1c6e8c" }
                            M.Button { text: root.backend ? root.backend.text.custom : ""; onClicked: root.backend.setValue("accent", custom.text) }
                        }
                        Repeater {
                            model: root.fields.filter(f => !["theme", "accent", "backgrounds", "text_size", "font", "density", "toolbar", "toolbar_place"].includes(f.key)
                                                      && !root.iconKeys.includes(f.key))
                            delegate: SettingField { required property var modelData; width: parent.width; backend: root.backend; field: modelData
                                                     section: root.section; values: root.values; labelWidth: root.labelWidth }
                        }
                    }
                }
    }
    Component {
        id: navigationHelp
                Column {
                    spacing: Theme.space.M
                    M.ReadableText { width: parent.width; wrapMode: Text.WordWrap; text: root.backend ? root.backend.navigationHelp.hint : "" }
                    M.ReadableText { width: parent.width; wrapMode: Text.WordWrap; text: root.backend ? root.backend.navigationHelp.audience : "" }
                    Column {
                        width: parent.width
                        spacing: Theme.space.S
                        Repeater {
                            model: root.backend ? root.backend.navigationHelp.gestures : []
                            delegate: RowLayout {
                                required property var modelData
                                width: parent.width
                                spacing: Theme.space.S
                                M.CopyLabel { Layout.preferredWidth: 122; text: modelData.action; textStyle: "strong" }
                                M.ReadableText { Layout.fillWidth: true; text: modelData.gesture; wrapMode: Text.WordWrap }
                            }
                        }
                    }
                    M.ReadableText { width: parent.width; wrapMode: Text.WordWrap; text: root.backend ? root.backend.navigationHelp.note : "" }
                }
    }

    Component {
        id: keyboard
        SettingsKeyboard { backend: root.backend }
    }



}
