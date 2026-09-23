import AgentWorldArt
import AgentWorldKit
import SwiftTerm
import SwiftUI

/// Code mode: tabs of terminals for the selected workspace, the launcher
/// behind "+", and the tips & kit inspector on the right.
struct CodeArea: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            TabStrip(tabs: model.tabs(in: model.selectedFolder))
            HStack(spacing: 0) {
                Group {
                    if model.showsLauncher || model.selectedTab == nil || model.selectedTab?.folder != model.selectedFolder {
                        LauncherView(folder: model.selectedFolder)
                    } else if let tab = model.selectedTab {
                        TabContent(tab: tab)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.showsInspector {
                    Rectangle().fill(Palette.border).frame(width: 1)
                    InspectorView(panel: model.panel, session: model.panelSession, folder: model.selectedFolder)
                        .frame(width: 340)
                        .background(Palette.panel)
                }
            }
        }
    }
}

// MARK: - Tabs

/// The workspace's tabs, drawn as tabs: the selected one opens onto the
/// terminals below it, each has a close button, and they reorder by dragging.
struct TabStrip: View {
    @EnvironmentObject private var model: AppModel
    let tabs: [TerminalTab]
    @State private var dragging: UUID?
    /// Full screen hides the traffic lights: no room to keep for them.
    @State private var fullScreen = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if !model.showsSidebar {
                // Room for the traffic lights, then the way back to the workspaces.
                Spacer().frame(width: fullScreen ? 8 : 74)
                SidebarToggle().frame(height: TabChip.height)
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").foregroundStyle(Palette.claude)
                    Text(model.workspaceName(model.selectedFolder)).foregroundStyle(Palette.cream).lineLimit(1)
                }
                .font(.mono(12, .semibold))
                .frame(height: TabChip.height)
                .padding(.horizontal, 10)
            }
            if !model.folders.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(tabs) { tab in
                            TabChip(tab: tab, dragging: $dragging)
                                .onDrag {
                                    dragging = tab.id
                                    return NSItemProvider(object: tab.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: TabDrop(target: tab.id, dragging: $dragging, model: model))
                        }
                        ChromeButton(symbol: "plus", active: model.showsLauncher, help: "Open another agent or terminal here (⌘T)") {
                            model.showsLauncher = true
                        }
                        .padding(.leading, 4)
                        .padding(.bottom, 4)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(-1)
            }
            WindowDragArea().frame(minWidth: 20, maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 6) {
                if let tab = model.selectedTab, !model.showsLauncher, tab.folder == model.selectedFolder {
                    if tab.sessions.count > 1 { LayoutPicker(tab: tab) }
                    AddPaneMenu(tab: tab)
                    Rectangle().fill(Palette.border).frame(width: 1, height: 16).padding(.horizontal, 4)
                }
                UsageButton()
                RunningSummary().padding(.trailing, 6)
                ChromeButton(symbol: "sidebar.right", active: model.showsInspector, help: "Show or hide agents, skills and tips (⌥⌘I)") {
                    model.showsInspector.toggle()
                }
            }
            .frame(height: TabChip.height)
            .padding(.bottom, 1)
        }
        .padding(.leading, model.showsSidebar ? 10 : 0)
        .padding(.trailing, 10)
        .frame(height: 44, alignment: .bottom)
        .background(alignment: .bottom) {
            // The line the selected tab breaks through.
            Rectangle().fill(Palette.border).frame(height: 1)
        }
        .background(Palette.panel.opacity(0.55))
        .background(Palette.background)
        // A drag let go outside the tabs still ends.
        .onDrop(of: [.text], isTargeted: nil) { _ in
            dragging = nil
            return true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in fullScreen = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { _ in fullScreen = false }
    }
}

