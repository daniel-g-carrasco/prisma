import QtQuick
import QtQuick.Controls as T
import Casa.Theme
import Casa.Controls as M

// r30-struttura A2: a copy left by a Casa that stopped without saving, offered back (backend/recovery_part.py).
// «Yes» takes it in hand, «No» deletes it: Esc does not answer for the designer.
Item {
    id: root
    anchors.fill: parent
    M.Dialog {
        objectName: "recoveryDialog"
        title: recoveryBackend.words.title
        acceptText: recoveryBackend.words.yes; rejectText: recoveryBackend.words.no
        closePolicy: T.Popup.NoAutoClose
        visible: recoveryBackend.offered
        onAccepted: recoveryBackend.answer(true)
        onRejected: recoveryBackend.answer(false)
        M.ReadableText { objectName: "recoveryQuestion"; width: parent.width; text: recoveryBackend.question; wrapMode: Text.Wrap }
    }
}
