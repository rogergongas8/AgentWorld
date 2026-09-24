import AgentWorldArt
import AgentWorldKit
import AppKit
import SwiftUI

/// The window: a top bar, the workspaces column, and the terminals.
struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            if model.showsSidebar {
                LeftColumn()
                    .modifier(FolderDrop())
                    .frame(width: 250)
                    .background(Palette.panel)
                    .transition(.move(edge: .leading))
                Rectangle().fill(Palette.border).frame(width: 1)
            }
            CodeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background)
        }
        .background(Palette.background)
        .overlay { overlays }
        .background { Shortcuts() }
        .background { TrafficLightAligner() }
        .ignoresSafeArea(.container, edges: .top)
    }

    @ViewBuilder private var overlays: some View {
        if model.showsNewProject {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { model.showsNewProject = false }
                NewProjectSheet(isPresented: $model.showsNewProject)
            }
            .transition(.opacity)
        }
        if let open = model.openChange {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { model.openChange = nil }
                DiffSheet(open: open)
            }
            .transition(.opacity)
        }
        if let state = model.switcher {
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { model.switcher = nil }
                SwitcherView(state: state)
            }
        }
        if model.showsMap {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { model.showsMap = false }
                GeometryReader { geometry in
                    ProjectMapView()
                        .frame(width: geometry.size.width - 60, height: geometry.size.height - 70)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2 + 10)
                }
            }
            .transition(.opacity)
        }
        if model.showsNotes {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { model.showsNotes = false }
                GeometryReader { geometry in
                    NotesView()
                        .frame(width: geometry.size.width - 60, height: geometry.size.height - 70)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2 + 10)
                }
            }
            .transition(.opacity)
        }
        if model.showsCommit {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { model.showsCommit = false }
                CommitSheet(isPresented: $model.showsCommit)
            }
            .transition(.opacity)
        }
        if model.showsShortcuts {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { model.showsShortcuts = false }
                ShortcutsSheet(isPresented: $model.showsShortcuts)
            }
            .transition(.opacity)
        }
        if model.showsPalette || model.showsKit {
            ZStack(alignment: .top) {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        model.showsPalette = false
                        model.showsKit = false
                    }
                if model.showsPalette {
                    CommandPalette(isPresented: $model.showsPalette).padding(.top, 90)
                } else {
                    KitBrowser(isPresented: $model.showsKit).padding(.top, 60)
                }
            }
            .transition(.opacity)
        }
    }
}

/// Keyboard shortcuts that don't belong in a menu, as invisible buttons.
struct Shortcuts: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            shortcut("k") { model.showsPalette.toggle(); model.showsKit = false }
            shortcut("k", [.command, .shift]) { model.showsKit.toggle(); model.showsPalette = false }
            shortcut("z", [.command, .shift]) {
                guard let tab = model.selectedTab, let session = model.focusedSession ?? tab.sessions.first, tab.sessions.count > 1 else { return }
                tab.zoomedID = tab.zoomedID == session.id ? nil : session.id
                DispatchQueue.main.async { session.focus() }
            }
            shortcut("d") {
                guard let tab = model.selectedTab, !model.showsLauncher else { return }
                let profile = (model.focusedSession ?? tab.sessions.last)?.profile
                if let profile { model.addPane(profile, to: tab) }
            }
            // ⌘1…9: tabs, like a browser. ⌥⌘1…9: panes in this tab.
            ForEach(1..<10) { index in
                shortcut(KeyEquivalent(Character("\(index)"))) { model.selectTab(number: index) }
                shortcut(KeyEquivalent(Character("\(index)")), [.command, .option]) {
                    let sessions = model.selectedTab.map(\.sessions) ?? []
                    if sessions.indices.contains(index - 1) { model.reveal(sessions[index - 1]) }
                }
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    private func shortcut(_ key: KeyEquivalent, _ modifiers: EventModifiers = .command, action: @escaping () -> Void) -> some View {
        Button("", action: action).keyboardShortcut(key, modifiers: modifiers)
    }
}

/// Shows or hides the workspaces column (⌃⌘S).
struct SidebarToggle: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ChromeButton(symbol: "sidebar.left", active: model.showsSidebar, help: "Show or hide workspaces (⌃⌘S)") {
            withAnimation(.easeOut(duration: 0.18)) { model.showsSidebar.toggle() }
        }
    }
}

/// A plain icon button for the window chrome, with a hover state.
struct ChromeButton: View {
    let symbol: String
    var active = false
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(active || hovering ? Palette.cream : Palette.muted)
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Palette.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Empty chrome that moves the window, and zooms it on a double-click, the
/// way a title bar does.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct RunningSummary: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let sessions = model.allSessions
        let busy = sessions.filter { $0.status.tone == .busy }.count
        let waiting = sessions.filter { $0.status.tone == .needsYou }.count
        HStack(spacing: 10) {
            if busy > 0 { Label("\(busy) working", systemImage: "circle.fill").foregroundStyle(Palette.live) }
            if waiting > 0 { Label("\(waiting) need you", systemImage: "circle.lefthalf.filled").foregroundStyle(Palette.warning) }
            if busy == 0, waiting == 0 {
                Text(sessions.isEmpty ? "nothing running" : "\(sessions.count) open").foregroundStyle(Palette.faint)
            }
        }
        .labelStyle(.titleAndIcon)
        .font(.mono(11))
        .imageScale(.small)
        .lineLimit(1)
        // A fixed slot: "1 open" → "1 working" → "1 need you" would otherwise
        // shove every title-bar control beside it each time a status changes.
        .frame(width: 180, alignment: .trailing)
    }
}
