import Foundation

/// Turns Claude Code JSONL lines (the on-disk transcript under
/// `~/.claude/projects/<slug>/<sessionId>.jsonl`, and `stream-json`) into
/// `TranscriptEvent`s.
///
/// The on-disk format carries many bookkeeping `type`s (attachment, mode,
/// file-history-*, queue-operation, custom-title…); they're ignored through
/// `default` rather than enumerated, since new ones appear regularly.
public struct TranscriptParser: Sendable {
    /// Used to shorten absolute paths in summaries.
    public let cwd: String

    public init(cwd: String) {
        self.cwd = cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd
    }

    public func parse(line: String) -> [TranscriptEvent] {
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = object["type"] as? String else { return [] }

        let timestamp = (object["timestamp"] as? String).flatMap(Self.parseDate)
        var kinds: [TranscriptEvent.Kind] = []

        var context = SessionContext(
            sessionId: object["sessionId"] as? String,
            gitBranch: (object["gitBranch"] as? String).flatMap { $0.isEmpty || $0 == "HEAD" ? nil : $0 },
            version: object["version"] as? String,
            permissionMode: object["permissionMode"] as? String
        )

        switch type {
        case "assistant":
            let message = object["message"] as? [String: Any] ?? [:]
            if let model = message["model"] as? String, model != "<synthetic>" { context.model = model }
            kinds += assistantKinds(message)

        case "user":
            // Subagent "prompts" and injected meta messages aren't the user talking.
            if object["isMeta"] as? Bool == true { break }
            kinds += userKinds(object["message"] as? [String: Any] ?? [:])

        case "system":
            switch object["subtype"] as? String {
            case "turn_duration": kinds.append(.turnEnded)
            case "compact_boundary": kinds.append(.compacted)
            case "init":
                if let model = object["model"] as? String { context.model = model }
            default: break
            }

        case "result":
            kinds.append(.turnEnded)

        default:
            break
        }

        if !context.isEmpty { kinds.insert(.context(context), at: 0) }
        return kinds.map { TranscriptEvent(timestamp: timestamp, kind: $0) }
    }

    // MARK: - Assistant

    private func assistantKinds(_ message: [String: Any]) -> [TranscriptEvent.Kind] {
        var kinds: [TranscriptEvent.Kind] = []
        for block in message["content"] as? [[String: Any]] ?? [] {
            switch block["type"] as? String {
            case "text":
                if let text = block["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    kinds.append(.assistantText(text))
                }
            case "thinking", "redacted_thinking":
                kinds.append(.thinking)
            case "tool_use", "server_tool_use":
                if let invocation = toolInvocation(block) { kinds.append(.toolUse(invocation)) }
            default:
                break
            }
        }

        if let usage = message["usage"] as? [String: Any] {
            kinds.append(.usage(messageId: message["id"] as? String, TokenUsage(
                input: usage["input_tokens"] as? Int ?? 0,
                cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
                cacheCreation: usage["cache_creation_input_tokens"] as? Int ?? 0,
                output: usage["output_tokens"] as? Int ?? 0
            )))
        }
        if message["stop_reason"] as? String == "end_turn" {
            kinds.append(.turnEnded)
        }
        return kinds
    }

    private func toolInvocation(_ block: [String: Any]) -> ToolInvocation? {
        guard let id = block["id"] as? String, let name = block["name"] as? String else { return nil }
        let input = block["input"] as? [String: Any] ?? [:]
        return ToolInvocation(
            id: id,
            name: name,
            summary: summary(forTool: name, input: input),
            subagentType: input["subagent_type"] as? String ?? (ToolKind(toolName: name) == .agent && name != "SendMessage" ? "general-purpose" : nil),
            subagentDescription: input["description"] as? String,
            skillName: name == "Skill" ? (input["skill"] as? String ?? input["command"] as? String) : nil,
            todos: name == "TodoWrite" ? todos(from: input) : nil,
            taskEdit: taskEdit(forTool: name, input: input)
        )
    }

