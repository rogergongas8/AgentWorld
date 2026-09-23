import Foundation

/// Folds `TranscriptEvent`s from the main transcript and its subagent
/// transcripts into the state the sidebar renders. Pure state machine: no I/O,
/// no timers, so it's fully unit-testable.
public final class SessionStore {
    public enum Source: Equatable {
        case main
        /// A subagent's own transcript, keyed by the spawning tool_use id.
        case subagent(String)
    }

    public private(set) var context = SessionContext()
    public private(set) var main: ActorState
    public private(set) var subagents: [Subagent] = []
    public private(set) var todos: [TodoItem] = []
    public private(set) var toolStats: [String: ToolStat] = [:]
    public private(set) var mcpUsage: [String: CapabilityUsage] = [:]
    public private(set) var skillUsage: [String: CapabilityUsage] = [:]
    public private(set) var log: [LogEntry] = []
    public private(set) var lastUsage: TokenUsage?
    public private(set) var outputTokens = 0
    public private(set) var startedAt: Date?
    public private(set) var lastEventAt: Date?
    public private(set) var turns = 0
    /// Last time any actor hit a tool error, for a brief on-stage reaction.
    public private(set) var lastErrorAt: Date?
    /// Files the session (or its helpers) edited, full paths, for the app's
    /// Changes: exactly who touched what.
    public private(set) var editedFiles: Set<String> = []

    private var pendingMainTools: [String: ToolInvocation] = [:]
    private var countedMessageIds = Set<String>()
    private var nextTaskId = 1
    private let logLimit: Int

    public init(now: Date = Date(), logLimit: Int = 300) {
        main = ActorState(status: .idle, since: now)
        self.logLimit = logLimit
    }

    public var runningSubagents: [Subagent] { subagents.filter(\.isRunning) }

    public var totalToolCalls: Int { toolStats.values.reduce(0) { $0 + $1.count } }

    // MARK: - Applying events

    public func apply(_ event: TranscriptEvent, from source: Source = .main) {
        let time = event.timestamp ?? lastEventAt ?? Date()
        if startedAt == nil, source == .main, let timestamp = event.timestamp { startedAt = timestamp }
        if case .context = event.kind {} else { lastEventAt = max(lastEventAt ?? time, time) }

        switch source {
        case .main: applyMain(event.kind, at: time)
        case .subagent(let id): applySubagent(id: id, event.kind, at: time)
        }
    }

    private func applyMain(_ kind: TranscriptEvent.Kind, at time: Date) {
        switch kind {
        case .context(let incoming):
            // Keep the first session id: after /clear the locator switches
            // files and a fresh store is created anyway.
            if context.sessionId == nil { context.sessionId = incoming.sessionId }
            context.model = incoming.model ?? context.model
            context.gitBranch = incoming.gitBranch ?? context.gitBranch
            context.version = incoming.version ?? context.version
            context.permissionMode = incoming.permissionMode ?? context.permissionMode

        case .userPrompt(let text):
            turns += 1
            setMain(.thinking, action: "Reading your prompt", at: time)
            append(.prompt, actor: nil, text: text, at: time)

        case .assistantText(let text):
            if pendingMainTools.isEmpty { setMain(.thinking, action: "Writing a reply", at: time) }
            append(.reply, actor: nil, text: text, at: time)

        case .thinking:
            if pendingMainTools.isEmpty { setMain(.thinking, action: "Thinking", at: time) }

        case .toolUse(let tool):
            pendingMainTools[tool.id] = tool
            record(tool, actor: nil, at: time)
            if tool.kind == .agent, let type = tool.subagentType {
                subagents.append(Subagent(
                    id: tool.id,
                    type: type,
                    description: tool.subagentDescription,
                    startedAt: time,
                    state: ActorState(status: .thinking, action: tool.subagentDescription, since: time)
                ))
                append(.subagentStarted, actor: type, text: tool.subagentDescription ?? "Started", at: time)
            }
            setMain(tool.kind.activeStatus, action: Self.actionText(for: tool), at: time)

        case .toolResult(let id, let isError):
            let tool = pendingMainTools.removeValue(forKey: id)
            if let index = subagents.firstIndex(where: { $0.id == id }) {
                subagents[index].finishedAt = time
                subagents[index].state = ActorState(status: isError ? .failed : .done, action: nil, since: time)
                append(.subagentFinished(failed: isError), actor: subagents[index].type, text: isError ? "Failed" : "Finished", at: time)
            }
            if isError, let tool {
                toolStats[tool.name]?.errors += 1
                lastErrorAt = time
                append(.toolError, actor: nil, text: "\(tool.name) failed", at: time)
            }
            if let still = pendingMainTools.values.first {
                setMain(still.kind.activeStatus, action: Self.actionText(for: still), at: time)
            } else {
                setMain(.thinking, action: "Reviewing results", at: time)
            }

        case .usage(let messageId, let usage):
            lastUsage = usage
            if let messageId {
                if countedMessageIds.insert(messageId).inserted { outputTokens += usage.output }
            } else {
                outputTokens += usage.output
            }

        case .turnEnded:
            guard main.status != .waitingForUser else { return }
            pendingMainTools.removeAll()
            finishDanglingSubagents(at: time)
            setMain(.waitingForUser, action: nil, at: time)
            append(.turnEnded, actor: nil, text: "Your turn", at: time)

        case .interrupted:
            pendingMainTools.removeAll()
            finishDanglingSubagents(at: time)
            setMain(.waitingForUser, action: "Interrupted", at: time)
            append(.interrupted, actor: nil, text: "Interrupted", at: time)

        case .compacted:
            append(.compacted, actor: nil, text: "Context compacted", at: time)
        }
    }

