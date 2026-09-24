import AgentWorldKit
import AppKit
import Foundation

/// The shared memory in the app: the notes of the workspace on screen and
/// the global ones, the notes view (⌘⇧O) and the way out to Obsidian.
extension AppModel {
    var memoryVault: MemoryVault { MemoryVault(root: URL(fileURLWithPath: Preferences.shared.memoryFolder, isDirectory: true)) }

    /// The selected workspace's scope in the vault.
    var memoryScope: String { MemoryVault.scope(for: selectedFolder) }

    /// Rereads every note off the main thread (a few hundred small files).
    func refreshMemory() {
        guard !memoryInFlight else { return }
        memoryInFlight = true
        let vault = memoryVault
        Task.detached(priority: .utility) {
            let notes = vault.notes()
            await MainActor.run {
                self.memoryInFlight = false
                if notes != self.memoryNotes { self.memoryNotes = notes }
            }
        }
    }

    /// Notes for the panel: this workspace's, then the global ones.
    var workspaceMemory: [MemoryNote] {
        let scope = memoryScope
        return memoryNotes.filter { $0.scope == scope } + memoryNotes.filter { $0.isGlobal && scope != MemoryVault.globalScope }
    }

    func memoryNote(_ id: String?) -> MemoryNote? {
        id.flatMap { id in memoryNotes.first { $0.id == id } }
    }

    /// A `[[link]]` from `note`: a note of the same scope first, then global, then any.
    func resolveLink(_ target: String, from note: MemoryNote?) -> MemoryNote? {
        let parts = target.split(separator: "/", maxSplits: 1).map(String.init)
        if parts.count == 2 { return memoryNotes.first { $0.scope == parts[0] && $0.name == MemoryVault.slug(parts[1]) } }
        let name = MemoryVault.slug(target)
        return memoryNotes.first { $0.name == name && $0.scope == note?.scope }
            ?? memoryNotes.first { $0.name == name && $0.isGlobal }
            ?? memoryNotes.first { $0.name == name }
    }

    /// The notes that link to `note`.
    func backlinks(_ note: MemoryNote) -> [MemoryNote] {
        memoryNotes.filter { other in other.id != note.id && other.links.contains { resolveLink($0, from: other)?.id == note.id } }
    }

    /// Registers the memory's MCP server with every CLI set up here (once
    /// the login shell's PATH is known, to find Claude's CLI).
    func connectMemoryEverywhere() {
        let claude = executable(for: LaunchProfile(name: Provider.claude.name, provider: .claude))
        Task.detached(priority: .utility) { MemoryMCP.connectAll(claudeExecutable: claude) }
    }

    func openNotes(_ id: String? = nil) {
        refreshMemory()
        if let id { openNoteID = id }
        showsNotes = true
    }

    /// An agent wrote or deleted a note (`agentworld-ctl` told us).
    func memoryChanged(_ action: String, id: String, by session: TerminalSession?) {
        refreshMemory()
        let name = id.split(separator: "/").last.map(String.init) ?? id
        session?.saying = .init(text: action == "deleted" ? "Forgot \(name)" : "Remembered \(name)", at: Date())
    }

    /// The agent CLI to hand a note to: the one you're in, else the panel's.
    var noteTarget: TerminalSession? {
        [focusedSession, panelSession].compactMap { $0 }.first { $0.provider.isAgent } ?? focusedSession ?? panelSession
    }

    /// Types a pointer to the note into the terminal: the file for CLIs that
    /// attach files, and how to read it for every other one.
    func mention(_ note: MemoryNote, in session: TerminalSession) {
        reveal(session)
        if session.provider.isAgent {
            session.type("(shared memory note \(note.id): \(note.url.path)) ")
        } else {
            session.type("agentworld-ctl memory read \(note.id)")
        }
    }
}

// MARK: - Obsidian

