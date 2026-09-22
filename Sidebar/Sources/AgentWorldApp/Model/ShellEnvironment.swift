import AgentWorldKit
import Foundation

/// The user's real shell environment. An app opened from the Finder or the
/// Dock gets a bare PATH, so the CLIs (claude, codex…) wouldn't be found; we
/// ask the login shell once for its environment and use that everywhere.
enum ShellEnvironment {
    static let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

    /// Captured at launch; falls back to this process's environment.
    nonisolated(unsafe) private(set) static var variables = ProcessInfo.processInfo.environment

    static func load() {
        let marker = "__AGENTWORLD_ENV__"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-i", "-c", "printf '\\n\(marker)\\n'; /usr/bin/env"]
        var environment = ProcessInfo.processInfo.environment
        // Our own zsh integration must stay out of the way inside the app.
        environment["AGENTWORLD_DISABLE"] = "1"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }

        // Don't hang forever on an unusual shell config.
        let deadline = Date().addingTimeInterval(6)
        while process.isRunning, Date() < deadline { usleep(20_000) }
        if process.isRunning { process.terminate(); return }

        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard let range = text.range(of: marker + "\n") else { return }
        var captured: [String: String] = [:]
        for line in text[range.upperBound...].split(separator: "\n") {
            guard let equals = line.firstIndex(of: "="), line[..<equals].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { continue }
            captured[String(line[..<equals])] = String(line[line.index(after: equals)...])
        }
        if captured["PATH"] != nil { variables = captured }
    }

    /// Environment for a terminal inside the app.
    /// `extra` carries the pane's `agentworld-ctl` handles; the app's own
    /// folder goes first on PATH so `agentworld-ctl` is always there.
    static func forTerminal(extra: [String: String] = [:]) -> [String] {
        var environment = variables.merging(extra) { _, new in new }
        if let tools = Bundle.main.executableURL?.deletingLastPathComponent().path {
            environment["PATH"] = tools + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        }
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "AgentWorld"
        environment["AGENTWORLD_DISABLE"] = "1"
        environment["LANG"] = environment["LANG"] ?? "en_US.UTF-8"
        return environment.map { "\($0.key)=\($0.value)" }
    }

    static func locate(_ command: String) -> String? {
        Provider.locate(command, environment: variables)
    }

    static func quote(_ value: String) -> String {
        if !value.isEmpty, value.allSatisfy({ $0.isLetter || $0.isNumber || "-_./=:@%+,".contains($0) }) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Folders you've opened terminals in, most recent first (shared with the
/// terminal hub through the same file).
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
        try? JSONEncoder().encode(Array(paths.prefix(12))).write(to: url)
    }

    static func forget(_ path: String) {
        try? JSONEncoder().encode(load().filter { $0 != path }).write(to: url)
    }
}
