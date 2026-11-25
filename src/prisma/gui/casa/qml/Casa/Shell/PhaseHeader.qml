import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Casa.Theme
import Casa.Controls as M

Item {
    id: header
    property string phase: "model"
    property string leavingPhase: ""
    property bool fileOpen: false
    property bool dirty: false          // R537: something to save, the dot on File (VS Code's on a tab, study 38)
    property string selectedTool: "select"
    property string barMode: "under"
    property bool barVisible: !fileOpen
    property var phases: shell.phases
    property int currentIndex: Math.max(0, phases.findIndex(p => p.id === phase))
    property var metrics: shell.metrics
    // The corner controls have a 4 px bottom margin in Widgets: their row is
    // 34 px, with the 32 px tab bar aligned to its bottom.
    property real rowHeight: metrics.tabHeight + Theme.space.XXS
    property real fileWidth: fileButton.width + Theme.space.L
    property real tailWidth: Theme.space.XL
    property var stalePhases: shell.stalePhases
    property url trailingSource: ""
    property bool trailingCanMove: true
    // R375: the button of «3D object», which the picker hangs from (Workbench.openObjects)
    property Item objectTool: null
    readonly property bool trailingShown: trailing.visible
    function phaseTitle(p) { return p.title+(stalePhases.includes(p.id) ? " ·" : "") }
    // R502: the same margin before the disc, after the name and above the disc (the disc is centred in the tab:
    // (tabHeight - badge) / 2 is that margin), ControlMetrics.inset; the width is the name's in the open tab's weight,
    // so that a tab keeps its width when it opens. R555 (2) (Daniel 08/11/2026: «lo spazio tra la scritta e il cerchio
    // col numero uguale ai margini esterni della linguetta»): the disc and the name's ink are as far apart as the
    // outline and the disc, pad less the outline's hair line; the name's own room before its first letter (the font's
    // side bearing, read by nameMetrics) is taken off the gap, so the ink and not the letter's box keeps the margin.
    readonly property real pad: M.ControlMetrics.inset
    FontMetrics { id: nameMetrics; font.family: Theme.fontFamily; font.pixelSize: Theme.text.strong.size; font.weight: Theme.text.strong.weight }
    function nameGap(p) { const revision = Theme.revision
        return Math.max(0, pad - Theme.line.HAIR - Math.max(0, nameMetrics.tightBoundingRect(phaseTitle(p)).x)) }
    // A page without a number (Page.numbered false) has no disc: its tab is its name between the two margins
    property var widths: phases.map(p => 2*pad + (p.number !== "" ? metrics.badge + nameGap(p) : 0) + Math.ceil(Theme.measureText(phaseTitle(p), "strong", false).width))
    property bool compact: width < fileWidth + widths.reduce((a,b) => a+b, 0) + tailWidth
    readonly property real dotWidth: Math.ceil(Theme.measureText("·", "control", false).width)
    function tabWidth(i) { return compact && i !== currentIndex ? (phases[i].number !== "" ? metrics.badge : dotWidth) + 2*pad+(stalePhases.includes(phases[i].id) ? Theme.space.M+dotWidth : 0) : widths[i] }
    // services['page_tabs'] 'several': with one page the row shows File alone and the bar is a plain card
    readonly property bool tabsShown: shell.pageTabs
    // A page off (Page.enabled false) does not open: the wheel passes over it
    function usable(i) { return phases[i].enabled !== false }
    // The reason of a command that is off, under its tooltip (R564: the same words beside it in the menus)
    function withNote(tip, command) { const note=shell.commandNote[command] || ""; return note ? (tip ? tip+"\n"+note : note) : tip }
    function tabX(i) { let x=fileWidth; for(let j=0;j<i;j++) x+=tabWidth(j); return x }
    // The tool in hand a command stands for, "" for a command run once (docs/design/sistema-grafico.md §4: only a mode
    // goes on a split button's face)
    function toolOf(command) { return command.startsWith("tool_") ? command.slice(5) : command==="strings_manual" ? "string" : "" }
    function toolMatches(command) { const tool=toolOf(command); return tool!=="" && tool===selectedTool }
    // R614 (Daniel 14/11/2026: «Measure» twice as wide as «Square», with air between the word and the arrow): the words
    // that can stand on the face, the button's own and the modes of its menu; a command run once, as «Remove all
    // measurements», and what a fixed button holds stay in the menu and never widen the button. They are measured in the
    // condensed face the button writes them in, as the plain buttons' (the split ones were measured in the wider one).
    function faceWords(tool) { return [tool].concat(tool.fixed ? [] : tool.more.filter(t=>toolOf(t.command)!=="")).map(t=>t.label) }
    function commandWidth(tool, mode=barMode) {
        if(mode==="icons") return Theme.bar.ICON_WIDTH
        if(mode==="small") return smallSize
        const word=Math.max(...faceWords(tool).map(w=>Math.round(Theme.measureText(w,"secondary",true).width)))
        const need=word+Theme.bar.PAD+(mode==="beside" ? Theme.bar.ICON.beside+Theme.bar.WORD_GAP : 0)
        return Math.max(mode==="under" ? Theme.bar.WORD_MIN : 0,Math.ceil(need/Theme.bar.STEP[mode])*Theme.bar.STEP[mode])
    }
    readonly property var layoutNeeds: {
        const result={}
        for(const mode of ["under","beside","icons","small"]) {
            result[mode]={}
            for(const phase of phases) {
                let width=2*Theme.space.XS+Math.max(0,phase.groups.length-1)*(Theme.line.HAIR+2*Theme.bar.GROUP_AIR)
                for(const group of phase.groups) {
                    const row=mode==="small" ? smallRow(group.tools)
                        : group.tools.reduce((sum,t)=>sum+commandWidth(t,mode)+(t.more.length ? Theme.bar.STRIP : 0),0)+Math.max(0,group.tools.length-1)*Theme.bar.GAP
                    width+=mode==="beside" ? row : Math.max(row,Theme.measureText(group.title,"group",true).width)
                }
                result[mode][phase.id]=width
            }
        }
        return result
    }
    // G5 (Daniel 21/11/2026, docs/28-barra-piccola.md): the small form, the commands of a group in columns of two from the
    // top, each column as wide as its widest button; when the groups do not fit the last ones go into «More»
    // (PhaseMore), from the right
    function smallRow(tools) {
        if(tools.length===1) return commandWidth(tools[0],"icons")+(tools[0].more.length ? Theme.bar.STRIP : 0)
        let width=0
        for(let at=0; at<tools.length; at+=2) {
            const column=tools.slice(at,at+2).map(t=>commandWidth(t,"small")+(t.more.length ? Theme.bar.STRIP : 0))
            width+=Math.max(...column)+(at>0 ? Theme.bar.GAP : 0)
        }
        return width
    }
    function smallGroup(group) { return Math.max(smallRow(group.tools),Theme.measureText(group.title,"group",true).width) }
    readonly property real moreWidth: Math.ceil(Math.max(Theme.bar.WORD_MIN,Theme.measureText(shell.words.more || "","secondary",true).width+Theme.bar.PAD)
                                                /Theme.bar.STEP.under)*Theme.bar.STEP.under
    // how many groups of the open page stand on the bar of small buttons; the others are in «More»
    readonly property int smallShown: {
        const groups=phases.length ? phases[currentIndex].groups : []
        if(barMode!=="small") return groups.length
        const room=toolbar.width, sep=Theme.line.HAIR+2*Theme.bar.GROUP_AIR
        let used=0
        for(let i=0;i<groups.length;i++) {
            const next=used+(i>0 ? sep : 0)+smallGroup(groups[i])
            const tail=i<groups.length-1 ? sep+moreWidth : 0
            if(next+tail>room && i>0) return i
            used=next
        }
        return groups.length
    }
    signal phaseChosen(string phase)
    signal fileRequested()
    // R23 F6 (docs/studio/39): the dot of a stale computation or layout on Plant's compute and on Layout (R564: «Fill» is in
    // its menu), made as a child of the tool's button when the Plant part is there
    function staleMark(button, command) {}
    // the commands of a group: one row of buttons, or two rows of small ones. The two rows stand in the height of the
    // word under the icon (Daniel 22/11/2026: the bar does not grow when it becomes small, and the forms of one row do
    // not grow either): the small square is half of it, never under Theme.bar.ICON.under (24, WCAG 2.2, 2.5.8)
    readonly property real wordHeight: Theme.bar.ICON.under + Math.round(Theme.measureText("Ag", "strong", true).height) + 2*Theme.space.XS + Theme.space.XXS
    readonly property real smallSize: Math.max(Theme.bar.ICON.under, Math.floor((wordHeight - Theme.bar.GAP)/2))
    readonly property real toolsHeight: barMode === "under" ? wordHeight
        : barMode === "small" ? Math.max(wordHeight, 2*smallSize + Theme.bar.GAP) : Theme.bar.HEIGHT
    property real buttonHeight: barMode === "small" ? smallSize : toolsHeight
    // a group of one command in the small form: its button as in the icons alone, the height of the two rows (Daniel
    // 22/11/2026); two or more: columns of two from the top
    function lone(group) { return barMode === "small" && group.tools.length === 1 }
    property real groupHeight: toolsHeight + (barMode === "beside" ? 0 : Theme.space.XS + Math.round(Theme.measureText("Ag", "group", true).height))
    // R502: the bar's tools start ControlMetrics.inset from the card's left side and top, as the summary ends from its
    // right side; the tools' row is groupHeight + 1 tall, with the card's bottom padding under the groups' titles.
    implicitHeight: rowHeight + (barVisible ? pad + groupHeight + 1 + metrics.cardPad[3] : 0)

    Rectangle {
        visible: !header.fileOpen && !header.barVisible && header.tabsShown
        x: header.tabX(header.currentIndex)+0.5; y: header.rowHeight-header.metrics.tabHeight+0.5
        width: header.tabWidth(header.currentIndex)-1; height: header.metrics.tabHeight-1
        radius: Theme.radius.CARD; color: Theme.colors.panel; border.color: Theme.colors.card_line
    }

    Shape {
        id: outline
        objectName: "phaseOutline"
        preferredRendererType: Shape.CurveRenderer
        antialiasing: true
        visible: header.barVisible && header.tabsShown
        anchors.fill: parent
        property real tx: header.tabX(header.currentIndex)
        property real tw: header.tabWidth(header.currentIndex)
        property real tabTop: header.rowHeight-header.metrics.tabHeight+0.5
        property real r: Theme.radius.CARD
        property real h: header.rowHeight + 0.5
        // the outline slides to the new tab only when the change of phase is animated (Theme.phaseMotion)
        Behavior on tx { NumberAnimation { duration: Theme.phaseMotion ? Theme.motion.FAST : 0; easing.type: Theme.motion.EASE } }
        Behavior on tw { NumberAnimation { duration: Theme.phaseMotion ? Theme.motion.FAST : 0; easing.type: Theme.motion.EASE } }
        ShapePath {
            fillColor: Theme.colors.panel
            strokeColor: Theme.colors.card_line
            strokeWidth: Theme.line.HAIR
            startX: outline.r+0.5; startY: outline.h
            PathLine { x: outline.tx+0.5-outline.r; y: outline.h }
            PathArc { x: outline.tx+0.5; y: outline.h-outline.r; radiusX: outline.r; radiusY: outline.r; direction: PathArc.Counterclockwise }
            PathLine { x: outline.tx+0.5; y: outline.tabTop+outline.r }
            PathArc { x: outline.tx+0.5+outline.r; y: outline.tabTop; radiusX: outline.r; radiusY: outline.r }
            PathLine { x: outline.tx+outline.tw-0.5-outline.r; y: outline.tabTop }
            PathArc { x: outline.tx+outline.tw-0.5; y: outline.tabTop+outline.r; radiusX: outline.r; radiusY: outline.r }
            PathLine { x: outline.tx+outline.tw-0.5; y: outline.h-outline.r }
            PathArc { x: outline.tx+outline.tw-0.5+outline.r; y: outline.h; radiusX: outline.r; radiusY: outline.r; direction: PathArc.Counterclockwise }
            PathLine { x: header.width-0.5-outline.r; y: outline.h }
            PathArc { x: header.width-0.5; y: outline.h+outline.r; radiusX: outline.r; radiusY: outline.r }
            PathLine { x: header.width-0.5; y: header.height-0.5-outline.r }
            PathArc { x: header.width-0.5-outline.r; y: header.height-0.5; radiusX: outline.r; radiusY: outline.r }
            PathLine { x: outline.r+0.5; y: header.height-0.5 }
            PathArc { x: 0.5; y: header.height-0.5-outline.r; radiusX: outline.r; radiusY: outline.r }
            PathLine { x: 0.5; y: outline.h+outline.r }
            PathArc { x: outline.r+0.5; y: outline.h; radiusX: outline.r; radiusY: outline.r }
        }
    }
    // Without the row of the tabs: the same card, the outline's colours and corners, without the open tab
    Rectangle {
        objectName: "phaseCard"
        visible: header.barVisible && !header.tabsShown
        x: 0.5; y: header.rowHeight + 0.5; width: header.width - 1; height: header.height - header.rowHeight - 1
        radius: Theme.radius.CARD; color: Theme.colors.panel; border.color: Theme.colors.card_line; border.width: Theme.line.HAIR
    }
    // R555 (3) (Daniel 08/11/2026: «File: hover e riempimento premuto con le stesse dimensioni degli hover delle linguette
    // delle fasi»): its hover and its press are a tab's: the same top and height (tabHeight less Theme.space.XXS above and
    // below) and the same margin from their sides to what is inside (inset less Theme.space.XXS, as a tab's hover round
    // its disc and its name).
    M.Button {
        id: fileButton
        objectName: "fileButton"
        readonly property real margin: header.pad - Theme.space.XXS
        x: 0; y: header.rowHeight - header.metrics.tabHeight + Theme.space.XXS
        width: Math.ceil(fileFace.implicitWidth) + 2 * margin; height: header.metrics.tabHeight - 2 * Theme.space.XXS
        padding: 0; leftPadding: margin; rightPadding: margin
        checked: header.fileOpen
        text: shell.words.file; iconName: "folder-open"; flat: true; onClicked: header.fileRequested()
        tip: header.dirty ? shell.words.unsaved : ""
        contentItem: Item { Row { id: fileFace; anchors.centerIn: parent; spacing: Theme.space.XS
            M.Icon { id: fileIcon; iconName: "folder-open"; width: Theme.icon.CONTROL-1; height: width; anchors.verticalCenter: parent.verticalCenter
                // R537: the dot of «modified», in the accent, lit by a change, off once saved; R555 (3): on the
                // folder's corner, so that the button's margins stay the same with it and without it
                Rectangle { objectName: "fileDirtyDot"; visible: header.dirty; width: 6; height: 6; radius: 3
                    color: Theme.colors.accent; x: parent.width - width / 2 - 1; y: -1
                    border.width: Theme.line.HAIR; border.color: Theme.colors.window }
            }
            M.Label { text: shell.words.file; textStyle: "strong"; anchors.verticalCenter: parent.verticalCenter }
        } }
    }
    // R705 (Daniel 17/11/2026: «come nel widget, scorrere tra le fasi con la rotella del mouse quando ho il puntatore
    // sulle linguette»): as a QTabBar, the wheel up goes to the phase before, down to the one after, with no wrap at the
    // ends; a high-resolution wheel's small steps add up to a notch (120). The mouse's wheel only: two fingers on a
    // touchpad (events in scroll phases, also Windows' touchpad as WindowsTouchpad hands it on) brushing the tabs would
    // change phase by mistake, and Wayland's touchpad steps are multiplied by 2,5 (TouchpadPace)
    readonly property real tabsEnd: phases.length ? tabX(phases.length - 1) + tabWidth(phases.length - 1) : 0
    property real wheelCarry: 0
    function wheelPhases(event) {
        if (event.phase !== Qt.NoScrollPhase) return
        wheelCarry += event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
        const steps = wheelCarry > 0 ? Math.floor(wheelCarry / 120) : Math.ceil(wheelCarry / 120)
        if (steps === 0) return
        wheelCarry -= steps * 120
        let to = currentIndex
        for (let left = Math.abs(steps), i = currentIndex; left > 0; ) {
            i -= Math.sign(steps)
            if (i < 0 || i >= phases.length) break
            if (usable(i)) { to = i; left-- }
        }
        if (to !== currentIndex || fileOpen) phaseChosen(phases[to].id)
    }
    Item {
        objectName: "phaseTabsWheel"
        enabled: header.tabsShown
        x: header.fileWidth; width: Math.max(0, header.tabsEnd - header.fileWidth); height: header.rowHeight
        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse
            onWheel: function(event) { header.wheelPhases(event) }
        }
    }
    Repeater {
        model: header.phases
        delegate: Item {
            id: phaseTab
            required property var modelData
            required property int index
            readonly property bool selected: header.currentIndex === index && !header.fileOpen
            readonly property bool usable: modelData.enabled !== false
            visible: header.tabsShown
            // R555 (11): its corners for Meridio's highlight (AssistantLayer.radiiOf): open, the outline's at the top
            // (its hair line is half a line inside) and none at the bottom, where it goes on into the bar; closed, its
            // hover's, Theme.space.XXS inside
            readonly property var highlightRadii: selected ? [outline.r + Theme.line.HAIR / 2, outline.r + Theme.line.HAIR / 2, 0, 0]
                                                           : Array(4).fill(Theme.radius.CONTROL + Theme.space.XXS)
            objectName: modelData.id + "Tab"
            x: header.tabX(index); y: header.rowHeight-height; width: header.tabWidth(index); height: header.metrics.tabHeight
            Rectangle {
                // R502: the hover hugs the disc and the name as the open tab does, in the weight shown (a closed tab's
                // name is lighter, so narrower than the width kept for it). R519 (Daniel 07/11/2026: «quando si
                // trovano a sinistra della linguetta selezionata sembra che lascino un po' di spazio in più»): the disc
                // and the name stand on the side of the open tab, the room the lighter name leaves on the far side, so
                // the hover is Theme.space.XXS from the open tab whether it is at its left or at its right.
                objectName: modelData.id + "TabHover"
                x: content.x - header.pad + Theme.space.XXS; y: Theme.space.XXS; height: parent.height - 2*Theme.space.XXS
                width: Math.min(parent.width, content.width + 2*header.pad) - 2*Theme.space.XXS
                radius: Theme.radius.CONTROL
                color: tabMouse.pressed ? Theme.colors.press : tabMouse.containsMouse ? Theme.colors.hover : "transparent"
                visible: (header.fileOpen || header.currentIndex !== phaseTab.index) && phaseTab.usable
            }
            Row {
                id: content
                x: !header.fileOpen && phaseTab.index < header.currentIndex ? Math.max(header.pad, parent.width - width - header.pad) : header.pad
                Behavior on x { NumberAnimation { duration: Theme.phaseMotion ? Theme.motion.FAST : 0; easing.type: Theme.motion.EASE } }
                anchors.verticalCenter: parent.verticalCenter; spacing: header.nameGap(phaseTab.modelData)
                Rectangle {
                    visible: phaseTab.modelData.number !== ""
                    width: header.metrics.badge; height: width; radius: width/2; anchors.verticalCenter: parent.verticalCenter
                    color: header.currentIndex === phaseTab.index && !header.fileOpen ? Theme.colors.accent : Theme.colors.line_soft
                    Shape { anchors.fill: parent; preferredRendererType: Shape.CurveRenderer; antialiasing: true
                        ShapePath { strokeWidth: -1
                            fillColor: header.currentIndex === phaseTab.index && !header.fileOpen ? Theme.colors.accent_fg : Theme.colors.muted
                            PathSvg { path: shell.glyphPath(Theme.fontFamily,Theme.text.label.size,Theme.text.label.weight,phaseTab.modelData.number,header.metrics.badge) }
                        }
                    }
                }
                M.Label { text: header.compact && header.currentIndex!==phaseTab.index ? "·" : header.phaseTitle(phaseTab.modelData); anchors.verticalCenter: parent.verticalCenter
                    textStyle: header.currentIndex === phaseTab.index && !header.fileOpen ? "strong" : "control"
                    color: !phaseTab.usable ? Theme.disabledText : header.currentIndex === phaseTab.index && !header.fileOpen || tabMouse.containsMouse ? Theme.colors.text : Theme.colors.text2
                    visible: !header.compact || header.currentIndex === phaseTab.index || header.stalePhases.includes(phaseTab.modelData.id) || phaseTab.modelData.number === "" }
            }
            MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true
                onClicked: if (phaseTab.usable) header.phaseChosen(phaseTab.modelData.id) }
            // A page off says why in its tooltip (Page.reason)
            readonly property string reason: usable ? "" : modelData.reason || ""
            M.ToolTip { pressed: tabMouse.pressed; visible: tabMouse.containsMouse && (header.compact || header.stalePhases.includes(phaseTab.modelData.id) || phaseTab.reason !== "")
                text: [header.compact ? phaseTab.modelData.title : "", header.stalePhases.includes(phaseTab.modelData.id) ? shell.staleTip : "", phaseTab.reason].filter(t => t !== "").join("\n") }
            Accessible.role: Accessible.PageTab
            Accessible.name: modelData.title
            Accessible.description: reason
            Accessible.selected: selected
        }
    }
    Loader {
        id: trailing
        objectName: "phaseTrailing"
        // Keep the summary and its controls when another phase has no trailing part.
        property url cachedSource: ""
        source: cachedSource
        function remember() { if (header.trailingSource.toString() !== "") cachedSource = header.trailingSource }
        Component.onCompleted: remember()
        Connections { target: header; function onTrailingSourceChanged() { trailing.remember() } }
        asynchronous: GraphicsInfo.api !== GraphicsInfo.Software
        // The room the tools leave, up to a measure; under 300 px, or under what the part asks (its `need`, R553: the
        // shadows of Production side by side), it goes above the plan (Workbench). Made while the bar is shown, so
        // that its need is known; seen only when it fits, or always where there are no views to stand above
        // (Production): there the part makes do with the room.
        readonly property real room: toolbar.parent.width - 2 * toolbar.x - groups.width - Theme.space.XL
        readonly property real need: item && item.need !== undefined ? item.need : 0
        readonly property bool fits: room >= Math.max(300 * Theme.type.BODY / 13, need) || (!header.trailingCanMove && room > 0)
        visible: header.barVisible && header.trailingSource.toString() !== "" && fits && status === Loader.Ready
        x: parent.width - width - header.pad; y: toolbar.y
        width: Math.min(720 * Theme.type.BODY / 13, room); height: toolbar.height - Theme.space.XXS
    }
    Flickable {
        id: toolbar
        objectName: "phaseToolbar"
        visible: header.barVisible
        x: header.pad; y: header.rowHeight + header.pad
        width: parent.width-2*x-(trailing.visible ? trailing.width+Theme.space.L : 0); height: parent.height-y-header.metrics.cardPad[3]
        contentWidth: groups.width; contentHeight: height; clip: true
        boundsBehavior: Flickable.StopAtBounds
        Item {
            id: groups
            width: { const row=phaseRows.itemAt(header.currentIndex); return row ? row.implicitWidth : 0 }
            height: toolbar.height
            // One row of groups for each phase, built once and shown for its phase (06/11/2026): a change of phase
            // used to build the bar again, 35-42 items each time.
            Repeater {
                id: phaseRows
                model: header.phases
                delegate: Row {
                    id: phaseGroups
                    required property var modelData
                    required property int index
                    readonly property var phaseGroupsList: modelData.groups
                    readonly property string phaseId: modelData.id
                    M.PhaseFade { current: phaseGroups.index === header.currentIndex; leaving: phaseGroups.modelData.id === header.leavingPhase }
                    spacing: Theme.bar.GROUP_AIR
            Repeater {
                model: phaseGroups.phaseGroupsList
                delegate: Row {
                    id: groupRow
                    required property var modelData
                    required property int index
                    readonly property bool lone: header.lone(modelData)
                    visible: header.barMode !== "small" || phaseGroups.index !== header.currentIndex || index < header.smallShown
                    spacing: Theme.bar.GROUP_AIR
                    Column {
                        spacing: Theme.space.XS
                        // G5: one row, or columns of two small buttons from the top
                        Grid {
                            flow: Grid.TopToBottom; rows: header.barMode === "small" ? 2 : 1
                            height: header.toolsHeight
                            rowSpacing: Theme.bar.GAP; columnSpacing: Theme.bar.GAP
                            Repeater {
                                model: modelData.tools
                                delegate: Loader {
                                    id: toolLoader
                                    required property var modelData
                                    property var family: [modelData].concat(modelData.more)
                                    property var face: !modelData.fixed ? (family.find(t=>header.toolMatches(t.command)) || modelData) : modelData
                                    sourceComponent: modelData.more.length ? splitTool : plainTool
                                    // A button that is off takes no hover: its Loader shows the reason (Command.reason)
                                    HoverHandler { id: offHover; enabled: !!toolLoader.item && !toolLoader.item.mainOn }
                                    M.ToolTip { objectName: "offTip_" + toolLoader.modelData.command
                                        text: header.withNote(toolLoader.modelData.more.length ? toolLoader.face.faceTip : toolLoader.face.tip, toolLoader.face.command)
                                        visible: offHover.hovered && !!toolLoader.item && !toolLoader.item.mainOn && !!shell.commandNote[toolLoader.face.command]
                                            && (!toolLoader.modelData.more.length || offHover.point.position.x < toolLoader.width - Theme.bar.STRIP) }
                                    Component {
                                        id: plainTool
                                        PhaseToolButton {
                                            objectName: "tool_" + toolLoader.modelData.command
                                            readonly property bool mainOn: enabled
                                            primary: toolLoader.modelData.primary
                                            text: toolLoader.face.label; iconName: shell.commandIcon[toolLoader.face.command] || toolLoader.face.icon
                                            faceTip: toolLoader.face.tip; mode: groupRow.lone ? "icons" : header.barMode
                                            busyTip: typeof work !== "undefined" && work !== null ? work.busyCommands[toolLoader.modelData.command] || "" : ""
                                            height: groupRow.lone ? header.toolsHeight : header.buttonHeight
                                            width: header.commandWidth(toolLoader.modelData, groupRow.lone ? "icons" : header.barMode)
                                            enabled: !busy && toolLoader.modelData.enabled && shell.commandEnabled[toolLoader.modelData.command]!==false
                                            active: header.toolMatches(toolLoader.modelData.command) || (toolLoader.modelData.command==="tool_building" && header.selectedTool==="rectangle")
                                                || shell.commandChecked[toolLoader.modelData.command]===true
                                            Accessible.checkable: shell.commandChecked[toolLoader.modelData.command]!==undefined
                                            Accessible.checked: shell.commandChecked[toolLoader.modelData.command]===true
                                            onClicked: shell.trigger(toolLoader.modelData.command)
                                            // R23 F6: Plant's stale mark (header.staleMark) made here, not from Python
                                            Component.onCompleted: { if (toolLoader.modelData.command === "object_3d") header.objectTool = this; header.staleMark(this, toolLoader.modelData.command) }
                                        }
                                    }
                                    Component {
                                        id: splitTool
                                        PhaseSplitButton {
                                            objectName: "tool_" + toolLoader.modelData.command
                                            readonly property bool mainOn: mainEnabled
                                            text: toolLoader.face.label; iconName: shell.commandIcon[toolLoader.face.command] || toolLoader.face.icon
                                            tip: toolLoader.face.faceTip; stripTip: toolLoader.modelData.stripTip; mode: groupRow.lone ? "icons" : header.barMode
                                            height: groupRow.lone ? header.toolsHeight : header.buttonHeight
                                            width: header.commandWidth(toolLoader.modelData, groupRow.lone ? "icons" : header.barMode)+Theme.bar.STRIP
                                            enabled: toolLoader.modelData.enabled || toolLoader.modelData.more.some(t => t.enabled)
                                            mainEnabled: toolLoader.face.enabled && shell.commandEnabled[toolLoader.face.command]!==false
                                            active: header.toolMatches(toolLoader.face.command) || shell.commandChecked[toolLoader.face.command]===true
                                            stripActive: toolLoader.family.some(t=>t.command!==toolLoader.face.command && (header.toolMatches(t.command) || shell.commandChecked[t.command]===true))
                                            model: toolLoader.family
                                            onClicked: shell.trigger(toolLoader.face.command)
                                            onChosen: index => shell.trigger(toolLoader.family[index].command)
                                            Component.onCompleted: header.staleMark(this, toolLoader.modelData.command)
                                        }
                                    }
                                }
                            }
                        }
                        M.Label { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.title
                            textStyle: "group"; condensed: true; visible: header.barMode !== "beside" }
                    }
                    Rectangle { visible: index < phaseGroups.phaseGroupsList.length-1
                        width: Theme.line.HAIR; height: header.toolsHeight; color: Theme.colors.line_soft }
                }
            }
                    PhaseMore {
                        visible: header.barMode === "small" && phaseGroups.index === header.currentIndex
                                 && header.smallShown < phaseGroups.phaseGroupsList.length
                        width: header.moreWidth; height: header.toolsHeight
                        label: shell.words.more || ""
                        groups: visible ? phaseGroups.phaseGroupsList.slice(header.smallShown) : []
                    }
                }
            }
        }
    }
}
