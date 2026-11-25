import QtQuick
import QtQuick.Controls as T
import Casa.Theme
import Casa.Controls as M

// The window closed with unsaved changes (backend/closing_part.py): «Save», «Don't save» (at the left, R518) or
// «Cancel»; Esc is «Cancel», Enter is «Save». Opened and closed by the backend's question, every time it is asked
// (a binding on visible would be broken by the first answer).
Item {
    id: root
    anchors.fill: parent
    Connections {
        target: closingBackend
        // the backend's signal is stateChanged (scaffold.Closing): with onChanged the question never came, and a window
        // with changes did not close (21/11/2026, Quotario modifying a bill)
        function onStateChanged() { if (closingBackend.asking) dialog.open(); else if (dialog.opened) dialog.close() }
    }
    M.Dialog {
        id: dialog
        objectName: "closeDialog"
        title: closingBackend.words.title
        acceptText: closingBackend.words.save; rejectText: closingBackend.words.cancel
        actions: [{text: closingBackend.words.discard}]
        onAccepted: closingBackend.answer("save")
        onRejected: closingBackend.answer("cancel")
        onActionTriggered: closingBackend.answer("discard")
        M.ReadableText { objectName: "closeQuestion"; width: parent.width; text: closingBackend.question; wrapMode: Text.Wrap }
    }
}
