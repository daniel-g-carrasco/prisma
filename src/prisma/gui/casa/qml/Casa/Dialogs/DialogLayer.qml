import QtQuick
import Casa.Theme
// The generic DialogWindow block of Meridiana's DialogLayer; photovoltaic
// catalogues, logos and export pickers are supplied by their owning apps.
Item {
    id: root
    required property var controller
    property var dialogsBackend: controller.scaffold.tasks
    DialogWindow {
        id: dialog
        objectName: "fileDialogOverlay"
        backend: root.dialogsBackend
        Connections { target: root.dialogsBackend; function onChanged() {
            if (root.dialogsBackend.source.toString() !== "" && controller.dialogController.current) dialog.open()
            else if (dialog.opened) dialog.close()
        } }
        onClosed: if (controller.dialogController.current) dialogsBackend.cancel()
    }
}
