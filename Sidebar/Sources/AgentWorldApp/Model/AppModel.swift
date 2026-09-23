import AgentWorldArt
import AgentWorldKit
import Combine
import AppKit
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

    /// A name you gave the tab (right-click › Rename), over the automatic one.
    @Published var customTitle: String?

    /// Yours, else "Claude", or for several panes "Terminal ×3", "Claude + Codex ×2".
    var title: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        guard sessions.count > 1 else { return sessions.first?.label ?? "" }
        var names: [String] = []
        var counts: [String: Int] = [:]
        for session in sessions {
            let name = session.provider.shortName
            if counts[name] == nil { names.append(name) }
            counts[name, default: 0] += 1
        }
        return names.map { counts[$0]! > 1 ? "\($0) ×\(counts[$0]!)" : $0 }.joined(separator: " + ")
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
    /// Both side columns come back the way you left them.
    @Published var showsInspector = UserDefaults.standard.object(forKey: "showsInspector") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsInspector, forKey: "showsInspector") }
    }
    @Published var showsSidebar = UserDefaults.standard.object(forKey: "showsSidebar") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsSidebar, forKey: "showsSidebar") }
    }
    /// ⌘K and the kit browser, over everything.
    @Published var showsPalette = false
    @Published var showsKit = false
    /// The terminal that had the keyboard when ⌘K opened: skills go there.
    weak var paletteTarget: TerminalSession?
    @Published var profiles: [LaunchProfile] = LaunchProfile.defaults
    /// The right panel's sections, selection and keyboard focus.
    let panel = PanelNavigator()
    /// The pane the panel was about before the keys moved to it.
    weak var lastPanelSession: TerminalSession?
    /// Names, pins and last time's panes, by folder (see `Workspaces.swift`).
    @Published var workspaceInfo: [String: SavedWorkspace] = [:]
    /// Branch and uncommitted changes, by folder.
    @Published var git: [String: GitInfo] = [:]
    /// Uncommitted changes per workspace, refreshed while you look at one.
    @Published var changes: [String: WorkspaceChanges] = [:]
    var changesInFlight: Set<String> = []
    /// Tokens by CLI and day, refreshed every 30 s.
    @Published var usage: UsageSummary?
    let usageLedger = UsageLedger()
    var usageInFlight = false
    /// The change whose diff is open over the window.
    @Published var openChange: OpenChange?
    private var ticks = 0
    /// ⌘/ and ⌘⇧N sheets.
    @Published var showsShortcuts = false
    @Published var showsNewProject = false
    /// The card the launcher's arrow keys are on.
    @Published var launcherIndex = 0
    @Published private(set) var environmentReady = false
    /// The last tick. Not published: animations run on their own
    /// `TimelineView`s, and republishing the whole model twice a second made
    /// the right panel flicker and drop hovers and clicks.
    private(set) var now = Date()
    /// What views read from sessions without observing them (status tones,
    /// helpers at work); the model republishes only when it changes.
    private var liveState: [String] = []

    private var configs: [String: (config: AgentConfiguration, at: Date)] = [:]
    private var installed: [String: String?] = [:]
    private var timer: AnyCancellable?
    private(set) lazy var notifier: Notifier? = Notifier(model: self)

    init(folder: String?) {
        let saved = WorkspaceFile.load()
        workspaceInfo = Dictionary(saved.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var ordered = saved.filter(\.pinned).map(\.path) + saved.filter { !$0.pinned }.map(\.path)
        if let folder, !ordered.contains(folder) { ordered.insert(folder, at: 0) }
        // Opened from the Dock: where you were last. No workspaces yet: the
        // launcher welcomes you and suggests some.
        let last = saved.max { $0.lastOpened < $1.lastOpened }?.path
        selectedFolder = folder ?? last ?? FileManager.default.homeDirectoryForCurrentUser.path
        folders = ordered
        profiles = LaunchProfile.load()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveWorkspaces() }
        }

        // The login shell's PATH, off the main thread; CLIs are found after.
        Task.detached {
            ShellEnvironment.load()
            await MainActor.run {
                self.installed = [:]
                self.environmentReady = true
            }
        }
        installKeyRouter()
        Preferences.shared.onTerminalLookChange = { [weak self] in
            self?.allSessions.forEach { $0.restyle() }
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
        let live = allSessions.map { session in
            "\(session.id) \(session.status.tone) " + (session.store?.runningSubagents.map { $0.type + ":" + ($0.state.action ?? "") }.joined(separator: ",") ?? "")
        }
        if live != liveState {
            liveState = live
            objectWillChange.send()
        }
        notifier?.update(allSessions, now: date)
        ticks += 1
        if ticks % 20 == 0 { saveWorkspaces() }
        if ticks % 60 == 1 { refreshGit() }
        if ticks % 60 == 3 { refreshUsage() }
        // The workspace on screen every 2 s, and any other where agents work.
        if ticks % 4 == 0 {
            refreshChanges(selectedFolder)
            for folder in Set(allSessions.filter { $0.status.tone == .busy && $0.folder != selectedFolder }.map(\.folder)) {
                refreshChanges(folder)
            }
        }
    }

    /// Replaces the custom launch profiles and writes them to profiles.json.
    func saveCustomProfiles(_ custom: [LaunchProfile]) {
        profiles = LaunchProfile.defaults + custom
        installed = [:]
        try? LaunchProfile.save(profiles)
    }

    // MARK: - Lookups

    var selectedTab: TerminalTab? { tabs.first { $0.id == selectedTabID } }

    func tabs(in folder: String) -> [TerminalTab] {
        tabs.filter { $0.folder == folder }
    }

    var allSessions: [TerminalSession] { tabs.flatMap(\.sessions) }

    /// The panes `lead` opened to help it, oldest first.
    func helpers(of lead: TerminalSession) -> [TerminalSession] {
        allSessions.filter { $0.openedBy === lead }
    }

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
        workspaceInfo[folder, default: SavedWorkspace(path: folder)].lastOpened = Date()
        let open = tabs(in: folder)
        selectedTabID = open.first?.id
        showsLauncher = open.isEmpty
    }

    func addFolder(_ path: String) {
        RecentFolders.remember(path)
        select(folder: path)
        saveWorkspaces()
        refreshGit()
    }

    func removeFolder(_ path: String) {
        for tab in tabs where tab.folder == path { close(tab) }
        folders.removeAll { $0 == path }
        RecentFolders.forget(path)
        if selectedFolder == path, let first = folders.first { select(folder: first) }
        workspaceInfo[path] = nil
        saveWorkspaces()
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