    private func summary(forTool name: String, input: [String: Any]) -> String? {
        if let path = input["file_path"] as? String ?? input["notebook_path"] as? String {
            return shortPath(path)
        }
        if let command = input["command"] as? String {
            return firstLine(command)
        }
        if let pattern = input["pattern"] as? String {
            return pattern
        }
        if let url = input["url"] as? String {
            return URL(string: url)?.host ?? url
        }
        if let query = input["query"] as? String {
            return firstLine(query)
        }
        if let description = input["description"] as? String {
            return firstLine(description)
        }
        if let skill = input["skill"] as? String {
            return skill
        }
        if let subject = input["subject"] as? String {
            return firstLine(subject)
        }
        if let todos = input["todos"] as? [Any] {
            return "\(todos.count) tasks"
        }
        // MCP & unknown tools: show the first short string argument.
        return input.sorted { $0.key < $1.key }
            .compactMap { $0.value as? String }
            .first { !$0.isEmpty && $0.count < 120 }
            .map(firstLine)
    }

    private func todos(from input: [String: Any]) -> [TodoItem] {
        (input["todos"] as? [[String: Any]] ?? []).enumerated().compactMap { index, todo in
            guard let content = todo["content"] as? String else { return nil }
            return TodoItem(
                id: todo["id"] as? String ?? String(index + 1),
                content: content,
                activeForm: todo["activeForm"] as? String,
                state: (todo["status"] as? String).flatMap(TodoItem.State.init(rawValue:)) ?? .pending
            )
        }
    }

    private func taskEdit(forTool name: String, input: [String: Any]) -> TaskEdit? {
        switch name {
        case "TaskCreate":
            guard let subject = input["subject"] as? String else { return nil }
            return .create(subject: subject, activeForm: input["activeForm"] as? String)
        case "TaskUpdate":
            guard let taskId = (input["taskId"] as? String) ?? (input["taskId"] as? Int).map(String.init) else { return nil }
            let status = input["status"] as? String
            if status == "deleted" { return .delete(taskId: taskId) }
            return .update(taskId: taskId, state: status.flatMap(TodoItem.State.init(rawValue:)), subject: input["subject"] as? String)
        default:
            return nil
        }
    }

    // MARK: - User

    private func userKinds(_ message: [String: Any]) -> [TranscriptEvent.Kind] {
        if let text = message["content"] as? String {
            return promptKinds(text)
        }

        var kinds: [TranscriptEvent.Kind] = []
        for block in message["content"] as? [[String: Any]] ?? [] {
            switch block["type"] as? String {
            case "tool_result":
                if let id = block["tool_use_id"] as? String {
                    kinds.append(.toolResult(id: id, isError: block["is_error"] as? Bool ?? false))
                }
            case "text":
                kinds += promptKinds(block["text"] as? String ?? "")
            default:
                break
            }
        }
        return kinds
    }

    private func promptKinds(_ text: String) -> [TranscriptEvent.Kind] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        if trimmed.hasPrefix("[Request interrupted") { return [.interrupted] }
        // Slash-command plumbing and local command output, not a real prompt.
        if trimmed.hasPrefix("<local-command") || trimmed.hasPrefix("<command-") || trimmed.hasPrefix("<system-reminder>") {
            if let name = Self.commandName(in: trimmed) { return [.userPrompt(name)] }
            return []
        }
        return [.userPrompt(firstLine(trimmed))]
    }

    private static func commandName(in text: String) -> String? {
        guard let start = text.range(of: "<command-name>"),
              let end = text.range(of: "</command-name>", range: start.upperBound..<text.endIndex) else { return nil }
        return String(text[start.upperBound..<end.lowerBound])
    }

    // MARK: - Helpers

    func shortPath(_ path: String) -> String {
        if path.hasPrefix(cwd + "/") { return String(path.dropFirst(cwd.count + 1)) }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home + "/") { return "~/" + path.dropFirst(home.count + 1) }
        return path
    }

    private func firstLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.trimmingCharacters(in: .whitespaces)
    }

    nonisolated(unsafe) private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let plainFormatter = ISO8601DateFormatter()

    static func parseDate(_ string: String) -> Date? {
        fractionalFormatter.date(from: string) ?? plainFormatter.date(from: string)
    }
}
