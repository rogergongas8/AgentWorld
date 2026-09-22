import Foundation

/// Coarse category of a Claude Code tool, which drives both the character's
/// animation and the colors/icons used across the sidebar.
public enum ToolKind: Sendable, Hashable {
    case read
    case search
    case edit
    case shell
    case web
    case agent
    case skill
    case todo
    case question
    case plan
    case mcp(server: String, tool: String)
    case other

    public init(toolName name: String) {
        if name.hasPrefix("mcp__") {
            let parts = name.dropFirst("mcp__".count).components(separatedBy: "__")
            let server = MCPName.displayName(forServerKey: parts.first ?? "mcp")
            self = .mcp(server: server, tool: parts.dropFirst().joined(separator: "__"))
            return
        }
        switch name {
        case "Read", "NotebookRead": self = .read
        case "Glob", "Grep", "LS", "ToolSearch", "ListMcpResourcesTool", "ReadMcpResourceTool": self = .search
        case "Edit", "MultiEdit", "Write", "NotebookEdit": self = .edit
        case "Bash", "BashOutput", "KillShell", "KillBash", "Monitor", "TaskStop": self = .shell
        case "WebFetch", "WebSearch": self = .web
        case "Agent", "Task", "SendMessage": self = .agent
        case "Skill": self = .skill
        case "TodoWrite", "TaskCreate", "TaskUpdate", "TaskList", "TaskGet": self = .todo
        case "AskUserQuestion": self = .question
        case "EnterPlanMode", "ExitPlanMode": self = .plan
        default: self = .other
        }
    }

    /// The status an actor shows while running a tool of this kind.
    public var activeStatus: ActorStatus {
        switch self {
        case .read, .search: .reading
        case .edit: .editing
        case .shell: .running
        case .web: .browsing
        case .agent: .delegating
        case .question: .waitingForUser
        case .skill, .todo, .plan: .thinking
        case .mcp, .other: .usingTool
        }
    }
}

public enum MCPName {
    /// Turns tool-name server keys into something readable:
    /// `claude_ai_Google_Drive` → `Google Drive`, `plugin_figma_figma` → `figma`.
    public static func displayName(forServerKey key: String) -> String {
        if key.hasPrefix("claude_ai_") {
            return key.dropFirst("claude_ai_".count).replacingOccurrences(of: "_", with: " ")
        }
        if key.hasPrefix("plugin_") {
            let parts = key.dropFirst("plugin_".count).split(separator: "_")
            if let last = parts.last { return String(last) }
        }
        return key
    }
}

/// What the actor is doing right now.
public enum ActorStatus: String, Sendable, CaseIterable {
    case idle
    case thinking
    case reading
    case editing
    case running
    case browsing
    case usingTool
    case delegating
    case waitingForUser
    case done
    case failed

    public var title: String {
        switch self {
        case .idle: "Idle"
        case .thinking: "Thinking"
        case .reading: "Reading"
        case .editing: "Editing"
        case .running: "Running"
        case .browsing: "Browsing"
        case .usingTool: "Using tool"
        case .delegating: "Delegating"
        case .waitingForUser: "Your turn"
        case .done: "Done"
        case .failed: "Failed"
        }
    }

    public var isBusy: Bool {
        switch self {
        case .idle, .waitingForUser, .done, .failed: false
        default: true
        }
    }
}
