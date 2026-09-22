import AgentWorldArt
import AgentWorldKit
import Combine
import Foundation
import SwiftUI

/// A tab: one terminal, or several launched together and shown side by side.
@MainActor
final class TerminalTab: ObservableObject, Identifiable {
    let id = UUID()
    let folder: String
    @Published var sessions: [TerminalSession]
    /// How several panes are arranged; see `TileLayout`.
    @Published var layout = TileLayout.grid
    /// One pane blown up to fill the tab, the others still running behind it.
    @Published var zoomedID: UUID?

    init(folder: String, sessions: [TerminalSession]) {
        self.folder = folder
        self.sessions = sessions
    }

    var title: String {
        sessions.count == 1 ? sessions[0].label : sessions.map(\.provider.shortName).joined(separator: " + ")
    }

    var agentName: String? { sessions.first?.agentName }
}

/// Everything the window shows, in one place.
@MainActor
final class AppModel: ObservableObject {
    @Published var folders: [String] = []
    @Published var selectedFolder: String
    @Published var tabs: [TerminalTab] = []
    @Published var selectedTabID: UUID?
    /// The launcher is shown instead of a terminal (the "+" tab).
    @Published var showsLauncher = true
    @Published var showsInspector = true
    /// ⌘K and the kit browser, over everything.
    @Published var showsPalette = false
    @Published var showsKit = false
    /// The terminal that had the keyboard when ⌘K opened: skills go there.
    weak var paletteTarget: TerminalSession?
    @Published var profiles: [LaunchProfile] = LaunchProfile.defaults
    @Published private(set) var environmentReady = false
    /// Ticks twice a second so statuses and animations stay fresh.
    @Published private(set) var now = Date()

    private var configs: [String: (config: AgentConfiguration, at: Date)] = [:]
    private var installed: [String: String?] = [:]
    private var timer: AnyCancellable?
    private(set) lazy var notifier: Notifier? = Notifier(model: self)

    init(folder: String?) {
        let recents = RecentFolders.load()
        let start = folder ?? recents.first ?? FileManager.default.homeDirectoryForCurrentUser.path
        selectedFolder = start
        folders = [start] + recents.filter { $0 != start }
        profiles = LaunchProfile.load()

        // The login shell's PATH, off the main thread; CLIs are found after.
        Task.detached {
            ShellEnvironment.load()
            await MainActor.run {
                self.installed = [:]
                self.environmentReady = true
            }
        }
        timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect().sink { [weak self] date in
            self?.tick(date)
        }
    }

    private func tick(_ date: Date) {
        now = date
        for tab in tabs {
            for session in tab.sessions { session.refresh(now: date) }
        }
        notifier?.update(allSessions, now: date)
    }

    // MARK: - Lookups

    var selectedTab: TerminalTab? { tabs.first { $0.id == selectedTabID } }

    func tabs(in folder: String) -> [TerminalTab] {
        tabs.filter { $0.folder == folder }
    }

    var allSessions: [TerminalSession] { tabs.flatMap(\.sessions) }

    /// A CLI's configuration for a folder, rescanned every 15 s.
    func config(_ provider: Provider, in folder: String) -> AgentConfiguration {
        let key = provider.id + "|" + folder
        if let cached = configs[key], Date().timeIntervalSince(cached.at) < 15 { return cached.config }
        let config = ProviderScanner(provider: provider, projectURL: URL(fileURLWithPath: folder, isDirectory: true)).scan()
        configs[key] = (config, Date())
        return config
    }

    func executable(for profile: LaunchProfile) -> String? {
        if let known = installed[profile.executable] { return known }
        let found = ShellEnvironment.locate(profile.executable)
        installed[profile.executable] = found
        return found
    }

    /// Agents across the CLIs for a folder, yours first.
    func agents(in folder: String) -> [(Provider, AgentDefinition)] {
        let all = Provider.all.filter(\.isAgent).flatMap { provider in config(provider, in: folder).agents.map { (provider, $0) } }
        return all.filter { $0.1.scope != .builtin } + all.filter { $0.1.scope == .builtin }
    }

    func agent(for key: String, in folder: String) -> (Provider, AgentDefinition)? {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let provider = Provider.named(parts[0]) else { return nil }
        return config(provider, in: folder).agents.first { $0.qualifiedName == parts[1] }.map { (provider, $0) }
    }

