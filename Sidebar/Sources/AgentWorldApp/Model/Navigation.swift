import AppKit
import SwiftUI

/// Getting around without the mouse: tabs, panes and workspaces in order,
/// wrapping at the ends. The menus (and ⌘/) list the keys.
extension AppModel {
    func selectTab(offset: Int) {
        let open = tabs(in: selectedFolder)
        guard !open.isEmpty else { return }
        let current = showsLauncher ? nil : open.firstIndex { $0.id == selectedTabID }
        let next = current.map { ($0 + offset + open.count) % open.count } ?? (offset > 0 ? 0 : open.count - 1)
        selectedTabID = open[next].id
        showsLauncher = false
        panel.isFocused = false
        if let session = open[next].sessions.first { DispatchQueue.main.async { session.focus() } }
    }

    /// Drags `id` to where `target` is, among the tabs of the same folder.
    func moveTab(_ id: UUID, to target: UUID) {
        guard id != target, let from = tabs.firstIndex(where: { $0.id == id }),
              let to = tabs.firstIndex(where: { $0.id == target }), tabs[from].folder == tabs[to].folder else { return }
        tabs.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    /// Closes `tab` from the UI: first asks, if an agent in it is still
    /// working and Settings says to.
    func requestClose(_ tab: TerminalTab) {
        guard confirmsClosing(tab.sessions) else { return }
        close(tab)
    }

    func requestClose(_ session: TerminalSession) {
        guard confirmsClosing([session]) else { return }
        close(session)
    }

    private func confirmsClosing(_ sessions: [TerminalSession]) -> Bool {
        let busy = sessions.filter { $0.status.tone == .busy }
        guard Preferences.shared.confirmClosingBusy, !busy.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = busy.count == 1 ? "\(busy[0].label) is still working" : "\(busy.count) agents are still working"
        alert.informativeText = "Closing ends the session and stops what it's doing."
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        let closes = alert.runModal() == .alertFirstButtonReturn
        if closes, alert.suppressionButton?.state == .on { Preferences.shared.confirmClosingBusy = false }
        return closes
    }

    /// Closes the tabs of `tab`'s folder other than it, or only those after it.
    func closeTabs(besides tab: TerminalTab, onlyAfter: Bool = false) {
        let open = tabs(in: tab.folder)
        guard let index = open.firstIndex(where: { $0.id == tab.id }) else { return }
        let doomed = onlyAfter ? Array(open[(index + 1)...]) : open.filter { $0.id != tab.id }
        for other in doomed { close(other) }
        selectedTabID = tab.id
        showsLauncher = false
    }

    /// The next or previous pane in the tab, keyboard and all.
    func focusPane(offset: Int) {
        guard let tab = selectedTab, !tab.sessions.isEmpty else { return }
        let current = focusedSession.flatMap { focused in tab.sessions.firstIndex { $0 === focused } } ?? 0
        let next = tab.sessions[(current + offset + tab.sessions.count) % tab.sessions.count]
        if tab.zoomedID != nil { tab.zoomedID = next.id }
        panel.isFocused = false
        lastPanelSession = next
        DispatchQueue.main.async { next.focus() }
    }

    func selectWorkspace(offset: Int) {
        guard !folders.isEmpty else { return }
        let current = folders.firstIndex(of: selectedFolder) ?? 0
        select(folder: folders[(current + offset + folders.count) % folders.count])
        panel.isFocused = false
        if let session = selectedTab?.sessions.first, !showsLauncher { DispatchQueue.main.async { session.focus() } }
    }

    /// Opens Settings through the app menu's own item: on macOS 13 SwiftUI
    /// offers no call for it, and the item doesn't answer the usual selector.
    func openSettings() {
        guard let menu = NSApp.mainMenu?.items.first?.submenu,
              let index = menu.items.firstIndex(where: { $0.keyEquivalent == "," }) else { return }
        NSApp.activate(ignoringOtherApps: true)
        menu.performActionForItem(at: index)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add Workspace"
        panel.message = "Pick one or more project folders to work on"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { addFolder(url.path) }
    }
}

/// ⌘/: every shortcut on one sheet.
struct ShortcutsSheet: View {
    @Binding var isPresented: Bool

    static let groups: [(String, [(String, String)])] = [
        ("Workspaces", [("⌘O", "Add a workspace (folder)"), ("⌘⇧N", "New project…"), ("⌥⌘↑ / ⌥⌘↓", "Previous / next workspace"),
                        ("⌃⌘S", "Show or hide the workspaces")]),
        ("Terminals", [("⌘T", "Open a CLI (launcher: arrows + ↩)"), ("⌘⇧[ / ⌘⇧]", "Previous / next tab"),
                       ("⌥⌘← / ⌥⌘→", "Previous / next pane"), ("⌘1…9", "Jump to a pane"), ("⌘D", "Add a pane beside"),
                       ("⌘⇧Z", "Zoom the pane"), ("⌘W", "Close the tab"), ("⌘⇧C", "Commit the changes")]),
        ("Right panel", [("⌘E", "Browse it with the keyboard"), ("↑↓ / j k", "Move"), ("← → / tab", "Crew · Skills · Tools · Tips"),
                         ("1-5", "Jump to a section"), ("/ or ⌘F", "Search"), ("↩", "Open the card"), ("u", "Use it in the terminal"),
                         ("e", "Change it (your CLI edits it)"), ("n", "New agent or skill"), ("esc", "Back to the terminal")]),
        ("Everything", [("⌘K", "Command palette"), ("⌘⇧K", "Kit: every CLI's skills, MCP, plugins"),
                        ("⌥⌘I", "Show or hide the panel"), ("⌘,", "Settings"), ("⌘/", "This sheet")]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Keyboard shortcuts").font(.mono(15, .bold)).foregroundStyle(Palette.cream)
                Spacer()
                Text("esc").font(.mono(10)).foregroundStyle(Palette.faint)
            }
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 16) { group(0); group(1) }
                VStack(alignment: .leading, spacing: 16) { group(2); group(3) }
            }
        }
        .padding(22)
        .frame(width: 760)
        .background(Palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .onExitCommand { isPresented = false }
    }

    private func group(_ index: Int) -> some View {
        let (title, rows) = Self.groups[index]
        return VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: title, color: Palette.claude)
            ForEach(rows, id: \.0) { key, label in
                HStack(spacing: 10) {
                    Text(key)
                        .font(.mono(11, .semibold))
                        .foregroundStyle(Palette.cream)
                        .frame(width: 112, alignment: .leading)
                    Text(label).font(.mono(11)).foregroundStyle(Palette.text)
                }
            }
        }
    }
}
