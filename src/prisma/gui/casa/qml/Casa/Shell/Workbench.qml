import QtQuick
import QtQuick.Controls as T
import QtQuick.Layouts
import QtQuick.Shapes
import QtQml.Models
import Casa.Theme
import Casa.Controls as M
import Casa.Dialogs as D

T.ApplicationWindow {
    id: root
    required property var controller
    property var shell: controller.scaffold
    property var filesBackend: shell.filePage
    property var filesSettingsBackend: shell.preferences
    property var filesDialogsBackend: null
    property var closingBackend: shell.closing
    property var recoveryBackend: shell.recovery
    property var work: shell.work
    property var filePart: shell.filePage
    property var propertiesBackend: shell.properties
    property Component headerSlot: null
    property Component footerSlot: null
    readonly property real bottomMargin: Theme.layout.GAP
    readonly property real tabMargin: Theme.layout.GAP
    objectName: "quickWindow"
    width: 1600; height: 960; minimumWidth: 800; minimumHeight: 560
    visible: false; title: shell.words.title; color: Theme.colors.window
    // with unsaved changes the closing waits for the answer to «Save the changes?» (backend/closing_part.py)
    onClosing: (close) => {
        if (typeof closingBackend !== "undefined" && closingBackend && !closingBackend.mayClose()) { close.accepted = false; return }
        close.accepted = controller.request_close()
    }
    font.family: Theme.fontFamily; font.pixelSize: Theme.type.BODY
    property string phase: controller.currentPage
    property string displayedPhase: phase
    property string leavingPhase: ""
    function phaseChanging() {
        phaseExit.stop()
        const ids = shell.phases.map(p => p.id)
        leavingPhase = Theme.phaseMotion && !fileShown && ids.includes(phase) && ids.includes(displayedPhase) && phase !== displayedPhase ? displayedPhase : ""
        displayedPhase = phase
        if (leavingPhase) phaseExit.start()
    }
    SequentialAnimation {
        id: phaseExit
        PauseAnimation { duration: Theme.motion.FAST }
        ScriptAction { script: root.leavingPhase = "" }
    }
    Connections { target: Theme; function onPhaseMotionChanged() { if (!Theme.phaseMotion) { phaseExit.stop(); root.leavingPhase = "" } } }

    onPhaseChanged: { workspace.allowPanels(phase); const leaving=displayedPhase, coming=phase; if(leaving) Qt.callLater(()=>workspace.switchPage(leaving, coming)); phaseChanging(); M.Help.close(); workspace.arrangementChanged(); arrangeTimer.restart(); phaseSelected(phase) }
    signal phaseSelected(string phase)
    property bool fileOpen: controller.activeView !== "pages"
    property bool fileShown: fileOpen
    function beginVeil() { fileVeil.t=0; fileVeil.waitFrames=1; fileVeil.running=true; root.requestUpdate() }
    property bool projectDirty: controller.fileController.dirty
    onFileOpenChanged: { beginVeil(); M.Help.close() }
    property real fileMotionTop: menus.height+phaseHeader.rowHeight
    property real fileMotionBottom: footer.height
    function findNamed(name) {
        let top = root.contentItem
        while (top.parent) top = top.parent
        const pending = [top]
        while (pending.length) {
            const item = pending.pop()
            if (item.objectName === name) return item
            const kids = item.children || []
            for (let i = kids.length - 1; i >= 0; i--) pending.push(kids[i])
        }
        return null
    }
    property bool menuOpen: false
    property bool menuAlways: false
    property var barMenu: null          // the menu of the bar now open (R475)
    property bool altArmed: false
    // the Python filter of the shell (alt.AltTap) is there: it alone tells a tap, since it sees the keys a shortcut
    // takes before this item (Alt+Down, 21/11/2026); the handler below opened the menus after them
    property bool altFilter: false
    // R317, R527: Alt held while a card is carried makes the middle of the card under the pointer a tab. Told by the
    // window's filter (backend/window_frame.AltTap.held), down and up, so the target answers with the mouse still.
    property bool altHeld: false
    function setAltHeld(down) { if(altHeld===!!down) return; altHeld=!!down; workspace.retarget() }
    function altPressed(event) {
        if(event.key===Qt.Key_Alt) setAltHeld(true)
        if(event.key===Qt.Key_Alt && !(event.modifiers & Qt.ControlModifier) && !workspace.draggedPanel) { altArmed=true; event.accepted=true }
        else altArmed=false
    }
    function altReleased(event) {
        // with the window's filter (backend/window_frame.AltTap, R481) the tap comes to altTapped and its release
        // never gets here; this is for a workbench made without it
        if(event.key===Qt.Key_Alt) setAltHeld(false)
        if(event.key===Qt.Key_Alt && altArmed && !altFilter && !workspace.draggedPanel) { altArmed=false; event.accepted=true; altTapped() }
        else if(event.key===Qt.Key_Alt) altArmed=false
    }
    // R481: Alt alone, wherever the focus is. Hidden: the bar shows with the focus on its first title. Shown: it hides
    // (a menu of it closed first) and the focus goes back where it was. Always shown (menuAlways): the focus goes to
    // it and back.
    property var focusBeforeMenu: null
    readonly property bool menuFocused: { const f=root.activeFocusItem; let n=f; while(n) { if(n===menus) return true; n=n.parent } return false }
    function altTapped() {
        const showing = menuAlways ? !menuFocused && !(barMenu && barMenu.visible) : !menuOpen
        if(showing) {
            focusBeforeMenu = root.activeFocusItem
            menuOpen = true
            focusMenu(0)
        } else {
            if(barMenu && barMenu.visible) barMenu.close()
            menuOpen = menuAlways
            returnFocus()
        }
    }
    function returnFocus() {
        const back = focusBeforeMenu
        focusBeforeMenu = null
        if(back && back.visible && back.enabled !== false) back.forceActiveFocus()
        else workspace.forceActiveFocus()
    }
    // a click outside the bar hides it, as Esc does (the click takes the focus where it lands)
    function pointerPressedAt(x, y) {
        if(!menuOpen || menuAlways || (barMenu && barMenu.visible)) return
        const p = menus.mapFromItem(null, x, y)
        if(p.x < 0 || p.y < 0 || p.x > menus.width || p.y > menus.height) { menuOpen = false; focusBeforeMenu = null }
    }
    function focusMenu(index) {
        const button=menuEntries.itemAt((index+menuEntries.count)%menuEntries.count)
        if(button) button.forceActiveFocus(Qt.MenuBarFocusReason)
    }
    property bool transitions: true
    property string viewMode: "page"
    property alias leftWidth: workspace.leftExtent
    property alias rightWidth: workspace.rightExtent
    readonly property real panelMinimum: 284 * Theme.type.BODY / 13
    property var workspaceItem: workspace
    property var partSources: shell.partSources
    property string toolbarMode: "auto"
    property string toolbarPosition: "top"
    property bool cleanScreen: false
    property var cleanLayout: null
    property var arrangementInfo: ({})
    property var shapeLayouts: ({})
    // services["workspaces"] (scaffold.py): each page its own workspace, its panels and their arrangement remembered
    // apart (Daniel 21/11/2026); without it one workspace for the window, as Meridiana
    readonly property bool pageWorkspaces: shell.panelMemory==="page"
    property var pageStates: ({})
    function shapeKey(shape) { return pageWorkspaces ? shape+"@"+phase : shape }
    // which panels a page has (scaffold.pagePanels), given to the cards at each change of page: a binding on each
    // card's phaseAllowed made the arrangement's bindings loop at the start
    readonly property var pagePanels: shell.pagePanels
    readonly property var pageSpans: shell.pageSpans
    function onPage(id, page) { const list=pagePanels[page]; return !list || list.indexOf(id)>=0 }
    // R628: with the sizes given by hand to the windows, by their kind (M.DialogSizes)
    readonly property int layoutVersion: 2
    function savedLayout() { return {version: layoutVersion, layout: cleanScreen && cleanLayout ? cleanLayout : workspace.snapshot(), shapes: shapeLayouts, dialogs: M.DialogSizes.sizes, toolbar: toolbarMode, position: toolbarPosition, menu: menuAlways,
        pages: pageWorkspaces ? workspace.pagesWithCurrent() : ({})} }
    function restoreLayout(saved) {
        const state = saved ? JSON.parse(JSON.stringify(saved)) : null
        function apply() {
            if (!state || state.version !== layoutVersion || !workspace.validLayout(state.layout)) {
                pageStates = {}; shapeLayouts = {}; shapePins = {}
                workspace.put(workspace.pageState(phase, true), false)
                return
            }
            pageStates = state.pages || ({}); shapeLayouts = state.shapes || ({})
            toolbarMode = state.toolbar || "auto"; toolbarPosition = state.position || "top"
            menuAlways = state.menu || false; menuOpen = menuAlways
            M.DialogSizes.sizes = state.dialogs || ({})
            workspace.put(state.layout, false)
        }
        // At startup, wait for the host panel delegates. Later restores apply immediately.
        if (workspace.initialized) apply()
        else Qt.callLater(apply)
    }
    property string viewsArrangement: arrangementInfo.views || "side"
    onWidthChanged: { arrangeTimer.restart(); controller.dialogController.set_bounds(width, height) }
    onHeightChanged: { arrangeTimer.restart(); controller.dialogController.set_bounds(width, height) }
    onToolbarModeChanged: arrangeTimer.restart()
    Timer { id: arrangeTimer; interval: Theme.motion.NORMAL; onTriggered: root.arrange() }
    // ui/window.py _arrange: what the window should be for its size; said, with its Undo for a few seconds, when the
    // program moved something (Daniel: nothing changes by surprise). D23.
    property var shapePins: ({})
    property var arrangeUndo: null
    Timer { id: arrangeUndoTimer; interval: 15000; onTriggered: root.arrangeUndo=null }
    function arrange() {
        if(fileOpen || cleanScreen) return
        const was=arrangementInfo, before=was.shape ? workspace.snapshot() : null
        // a bar mode fixed by the host ("under", "beside": ShellController.bind) is what the bar shows, so the
        // arrangement takes it as chosen and never says «the icons alone» while the words stay (the showcase, 20/11/2026)
        const fixedBar=toolbarMode==="under" || toolbarMode==="beside" ? {bar:toolbarMode} : {}
        const next=shell.layoutFor(width,height,phase,{previous:was,toolbar:toolbarMode==="icons" ? "icons" : "text",needs:phaseHeader.layoutNeeds,columns:[workspace.leftExtent,workspace.rightExtent],checks:workspace.bottomExtent,pins:Object.assign({},shapePins[was.shape || ""] || {},fixedBar)})
        if(pageWorkspaces) { arrangementInfo=next; return }
        let remembered=false
        if(next.shape!==was.shape) {
            if(was.shape) shapeLayouts[shapeKey(was.shape)]=before
            if(workspace.validLayout(shapeLayouts[shapeKey(next.shape)])) { workspace.put(shapeLayouts[shapeKey(next.shape)]); remembered=true; sideProject(next.panels,false) }
            else {
                sideProject(next.panels,true)
                checks.opened=next.checks_open
                workspace.selectPanel("properties")
            }
        } else {
            if(next.checks_open!==was.checks_open) checks.opened=next.checks_open
            if(next.panels!==was.panels) sideProject(next.panels,true)
        }
        arrangementInfo=next
        workspace.arrangementChanged()
        if(was.shape) {
            const said=shell.arrangedSay(was,next,remembered)
            if(said.fields.length || remembered) { arrangeUndo={before:before,was:was,fields:said.fields}; arrangeUndoTimer.restart() }
        }
    }
    // R549: the side of Project follows the room. A window too narrow for two columns has it as a tab beside Properties
    // on the right; once there is room again it goes back to the left (`back`), also within one shape: «medium» goes
    // from 800 px to well past NARROW, and Niri opens a window at half the laptop's screen (800 x 828) and widens it
    // there, where the side was set only when the shape changed and Project stayed behind Properties. A card on the
    // bottom or floating is the user's and stays.
    function sideProject(panels, back) {
        if(panels==="together" && project.zone==="left") { workspace.unstack(project.panelId); project.zone="right" }
        else if(back && panels==="apart" && project.zone==="right") { workspace.unstack(project.panelId); project.zone="left" }
        workspace.arrangementChanged()
    }
    function undoArrange() {
        if(!arrangeUndo) return
        const undo=arrangeUndo
        arrangeUndo=null; arrangeUndoTimer.stop()
        const pins=Object.assign({},shapePins)
        pins[arrangementInfo.shape]=shell.arrangePinned(pins[arrangementInfo.shape] || {},undo.was,undo.fields)
        shapePins=pins
        workspace.put(undo.before)
        arrangementInfo=Object.assign({},undo.was,{shape:arrangementInfo.shape})
        arrange()
        arrangeUndo=null
        shell.arrangeBack()
    }
    function showPhase(value) { controller.select_page(value) }
    // A page off (Page.enabled false) is passed over
    function cyclePhase(delta) { const ids=shell.phases.filter(p=>p.enabled!==false).map(p=>p.id); showPhase(ids[(ids.indexOf(phase)+delta+ids.length)%ids.length]) }
    function runCommand(command) {
        if (command.startsWith("panel_")) workspace.togglePanel(command.substring(6))
        else if (command === "side_left") workspace.toggleEdge("left")
        else if (command === "default_layout") workspace.restore()
        else if (command === "next_phase") cyclePhase(1)
        else if (command === "previous_phase") cyclePhase(-1)
        else if (command === "toolbar_text") toolbarMode=toolbarMode==="icons" ? "auto" : "icons"
        // G5 (Daniel 21/11/2026): the bar of small buttons on two rows, on and off (View menu, Appearance)
        else if (command === "toolbar_small") toolbarMode=toolbarMode==="small" ? "auto" : "small"
        else if (command === "menu_bar") altTapped()
        else if (command === "fullscreen") controller.frameController.toggle_fullscreen()
    }
    property bool toolsShown: true
    property bool escTaken: false
    Shortcut { sequence: "Esc"; enabled: !root.escTaken; onActivated: { if(M.Help.close()) return; if(root.fileOpen) controller.show_view("pages"); else if(root.menuOpen && !root.menuAlways) { root.menuOpen=false; root.returnFocus() } else workspace.cancelDrag() } }
    Connections { target: shell; function onCommandRequested(command) { root.runCommand(command) } }
    M.Menu {
        id: titleMenu; objectName: "cardTitleMenu"
        Repeater { model: workspace.panels
            M.MenuItem { required property var modelData; text: modelData.title; checkable: true
                checked: modelData.opened && modelData.phaseAllowed; enabled: modelData.phaseAllowed
                onTriggered: { modelData.opened=!modelData.opened; if(modelData.opened) workspace.selectPanel(modelData.panelId); else workspace.arrangementChanged() } }
        }
        M.MenuItem { text: shell.words.tools; checkable: true; checked: root.toolsShown; onTriggered: root.toolsShown=!root.toolsShown }
    }
    Repeater {
        model: shell.keyCommands
        delegate: Item {
            required property var modelData
            Shortcut {
                sequences: modelData.keys
                enabled: !modelData.keys.some(k => k.length===1) || !root.activeFocusItem || root.activeFocusItem.cursorPosition===undefined
                onActivated: shell.trigger(modelData.id)
            }
        }
    }
    header: Column {
        Keys.onPressed: event => root.altPressed(event)
        Keys.onReleased: event => root.altReleased(event)
        spacing: 0
        TitleBar { width: root.width; controller: root.controller
            visible: controller.frameController.mode === "casa"; height: visible ? implicitHeight : 0 }
        Row {
            id: menus; objectName: "altMenuBar"
            // Daniel 21/11/2026 («la comparsa della barra menu Alt è molto scattosa e lenta», over a table of 50,000
            // rows): its room is taken and given back in one step, so the page is laid out once; the bar comes and
            // goes by its opacity and a slide, with the kit's duration and curve (before, its height grew frame by
            // frame and every frame laid out the page and its table again)
            height: root.menuOpen || menusFade.running ? Theme.size.CONTROL : 0
            visible: height>0; clip: true
            opacity: root.menuOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { id: menusFade; duration: Theme.reducedMotion ? 0 : Theme.motion.NORMAL; easing.type: Theme.motion.EASE } }
            transform: Translate { y: (menus.opacity-1)*Theme.space.S }
            x: Theme.layout.EDGE
            Repeater {
                id: menuEntries
                model: shell.menus
                M.Button {
                    id: menuButton
                    required property var modelData
                    required property int index
                    objectName: "mainMenu_"+index
                    readonly property bool menuOpened: menuPopup.visible
                    text: modelData.title; flat: true
                    active: activeFocus || menuPopup.visible
                    Keys.onRightPressed: root.focusMenu(index+1)
                    Keys.onLeftPressed: root.focusMenu(index-1)
                    Keys.onDownPressed: menuPopup.open()
                    Keys.onReturnPressed: menuPopup.open()
                    Keys.onEnterPressed: menuPopup.open()
                    // R475: a second click on the same title closes its menu; passing over the next title while a
                    // menu is open opens that one, as in a menu bar.
                    onClicked: menuPopup.visible ? menuPopup.close() : menuPopup.open()
                    onHoveredChanged: if (hovered && root.barMenu && root.barMenu !== menuPopup && root.barMenu.visible) menuPopup.open()
                    Shortcut { sequence: "Alt+"+menuButton.modelData.mnemonic
                        onActivated: { root.menuOpen=true; menuPopup.open() }
                        // Two menus with one letter (Varianti, Aiuto): each press goes to the next, as in a menu bar.
                        onActivatedAmbiguously: { root.menuOpen=true; menuPopup.open() } }
                    M.Menu {
                        id: menuPopup; y: menuButton.height
                        objectName: "mainMenuPopup_" + menuButton.index
                        // a press on its own title is the title's: it closes the menu by the click above
                        closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutsideParent
                        onAboutToShow: { if (root.barMenu && root.barMenu !== menuPopup) root.barMenu.close(); root.barMenu = menuPopup }
                        onClosed: if (root.barMenu === menuPopup) root.barMenu = null
                        Repeater {
                            model: menuButton.modelData.commands
                            M.MenuItem { required property var modelData
                                // R564: an entry off says why in the column of the keys (Command.reason), as MenuEntry
                                text: modelData.text; shortcutText: shell.commandNote[modelData.id] || modelData.keys.join(", "); tip: modelData.tip; enabled: modelData.enabled && shell.commandEnabled[modelData.id]!==false
                                // R646: Full screen says it is on with the check of the menus, and so does a command
                                // with two states (Command.checked); not checkable: a click would break the binding
                                checked: modelData.id==="fullscreen" && root.visibility===Window.FullScreen || shell.commandChecked[modelData.id]===true
                                onTriggered: { shell.trigger(modelData.id); root.menuOpen=root.menuAlways } }
                        }
                        Instantiator {
                            model: menuButton.modelData.submenus
                            delegate: M.Menu {
                                required property var modelData
                                title: modelData.title
                                Repeater { model: modelData.commands
                                    M.MenuItem { required property var modelData
                                        text: modelData.text; shortcutText: shell.commandNote[modelData.id] || modelData.keys.join(", "); tip: modelData.tip; enabled: modelData.enabled && shell.commandEnabled[modelData.id]!==false
                                        checked: shell.commandChecked[modelData.id]===true
                                        onTriggered: { shell.trigger(modelData.id); root.menuOpen=root.menuAlways } }
                                }
                            }
                            onObjectAdded: (index, object) => menuPopup.insertMenu(index+3,object)
                            onObjectRemoved: (index, object) => menuPopup.removeMenu(object)
                        }
                    }
                }
            }
        }
        PhaseHeader {
            id: phaseHeader; objectName: "phaseBar"
            width: root.width-2*Theme.layout.EDGE; x: Theme.layout.EDGE
            phase: root.phase; fileOpen: root.fileShown; dirty: root.projectDirty
            leavingPhase: root.leavingPhase
            trailingSource: root.partSources[root.phase+"Trailing"] || ""
            trailingCanMove: false         // R553: above the views when the bar has no room; no views, it stays
            onLayoutNeedsChanged: arrangeTimer.restart()
            selectedTool: ""
            barVisible: !root.fileShown && !root.cleanScreen && root.toolbarPosition==="top" && root.toolsShown
            barMode: fitting(root.toolbarMode==="auto" ? (root.arrangementInfo.bar || (root.height < shell.metrics.lowWindow ? "beside" : "under")) : root.toolbarMode)
            // G5 (docs/28-barra-piccola.md): a form that does not fit in the width becomes the small one, whose last
            // groups then go into «More»; the form chosen comes back when the window widens
            function fitting(mode) { const needs=layoutNeeds, room=width-2*pad, page=phases.length ? phases[currentIndex].id : ""
                return mode!=="small" && needs[mode] && needs[mode][page]>room && needs.small[page]<needs[mode][page] ? "small" : mode }
            onPhaseChosen: phase => root.showPhase(phase)
            onFileRequested: controller.show_view(root.fileOpen ? "pages" : "file")
        }
    }
    Item {
        id: sideTools; visible: root.toolbarPosition==="left" && !root.fileShown && !root.cleanScreen && root.toolsShown
        // Native QToolBar: 33 px buttons and 2 px padding, no surrounding card.
        property real buttonExtent: Theme.icon.BAR+2*Theme.space.XS+3
        x: 0; y: 0; width: buttonExtent+2*Theme.space.XXS
        height: parent.height
        Flickable { anchors.fill: parent; anchors.margins: Theme.space.XXS; contentHeight: sideColumn.height; clip: true
            Column { id: sideColumn; spacing: Theme.space.XXS
                // Built only while the tools stand on the left (06/11/2026): hidden, they were rebuilt at every phase.
                Repeater { model: sideTools.visible ? shell.phases.find(p=>p.id===root.phase).groups : []
                    Column { required property var modelData; spacing: Theme.space.XXS
                        Repeater { model: modelData.tools
                            Loader {
                                id: sideLoader
                                required property var modelData
                                property var family: [modelData].concat(modelData.more)
                                property var face: !modelData.fixed ? (family.find(t=>phaseHeader.toolMatches(t.command)) || modelData) : modelData
                                sourceComponent: modelData.more.length ? sideSplit : sidePlain
                                // As in PhaseHeader: a button that is off takes no hover, its Loader says why
                                readonly property bool faceOn: sideLoader.face.enabled && shell.commandEnabled[sideLoader.face.command]!==false
                                HoverHandler { id: sideOffHover; enabled: !sideLoader.faceOn }
                                M.ToolTip { objectName: "sideOffTip_" + sideLoader.modelData.command
                                    text: phaseHeader.withNote(sideLoader.modelData.more.length ? sideLoader.face.faceTip : sideLoader.face.tip, sideLoader.face.command)
                                    visible: sideOffHover.hovered && !sideLoader.faceOn && !!shell.commandNote[sideLoader.face.command]
                                        && (!sideLoader.modelData.more.length || sideOffHover.point.position.x < sideLoader.width - Theme.space.M) }
                                Component {
                                    id: sidePlain
                                    PhaseToolButton {
                                        objectName: "sideTool_"+sideLoader.modelData.command
                                        mode: "icons"; width: sideTools.buttonExtent; height: width
                                        text: sideLoader.face.label
                                        iconName: shell.commandIcon[sideLoader.face.command] || sideLoader.face.icon; tip: sideLoader.face.tip
                                        enabled: sideLoader.face.enabled && shell.commandEnabled[sideLoader.face.command]!==false
                                        active: phaseHeader.toolMatches(sideLoader.face.command) || shell.commandChecked[sideLoader.face.command]===true
                                        onClicked: shell.trigger(sideLoader.face.command)
                                    }
                                }
                                Component {
                                    id: sideSplit
                                    PhaseSplitButton {
                                        objectName: "sideTool_"+sideLoader.modelData.command
                                        mode: "icons"; width: sideTools.buttonExtent; height: width; stripWidth: Theme.space.M
                                        text: sideLoader.face.label
                                        iconName: shell.commandIcon[sideLoader.face.command] || sideLoader.face.icon; tip: sideLoader.face.faceTip
                                        stripTip: sideLoader.modelData.stripTip
                                        enabled: sideLoader.family.some(t=>t.enabled)
                                        mainEnabled: sideLoader.face.enabled && shell.commandEnabled[sideLoader.face.command]!==false
                                        active: phaseHeader.toolMatches(sideLoader.face.command) || shell.commandChecked[sideLoader.face.command]===true
                                        stripActive: sideLoader.family.some(t=>t.command!==sideLoader.face.command && (phaseHeader.toolMatches(t.command) || shell.commandChecked[t.command]===true))
                                        model: sideLoader.family
                                        onClicked: shell.trigger(sideLoader.face.command)
                                        onChosen: index=>shell.trigger(sideLoader.family[index].command)
                                    }
                                }
                            }
                        }
                        Item { width: sideTools.buttonExtent; height: Theme.space.S
                            Rectangle { anchors.centerIn: parent; width: parent.width-2*Theme.space.XS; height: Theme.line.HAIR; color: Theme.colors.line_soft }
                        }
                    }
                }
            }
        }
    }
    Item {
        id: workspace
        objectName: "workspace"
        anchors.fill: parent; anchors.leftMargin: Theme.layout.EDGE+(sideTools.visible ? sideTools.width : 0); anchors.rightMargin: Theme.layout.EDGE
        // R645: no gap at the foot: the bar under the cards keeps its words and signs as far from the cards above as
        // from the window's foot (its own half height)
        anchors.topMargin: Theme.layout.GAP; anchors.bottomMargin: 0
        visible: !root.fileShown
        focus: true
        Keys.onPressed: event => root.altPressed(event)
        Keys.onReleased: event => root.altReleased(event)
        property real leftExtent: shell.metrics.leftWidth
        property real rightExtent: shell.metrics.rightWidth
        property real bottomExtent: shell.metrics.checksHeight
        // set with the page (allowPanels): read in a binding of the cards' geometry, the page started its change
        // handler in the middle of it (a binding loop)
        property bool bottomUnderCenter: shell.bottomSpan==="center"
        readonly property real centreShare: 0.6
        property int revision: 0
        readonly property bool phaseTransition: root.leavingPhase!==""
        property var phaseSlots: ({})
        property var phaseCards: ({})
        function rememberPhase() {
            // Snapshot before changing the phase: retiring a card must not slide its neighbours under it.
            const slots={}, cards={}
            for(const zone of ["left","right","bottom","center"]) slots[zone]=slot(zone)
            if(!has("left")) delete slots.left
            for(const card of panels) if(card.visible) cards[card.panelId]=true
            phaseSlots=slots; phaseCards=cards
        }
        property bool settling: false
        // R37 (Meridiana d338e66f): an edge or the line between two cards is being dragged: the cards hold what they
        // show (DockPanel.held), the page in the middle keeps its size and is laid out once at the release
        property bool resizing: false
        // the sign of the border taken (Qt.SplitVCursor, Qt.SplitHCursor), kept by resizeCursorCover for the whole gesture
        property int resizeCursor: Qt.ArrowCursor
        // Daniel 21/11/2026 («vorrei che il contenuto si spostasse dinamicamente... come Electron»): the content follows
        // the border live; what costs (the tables' heights and wrapped texts) waits for the release
        // (ControlMetrics.resizing). Only when a step still costs past 33 ms, the median of the last five (from the new
        // size to its frame drawn: `stepCosts`), the cards and the page hold their content for the rest of the drag
        // (`holdContent`), as before. Not the time between frames: a hand moving slowly leaves long gaps with little
        // work, and the content was held for nothing (21/11/2026, measured on the Dell)
        property bool holdContent: false
        property real stepAt: 0
        property var stepCosts: []
        readonly property real stepCost: stepCosts.length ? stepCosts[stepCosts.length-1] : 0
        onResizingChanged: { holdContent=false; stepAt=0; if(resizing) stepCosts=[]; M.ControlMetrics.resizing=resizing }
        function stepped() { if(resizing) { stepAt=Date.now(); root.requestUpdate() } }
        Connections {
            target: workspace.resizing && workspace.stepAt>0 ? root : null
            function onFrameSwapped() {
                // a second frame before the target lets go: no step to count
                if(workspace.stepAt<=0) return
                workspace.stepCosts=workspace.stepCosts.concat([Date.now()-workspace.stepAt])
                workspace.stepAt=0
                // the median of the last five: the first steps of a drag cost more (the table's first layout at a new
                // width) and must not hold the content alone
                const last=workspace.stepCosts.slice(-5).sort((a,b)=>a-b)
                // and only after the first eight steps, which pay the first layout without the mask (about 40 ms)
                if(!workspace.holdContent && workspace.stepCosts.length>=8 && last[2]>33) workspace.holdContent=true
            }
        }
        property var panels: {
            let list=[project, properties, checks]
            for (let i=0; i<hostPanels.count; i++) { const p=hostPanels.itemAt(i); if(p) list.push(p) }
            return list
        }
        property var selected: ({left:"project",right:"properties",bottom:"checks"})
        property string draggedPanel: ""
        property point dragStart
        property point dragOrigin
        property string candidate: ""
        property string targetZone: ""
        property bool grouping: false
        // Each zone is a line of slices: "*" the cards in tabs, any other a card with a slice of its own (ui/dock_motion.py).
        property var stacks: ({left:[],right:[],bottom:[]})
        property var weights: ({})
        property var dragTarget: null
        function stackedHere(panel) { return (stacks[panel.zone] || []).includes(panel.panelId) }
        function tabMembers(zone) { const r=revision; return members(zone).filter(p=>!(stacks[zone] || []).includes(p.panelId)) }
        // A tab joins the shared group, replacing a standalone slice if necessary.
        // The preview and the committed topology use exactly the same operation.
        function tabLine(line, anchor) {
            return line.includes("*") ? line.filter(id=>id!==anchor) : line.map(id=>id===anchor ? "*" : id)
        }
        function sliceList(zone, target=dragTarget) {
            const r=revision
            const here=panels.filter(p=>p && p.opened && p.phaseAllowed && p.zone===zone && (!target || p.panelId!==draggedPanel))
            const ids=here.map(p=>p.panelId), own=(stacks[zone] || []).filter(id=>ids.includes(id))
            let line=(stacks[zone] || []).filter(id=>id==="*" || ids.includes(id))
            const tabs=ids.filter(id=>!own.includes(id))
            if(!line.includes("*") && tabs.length) line=["*"].concat(line)
            if(line.includes("*") && !tabs.length) line=line.filter(id=>id!=="*")
            if(target && target.zone===zone && target.where==="tab") line=tabLine(line,target.anchor)
            if(target && target.zone===zone && target.where!=="tab") {
                let at=line.length
                if(target.anchor) { const key=line.includes(target.anchor) ? target.anchor : "*"; const i=line.indexOf(key); if(i>=0) at=target.where==="before" ? i : i+1 }
                line=line.slice(0,at).concat([draggedPanel]).concat(line.slice(at))
            }
            return line
        }
        function sliceRect(zone, key, target=dragTarget) {
            const line=sliceList(zone,target), whole=slot(zone,target), i=line.indexOf(key)
            if(i<0) return whole
            const across=zone==="bottom", gap=Theme.layout.GAP
            const room=Math.max(0,(across ? whole.width : whole.height)-gap*(line.length-1))
            const sum=line.reduce((n,id)=>n+(weights[id] || 1),0)
            let at=0
            for(let k=0;k<i;k++) at+=Math.round(room*(weights[line[k]] || 1)/sum)+gap
            const size=i===line.length-1 ? room+gap*(line.length-1)-at : Math.round(room*(weights[key] || 1)/sum)
            return across ? Qt.rect(whole.x+at,whole.y,size,whole.height) : Qt.rect(whole.x,whole.y+at,whole.width,size)
        }
        function place(panel) { return sliceRect(panel.zone,stackedHere(panel) ? panel.panelId : "*") }
        function snapshot() { return {stacks:JSON.parse(JSON.stringify(stacks)),weights:Object.assign({},weights),left:leftExtent,right:rightExtent,bottom:bottomExtent,selected:Object.assign({},selected),view:root.viewMode,
            panels:panels.map(p=>({id:p.panelId,zone:p.zone,opened:p.opened,x:p.floatX,y:p.floatY,width:p.floatWidth,height:p.floatHeight}))} }
        function validLayout(state) {
            const zones = ["left", "right", "bottom"]
            if (!state || !state.stacks || !state.weights || !state.selected || !Array.isArray(state.panels)
                || !["page", "split", "focus"].includes(state.view)) return false
            const byId = new Map()
            for (const panel of state.panels) {
                if (!panel || typeof panel.id !== "string" || byId.has(panel.id)
                    || !panels.some(p => p.panelId === panel.id)
                    || !zones.concat("floating").includes(panel.zone) || typeof panel.opened !== "boolean"
                    || ![panel.x, panel.y, panel.width, panel.height].every(Number.isFinite)
                    || panel.width <= 0 || panel.height <= 0) return false
                byId.set(panel.id, panel)
            }
            return byId.size === panels.length && Object.values(state.weights).every(w => Number.isFinite(w) && w > 0)
                && zones.every(zone => {
                    const ids = state.stacks[zone]
                    return Number.isFinite(state[zone]) && state[zone] > 0 && typeof state.selected[zone] === "string"
                        && Array.isArray(ids) && new Set(ids).size === ids.length
                        && ids.every(id => id === "*" || byId.get(id)?.zone === zone)
                })
        }
        function put(state, animate=true) { if(!state) return; settling=animate; stacks=state.stacks; weights=state.weights; leftExtent=state.left;rightExtent=state.right;bottomExtent=state.bottom;selected=state.selected;root.viewMode=state.view
            state.panels.forEach(s=>{ const p=panels.find(p=>p.panelId===s.id);if(!p) return;p.zone=s.zone;p.opened=s.opened;p.floatX=s.x;p.floatY=s.y;p.floatWidth=s.width;p.floatHeight=s.height })
            arrangementChanged(); if(animate) settleTimer.restart(); else settleTimer.stop() }
        signal arrangementChanged()
        onArrangementChanged: revision++
        function members(zone) { const r=revision; return panels.filter(p => p && p.opened && p.phaseAllowed && p.zone===zone) }
        function has(zone, target=dragTarget) { return sliceList(zone,target).length>0 }
        function activePanel(zone) { const list=tabMembers(zone); return list.some(p => p.panelId===selected[zone]) ? selected[zone] : list.length ? list[0].panelId : "" }
        function slot(zone, target=dragTarget) {
            if(phaseTransition && phaseSlots[zone]) return phaseSlots[zone]
            // Whole pixels: the 3D renders to a texture, and a texture at a fraction is resampled and blurred.
            const l=has("left",target) ? Math.round(Math.min(leftExtent,width*0.32)) : 0
            const r=has("right",target) ? Math.round(Math.max(root.panelMinimum,Math.min(rightExtent,width*0.34))) : 0
            // bottom_span "center": in a low window the bottom panel gives way before the centre (Daniel 20/11/2026:
            // at 1100 x 700 the Description stood higher than the bill): the centre keeps at least centreShare of
            // the height, the panel takes the rest, never less than Theme.size.PANEL_MIN nor more than its own extent
            const b=has("bottom",target) ? Math.round(Math.min(bottomExtent,bottomUnderCenter
                ? Math.max(Theme.size.PANEL_MIN,height*(1-centreShare)-Theme.layout.GAP) : height*0.48)) : 0
            const lg=l>0 ? Theme.layout.GAP : 0, rg=r>0 ? Theme.layout.GAP : 0, bg=b>0 ? Theme.layout.GAP : 0
            // services["bottom_span"]: "wide" (Meridiana) runs the bottom under the left and the centre; "center" only
            // under the centre, and the left goes to the foot as the right does
            if(zone==="left") return Qt.rect(0,0,l,bottomUnderCenter ? height : height-b-bg)
            if(zone==="right") return Qt.rect(width-r,0,r,height)
            if(zone==="bottom") return bottomUnderCenter ? Qt.rect(l+lg,height-b,width-l-lg-r-rg,b) : Qt.rect(0,height-b,width-r-rg,b)
            return Qt.rect(l+lg,0,width-l-lg-r-rg,height-b-bg)
        }
        // A page's workspace at its first visit, as its host declared it (scaffold.workspaceFor); what it does not
        // declare stays as the window has it. `home`: as at the first start (Restore the default layout)
        function pageState(page, home) {
            const w=shell.workspaceFor(page)
            const size=side=>w.sizes[side]!==undefined ? w.sizes[side] : home ? w.firstSizes[side]
                : side==="left" ? leftExtent : side==="right" ? rightExtent : bottomExtent
            return {stacks:{left:[],right:[],bottom:[]},weights:{},left:size("left"),right:size("right"),bottom:size("bottom"),
                selected:{left:"project",right:"properties",bottom:"checks"},view:root.viewMode,
                panels:panels.map(p=>({id:p.panelId,zone:w.zones[p.panelId] || w.homes[p.panelId] || p.zone,
                    opened:!!w.open[p.panelId],x:p.floatX,y:p.floatY,width:p.floatWidth,height:p.floatHeight}))}
        }
        function pagesWithCurrent() { const states=Object.assign({},root.pageStates); states[root.phase]=snapshot(); return states }
        // Leaving a page keeps its arrangement; the next page comes back as it was left, or as declared
        function switchPage(from, to) {
            if(!root.pageWorkspaces || !to || from===to) return
            cancelDrag()
            const states=Object.assign({},root.pageStates)
            if(from) states[from]=snapshot()
            root.pageStates=states
            put(validLayout(states[to]) ? states[to] : pageState(to, true), false)
        }
        function allowPanels(page) { bottomUnderCenter=(root.pageSpans[page] || shell.bottomSpan)==="center"
            for(const p of panels) p.phaseAllowed=root.onPage(p.panelId, page) }
        property bool initialized: false
        Component.onCompleted: Qt.callLater(() => {
            allowPanels(root.phase)
            if (root.pageWorkspaces) put(pageState(root.phase, true), false)
            initialized = true
        })
        function selectPanel(id) { const p=panels.find(p => p.panelId===id); const next=Object.assign({},selected); next[p.zone]=id; selected=next; arrangementChanged() }
        function togglePanel(id) { const p=panels.find(p => p.panelId===id); if(p && p.phaseAllowed) { if(p.opened && !p.selected) selectPanel(id); else p.opened=!p.opened; if(p.opened) selectPanel(id); arrangementChanged() } }
        // R549 (Daniel 08/11/2026, as VS Code): each button of the status bar is a side, the left, the bottom, the right,
        // whatever cards stand there; its picture always says the truth. Shown, it hides all the cards of its side,
        // a group of tabs as a whole (the tab in front is kept in `selected`); the side empty, it brings back the
        // cards it hid last, there, and when it never hid any the card of that side at the first start. One card
        // alone is closed by its X or from the Panels menu, by its name. Before, the bottom button took the cards of
        // the right side too, and Project moved to the right answered to the left one.
        property var collapsedEdges: ({})
        readonly property var homeCards: ({left:"project",bottom:"checks",right:"properties"})
        function toggleEdge(zone) {
            const here=panels.filter(p=>p.opened && p.phaseAllowed && !p.floating && p.zone===zone)
            if(here.length) { collapsedEdges[zone]=here.map(p=>p.panelId); here.forEach(p=>p.opened=false) }
            else {
                // hidden by this button and not opened elsewhere since; when none is left, the side's own card
                let back=(collapsedEdges[zone] || []).map(id=>panels.find(p=>p.panelId===id)).filter(p=>p && !p.opened && p.phaseAllowed)
                if(!back.length) back=panels.filter(p=>p.panelId===homeCards[zone] && p.phaseAllowed && shell.hasPanel(p.panelId))
                back.forEach(p=>{ if(p.zone!==zone) { unstack(p.panelId); p.zone=zone; settling=true; settleTimer.restart() } p.opened=true })
                if(back.length===1) selectPanel(back[0].panelId)
            }
            arrangementChanged()
        }
        function unstack(id) {
            const next=Object.assign({},stacks)
            for(const zone of Object.keys(next)) next[zone]=(next[zone] || []).filter(x=>x!==id)
            stacks=next
        }
        // What a side's button says: the cards there now, or the ones it would bring back
        function edgeCards(zone) {
            const r=revision, shown=panels.filter(p=>p.opened && p.phaseAllowed && !p.floating && p.zone===zone)
            if(shown.length) return {shown:true,titles:shown.map(p=>p.title)}
            let back=(collapsedEdges[zone] || []).map(id=>panels.find(p=>p.panelId===id)).filter(p=>p && !p.opened && p.phaseAllowed)
            if(!back.length) back=panels.filter(p=>p.panelId===homeCards[zone] && p.phaseAllowed && shell.hasPanel(p.panelId))
            return {shown:false,titles:back.map(p=>p.title)}
        }
        function restore() {
            if(layoutUndo.running && previousLayout) { layoutUndo.stop(); put(previousLayout); previousLayout=null; shell.layoutRestored(true); return }
            previousLayout=snapshot(); layoutUndo.restart(); cancelDrag()
            if(root.pageWorkspaces) { root.cleanScreen=false; root.shapeLayouts={}; root.shapePins={}; root.pageStates={}
                put(pageState(root.phase, true)); shell.layoutRestored(false); return }
            root.cleanScreen=false; root.shapeLayouts={}; root.shapePins={}; stacks={left:[],right:[],bottom:[]}; weights={}
            settling=true; project.zone="left"; properties.zone="right"; checks.zone="bottom"
            panels.forEach(p => p.opened=shell.hasPanel(p.panelId))
            leftExtent=shell.metrics.leftWidth; rightExtent=shell.metrics.rightWidth; bottomExtent=shell.metrics.checksHeight
            selected={left:"project",right:"properties",bottom:"checks"}; arrangementChanged(); settleTimer.restart()
            shell.layoutRestored(false)
        }
        property var previousLayout: null
        Timer { id: layoutUndo; interval: 15000; onTriggered: workspace.previousLayout=null }
        function floatPanel(id) { const p=panels.find(p => p.panelId===id); p.floatX=p.x; p.floatY=p.y; p.floatWidth=p.width; p.floatHeight=p.height; unstack(id); p.zone="floating"; arrangementChanged() }
        function beginDrag(panel, pos) {
            if(landing) completeLanding()
            settling=false; dragTarget=null; ghostReady=false; panel.frozen=Qt.rect(panel.x,panel.y,panel.width,panel.height)
            // Hit targets stay where they were when picked up; reflow must not retarget the same pointer.
            const areas={}
            for(const card of panels) areas[card.panelId]=Qt.rect(card.x,card.y,card.width,card.height)
            dragAreas=areas
            draggedPanel=panel.panelId; dragStart=pos; dragOrigin=Qt.point(panel.x,panel.y)
            ghost.opacity=0.94
            ghost.x=panel.x; ghost.y=panel.y; ghost.width=panel.width; ghost.height=panel.height; ghost.title=panel.title
            ghostPicture.sourceItem=panel.faceItem; ghostPicture.scheduleUpdate()
            candidate=""; targetZone=""
        }
        // R504, the zones (docs/studio/36-aggancio-schede.md). A band `band` wide along the workspace's left, right
        // and bottom sides: inside it the nearest side wins, whatever the half of the window (Daniel: «nell'ultimo
        // centimetro in basso deve preferire la parte bassa»); a card of that side lying under the point takes the
        // new one beside itself, by the half of the point along the side. Elsewhere, a card under the point takes it
        // in its own column or row, before or after itself by the half of the point; a tab behind it never by
        // default (R317, R527: Daniel, «mi propone di sovrapporre le schede tra di loro anche se non premo la
        // scorciatoia»): only with Alt held, and then the middle third is the tab, the first and last thirds before
        // and after it. Over the centre: nothing, it floats.
        readonly property real band: Theme.space.XXXL
        readonly property real inertia: Theme.space.M
        property var dragAreas: ({})
        function hitRect(panel) { return draggedPanel && dragAreas[panel.panelId] ? dragAreas[panel.panelId] : Qt.rect(panel.x,panel.y,panel.width,panel.height) }
        function panelAt(pos, zone) {
            return panels.find(p => {
                if(p.panelId===draggedPanel || !p.visible || p.floating || (zone && p.zone!==zone)) return false
                const r=hitRect(p)
                return zone==="bottom" ? pos.x>=r.x && pos.x<=r.x+r.width
                    : zone ? pos.y>=r.y && pos.y<=r.y+r.height
                    : pos.x>=r.x && pos.x<=r.x+r.width && pos.y>=r.y && pos.y<=r.y+r.height
            })
        }
        function targetAt(pos) {
            const sides=[[pos.x,"left"],[width-pos.x,"right"],[height-pos.y,"bottom"]].sort((a,b)=>a[0]-b[0])
            if(sides[0][0]<band) {
                const zone=sides[0][1], there=panelAt(pos,zone)
                if(!there) return {zone:zone,anchor:"",where:"after"}
                const r=hitRect(there), share=zone==="bottom" ? (pos.x-r.x)/Math.max(1,r.width) : (pos.y-r.y)/Math.max(1,r.height)
                return {zone:zone,anchor:there.panelId,where:share<0.5 ? "before" : "after"}
            }
            const hit=panelAt(pos,"")
            if(hit) {
                const r=hitRect(hit), share=hit.zone==="bottom" ? (pos.x-r.x)/Math.max(1,r.width) : (pos.y-r.y)/Math.max(1,r.height)
                if(!root.altHeld) return {zone:hit.zone,anchor:hit.panelId,where:share<0.5 ? "before" : "after",card:true}
                return {zone:hit.zone,anchor:hit.panelId,where:share<1/3 ? "before" : share>2/3 ? "after" : "tab",card:true}
            }
            return {zone:"floating",anchor:"",where:"after"}
        }
        function sameTarget(a, b) { return !!a && !!b && a.zone===b.zone && a.anchor===b.anchor && a.where===b.where }
        // Inertia (R317 of the Widgets): the zone the pointer is in holds until the pointer is `inertia` inside the
        // next one, so the answer does not hop at a boundary.
        function settledTarget(pos) {
            const wanted=targetAt(pos), here=pendingTarget
            if(!here || sameTarget(wanted,here) || pos.x<0 || pos.y<0 || pos.x>width || pos.y>height) return wanted
            for(const d of [[inertia,0],[-inertia,0],[0,inertia],[0,-inertia],
                            [inertia,inertia],[inertia,-inertia],[-inertia,inertia],[-inertia,-inertia]]) {
                const probe=Qt.point(Math.max(0,Math.min(width,pos.x+d[0])),Math.max(0,Math.min(height,pos.y+d[1])))
                if(sameTarget(targetAt(probe),here)) return here
            }
            return wanted
        }
        property point dragAt
        function moveDrag(pos) {
            // The carried card is at the pointer at once; the zones answer after the dwell, nothing else is laid out.
            ghost.x=Math.max(0,Math.min(width-Theme.size.PANEL_MIN,dragOrigin.x+pos.x-dragStart.x))
            ghost.y=Math.max(0,Math.min(height-Theme.size.CONTROL,dragOrigin.y+pos.y-dragStart.y))
            dragAt=pos
            aim(settledTarget(pos))
        }
        // Alt down or up with the mouse still: the target where the pointer is, at once (no inertia: the key is
        // a choice, not a boundary crossed by the hand).
        function retarget() { if(draggedPanel) aim(targetAt(dragAt)) }
        function aim(target) {
            const name=target.zone+"|"+target.anchor+"|"+target.where
            if(candidate!==name) {
                candidate=name; pendingTarget=target
                // The outline answers at once; the dwell brings the drop zone and the room made by the others.
                if(target.zone==="floating") hint.hide(); else hint.show(previewRect(target))
                if(Theme.reducedMotion) acceptTarget(); else dwell.restart()
            }
        }
        property var pendingTarget: null
        // Both signals promise the exact projected layout, including the space freed at the origin.
        function previewRect(target) {
            if(target.where==="tab") return sliceRect(target.zone,"*",target)
            return sliceRect(target.zone,draggedPanel,target)
        }
        function titleMenuAt(x,y) { titleMenu.popup(workspace,x,y) }
        function finishDrag() {
            if(!draggedPanel || landing) return
            // Commit the target belonging to the single displayed promise, never a fresh pointer hit.
            const p=panels.find(p => p.panelId===draggedPanel), target=hint.shown ? pendingTarget : dragTarget || pendingTarget
            settling=true; landing=true; p.floatX=ghost.x; p.floatY=ghost.y; p.floatWidth=ghost.width; p.floatHeight=ghost.height
            const next=Object.assign({},stacks)
            for(const zone of Object.keys(next)) next[zone]=(next[zone] || []).filter(id=>id!==p.panelId)
            if(target && target.zone!=="floating") {
                const zone=target.zone
                if(target.where==="tab") {
                    next[zone]=tabLine(next[zone] || [],target.anchor)
                    const chosen=Object.assign({},selected); chosen[zone]=p.panelId; selected=chosen
                }
                else {
                    let line=sliceList(zone).filter(id=>id!==p.panelId)
                    let at=line.length
                    if(target.anchor) { const key=line.includes(target.anchor) ? target.anchor : "*"; const i=line.indexOf(key); if(i>=0) at=target.where==="before" ? i : i+1 }
                    next[zone]=line.slice(0,at).concat([p.panelId]).concat(line.slice(at))
                }
                p.zone=zone
            } else p.zone="floating"
            stacks=next
            // Commit the topology under the carried picture; show the real card only at arrival.
            dragTarget=null; pendingTarget=null; dwell.stop(); hint.hide()
            arrangementChanged()
            landingRect=p.floating ? Qt.rect(p.floatX,p.floatY,p.floatWidth,p.floatHeight) : place(p)
            if(Theme.reducedMotion) completeLanding(); else landingFlight.start()
            settleTimer.restart()
        }
        property bool landing: false
        property rect landingRect
        function completeLanding() {
            if(!landing) return
            landingFlight.stop()
            const p=panels.find(p=>p.panelId===draggedPanel)
            p.frozen=landingRect
            landing=false
            cancelDrag()
        }
        SequentialAnimation {
            id: landingFlight
            ParallelAnimation {
                NumberAnimation { target: ghost; property: "x"; to: workspace.landingRect.x; duration: Theme.motion.CAREFUL; easing.type: Theme.motion.EASE }
                NumberAnimation { target: ghost; property: "y"; to: workspace.landingRect.y; duration: Theme.motion.CAREFUL; easing.type: Theme.motion.EASE }
                NumberAnimation { target: ghost; property: "width"; to: workspace.landingRect.width; duration: Theme.motion.CAREFUL; easing.type: Theme.motion.EASE }
                NumberAnimation { target: ghost; property: "height"; to: workspace.landingRect.height; duration: Theme.motion.CAREFUL; easing.type: Theme.motion.EASE }
                NumberAnimation { target: ghost; property: "opacity"; to: 1; duration: Theme.motion.CAREFUL; easing.type: Theme.motion.EASE }
            }
            ScriptAction { script: workspace.completeLanding() }
        }
        Connections { target: Theme; function onReducedMotionChanged() { if(Theme.reducedMotion) workspace.completeLanding() } }
        function cancelDrag() { if(landing) { completeLanding(); return }; draggedPanel=""; candidate=""; targetZone=""; grouping=false; dragTarget=null; pendingTarget=null; ghostReady=false; dwell.stop(); hint.hide() }
        property bool ghostReady: false
        function acceptTarget() {
            if(!pendingTarget || landing) return
            if(!dragTarget || dragTarget.zone==="floating") dropZone.jumpTo(hint.shown ? Qt.rect(hint.x,hint.y,hint.width,hint.height) : Qt.rect(ghost.x,ghost.y,ghost.width,ghost.height))
            hint.hide()
            settling=true; dragTarget=pendingTarget; targetZone=pendingTarget.zone; grouping=pendingTarget.where==="tab"
        }
        Timer { id: dwell; interval: Theme.motion.DWELL; onTriggered: workspace.acceptTarget() }
        Timer { id: settleTimer; interval: Theme.motion.CAREFUL; onTriggered: workspace.settling=false }
        DockPanel { id: project; objectName: "leftPanel"; panelId: "project"; zone: "left"; title: shell.panelTitle("project"); workspace: root.workspaceItem
            opened: shell.hasPanel("project")
            Loader { anchors.fill: parent; source: shell.panelSource("project") } }
        DockPanel { id: properties; objectName: "rightPanel"; panelId: "properties"; zone: "right"; title: shell.words.properties; workspace: root.workspaceItem
            opened: shell.hasPanel("properties")
            Loader { anchors.fill: parent; source: shell.panelSource("properties") || "PropertiesPanel.qml" } }
        DockPanel { id: checks; objectName: "checksPanel"; panelId: "checks"; zone: "bottom"; title: shell.panelTitle("checks"); workspace: root.workspaceItem
            opened: shell.hasPanel("checks")
            Loader { anchors.fill: parent; source: shell.panelSource("checks") } }
        Repeater { id: hostPanels; onItemAdded: (index, item) => item.phaseAllowed=root.onPage(item.panelId, root.phase); model: controller.panels.filter(p=>!["project","properties","checks"].includes(p.id))
            DockPanel { required property var modelData
                objectName: "panel_"+modelData.id; panelId: modelData.id; title: modelData.title || ""
                zone: modelData.zone || "right"; workspace: root.workspaceItem
                Loader { anchors.fill: parent; source: modelData.source || "" }
            }
        }
        Rectangle {
            id: central; objectName: "centralPanel"
            DockMotion on x { settling: workspace.settling }
            DockMotion on y { settling: workspace.settling }
            DockMotion on width { settling: workspace.settling }
            DockMotion on height { settling: workspace.settling }
            x: workspace.slot("center").x; y: 0; width: workspace.slot("center").width; height: workspace.slot("center").height
            readonly property bool framed: controller.pages.find(page => page.id === root.phase)?.framed !== false
            radius: Theme.radius.CARD; color: framed ? Theme.colors.panel : "transparent"
            border.color: Theme.colors.line; border.width: framed ? Theme.line.HAIR : 0; clip: true
            Repeater { model: controller.pages
                M.PhaseLoader { required property var modelData
                    objectName: "page_"+modelData.id
                    // a page not in view does not follow a drag; the page in view follows it, unless held
                    anchors.fill: shown && !(workspace.resizing && workspace.holdContent) ? parent : undefined
                    anchors.margins: modelData.framed ? Theme.layout.PAD : 0
                    property bool visited: false
                    M.PhaseFade { current: root.phase===modelData.id; leaving: root.leavingPhase===modelData.id }
                    shown: root.phase===modelData.id
                    onShownChanged: if(shown) { visited=true; if(item) item.forceActiveFocus() }
                    onLoaded: if(shown && item) item.forceActiveFocus()
                    wanted: visited || shown
                    source: modelData.source
                }
            }
        }
        Repeater {
            model: ["left","right","bottom"]
            MouseArea {
                required property string modelData
                objectName: modelData+"ResizeHandle"
                visible: workspace.has(modelData)
                property bool vertical: modelData==="bottom"
                x: vertical ? workspace.slot("bottom").x : modelData==="left" ? workspace.slot("left").width : workspace.slot("right").x-Theme.layout.GAP
                y: vertical ? workspace.slot("bottom").y-Theme.layout.GAP : 0
                width: vertical ? workspace.slot("bottom").width : Theme.layout.GAP
                // A side handle ends with its own slot, above any card below it.
                height: vertical ? Theme.layout.GAP : workspace.slot(modelData).height
                cursorShape: vertical ? Qt.SplitVCursor : Qt.SplitHCursor
                hoverEnabled: true
                property point start
                property real extent
                onCanceled: { workspace.resizing=false; workspace.resizeCursor=Qt.ArrowCursor }
                onPressed: mouse => { workspace.settling=false; workspace.resizing=true; workspace.resizeCursor=cursorShape
                    start=mapToItem(workspace,mouse.x,mouse.y)
                    extent=shown() }
                // The size shown, not the one asked: past a limit the extent keeps what the pointer asked, and the next
                // gesture started from there, the border standing still until the pointer made up the difference
                // (21/11/2026, Quotario's Description dragged up past its largest size, then down). At the release the
                // extent becomes the size shown.
                function shown() { const r=workspace.slot(modelData); return modelData==="bottom" ? r.height : r.width }
                function settle() {
                    if(modelData==="left") workspace.leftExtent=shown()
                    else if(modelData==="right") workspace.rightExtent=shown()
                    else workspace.bottomExtent=shown()
                }
                // Daniel 21/11/2026 (Meridiana's borders jerky in every phase): one size for each turn of the events, as a
                // column's edge (DataHeader): the pointer gives several moves in a frame, the page is laid out once
                property point at
                function apply(done) {
                    if(!pressed && !done) return
                    workspace.stepped()
                    if(modelData==="left") workspace.leftExtent=Math.max(Theme.size.PANEL_MIN,extent+at.x-start.x)
                    else if(modelData==="right") workspace.rightExtent=Math.max(root.panelMinimum,extent-at.x+start.x)
                    else workspace.bottomExtent=Math.max(Theme.size.PANEL_MIN,extent-at.y+start.y)
                }
                onPositionChanged: mouse => {
                    if(!pressed) return
                    at=mapToItem(workspace,mouse.x,mouse.y)
                    Qt.callLater(apply)
                }
                onReleased: { apply(true); settle(); workspace.resizing=false; workspace.resizeCursor=Qt.ArrowCursor }
                Rectangle { anchors.centerIn: parent; width: parent.vertical ? parent.width : Theme.line.HAIR
                    height: parent.vertical ? Theme.line.HAIR : parent.height; color: Theme.colors.accent; visible: parent.pressed }
            }
        }
        // Daniel 21/11/2026 (a recording of Quotario: the pointer showed the sign of moving a card, or of a text, while
        // a border was dragged): Qt Quick takes the pointer's sign from the item under it, and at every move the pointer
        // is past the thin handle until the border reaches it a frame later, or past a limit where the border stops. So,
        // for the whole gesture, a cover over the workspace with the resizing sign; it takes no button.
        MouseArea {
            // over the whole window, the bar at the foot too
            objectName: "resizeCursorCover"; parent: Window.contentItem; anchors.fill: parent; z: 1000
            visible: workspace.resizing && workspace.resizeCursor !== Qt.ArrowCursor
            acceptedButtons: Qt.NoButton; cursorShape: workspace.resizeCursor
        }
        M.DropOutline { id: hint; z: 49 }
        // R527: over a card, without Alt, a word on the key that makes it a tab, low in the card, out of the way of
        // the outline's halves' meeting line; gone with Alt held (the whole card outlined says it).
        Rectangle {
            id: tabHint; objectName: "tabHint"; z: 51
            readonly property var target: workspace.pendingTarget
            readonly property var card: target && target.card ? workspace.panels.find(p=>p.panelId===target.anchor) : null
            readonly property bool shown: workspace.draggedPanel!=="" && !!card && !root.altHeld
            property rect place
            onCardChanged: if(card) place=Qt.rect(card.x,card.y,card.width,card.height)
            x: Math.round(place.x+(place.width-width)/2); y: Math.round(place.y+place.height-height-M.ControlMetrics.inset-Theme.layout.PAD)
            width: hintText.implicitWidth+2*Theme.space.S; height: hintText.implicitHeight+2*Theme.space.XXS
            radius: Theme.radius.CONTROL; color: Theme.colors.panel
            border.color: Theme.colors.line; border.width: Theme.line.HAIR
            visible: opacity>0
            opacity: shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.reducedMotion ? 0 : Theme.motion.FAST } }
            M.CopyLabel { id: hintText; anchors.centerIn: parent; text: shell.words.altTabs; textStyle: "secondary"; color: Theme.colors.text2 }
        }
        Item {
            // ui/dock_motion.py Reflow.paintEvent: where the card will fall, dashed, with its name.
            id: dropZone; objectName: "dropZone"; z: 50
            readonly property var target: workspace.dragTarget
            readonly property bool shown: workspace.draggedPanel!=="" && target!==null && target.zone!=="floating" && !hint.shown && !workspace.landing
            // The promise stands at its exact final rectangle; only the surrounding cards animate.
            property rect lastArea
            property bool animated: true
            function jumpTo(r) { animated=false; lastArea=r; animated=true }
            readonly property rect area: {
                if(!shown) return lastArea
                return workspace.previewRect(target)
            }
            onAreaChanged: if(shown) lastArea=area
            visible: shown && opacity>0
            opacity: shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.reducedMotion ? 0 : Theme.motion.FAST } }
            x: area.x; y: area.y; width: area.width; height: area.height
            Shape {
                anchors.fill: parent; preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    // The neutral ground and border shared with the immediate outline: one place says «here».
                    id: dropPath
                    strokeColor: Theme.colors.card_line; strokeWidth: Theme.line.HAIR; strokeStyle: ShapePath.DashLine
                    fillColor: Theme.colors.hover
                    PathRectangle {
                        x: dropPath.strokeWidth/2; y: x
                        width: Math.max(0,dropZone.width-dropPath.strokeWidth)
                        height: Math.max(0,dropZone.height-dropPath.strokeWidth)
                        radius: Math.max(0,Theme.radius.CARD-dropPath.strokeWidth/2)
                    }
                }
            }
            M.CopyLabel { anchors.centerIn: parent; text: ghost.title; color: Theme.colors.text2 }
        }
        Repeater {
            // Between two slices of a zone, the line that shares them out.
            model: { const r=workspace.revision, list=[]; for(const zone of ["left","right","bottom"]) { const line=workspace.sliceList(zone); for(let i=0;i+1<line.length;i++) list.push({zone:zone,first:line[i],second:line[i+1]}) } return list }
            MouseArea {
                required property var modelData
                objectName: "sliceHandle"
                readonly property bool across: modelData.zone==="bottom"
                readonly property rect one: workspace.sliceRect(modelData.zone,modelData.first)
                x: across ? one.x+one.width : one.x; y: across ? one.y : one.y+one.height
                width: across ? Theme.layout.GAP : one.width; height: across ? one.height : Theme.layout.GAP
                cursorShape: across ? Qt.SplitHCursor : Qt.SplitVCursor; hoverEnabled: true; z: 40
                property real start
                property real a
                property real b
                onReleased: { workspace.resizing=false; workspace.resizeCursor=Qt.ArrowCursor }
                onCanceled: { workspace.resizing=false; workspace.resizeCursor=Qt.ArrowCursor }
                onPressed: mouse => { workspace.settling=false; workspace.resizing=true; workspace.resizeCursor=cursorShape; const p=mapToItem(workspace,mouse.x,mouse.y); start=across ? p.x : p.y; a=workspace.weights[modelData.first] || 1; b=workspace.weights[modelData.second] || 1 }
                onPositionChanged: mouse => {
                    if(!pressed) return
                    const p=mapToItem(workspace,mouse.x,mouse.y), whole=workspace.slot(modelData.zone), line=workspace.sliceList(modelData.zone)
                    const room=across ? whole.width : whole.height, sum=line.reduce((n,id)=>n+(workspace.weights[id] || 1),0)
                    const moved=((across ? p.x : p.y)-start)*sum/Math.max(1,room), least=Theme.size.PANEL_MIN*sum/Math.max(1,room)
                    const first=Math.max(least,Math.min(a+b-least,a+moved))
                    const next=Object.assign({},workspace.weights); next[modelData.first]=first; next[modelData.second]=a+b-first; workspace.weights=next
                }
            }
        }
        M.Card { id: ghost; objectName: "cardLift"; property string sourceId: workspace.draggedPanel; titleShown: false
            // The frame changes size; its content picture stays at natural size and is clipped.
            visible: sourceId!==""; opacity: 0.94; clip: true; z: 51; color: Theme.colors.panel; border.color: Theme.colors.line
            ShaderEffectSource { id: ghostPicture; parent: ghost; live: false; recursive: false
                width: sourceItem ? sourceItem.width : 0
                height: sourceItem ? sourceItem.height : 0
                onScheduledUpdateCompleted: workspace.ghostReady=true }
        }
    }
    Item {
        id: filePage
        objectName: "filePage"; visible: root.fileShown
        Keys.onPressed: event => root.altPressed(event)
        Keys.onReleased: event => root.altReleased(event)
        anchors.fill: parent; anchors.leftMargin: Theme.layout.EDGE; anchors.rightMargin: Theme.layout.EDGE
        anchors.topMargin: Theme.layout.GAP; anchors.bottomMargin: 0       // R645, as the cards
        Loader { objectName: "filePartLoader"; anchors.fill: parent; source: root.partSources.file || "FallbackFile.qml" }
    }
    // R536 (Daniel: «le schede che si spostano devono superare le scritte al fondo»): the bar at the foot under the
    // window's content, so a card carried, floating or docked low is drawn over its words, never under them (the
    // window has no background item: below the content there is only its colour).
    footer: RowLayout {
        z: -1
        Keys.onPressed: event => root.altPressed(event)
        Keys.onReleased: event => root.altReleased(event)
        // R645 (Daniel 15/11/2026: «il testo e i simboli fuori scheda vorrei che avessero margine sopra quanto ne hanno
        // sotto»): a control's height and Theme.layout.FOOT above and under it, and no gap over it (the cards end at its
        // top): its signs 8 from the cards and 8 from the window's foot (until R645 19 and 10, until 23/11/2026 10 and 10)
        height: Theme.size.CONTROL+2*Theme.layout.FOOT; spacing: Theme.space.XXS
        // R486: as far from the window's side as the panels above and the bar's right end (Theme.layout.EDGE)
        // R537 (study 38): a save told as Office and Blender do, in this bar: the tick of the checks when done, their
        // stop sign for an error (in red, until its cross); the sentence of a save fades at its end (noticeFading).
        readonly property string noticeKind: shell.noticeKind
        M.Icon { id: statusNoticeIcon; objectName: "statusNoticeIcon"; Layout.leftMargin: Theme.layout.EDGE; Layout.alignment: Qt.AlignVCenter
            visible: parent.noticeKind==="done" || parent.noticeKind.startsWith("error")
            name: parent.noticeKind.startsWith("error") ? "symbol:fail" : "symbol:ok"; dimDisabled: false
            width: Theme.icon.CONTROL-2; height: width; opacity: statusHint.opacity }
        M.CopyLabel { id: statusHint; objectName: "statusHint"; Layout.leftMargin: statusNoticeIcon.visible ? Theme.space.XS : Theme.layout.EDGE; Layout.alignment: Qt.AlignVCenter; text: shell.notice || shell.summary
            textStyle: "secondary"; Layout.fillWidth: true; elide: Text.ElideRight
            color: parent.noticeKind.startsWith("error") ? Theme.colors.danger : Theme.colors[spec.tone]
            opacity: parent.noticeKind==="done" && shell.noticeFading ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Theme.reducedMotion ? 0 : Theme.motion.SLOW; easing.type: Theme.motion.EASE } }
            // a sentence cut by a narrow window, whole under the pointer
            HoverHandler { id: statusHintHover }
            M.ToolTip { visible: statusHintHover.hovered && statusHint.truncated; text: statusHint.text } }
        M.ProgressBar { objectName: "statusSaving"; visible: parent.noticeKind==="busy"; indeterminate: true
            Layout.preferredWidth: 80; Layout.alignment: Qt.AlignVCenter }
        M.Button { objectName: "statusSaveAs"; flat: true; text: shell.words.saveAs; visible: parent.noticeKind==="error"; padding: Theme.space.S
            onClicked: { shell.dismissNotice(); shell.trigger("save_as") } }
        M.Button { objectName: "statusNoticeClose"; flat: true; iconName: "x"; tip: shell.words.close; visible: parent.noticeKind.startsWith("error")
            padding: Theme.space.S; onClicked: shell.dismissNotice() }
        M.Button { objectName: "arrangeUndo"; flat: true; text: shell.words.undo; visible: root.arrangeUndo!==null; padding: Theme.space.S; onClicked: root.undoArrange() }
        // R598 (study 48): the one bar of the heavy jobs, the year among them (backend/work.py adopts its progress)
        WorkBar { id: statusProgress; Layout.alignment: Qt.AlignVCenter }
        // R623 (Daniel 15/11/2026: «togli da qua sotto in basso a destra i vari segnetti di to fix, to check, to know»):
        // no counts of the checks in this bar; they are in the Checks panel (Ctrl+J, Ctrl+Shift+M, the panels' menu)
        // ui/window.py: measure_label: what the selection measures. Where the pointer is went to the plan, by the
        // scale (R484): here its width changed at every step of the pointer and moved the counts and the progress.
        StatusButton { objectName: "statusPanelLeft"; Layout.preferredWidth: Theme.size.CONTROL; visible: workspace.has("left") || workspace.edgeCards("left").titles.length>0; iconName: "panel-left"; tip: shell.sideTip("left",workspace.edgeCards("left")); seen: workspace.has("left"); onClicked: workspace.toggleEdge("left")
            TapHandler { acceptedButtons: Qt.RightButton; onTapped: panelMenu.open() } }
        StatusButton { objectName: "statusPanelBottom"; Layout.preferredWidth: Theme.size.CONTROL; visible: workspace.has("bottom") || workspace.edgeCards("bottom").titles.length>0; iconName: "panel-bottom"; tip: shell.sideTip("bottom",workspace.edgeCards("bottom")); seen: workspace.has("bottom"); onClicked: workspace.toggleEdge("bottom")
            TapHandler { acceptedButtons: Qt.RightButton; onTapped: panelMenu.open() } }
        StatusButton { objectName: "statusPanelRight"; Layout.preferredWidth: Theme.size.CONTROL; visible: workspace.has("right") || workspace.edgeCards("right").titles.length>0; iconName: "panel-right"; tip: shell.sideTip("right",workspace.edgeCards("right")); seen: workspace.has("right"); onClicked: workspace.toggleEdge("right")
            TapHandler { acceptedButtons: Qt.RightButton; onTapped: panelMenu.open() } }
        Item { Layout.preferredWidth: Theme.space.L }
    }
    CloseDialog {}
    RecoveryDialog {}
    CommandDialogs { anchors.fill: parent; controller: root.controller }
    D.DialogLayer { anchors.fill: parent; controller: root.controller }
    M.Menu { id: panelMenu
        Repeater { model: workspace.panels
            M.MenuItem { required property var modelData; text: modelData.title; enabled: modelData.phaseAllowed
                onTriggered: workspace.togglePanel(modelData.panelId) } }
    }
    Connections { target: controller; function onClosed() { root.hide() } }
    Item {
        id: fileVeil; objectName: "fileTransition"; parent: T.Overlay.overlay
        x: 0; y: root.fileMotionTop; width: root.width; height: root.height-y-root.fileMotionBottom
        property bool running: false
        property real direction: 1
        property real t: 0
        readonly property real shown: 1 - Math.pow(1 - t, 3)
        property int waitFrames: 0
        property real lastFrame: 0
        visible: running
        z: Theme.stack.TRANSITION; clip: true
        Rectangle {
            // the window's ground over the new page, fading out: the page fades in
            width: fileVeil.width; height: fileVeil.height
            color: Theme.colors.window
            opacity: 1-fileVeil.shown
        }
        Connections {
            target: fileVeil.visible ? root : null
            function onFrameSwapped() {
                const now = Date.now()
                if (fileVeil.waitFrames > 0) { fileVeil.waitFrames--; fileVeil.lastFrame = now; root.requestUpdate(); return }
                const step = Math.min((now - fileVeil.lastFrame) / Theme.motion.FAST, .12)
                fileVeil.lastFrame = now
                fileVeil.t = Math.min(1, fileVeil.t + Math.max(step, .02))
                if (fileVeil.t >= 1) fileVeil.running = false
            }
        }
    }
}