    /// Suggestions for a session (from what you asked it) or for the folder.
    func tips(for session: TerminalSession?, in folder: String) -> [Suggestion] {
        let provider = session?.provider.isAgent == true ? session!.provider : .claude
        let config = config(provider, in: folder)
        let log = session?.store?.log ?? []
        let prompts = log.filter { $0.kind == .prompt }.map(\.text)
        let files = log.compactMap { entry -> String? in
            guard case .tool(let kind) = entry.kind, kind == .edit || kind == .read else { return nil }
            return entry.text.split(separator: " ").last.map(String.init)
        }.suffix(20)
        let fromPrompts = prompts.isEmpty ? [] : Recommender.suggest(config: config, prompts: prompts, files: Array(files))
        return fromPrompts.isEmpty ? Recommender.suggest(config: config, prompts: [], files: Array(files)) : fromPrompts
    }

    // MARK: - Folders

    func select(folder: String) {
        if !folders.contains(folder) { folders.insert(folder, at: 0) }
        selectedFolder = folder
        let open = tabs(in: folder)
        selectedTabID = open.first?.id
        showsLauncher = open.isEmpty
    }

    func addFolder(_ path: String) {
        RecentFolders.remember(path)
        select(folder: path)
    }

    func removeFolder(_ path: String) {
        for tab in tabs where tab.folder == path { close(tab) }
        folders.removeAll { $0 == path }
        RecentFolders.forget(path)
        if selectedFolder == path, let first = folders.first { select(folder: first) }
    }

    // MARK: - Launching

    @discardableResult
    func launch(_ profile: LaunchProfile, in folder: String, typing: String? = nil, submitTyping: Bool = false, agentName: String? = nil) -> TerminalSession? {
        guard let executable = executable(for: profile) else { return nil }
        let session = TerminalSession(profile: profile, executable: executable, folder: folder, agentName: agentName,
                                      typing: typing, submitTyping: submitTyping)
        let tab = TerminalTab(folder: folder, sessions: [session])
        tabs.append(tab)
        selectedTabID = tab.id
        showsLauncher = false
        RecentFolders.remember(folder)
        if !folders.contains(folder) { folders.insert(folder, at: 0) }
        return session
    }

    func launchTogether(_ chosen: [LaunchProfile], in folder: String) {
        let sessions = chosen.prefix(Self.maxPanes).compactMap { profile in
            executable(for: profile).map { TerminalSession(profile: profile, executable: $0, folder: folder) }
        }
        guard !sessions.isEmpty else { return }
        let tab = TerminalTab(folder: folder, sessions: sessions)
        tabs.append(tab)
        selectedTabID = tab.id
        showsLauncher = false
        // Three or more panes need the width more than the tips do.
        if sessions.count >= 3 { showsInspector = false }
        RecentFolders.remember(folder)
    }

    /// Agent mode: a conversation with one agent, in its own tab.
    func startChat(with agent: AgentDefinition, provider: Provider, in folder: String) {
        let profile = profiles.first { $0.provider == provider && !$0.isCustom } ?? LaunchProfile(name: provider.name, provider: provider)
        launch(profile, in: folder, typing: "Use the \(agent.qualifiedName) agent to ", agentName: agent.name)
    }

    func close(_ tab: TerminalTab) {
        for session in tab.sessions { session.terminate() }
        let index = tabs.firstIndex { $0.id == tab.id }
        tabs.removeAll { $0.id == tab.id }
        if selectedTabID == tab.id {
            let siblings = tabs(in: tab.folder)
            if let index, !siblings.isEmpty {
                selectedTabID = siblings[min(max(0, index - 1), siblings.count - 1)].id
            } else {
                selectedTabID = siblings.last?.id
            }
            showsLauncher = selectedTabID == nil
        }
    }

    func close(_ session: TerminalSession) {
        guard let tab = tabs.first(where: { $0.sessions.contains { $0.id == session.id } }) else { return }
        if tab.sessions.count == 1 {
            close(tab)
        } else {
            session.terminate()
            tab.sessions.removeAll { $0.id == session.id }
            objectWillChange.send()
        }
    }
}
