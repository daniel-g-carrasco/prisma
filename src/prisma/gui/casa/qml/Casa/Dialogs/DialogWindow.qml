import QtQuick
import Casa.Controls as M

// R586 (census of the 11/11, «secondo contenitore generico»): the windows of File (new project, site, import from
// PVsyst or IFC, models, canopy, registry, shortcuts, update, report a bug, about) are the common window, M.Dialog: its
// title, its body that scrolls when it is taller than the room, its row of buttons, its move by the title. Before, a
// popup of their own drew title and buttons inside the page (DialogsPage) and let a tall page run out of the frame
// (Daniel 11/11/2026, «Importa un modello IFC»: «i contenuti della finestra sbordano»). DialogsPage keeps the content.
M.Dialog {
    id: root
    property var backend
    readonly property string kind: backend ? backend.kind : ""
    // the dialogs whose content fills what it is given have a height of their own; the others take their content's
    readonly property var size: M.ControlMetrics.dialogSize.file[kind] || M.ControlMetrics.dialogSize.file.other
    // R628: the size given by hand is kept for each kind of File's window
    sizeKey: kind ? "file-" + kind : ""
    implicitWidth: size[0]
    implicitHeight: size[1] || fitHeight
    title: backend ? backend.state.title || "" : ""
    // R607: the file a window reads (IFC, PVsyst) by its short name in the head, its whole path in the tooltip
    subtitle: backend ? backend.state.fileShort || "" : ""
    subtitleTip: backend ? backend.state.fileName || "" : ""
    // New project has its own «Create» under its form (NewProjectPage); the registry, the update, about and the report
    // of a bug have nothing to accept
    acceptText: !backend || kind === "about" ? "" : backend.labels.accept
    acceptEnabled: !!backend && !!backend.state.valid && !backend.busy
    acceptOnReturn: false
    // R601 (r35-segni): the shortcuts' list is the only thing that scrolls in its window, the search above it and the
    // new keys under it always in sight; the body does not scroll round it (a low window took the list inside it)
    bodyScrolls: kind !== "shortcuts"
    // the backend closes the window when what it was given is done (dialogs.closed)
    acceptCheck: () => { backend.accept(); return false }
    rejectText: !backend ? "" : kind === "about" ? backend.labels.close : backend.labels.cancel
    // R607 (Daniel 14/11/2026, «il tasto di importare l'IFC è più in alto rispetto al resto»): the commands of a window
    // are on its one row of buttons, the others at its left: the file to read (IFC, PVsyst; gone once a model is read),
    // the variants of a PVsyst project, the search of an update. None stands alone in the body any more.
    readonly property var given: backend ? backend.state : ({})
    actions: []
    Loader { objectName: "dialogContent"; width: parent.width; height: root.bodyScrolls ? implicitHeight : parent.height
        property url hostSource: root.backend ? root.backend.source : ""
        onHostSourceChanged: if (hostSource.toString() !== "") setSource(hostSource, root.kind === "shortcuts" || root.given.usesBackend ? {backend: root.backend} : {})
        onLoaded: if (item && "backend" in item) item.backend=root.backend }
}
