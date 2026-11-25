import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as T
import QtQuick.Dialogs
import Casa.Theme
import Casa.Controls as M
import Casa.Dialogs as D
Item {
    id: root
    required property var controller
    property var shellTasks: shell.tasks
    property var words: shellTasks.labels
    Connections { target: shellTasks
        function onShowDialog(kind) { if (shellTasks.source.toString() === "") { dialog.kind=kind; dialog.open() } }
        function onChanged() { if (!controller.dialogController.current && dialog.opened) dialog.close() }
    }
    M.Dialog {
        id: dialog; objectName: "shellCommandDialog"
        property string kind: "message"
        implicitWidth: kind==="compare" ? M.ControlMetrics.dialogSize.compare.width : M.ControlMetrics.dialogSize.message.width
        // the words take what they need; only the comparison table fills a height of its own
        implicitHeight: kind==="shortcuts" ? 560 : kind==="about" || kind==="message" ? fitHeight : M.ControlMetrics.dialogSize.compare.height
        title: controller.dialogController.content.title || root.words[kind] || shell.words.title
        // R607: one command stops the comparison under way, the window's own: «Cancel» while it runs (it stops and
        // closes), «Close» after; a report's draft is sent from the window's row of buttons, not from a row in the body
        rejectText: kind==="compare" && shellTasks.busy ? root.words.cancel : root.words.close
        actions: kind==="compare" ? [{text: root.words.copy, enabled: !shellTasks.busy}]
            : kind==="feedback" ? [{text: root.words.copyDraft},
                                   {text: root.words.openDraft, enabled: shellTasks.canShare && summary.text.trim().length>0 && description.text.trim().length>0}] : []
        onActionTriggered: index => kind==="compare" ? shellTasks.copyComparison()
            : shellTasks.shareDraft(summary.text,description.text,environment.checked,index===1)
        onClosed: controller.dialogController.dismiss()
        bodyScrolls: kind !== "shortcuts"
        onRejected: controller.dialogController.dismiss()
        ColumnLayout {
            visible: shellTasks.source.toString() === ""
            M.ReadableText { visible: dialog.kind==="about"; Layout.fillWidth: true; text: shellTasks.about(); wrapMode: Text.Wrap }
            M.ReadableText { visible: dialog.kind!=="feedback" && dialog.kind!=="about"; Layout.fillWidth: true; text: shellTasks.message; wrapMode: Text.Wrap }
            M.ProgressBar { visible: shellTasks.busy; Layout.fillWidth: true; indeterminate: true }
            M.Table { id: comparison; visible: dialog.kind==="compare"; Layout.fillWidth: true; Layout.fillHeight: true
                columns: shellTasks.columns; model: shellTasks.rows
                // the best of each figure drawn strong (r23-tabelle: in place of a delegate of its own)
                emphasis: (row, column) => row.best !== null && row.best !== undefined && String(row.best) === column.key }
            ColumnLayout {
                visible: dialog.kind==="feedback"; Layout.fillWidth: true; Layout.fillHeight: true
                M.ReadableText { Layout.fillWidth: true; text: root.words.intro; wrapMode: Text.Wrap }
                M.TextField { id: summary; objectName: "feedbackTitle"; Layout.fillWidth: true; placeholderText: root.words.title; maximumLength: 180 }
                M.ScrollPage { Layout.fillWidth: true; Layout.preferredHeight: 150; follow: description
                    M.TextArea { id: description; width: parent.width; objectName: "feedbackDescription"; placeholderText: root.words.description
                        color: Theme.colors.text; wrapMode: Text.Wrap; selectByMouse: true }
                }
                M.CheckBox { id: environment; checked: true; text: root.words.environment }
                M.CopyLabel { text: root.words.preview }
                M.ScrollPage { Layout.fillWidth: true; Layout.fillHeight: true
                    M.TextArea { bare: true; width: parent.width; readOnly: true; selectByMouse: true; wrapMode: Text.Wrap; color: Theme.colors.text
                        text: shellTasks.preview(summary.text,description.text,environment.checked) }
                }
            }
        }
    }
}
