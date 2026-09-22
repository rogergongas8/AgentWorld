import AgentWorldArt
import AgentWorldKit
import Foundation

/// The hub's terminals, as tmux windows and panes in the hub's own tmux
/// server (the `agentworld` shell command starts it with `tmux -L agentworld`).
/// A window holds one CLI plus its AgentWorld sidebar, or several CLIs tiled
/// side by side. Pane options (`@aw_*`) remember which CLI, folder and Claude
/// session each pane is; the border shows `@aw_label` as a title bar.
struct Workspace {
    struct Pane: Equatable {
        let id: String
        let windowId: String
        let windowIndex: Int
        /// "Claude Code", "Codex"…
        let label: String
        /// What the program itself set as its title (Claude shows its task).
        let title: String
        let provider: Provider?
        let cwd: String?
        let sessionId: String?
        let isFocused: Bool
        /// When tmux last saw output in its window.
        let lastActivity: Date?
        /// When the hub opened it.
        let startedAt: Date?

        var folderName: String { cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "?" }
    }

    enum Failure: Error, CustomStringConvertible {
        case notInTmux
        case tmux(String)

        var description: String {
            switch self {
            case .notInTmux: "Not inside the hub: run `agentworld` to open it."
            case .tmux(let message): "tmux: \(message)"
            }
        }
    }

    /// The sidebar binary to put next to each CLI (this same executable).
    let sidebarBinary: String
    var sidebarWidth = ProcessInfo.processInfo.environment["AGENTWORLD_WIDTH"] ?? "34%"

    static var isInsideTmux: Bool { ProcessInfo.processInfo.environment["TMUX"] != nil }

    /// Whether this process runs inside the `agentworld` hub (its tmux server
    /// socket is named "agentworld"), where new terminals become tabs.
    static var isInsideHub: Bool {
        guard let socket = ProcessInfo.processInfo.environment["TMUX"]?.split(separator: ",").first else { return false }
        return URL(fileURLWithPath: String(socket)).lastPathComponent == "agentworld"
    }

    // MARK: - Queries