/// Opens the vault (or one note) in Obsidian, registering the vault with
/// Obsidian the first time so its `obsidian://` links work.
enum Obsidian {
    static let bundleID = "md.obsidian"

    static var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    static var isInstalled: Bool { appURL != nil }
    static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    private static var registry: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/obsidian/obsidian.json")
    }

    static func isRegistered(_ vault: URL) -> Bool {
        registeredPaths().contains(vault.standardizedFileURL.path)
    }

    private static func registeredPaths() -> [String] {
        guard let data = try? Data(contentsOf: registry),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vaults = json["vaults"] as? [String: Any] else { return [] }
        return vaults.values.compactMap { ($0 as? [String: Any])?["path"] as? String }.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
    }

    /// Adds the vault to Obsidian's list. Only while Obsidian is closed: it
    /// rewrites that file itself when it quits.
    @discardableResult
    static func register(_ vault: URL) -> Bool {
        guard !isRunning else { return false }
        var json = (try? Data(contentsOf: registry)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        var vaults = json["vaults"] as? [String: Any] ?? [:]
        let id = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16))
        vaults[id] = ["path": vault.standardizedFileURL.path, "ts": Int(Date().timeIntervalSince1970 * 1000), "open": true]
        json["vaults"] = vaults
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) else { return false }
        try? FileManager.default.createDirectory(at: registry.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: registry, options: .atomic)) != nil
    }

    enum Outcome { case opened, notInstalled, needsVault }

    /// Opens `file` (a note) or the vault's Home. When Obsidian is already
    /// open and doesn't know the vault yet, it opens Obsidian and says so.
    @discardableResult
    static func open(vault: URL, file: URL? = nil) -> Outcome {
        guard let app = appURL else { return .notInstalled }
        try? MemoryVault(root: vault).prepare()
        if !isRegistered(vault), !register(vault) {
            NSWorkspace.shared.openApplication(at: app, configuration: .init())
            return .needsVault
        }
        let target = file ?? vault.appendingPathComponent("Home.md")
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: target.path)]
        if let url = components.url { NSWorkspace.shared.open(url) }
        return .opened
    }
}

// MARK: - MCP for every CLI

/// Registers `agentworld-ctl mcp` as the `agentworld-memory` MCP server in
/// each CLI's own config, the way that CLI keeps them: Claude through
/// `claude mcp add`, Codex in config.toml, the rest in their JSON files.
enum MemoryMCP {
    static let name = MemoryMCPServer.name

    struct Target {
        let provider: Provider
        /// The CLI's config folder under home; the CLI counts as set up when it exists.
        let home: String
        let file: String
        let format: Format
    }

    enum Format { case claude, codexTOML, json(key: String), opencode }

    static let targets: [Target] = [
        Target(provider: .claude, home: ".claude", file: ".claude.json", format: .claude),
        Target(provider: .codex, home: ".codex", file: ".codex/config.toml", format: .codexTOML),
        Target(provider: .gemini, home: ".gemini", file: ".gemini/settings.json", format: .json(key: "mcpServers")),
        Target(provider: .kimi, home: ".kimi", file: ".kimi/mcp.json", format: .json(key: "mcpServers")),
        Target(provider: .grok, home: ".grok", file: ".grok/user-settings.json", format: .json(key: "mcpServers")),
        Target(provider: .opencode, home: ".config/opencode", file: ".config/opencode/opencode.json", format: .opencode),
        Target(provider: .cursor, home: ".cursor", file: ".cursor/mcp.json", format: .json(key: "mcpServers")),
        Target(provider: .kiro, home: ".kiro", file: ".kiro/settings/mcp.json", format: .json(key: "mcpServers")),
    ]

