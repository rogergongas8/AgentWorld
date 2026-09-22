import Foundation

/// Live state of one character on stage: the main Claude session or a subagent.
public struct ActorState: Sendable, Equatable {
    public var status: ActorStatus
    /// Short description of the current action ("Edit SessionStore.swift").
    public var action: String?
    /// When `status` last changed (event time).
    public var since: Date

    public init(status: ActorStatus, action: String? = nil, since: Date) {
        self.status = status
        self.action = action
        self.since = since
    }
}

public struct Subagent: Sendable, Identifiable, Equatable {
    /// The `tool_use` id of the `Agent`/`Task` call that spawned it.
    public let id: String
    public let type: String
    public let description: String?
    public let startedAt: Date
    public var finishedAt: Date?
    public var state: ActorState
    public var toolCalls: Int = 0

    public var isRunning: Bool { finishedAt == nil }
}

public struct ToolStat: Sendable, Equatable {
    public let name: String
    public let kind: ToolKind
    public var count: Int
    public var errors: Int
    public var lastUsed: Date
}

public struct CapabilityUsage: Sendable, Equatable {
    public let name: String
    public var count: Int
    public var lastUsed: Date
    /// Latest detail: MCP tool name, or skill args.
    public var lastDetail: String?
}

public struct LogEntry: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case prompt
        case reply
        case tool(ToolKind)
        case toolError
        case subagentStarted
        case subagentFinished(failed: Bool)
        case turnEnded
        case interrupted
        case compacted
    }

    public let time: Date
    public let kind: Kind
    /// Who did it: nil for the main session, otherwise the subagent type.
    public let actor: String?
    public let text: String
}