    /// Every CLI pane in the session (sidebars and the hub itself excluded).
    func panes() -> [Pane] {
        let fields = ["#{pane_id}", "#{window_id}", "#{window_index}", "#{@aw_label}", "#{pane_title}", "#{@aw_provider}",
                      "#{@aw_cwd}", "#{@aw_session}", "#{&&:#{window_active},#{pane_active}}", "#{window_activity}", "#{@aw_role}", "#{@aw_started}"]
        guard let output = try? tmux(["list-panes", "-s", "-F", fields.joined(separator: "\t")]) else { return [] }
        return output.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count == fields.count, f[10] == "cli", let index = Int(f[2]) else { return nil }
            return Pane(
                id: f[0], windowId: f[1], windowIndex: index,
                label: f[3].isEmpty ? f[4] : f[3],
                title: f[4],
                provider: Provider.named(f[5]),
                cwd: f[6].isEmpty ? nil : f[6],
                sessionId: f[7].isEmpty ? nil : f[7],
                isFocused: f[8] == "1",
                lastActivity: Double(f[9]).map { Date(timeIntervalSince1970: $0) },
                startedAt: Double(f[11]).map { Date(timeIntervalSince1970: $0) }
            )
        }
    }

    /// A session option the shell sets when you run `agentworld` from another
    /// folder, so the picker follows you.
    func requestedDirectory() -> String? {
        let value = try? tmux(["show-options", "-qv", "@aw_request_cwd"])
        return value.flatMap { $0.isEmpty ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func clearRequestedDirectory() {
        _ = try? tmux(["set-option", "-u", "@aw_request_cwd"])
    }

    // MARK: - Launching

    struct Launch {
        let profile: LaunchProfile
        let executable: String
    }

    /// One CLI in a new window, with its AgentWorld sidebar on the right
    /// (not for the plain terminal, nor for Agent-mode chats). `typing` is pre-filled into its prompt
    /// once it has started, without pressing enter. Returns the CLI's pane id.
    @discardableResult
    func launch(_ launch: Launch, in directory: String, typing: String? = nil, withSidebar: Bool = true) throws -> String {
        let (command, sessionId) = Self.command(for: launch)
        let pane = try tmux(["new-window", "-P", "-F", "#{pane_id}", "-n", windowName([launch], directory), "-c", directory] + env(launch) + [command])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        tag(pane, launch, directory: directory, sessionId: sessionId)

        if withSidebar, launch.profile.provider.isAgent {
            var arguments = ["--provider", launch.profile.provider.id, "--cwd", directory]
            if let sessionId { arguments += ["--session-id", sessionId] }
            let sidebar = ([sidebarBinary] + arguments).map(Self.shellQuote).joined(separator: " ")
            if let sidebarPane = try? tmux(["split-window", "-h", "-d", "-P", "-F", "#{pane_id}", "-t", pane, "-l", sidebarWidth, "-c", directory, sidebar])
                .trimmingCharacters(in: .whitespacesAndNewlines) {
                setPaneOptions(sidebarPane, ["@aw_role": "sidebar", "@aw_label": "AgentWorld · \(launch.profile.provider.shortName)"])
            }
        }
        if let typing { typeLater(typing, into: pane) }
        return pane
    }

    /// Several CLIs tiled in one new window, side by side.
    func launchTogether(_ launches: [Launch], in directory: String) throws {
        guard let first = launches.first else { return }
        let (command, sessionId) = Self.command(for: first)
        let firstPane = try tmux(["new-window", "-P", "-F", "#{pane_id}", "-n", windowName(launches, directory), "-c", directory] + env(first) + [command])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        tag(firstPane, first, directory: directory, sessionId: sessionId)
        for launch in launches.dropFirst() {
            let (command, sessionId) = Self.command(for: launch)
            let pane = try tmux(["split-window", "-h", "-d", "-P", "-F", "#{pane_id}", "-t", firstPane, "-c", directory] + env(launch) + [command])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            tag(pane, launch, directory: directory, sessionId: sessionId)
            // Re-tile after each split so the next one has room.
            _ = try? tmux(["select-layout", "-t", firstPane, "tiled"])
        }
        _ = try? tmux(["select-layout", "-t", firstPane, launches.count <= 3 ? "even-horizontal" : "tiled"])
        _ = try? tmux(["select-pane", "-t", firstPane])
    }

    /// The shell command for a CLI pane, and the Claude session id it pins.
    /// When the CLI exits its pane closes, and the window with it once only
    /// sidebars are left. A failure (not a Ctrl-C quit, 130) waits so its
    /// message can be read. `aw_status`, not `status` (read-only in zsh);
    /// trapping INT (not ignoring it) keeps this shell alive through the
    /// Ctrl-C that quits the CLI while the CLI still receives it.
    static func command(for launch: Launch) -> (String, String?) {
        let provider = launch.profile.provider
        var arguments = launch.profile.args
        var sessionId: String?
        let resumeFlags: Set<String> = ["-c", "--continue", "-r", "--resume", "--session-id", "--fork-session"]
        if provider.kind == .claude, !arguments.contains(where: { resumeFlags.contains($0.components(separatedBy: "=")[0]) }) {
            let id = UUID().uuidString.lowercased()
            sessionId = id
            arguments = ["--session-id", id] + arguments
        }
        let cli = ([launch.executable] + arguments).map(shellQuote).joined(separator: " ")
        let command = [
            "trap : INT; \(cli); aw_status=$?;",
            "if [ $aw_status -ne 0 ] && [ $aw_status -ne 130 ]; then printf '\\n[%s exited with %s, press enter]' \(shellQuote(provider.name)) $aw_status; read _; fi;",
            "aw_window=$(tmux display-message -p -t \"$TMUX_PANE\" '#{window_id}');",
            "aw_others=$(tmux list-panes -t \"$aw_window\" -F '#{pane_id} #{@aw_role}' | grep -v \"^$TMUX_PANE \" | grep -c ' cli$');",
            "if [ \"$aw_others\" -eq 0 ]; then tmux kill-window -t \"$aw_window\"; else tmux kill-pane -t \"$TMUX_PANE\"; fi",
        ].joined(separator: " ")
        return (command, sessionId)
    }

    private func tag(_ pane: String, _ launch: Launch, directory: String, sessionId: String?) {
        var options = ["@aw_role": "cli", "@aw_provider": launch.profile.provider.id, "@aw_cwd": directory,
                       "@aw_started": String(Int(Date().timeIntervalSince1970)),
                       "@aw_label": launch.profile.isCustom ? launch.profile.name : launch.profile.provider.name]
        if let sessionId { options["@aw_session"] = sessionId }
        setPaneOptions(pane, options)
        // Keep the tab name we chose.
        _ = try? tmux(["set-option", "-w", "-t", pane, "automatic-rename", "off"])
    }

    private func setPaneOptions(_ pane: String, _ options: [String: String]) {
        for (key, value) in options.sorted(by: { $0.key < $1.key }) {
            _ = try? tmux(["set-option", "-p", "-t", pane, key, value])
        }
    }

    private func env(_ launch: Launch) -> [String] {
        launch.profile.env.sorted { $0.key < $1.key }.flatMap { ["-e", "\($0.key)=\($0.value)"] }
    }

    private func windowName(_ launches: [Launch], _ directory: String) -> String {
        let names = launches.map(\.profile.provider.shortName)
        let who = names.count > 2 ? "\(names[0]) +\(names.count - 1)" : names.joined(separator: "+")
        return "\(who) · \(URL(fileURLWithPath: directory).lastPathComponent)"
    }

    // MARK: - Actions

    func focus(_ pane: Pane) {
        _ = try? tmux(["select-window", "-t", pane.windowId])
        _ = try? tmux(["select-pane", "-t", pane.id])
    }

    /// Closes a CLI: its whole window when it's the only CLI there.
    func close(_ pane: Pane) {
        let others = panes().filter { $0.windowId == pane.windowId && $0.id != pane.id }
        _ = try? tmux(others.isEmpty ? ["kill-window", "-t", pane.windowId] : ["kill-pane", "-t", pane.id])
    }

    /// Types into a pane's prompt without pressing enter.
    func type(_ text: String, into pane: String) {
        _ = try? tmux(["send-keys", "-t", pane, "-l", text])
    }

    /// Same, after the CLI has had time to start (typing into a CLI that is
    /// still booting can get lost).
    func typeLater(_ text: String, into pane: String, after seconds: Double = 2.5) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep \(seconds); tmux send-keys -t \(Self.shellQuote(pane)) -l \(Self.shellQuote(text))"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    /// Tells the top bar which mode (Agent / Code) the hub shows.
    func publishTab(_ name: String) {
        _ = try? tmux(["set-option", "-g", "@aw_tab", name])
        _ = try? tmux(["refresh-client", "-S"])
    }

    /// The hub's own window needs no title bar over its single pane.
    func hideOwnTitleBar() {
        guard let me = ProcessInfo.processInfo.environment["TMUX_PANE"] else { return }
        _ = try? tmux(["set-option", "-w", "-t", me, "pane-border-status", "off"])
    }

    /// Leaves the hub running in the background.
    func detach() {
        _ = try? tmux(["detach-client"])
    }

    // MARK: - Helpers

    @discardableResult
    private func tmux(_ arguments: [String]) throws -> String {
        guard Self.isInsideTmux else { throw Failure.notInTmux }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tmux"] + arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure.tmux(String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func shellQuote(_ value: String) -> String {
        if !value.isEmpty, value.allSatisfy({ $0.isLetter || $0.isNumber || "-_./=:@%+,".contains($0) }) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Which commands are on PATH, re-checked at most every 10 seconds (views
/// ask every frame).
enum InstalledCLIs {
    nonisolated(unsafe) private static var cache: (paths: [String: String], at: Date)?

    static func path(for provider: Provider) -> String? {
        path(forCommand: provider.command)
    }

    static func path(forCommand command: String) -> String? {
        if cache == nil || Date().timeIntervalSince(cache!.at) > 10 {
            cache = ([:], Date())
        }
        if let known = cache?.paths[command] { return known.isEmpty ? nil : known }
        let found = Provider.locate(command)
        cache?.paths[command] = found ?? ""
        return found
    }
}

/// Folders you've opened terminals in, most recent first.
enum RecentFolders {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/agentworld/recent.json")
    }

    static func load() -> [String] {
        guard let data = try? Data(contentsOf: url), let paths = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return paths.filter { FileManager.default.fileExists(atPath: $0) }
    }

    static func remember(_ path: String) {
        let paths = [path] + load().filter { $0 != path }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(Array(paths.prefix(8))).write(to: url)
    }
}