    /// The `agentworld-ctl` the CLIs should run: the installed app's when
    /// there is one (it outlives development builds), else this build's.
    static var command: String? {
        let installed = ["/Applications", FileManager.default.homeDirectoryForCurrentUser.path + "/Applications"]
            .map { $0 + "/AgentWorld.app/Contents/MacOS/agentworld-ctl" }
        let own = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("agentworld-ctl").path
        return (installed + [own].compactMap { $0 }).first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static func isSetUp(_ target: Target) -> Bool {
        FileManager.default.fileExists(atPath: home.appendingPathComponent(target.home).path)
    }

    /// Whether the CLI already has the server (any command).
    static func isConnected(_ target: Target) -> Bool {
        let url = home.appendingPathComponent(target.file)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        switch target.format {
        case .codexTOML: return text.contains("[mcp_servers.\(name)]")
        case .claude, .json, .opencode: return text.contains("\"\(name)\"")
        }
    }

    static func status() -> [(target: Target, connected: Bool)] {
        targets.filter(isSetUp).map { ($0, isConnected($0)) }
    }

    /// Connects every CLI set up here that doesn't have it yet. Off the main
    /// thread (Claude's goes through its CLI).
    static func connectAll(claudeExecutable: String?) {
        guard let command else { return }
        for target in targets where isSetUp(target) && !isConnected(target) {
            connect(target, command: command, claudeExecutable: claudeExecutable)
        }
    }

    static func connect(_ target: Target, command: String, claudeExecutable: String?) {
        let url = home.appendingPathComponent(target.file)
        switch target.format {
        case .claude:
            // ~/.claude.json is Claude's own busy file: let its CLI write it.
            guard let claude = claudeExecutable else { return }
            run(claude, ["mcp", "add", "--scope", "user", name, "--", command, "mcp"])
        case .codexTOML:
            let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let table = "\n[mcp_servers.\(name)]\ncommand = \"\(command)\"\nargs = [\"mcp\"]\n"
            try? (existing + (existing.hasSuffix("\n") || existing.isEmpty ? "" : "\n") + table).write(to: url, atomically: true, encoding: .utf8)
        case .json(let key):
            updateJSON(url) { json in
                var servers = json[key] as? [String: Any] ?? [:]
                servers[name] = ["command": command, "args": ["mcp"]]
                json[key] = servers
            }
        case .opencode:
            updateJSON(url) { json in
                var servers = json["mcp"] as? [String: Any] ?? [:]
                servers[name] = ["type": "local", "command": [command, "mcp"], "enabled": true]
                json["mcp"] = servers
            }
        }
    }

    static func disconnect(_ target: Target, claudeExecutable: String?) {
        let url = home.appendingPathComponent(target.file)
        switch target.format {
        case .claude:
            guard let claude = claudeExecutable else { return }
            run(claude, ["mcp", "remove", "--scope", "user", name])
        case .codexTOML:
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            var kept: [Substring] = []
            var skipping = false
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") { skipping = trimmed == "[mcp_servers.\(name)]" || trimmed.hasPrefix("[mcp_servers.\(name).") }
                if !skipping { kept.append(line) }
            }
            try? kept.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        case .json(let key):
            updateJSON(url) { json in
                var servers = json[key] as? [String: Any] ?? [:]
                servers[name] = nil
                json[key] = servers
            }
        case .opencode:
            updateJSON(url) { json in
                var servers = json["mcp"] as? [String: Any] ?? [:]
                servers[name] = nil
                json["mcp"] = servers
            }
        }
    }

    /// Changes a JSON config, leaving it alone when it doesn't parse (a
    /// comment, a trailing comma: better no server than a broken config).
    private static func updateJSON(_ url: URL, _ change: (inout [String: Any]) -> Void) {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            json = parsed
        }
        change(&json)
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private static func run(_ executable: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ShellEnvironment.variables
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        process.waitUntilExit()
    }
}

// MARK: - Always-on instructions

/// A short block in each CLI's global instructions file (the one it reads
/// in every session), so agents use the memory without being asked: search
/// before a task, write what they learn. Between markers, so it can be
/// updated or removed without touching the rest of the file.
enum MemoryInstructions {
    static let start = "<!-- agentworld-memory:start — added by AgentWorld; turn off in Settings › Memory -->"
    static let end = "<!-- agentworld-memory:end -->"

