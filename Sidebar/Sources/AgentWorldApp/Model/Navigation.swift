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

    private let groups: [(String, [(String, String)])] = [
        ("Workspaces", [("⌘O", "Add a workspace (folder)"), ("⌘⇧N", "New project…"), ("⌥⌘↑ / ⌥⌘↓", "Previous / next workspace")]),
        ("Terminals", [("⌘T", "Open a CLI (launcher: arrows + ↩)"), ("⌘⇧[ / ⌘⇧]", "Previous / next tab"),
                       ("⌥⌘← / ⌥⌘→", "Previous / next pane"), ("⌘1…9", "Jump to a pane"), ("⌘D", "Add a pane beside"),
                       ("⌘⇧Z", "Zoom the pane"), ("⌘W", "Close the tab")]),
        ("Right panel", [("⌘E", "Browse it with the keyboard"), ("↑↓ / j k", "Move"), ("← → / tab", "Crew · Skills · Tools · Tips"),
                         ("1-4", "Jump to a section"), ("↩", "Open the card"), ("u", "Use it in the terminal"),
                         ("e", "Change it (your CLI edits it)"), ("n", "New agent or skill"), ("esc", "Back to the terminal")]),
        ("Everything", [("⌘K", "Command palette"), ("⌘⇧K", "Kit: every CLI's skills, MCP, plugins"),
                        ("⌥⌘I", "Show or hide the panel"), ("⌘/", "This sheet")]),
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
        let (title, rows) = groups[index]
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
