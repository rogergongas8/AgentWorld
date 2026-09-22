import Foundation

/// Where a piece of configuration came from. Mirrors Claude Code's own scopes.
public enum ConfigScope: String, Sendable, Comparable {
    case project
    case local
    case user

    public static func < (lhs: ConfigScope, rhs: ConfigScope) -> Bool {
        lhs.order < rhs.order
    }

    private var order: Int {
        switch self {
        case .project: 0
        case .local: 1
        case .user: 2
        }
    }
}

/// A subagent declared in `.claude/agents/*.md`.
public struct AgentDefinition: Sendable, Hashable {
    public let name: String
    public let description: String?
    public let model: String?
    public let scope: ConfigScope
}

/// A skill declared in `.claude/skills/<name>/SKILL.md`.
public struct SkillDefinition: Sendable, Hashable {
    public let name: String
    public let description: String?
    public let scope: ConfigScope
}

/// An MCP server declared in `.mcp.json` or `~/.claude.json`.
public struct MCPServerDefinition: Sendable, Hashable {
    public let name: String
    /// "stdio", "http", "sse"… as written in the config (stdio when omitted).
    public let transport: String
    public let scope: ConfigScope
}

public struct ClaudeConfiguration: Sendable, Equatable {
    public var agents: [AgentDefinition]
    public var skills: [SkillDefinition]
    public var mcpServers: [MCPServerDefinition]

    public init(agents: [AgentDefinition] = [], skills: [SkillDefinition] = [], mcpServers: [MCPServerDefinition] = []) {
        self.agents = agents
        self.skills = skills
        self.mcpServers = mcpServers
    }

    public static let empty = ClaudeConfiguration()
}