    private func applySubagent(id: String, _ kind: TranscriptEvent.Kind, at time: Date) {
        guard let index = subagents.firstIndex(where: { $0.id == id }) else { return }
        // When replaying history the spawning call may already be finished;
        // still count its work, just don't bring it back to life.
        if case .toolUse(let tool) = kind {
            subagents[index].toolCalls += 1
            record(tool, actor: subagents[index].type, at: time)
        }
        guard subagents[index].isRunning else { return }

        switch kind {
        case .toolUse(let tool):
            subagents[index].state = ActorState(status: tool.kind.activeStatus, action: Self.actionText(for: tool), since: time)
        case .toolResult(_, let isError):
            if isError { lastErrorAt = time }
            subagents[index].state = ActorState(status: .thinking, action: "Reviewing results", since: time)
        case .assistantText, .thinking:
            subagents[index].state = ActorState(status: .thinking, action: subagents[index].state.action, since: time)
        default:
            break
        }
    }

    // MARK: - Helpers

    private func record(_ tool: ToolInvocation, actor: String?, at time: Date) {
        if let path = tool.editedPath { editedFiles.insert(path) }
        toolStats[tool.name, default: ToolStat(name: tool.name, kind: tool.kind, count: 0, errors: 0, lastUsed: time)].count += 1
        toolStats[tool.name]?.lastUsed = time

        if case .mcp(let server, let toolName) = tool.kind {
            mcpUsage[server, default: CapabilityUsage(name: server, count: 0, lastUsed: time)].count += 1
            mcpUsage[server]?.lastUsed = time
            mcpUsage[server]?.lastDetail = toolName
        }
        if let skill = tool.skillName {
            skillUsage[skill, default: CapabilityUsage(name: skill, count: 0, lastUsed: time)].count += 1
            skillUsage[skill]?.lastUsed = time
        }
        if let todos = tool.todos {
            self.todos = todos
        }
        if let edit = tool.taskEdit {
            applyTaskEdit(edit)
        }

        // Agent spawns get their own, richer log line.
        if tool.kind != .agent {
            append(.tool(tool.kind), actor: actor, text: Self.actionText(for: tool), at: time)
        }
    }

    private func applyTaskEdit(_ edit: TaskEdit) {
        switch edit {
        case .create(let subject, let activeForm):
            todos.append(TodoItem(id: String(nextTaskId), content: subject, activeForm: activeForm, state: .pending))
            nextTaskId += 1
        case .update(let taskId, let state, let subject):
            guard let index = todos.firstIndex(where: { $0.id == taskId }) else { return }
            if let state { todos[index].state = state }
            if let subject { todos[index].content = subject }
        case .delete(let taskId):
            todos.removeAll { $0.id == taskId }
        }
    }

    private func finishDanglingSubagents(at time: Date) {
        for index in subagents.indices where subagents[index].isRunning {
            subagents[index].finishedAt = time
            subagents[index].state = ActorState(status: .done, since: time)
        }
    }

    private func setMain(_ status: ActorStatus, action: String?, at time: Date) {
        if status != main.status { main.since = time }
        main.status = status
        main.action = action
    }

    private func append(_ kind: LogEntry.Kind, actor: String?, text: String, at time: Date) {
        // Subagent transcripts are read after the main one, so keep the log
        // chronological by inserting from the end (almost always a plain append).
        var index = log.endIndex
        while index > log.startIndex, log[index - 1].time > time { index -= 1 }
        log.insert(LogEntry(time: time, kind: kind, actor: actor, text: text), at: index)
        if log.count > logLimit { log.removeFirst(log.count - logLimit) }
    }

    static func actionText(for tool: ToolInvocation) -> String {
        let verb: String
        switch tool.kind {
        case .mcp(let server, let toolName): return "\(server) · \(toolName)"
        case .skill: return "Skill \(tool.skillName ?? "")"
        case .agent: return "\(tool.subagentType ?? "Agent"): \(tool.subagentDescription ?? "")"
        default: verb = tool.name
        }
        guard let summary = tool.summary, !summary.isEmpty else { return verb }
        return "\(verb) \(summary)"
    }
}
