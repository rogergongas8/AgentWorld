import Foundation

/// An agent CLI AgentWorld can host: Claude Code, Codex, Gemini, Kimi, Grok…
/// Each has its own config layout (read by `ProviderScanner`) and character.
public struct Provider: Sendable, Hashable, Identifiable {
    public enum Kind: String, CaseIterable, Sendable {
        case claude, codex, gemini, kimi, grok, opencode, cursor
        /// A plain shell: no agent, just a terminal in the workspace.
        case terminal
    }

    public let kind: Kind
    public let name: String
    /// Executable to run.
    public let command: String
    public let tagline: String
    /// Files the CLI reads as repository instructions, in priority order.
    public let instructionsFiles: [String]
    /// How to install it, when we're confident of the official way.
    public let installHint: String?
    /// Whether AgentWorld can follow its sessions live (activity, subagents).
    public let followsLiveSessions: Bool

    public var id: String { kind.rawValue }

    public static let claude = Provider(
        kind: .claude, name: "Claude Code", command: "claude",
        tagline: "Anthropic's coding agent",
        instructionsFiles: ["CLAUDE.md", ".claude/CLAUDE.md"],
        installHint: "curl -fsSL https://claude.ai/install.sh | bash",
        followsLiveSessions: true
    )
    public static let codex = Provider(
        kind: .codex, name: "Codex", command: "codex",
        tagline: "OpenAI's coding agent",
        instructionsFiles: ["AGENTS.md"],
        installHint: "npm install -g @openai/codex",
        followsLiveSessions: false
    )
    public static let gemini = Provider(
        kind: .gemini, name: "Gemini CLI", command: "gemini",
        tagline: "Google's coding agent",
        instructionsFiles: ["GEMINI.md", "AGENTS.md"],
        installHint: "npm install -g @google/gemini-cli",
        followsLiveSessions: false
    )
    public static let kimi = Provider(
        kind: .kimi, name: "Kimi CLI", command: "kimi",
        tagline: "Moonshot AI's coding agent",
        instructionsFiles: ["AGENTS.md"],
        installHint: "uv tool install kimi-cli",
        followsLiveSessions: false
    )
    public static let grok = Provider(
        kind: .grok, name: "Grok CLI", command: "grok",
        tagline: "xAI's Grok in the terminal",
        instructionsFiles: ["GROK.md", "AGENTS.md"],
        installHint: nil,
        followsLiveSessions: false
    )

    public static let opencode = Provider(
        kind: .opencode, name: "OpenCode", command: "opencode",
        tagline: "Open-source coding agent",
        instructionsFiles: ["AGENTS.md"],
        installHint: "npm install -g opencode-ai",
        followsLiveSessions: false
    )
    public static let cursor = Provider(
        kind: .cursor, name: "Cursor Agent", command: "cursor-agent",
        tagline: "Cursor's agent in the terminal",
        instructionsFiles: ["AGENTS.md", ".cursorrules"],
        installHint: "curl https://cursor.com/install -fsS | bash",
        followsLiveSessions: false
    )
    public static let terminal = Provider(
        kind: .terminal, name: "Terminal", command: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        tagline: "A plain shell in this workspace",
        instructionsFiles: [],
        installHint: nil,
        followsLiveSessions: false
    )

    public static let all: [Provider] = [.claude, .codex, .gemini, .kimi, .grok, .opencode, .cursor, .terminal]

    /// Whether it's an agent CLI (everything but the plain terminal).
    public var isAgent: Bool { kind != .terminal }

    public static func named(_ id: String) -> Provider? {
        all.first { $0.id == id.lowercased() }
    }

    /// Full path of `command` on PATH (plus the usual install locations
    /// PATH sometimes misses), or nil when it isn't installed.
    public static func locate(_ command: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if command.contains("/") {
            return FileManager.default.isExecutableFile(atPath: command) ? command : nil
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.cargo/bin"]
        for directory in path where !directory.isEmpty {
            let candidate = (directory as NSString).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}

/// A saved way to open a terminal: which CLI, with which flags and
/// environment. The defaults are one plain profile per provider; people add
/// their own in `~/.config/agentworld/profiles.json`, e.g.
///
///     [{ "name": "Claude · Opus plan", "provider": "claude",
///        "args": ["--model", "opus", "--permission-mode", "plan"] },
///      { "name": "Codex high", "provider": "codex",
///        "args": ["-c", "model_reasoning_effort=high"], "env": {"FOO": "1"} }]
public struct LaunchProfile: Sendable, Hashable, Identifiable {
    public let name: String
    public let provider: Provider
    /// Overrides the provider's executable (a wrapper script, another path).
    public let command: String?
    public let args: [String]
    public let env: [String: String]
    public let isCustom: Bool

    public var id: String { (isCustom ? "custom:" : "") + name }
    public var executable: String { command ?? provider.command }

    public init(name: String, provider: Provider, command: String? = nil, args: [String] = [], env: [String: String] = [:], isCustom: Bool = false) {
        self.name = name
        self.provider = provider
        self.command = command
        self.args = args
        self.env = env
        self.isCustom = isCustom
    }

    public static let defaults: [LaunchProfile] = Provider.all.map { LaunchProfile(name: $0.name, provider: $0) }

    /// `~/.config/agentworld/profiles.json`, or `$AGENTWORLD_PROFILES`.
    public static var configURL: URL {
        if let path = ProcessInfo.processInfo.environment["AGENTWORLD_PROFILES"] { return URL(fileURLWithPath: path) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/agentworld/profiles.json")
    }

    /// Defaults followed by the custom profiles in `url`. Malformed entries
    /// are skipped rather than failing the whole file.
    public static func load(from url: URL = configURL) -> [LaunchProfile] {
        guard let data = try? Data(contentsOf: url),
              let entries = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return defaults }
        let custom = entries.compactMap { entry -> LaunchProfile? in
            guard let name = entry["name"] as? String,
                  let provider = (entry["provider"] as? String).flatMap(Provider.named) else { return nil }
            return LaunchProfile(
                name: name,
                provider: provider,
                command: entry["command"] as? String,
                args: entry["args"] as? [String] ?? [],
                env: entry["env"] as? [String: String] ?? [:],
                isCustom: true
            )
        }
        return defaults + custom
    }
}
