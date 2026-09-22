import Foundation

/// Where a piece of configuration came from. Mirrors Claude Code's own scopes,
/// plus plugins and the agents built into Claude Code itself.
public enum ConfigScope: String, Sendable, Comparable {
    case project
    case local
    case user
    case plugin
    case builtin = "built-in"

    public static func < (lhs: ConfigScope, rhs: ConfigScope) -> Bool {
        lhs.order < rhs.order
    }

    private var order: Int {
        switch self {
        case .project: 0
        case .local: 1
        case .user: 2
        case .plugin: 3
        case .builtin: 4
        }
    }
}

/// A subagent declared in `.claude/agents/*.md`, a plugin, or built into Claude Code.
public struct AgentDefinition: Sendable, Hashable {
    public let name: String
    public let description: String?
    public let model: String?
    public let scope: ConfigScope
    /// Tools the agent may use; empty means "inherits every tool".
    public let tools: [String]
    /// Skills preloaded into the agent (`skills:` front matter).
    public let skills: [String]
    /// Owning plugin, for plugin agents.
    public let plugin: String?
    public let path: String?

    public init(
        name: String,
        description: String? = nil,
        model: String? = nil,
        scope: ConfigScope,
        tools: [String] = [],
        skills: [String] = [],
        plugin: String? = nil,
        path: String? = nil
    ) {
        self.name = name
        self.description = description
        self.model = model
        self.scope = scope
        self.tools = tools
        self.skills = skills
        self.plugin = plugin
        self.path = path
    }

    /// The name Claude Code knows it by (`plugin:agent` for plugin agents).
    public var qualifiedName: String { plugin.map { "\($0):\(name)" } ?? name }

    /// The subagents every Claude Code install ships with.
    public static let builtIns: [AgentDefinition] = [
        AgentDefinition(
            name: "general-purpose",
            description: "Researches complex questions, searches code and runs multi-step tasks on its own.",
            scope: .builtin
        ),
        AgentDefinition(
            name: "Explore",
            description: "Fast read-only search across the codebase: finds files, symbols and conventions and reports back.",
            model: "haiku",
            scope: .builtin,
            tools: ["Read", "Grep", "Glob", "Bash"]
        ),
        AgentDefinition(
            name: "Plan",
            description: "Software architect: designs an implementation plan, finds the critical files and weighs trade-offs.",
            scope: .builtin,
            tools: ["Read", "Grep", "Glob", "Bash"]
        ),
    ]
}

/// A skill declared in `.claude/skills/<name>/SKILL.md` or a plugin's `skills/`.
public struct SkillDefinition: Sendable, Hashable {
    public let name: String
    public let description: String?
    public let scope: ConfigScope
    public let plugin: String?
    public let path: String?
    /// Where it sits on the shelves: the `category:` front matter, else a guess.
    public let category: SkillCategory

    public init(name: String, description: String? = nil, scope: ConfigScope, plugin: String? = nil, path: String? = nil, category: String? = nil) {
        self.name = name
        self.description = description
        self.scope = scope
        self.plugin = plugin
        self.path = path
        self.category = category.flatMap(SkillCategory.named) ?? SkillCategory.guess(name: name, description: description, plugin: plugin)
    }

    /// One human sentence about what it does (descriptions are often written
    /// as triggers for the model: "Use this skill whenever…").
    public var summary: String? { description.map(SkillCategory.summarize) }

    /// How to invoke it: `/name`, or `/plugin:name` for plugin skills.
    public var qualifiedName: String { plugin.map { "\($0):\(name)" } ?? name }
}

/// A slash command declared in `.claude/commands/*.md` or a plugin's `commands/`.
public struct CommandDefinition: Sendable, Hashable {
    public let name: String
    public let description: String?
    public let scope: ConfigScope
    public let plugin: String?

    public init(name: String, description: String? = nil, scope: ConfigScope, plugin: String? = nil) {
        self.name = name
        self.description = description
        self.scope = scope
        self.plugin = plugin
    }