    static let text = """
    ## Shared memory (AgentWorld)

    You share a memory with the user's other agent CLIs (Claude Code, Codex,
    Gemini…): Markdown notes per project, plus global ones about the user.
    Use the `agentworld-memory` MCP tools (memory_search, memory_read,
    memory_write…) if you have them, else `agentworld-ctl memory` in the shell.

    - Before non-trivial work in a project, search the memory for the topic.
    - When you learn something another agent would need (how to build, test
      or run it; a decision and why; a gotcha; a user preference), write it:
      one topic per note, a clear name, a one-line description, and its kind
      (decision, howto, gotcha, context or preference).
    - Update or delete notes that turn out wrong. No secrets, and nothing the
      code or git history already records.

    Inside AgentWorld, other agents may work in the same project at the same
    time. Check `agentworld-ctl board` (or team_board) when you start, say what
    you're on with `agentworld-ctl doing "…"`, and message an agent before
    editing files it touched (`agentworld-ctl message '#n' "…"`).
    """

    struct Target {
        let provider: Provider
        /// The CLI's config folder under home; set up when it exists.
        let home: String
        /// The global instructions file it reads every session.
        let file: String
        /// A file of its own (Kiro's steering) instead of a block in a shared one.
        var ownFile = false
    }

    static let targets: [Target] = [
        Target(provider: .claude, home: ".claude", file: ".claude/CLAUDE.md"),
        Target(provider: .codex, home: ".codex", file: ".codex/AGENTS.md"),
        Target(provider: .gemini, home: ".gemini", file: ".gemini/GEMINI.md"),
        Target(provider: .opencode, home: ".config/opencode", file: ".config/opencode/AGENTS.md"),
        Target(provider: .kiro, home: ".kiro", file: ".kiro/steering/agentworld-memory.md", ownFile: true),
    ]

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static func status() -> [(target: Target, installed: Bool)] {
        targets.filter { FileManager.default.fileExists(atPath: home.appendingPathComponent($0.home).path) }.map { target in
            let text = try? String(contentsOf: home.appendingPathComponent(target.file), encoding: .utf8)
            return (target, text?.contains(start) == true)
        }
    }

    static func installAll() {
        for (target, _) in status() { install(target) }
    }

    static func uninstallAll() {
        for (target, installed) in status() where installed { uninstall(target) }
    }

    static func install(_ target: Target) {
        let url = home.appendingPathComponent(target.file)
        let block = start + "\n" + text + "\n" + end + "\n"
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let next: String
        if target.ownFile {
            next = block
        } else if let range = blockRange(in: existing) {
            next = existing.replacingCharacters(in: range, with: block)
        } else {
            let trimmed = existing.trimmingCharacters(in: .newlines)
            next = trimmed.isEmpty ? block : trimmed + "\n\n" + block
        }
        guard next != existing else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? next.write(to: url, atomically: true, encoding: .utf8)
    }

    static func uninstall(_ target: Target) {
        let url = home.appendingPathComponent(target.file)
        if target.ownFile {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let existing = try? String(contentsOf: url, encoding: .utf8), let range = blockRange(in: existing) else { return }
        var next = existing
        next.removeSubrange(range)
        next = next.trimmingCharacters(in: .newlines)
        try? (next.isEmpty ? "" : next + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// From the start marker to the end marker and its newline.
    private static func blockRange(in text: String) -> Range<String.Index>? {
        guard let open = text.range(of: start), let close = text.range(of: end, range: open.upperBound..<text.endIndex) else { return nil }
        let after = text[close.upperBound...].first == "\n" ? text.index(after: close.upperBound) : close.upperBound
        return open.lowerBound..<after
    }
}
