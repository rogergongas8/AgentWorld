import AgentWorldKit
import Foundation

/// The hub's terminals, as tmux windows in the hub's own tmux server (the
/// `agentworld` shell command starts it with `tmux -L agentworld`). Each
/// window runs one agent CLI on the left and its AgentWorld sidebar on the
/// right; window options (`@aw_*`) remember which CLI and folder it is.
struct Workspace {
    struct Window: Equatable {
        let id: String
        let index: Int
        let name: String
        let provider: Provider?
        let cwd: String?
        let profile: String?
        let isActive: Bool
        /// When tmux last saw output in it.
        let lastActivity: Date?
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

    // MARK: - Queries

    func windows() -> [Window] {
        let format = ["#{window_id}", "#{window_index}", "#{window_name}", "#{@aw_provider}", "#{@aw_cwd}", "#{@aw_profile}", "#{window_active}", "#{window_activity}"]
            .joined(separator: "\t")
        guard let output = try? tmux(["list-windows", "-F", format]) else { return [] }
        return output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 8, let index = Int(fields[1]) else { return nil }
            return Window(
                id: fields[0],
                index: index,
                name: fields[2],
                provider: Provider.named(fields[3]),
                cwd: fields[4].isEmpty ? nil : fields[4],
                profile: fields[5].isEmpty ? nil : fields[5],
                isActive: fields[6] == "1",
                lastActivity: Double(fields[7]).map { Date(timeIntervalSince1970: $0) }
            )
        }
    }

    /// A session option the shell sets when you run `agentworld` from another
    /// folder, so the picker follows you.
    func requestedDirectory() -> String? {
        let value = try? tmux(["show-options", "-qv", "@aw_request_cwd"])
        return value.flatMap { $0.isEmpty ? nil : $0 }
    }

    func clearRequestedDirectory() {
        _ = try? tmux(["set-option", "-u", "@aw_request_cwd"])
    }

    // MARK: - Actions

    /// Opens a new window: the profile's CLI on the left, its sidebar on the
    /// right. Returns the new window's id.
    @discardableResult
    func launch(_ profile: LaunchProfile, executable: String, in directory: String) throws -> String {
        guard Self.isInsideTmux else { throw Failure.notInTmux }
        let provider = profile.provider

        var cliArguments = profile.args
        var sidebarArguments = ["--provider", provider.id, "--cwd", directory]
        // Pin Claude sessions so the sidebar follows exactly this conversation.
        let resumeFlags: Set<String> = ["-c", "--continue", "-r", "--resume", "--session-id", "--fork-session"]
        if provider.kind == .claude, !cliArguments.contains(where: { resumeFlags.contains($0.components(separatedBy: "=")[0]) }) {
            let sessionId = UUID().uuidString.lowercased()
            cliArguments = ["--session-id", sessionId] + cliArguments
            sidebarArguments += ["--session-id", sessionId]
        }

        // The window closes with the CLI; a failure waits so its message can be read
        // (`aw_status`, not `status`: that one is read-only in zsh).
        let cli = ([executable] + cliArguments).map(Self.shellQuote).joined(separator: " ")
        let command = """
        \(cli); aw_status=$?; if [ $aw_status -ne 0 ]; then printf '\\n[%s exited with %s, press enter]' \(Self.shellQuote(provider.name)) $aw_status; read _; fi; tmux kill-window -t "$TMUX_PANE"
        """
        let name = "\(provider.shortName) · \(URL(fileURLWithPath: directory).lastPathComponent)"

        var arguments = ["new-window", "-P", "-F", "#{window_id}", "-n", name, "-c", directory]
        for (key, value) in profile.env.sorted(by: { $0.key < $1.key }) { arguments += ["-e", "\(key)=\(value)"] }
        arguments.append(command)
        let windowId = try tmux(arguments).trimmingCharacters(in: .whitespacesAndNewlines)

        for (option, value) in [("@aw_provider", provider.id), ("@aw_cwd", directory), ("@aw_profile", profile.name)] {
            _ = try? tmux(["set-option", "-w", "-t", windowId, option, value])
        }
        _ = try? tmux(["set-option", "-w", "-t", windowId, "automatic-rename", "off"])

        let sidebar = ([sidebarBinary] + sidebarArguments).map(Self.shellQuote).joined(separator: " ")
        _ = try? tmux(["split-window", "-h", "-d", "-t", windowId, "-l", sidebarWidth, "-c", directory, sidebar])
        return windowId
    }

    func select(_ window: Window) {
        _ = try? tmux(["select-window", "-t", window.id])
    }

    func close(_ window: Window) {
        _ = try? tmux(["kill-window", "-t", window.id])
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
