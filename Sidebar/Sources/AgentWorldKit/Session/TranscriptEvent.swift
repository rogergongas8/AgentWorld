import Foundation

/// One meaningful thing that happened in a transcript, already reduced from
/// Claude Code's raw JSONL into what the sidebar cares about.
public struct TranscriptEvent: Sendable {
    public let timestamp: Date?
    public let kind: Kind

    public init(timestamp: Date?, kind: Kind) {
        self.timestamp = timestamp
        self.kind = kind
    }

    public enum Kind: Sendable {
        /// Context fields carried on most lines (deduplicated by the store).
        case context(SessionContext)
        case userPrompt(String)
        case assistantText(String)
        case thinking
        case toolUse(ToolInvocation)
        case toolResult(id: String, isError: Bool)
        case usage(messageId: String?, TokenUsage)
        case turnEnded
        case interrupted
        case compacted
    }
}

public struct SessionContext: Sendable, Equatable {
    public var sessionId: String?
    public var model: String?
    public var gitBranch: String?
    public var version: String?
    public var permissionMode: String?

    public init(sessionId: String? = nil, model: String? = nil, gitBranch: String? = nil, version: String? = nil, permissionMode: String? = nil) {
        self.sessionId = sessionId
        self.model = model
        self.gitBranch = gitBranch
        self.version = version
        self.permissionMode = permissionMode
    }

    var isEmpty: Bool { self == SessionContext() }
}

public struct TokenUsage: Sendable, Equatable {
    public var input: Int
    public var cacheRead: Int
    public var cacheCreation: Int
    public var output: Int

    public init(input: Int = 0, cacheRead: Int = 0, cacheCreation: Int = 0, output: Int = 0) {
        self.input = input
        self.cacheRead = cacheRead
        self.cacheCreation = cacheCreation
        self.output = output
    }

    /// Tokens occupying the context window for this request.
    public var context: Int { input + cacheRead + cacheCreation }
}

/// A tool call, with the handful of input fields the sidebar displays
/// already extracted (raw `input` dictionaries aren't Sendable, nor needed).
public struct ToolInvocation: Sendable {
    public let id: String
    public let name: String
    public let kind: ToolKind
    /// One-line human summary: a file name, a command, a query…
    public let summary: String?
    /// For `Agent`/`Task`: which subagent and what for.
    public let subagentType: String?
    public let subagentDescription: String?
    /// For `Skill`.
    public let skillName: String?
    /// For `TodoWrite` (full replacement list).
    public let todos: [TodoItem]?
    /// For `TaskCreate`/`TaskUpdate` (incremental task list edits).
    public let taskEdit: TaskEdit?

    public init(id: String, name: String, summary: String? = nil, subagentType: String? = nil, subagentDescription: String? = nil, skillName: String? = nil, todos: [TodoItem]? = nil, taskEdit: TaskEdit? = nil) {
        self.id = id
        self.name = name
        self.kind = ToolKind(toolName: name)
        self.summary = summary
        self.subagentType = subagentType
        self.subagentDescription = subagentDescription
        self.skillName = skillName
        self.todos = todos
        self.taskEdit = taskEdit
    }
}

public struct TodoItem: Sendable, Equatable {
    public enum State: String, Sendable {
        case pending
        case inProgress = "in_progress"
        case completed
    }

    public var id: String
    public var content: String
    public var activeForm: String?
    public var state: State

    public init(id: String, content: String, activeForm: String? = nil, state: State) {
        self.id = id
        self.content = content
        self.activeForm = activeForm
        self.state = state
    }
}

public enum TaskEdit: Sendable, Equatable {
    case create(subject: String, activeForm: String?)
    case update(taskId: String, state: TodoItem.State?, subject: String?)
    case delete(taskId: String)
}