/// One tab. Its width stays put so tabs don't jump as statuses change.
struct TabChip: View {
    static let height: CGFloat = 34
    @EnvironmentObject private var model: AppModel
    @ObservedObject var tab: TerminalTab
    @Binding var dragging: UUID?
    @State private var hovering = false
    @State private var hoveringClose = false
    @State private var renaming = false
    @State private var newTitle = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        let selected = model.selectedTabID == tab.id && !model.showsLauncher
        let accent = tab.sessions.first?.provider.swiftColor ?? Palette.claude
        HStack(spacing: 8) {
            if let lead = tab.sessions.first {
                TabFace(session: lead).frame(width: 16, height: 10)
            }
            if renaming {
                TextField("Tab name", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.mono(11.5, .semibold))
                    .foregroundStyle(Palette.cream)
                    .focused($nameFocused)
                    .frame(minWidth: 90)
                    .onSubmit { finishRenaming() }
                    .onExitCommand { renaming = false }
                    .onChange(of: nameFocused) { focused in if !focused { finishRenaming() } }
            } else {
                Text(tab.title)
                    .font(.mono(11.5, selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Palette.cream : hovering ? Palette.text : Palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                ForEach(tab.sessions) { session in TabStatusDot(session: session) }
            }
            Button {
                model.requestClose(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(hoveringClose ? Palette.cream : selected || hovering ? Palette.muted : Palette.faint)
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 4).fill(hoveringClose ? Palette.hover : .clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringClose = $0 }
            .help("Close (⌘W): ends this session")
        }
        .padding(.leading, 12)
        .padding(.trailing, 7)
        .frame(minWidth: 150, maxWidth: 230, minHeight: Self.height, maxHeight: Self.height)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            TabShape(radius: 8)
                .fill(selected ? Palette.panel : hovering ? Palette.raised : .clear)
                // Covers the strip's bottom line so the tab opens onto its content.
                .padding(.bottom, selected ? -1 : 0)
        )
        .overlay(
            TabShape(radius: 8, open: true)
                .stroke(selected ? Palette.border : .clear, lineWidth: 1)
        )
        .overlay(alignment: .top) {
            if selected { Rectangle().fill(accent).frame(height: 2).padding(.horizontal, 8) }
        }
        .opacity(dragging == tab.id ? 0.4 : 1)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            // Back from a drag that ended somewhere nothing noticed.
            if inside, dragging != nil, NSEvent.pressedMouseButtons == 0 { dragging = nil }
        }
        .onTapGesture {
            model.selectedTabID = tab.id
            model.showsLauncher = false
            DispatchQueue.main.async { tab.sessions.first?.focus() }
        }
        .contextMenu {
            Button("Rename Tab…") {
                newTitle = tab.title
                renaming = true
                DispatchQueue.main.async { nameFocused = true }
            }
            if tab.customTitle != nil {
                Button("Use the Automatic Name") { tab.customTitle = nil }
            }
            Divider()
            Button("Close Tab") { model.requestClose(tab) }
            Button("Close Other Tabs") { model.closeTabs(besides: tab) }
            Button("Close Tabs to the Right") { model.closeTabs(besides: tab, onlyAfter: true) }
        }
        .help(tab.sessions.map { "\($0.label): \($0.status.text)" }.joined(separator: "\n"))
    }
}

extension TabChip {
    fileprivate func finishRenaming() {
        guard renaming else { return }
        renaming = false
        let name = newTitle.trimmingCharacters(in: .whitespaces)
        tab.customTitle = name.isEmpty ? nil : name
    }
}

/// A tab's outline: rounded on top, square at the bottom. `open` leaves the
/// bottom edge out, for the border of a tab that joins what's below.
struct TabShape: Shape {
    var radius: CGFloat
    var open = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        if !open { path.closeSubpath() }
        return path
    }
}

/// Moves the dragged tab over the one it's dragged onto, as it happens.
struct TabDrop: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    let model: AppModel

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        withAnimation(.easeOut(duration: 0.15)) { model.moveTab(dragging, to: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

struct TabFace: View {
    @ObservedObject var session: TerminalSession
    var body: some View { FaceView(figure: session.provider.figure, scale: 1.6, busy: session.status.tone == .busy) }
}

struct TabStatusDot: View {
    @ObservedObject var session: TerminalSession
    var body: some View { StatusDot(tone: session.status.tone).help(session.status.text) }
}

// MARK: - Terminals

/// One terminal, or up to six tiled, each with a small title bar.
struct TabContent: View {
    @ObservedObject var tab: TerminalTab

    var body: some View { TileGrid(tab: tab) }
}

struct SessionPane: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: TerminalSession
    let showsHeader: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                HStack(spacing: 8) {
                    FaceView(figure: session.provider.figure, scale: 1.4, busy: session.status.tone == .busy)
                        .frame(width: 14, height: 9)
                    Text(session.label).font(.mono(11, .semibold)).foregroundStyle(session.provider.swiftColor)
                    StatusDot(tone: session.status.tone)
                    Text(session.status.text).font(.mono(10)).foregroundStyle(Palette.faint).lineLimit(1)
                    Spacer()
                    Button { model.requestClose(session) } label: {
                        Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold)).foregroundStyle(Palette.faint)
                    }
                    .buttonStyle(.plain)
                    .help("Close this one")
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Palette.panel)
            }
            ZStack {
                Palette.terminalBackground
                TerminalHost(view: session.terminal)
                    .padding(.leading, 10)
                    .padding(.top, 6)
                if case .exited = session.health {
                    EndedOverlay(session: session)
                }
            }
        }
    }
}

/// Hosts the long-lived terminal view (created once per session).
struct TerminalHost: NSViewRepresentable {
    let view: LocalProcessTerminalView

    func makeNSView(context: Context) -> LocalProcessTerminalView { view }
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}

struct EndedOverlay: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: TerminalSession

    var body: some View {
        VStack(spacing: 10) {
            Text("\(session.label) \(session.status.text)").font(.mono(13, .semibold)).foregroundStyle(Palette.cream)
            HStack(spacing: 10) {
                Button("Close") { model.close(session) }
                Button("Start again") {
                    model.close(session)
                    model.launch(session.profile, in: session.folder)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.raised))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.border))
    }
}