    public var qualifiedName: String { plugin.map { "\($0):\(name)" } ?? name }
}

/// An MCP server declared in `.mcp.json`, `~/.claude.json` or a plugin.
public struct MCPServerDefinition: Sendable, Hashable {
    public let name: String
    /// "stdio", "http", "sse"… as written in the config (stdio when omitted).
    public let transport: String
    public let scope: ConfigScope
    public let plugin: String?

    public init(name: String, transport: String, scope: ConfigScope, plugin: String? = nil) {
        self.name = name
        self.transport = transport
        self.scope = scope
        self.plugin = plugin
    }
}

/// An installed plugin and everything it contributes.
public struct PluginDefinition: Sendable, Hashable {
    public let name: String
    public let description: String?
    public let version: String?
    public let author: String?
    public let skills: [String]
    public let agents: [String]
    public let commands: [String]
    public let mcpServers: [String]
    public let hasHooks: Bool

    public init(
        name: String,
        description: String? = nil,
        version: String? = nil,
        author: String? = nil,
        skills: [String] = [],
        agents: [String] = [],
        commands: [String] = [],
        mcpServers: [String] = [],
        hasHooks: Bool = false
    ) {
        self.name = name
        self.description = description
        self.version = version
        self.author = author
        self.skills = skills
        self.agents = agents
        self.commands = commands
        self.mcpServers = mcpServers
        self.hasHooks = hasHooks
    }
}

/// What the repository itself tells us: its instructions for Claude and the
/// kind of project it is (used for suggestions before any prompt is sent).
public struct RepositoryProfile: Sendable, Hashable {
    /// The instructions file the CLI reads (CLAUDE.md, AGENTS.md…): the one
    /// found, or the one it would read when there's none yet.
    public var instructionsFile: String?
    /// Its first heading and a few lines, if it exists.
    public var instructionsTitle: String?
    public var instructionsExcerpt: [String]
    public var instructionsLines: Int
    /// Detected stacks ("swift", "node", "python"…), most significant first.
    public var stacks: [String]
    /// Top-level folders, excluding hidden and build output.
    public var folders: [String]
    /// Hook events configured for this project (settings.json / settings.local.json).
    public var hookEvents: [String]

    public init(
        instructionsFile: String? = nil,
        instructionsTitle: String? = nil,
        instructionsExcerpt: [String] = [],
        instructionsLines: Int = 0,
        stacks: [String] = [],
        folders: [String] = [],
        hookEvents: [String] = []
    ) {
        self.instructionsFile = instructionsFile
        self.instructionsTitle = instructionsTitle
        self.instructionsExcerpt = instructionsExcerpt
        self.instructionsLines = instructionsLines
        self.stacks = stacks
        self.folders = folders
        self.hookEvents = hookEvents
    }

    public var hasInstructions: Bool { instructionsLines > 0 }
}

/// Everything one agent CLI is set up with, for one project.
public struct AgentConfiguration: Sendable, Equatable {
    /// Default model from the CLI's settings, when it declares one.
    public var model: String?
    public var agents: [AgentDefinition]
    public var skills: [SkillDefinition]
    public var mcpServers: [MCPServerDefinition]
    public var commands: [CommandDefinition]
    public var plugins: [PluginDefinition]
    public var repository: RepositoryProfile

    public init(
        model: String? = nil,
        agents: [AgentDefinition] = [],
        skills: [SkillDefinition] = [],
        mcpServers: [MCPServerDefinition] = [],
        commands: [CommandDefinition] = [],
        plugins: [PluginDefinition] = [],
        repository: RepositoryProfile = RepositoryProfile()
    ) {
        self.model = model
        self.agents = agents
        self.skills = skills
        self.mcpServers = mcpServers
        self.commands = commands
        self.plugins = plugins
        self.repository = repository
    }

    public static let empty = AgentConfiguration()

    /// Agents you declared yourself (project/user/plugin), without built-ins.
    public var customAgents: [AgentDefinition] { agents.filter { $0.scope != .builtin } }
}
