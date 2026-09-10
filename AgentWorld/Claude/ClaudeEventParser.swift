import Foundation

struct ClaudeRuntimeActivity: Identifiable {
    let id = UUID()
    let title: String
    let detail: String?
    let timestamp = Date()
}

enum ClaudeRuntimeSignal {
    case status(AgentStatus)
    case activity(ClaudeRuntimeActivity)
    case agentActivated(name: String)
}

/// Translates Claude Code's JSONL output into the small set of UI events AgentWorld needs.
struct ClaudeEventParser {
    func parse(line: String) -> [ClaudeRuntimeSignal] {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return []
        }

        switch type {
        case "system":
            guard object["subtype"] as? String == "init" else { return [] }
            return [.status(.thinking), .activity(.init(title: "Sesión iniciada", detail: nil))]

        case "assistant":
            return assistantSignals(from: object)

        case "user":
            return [.status(.waiting), .activity(.init(title: "Herramienta finalizada", detail: nil))]

        case "result":
            let failed = object["is_error"] as? Bool ?? false
            let summary = object["result"] as? String
            return [
                .status(failed ? .error : .completed),
                .activity(.init(title: failed ? "La sesión terminó con un error" : "Trabajo completado", detail: summary))
            ]

        case "stream_event":
            return streamEventSignals(from: object)

        default:
            return []
        }
    }

    private func assistantSignals(from object: [String: Any]) -> [ClaudeRuntimeSignal] {
        guard let message = object["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            return [.status(.thinking)]
        }

        var signals: [ClaudeRuntimeSignal] = []
        for block in content {
            if block["type"] as? String == "tool_use", let name = block["name"] as? String {
                signals.append(.status(status(forToolNamed: name)))
                signals.append(.activity(.init(title: "Usando \(name)", detail: toolDetail(from: block))))
                if name == "Task",
                   let input = block["input"] as? [String: Any],
                   let subagentType = input["subagent_type"] as? String {
                    signals.append(.agentActivated(name: subagentType))
                }
            } else if block["type"] as? String == "text", let text = block["text"] as? String, !text.isEmpty {
                signals.append(.status(.thinking))
                signals.append(.activity(.init(title: "Claude está respondiendo", detail: text)))
            }
        }
        return signals
    }

    private func streamEventSignals(from object: [String: Any]) -> [ClaudeRuntimeSignal] {
        guard let event = object["event"] as? [String: Any],
              event["type"] as? String == "content_block_start",
              let block = event["content_block"] as? [String: Any],
              block["type"] as? String == "tool_use",
              let name = block["name"] as? String else {
            return []
        }

        return [
            .status(status(forToolNamed: name)),
            .activity(.init(title: "Preparando \(name)", detail: nil))
        ]
    }

    private func status(forToolNamed name: String) -> AgentStatus {
        switch name.lowercased() {
        case "read", "glob", "grep": .reading
        case "edit", "write", "bash": .working
        default: .thinking
        }
    }

    private func toolDetail(from block: [String: Any]) -> String? {
        guard let input = block["input"] as? [String: Any] else { return nil }
        return input["file_path"] as? String ?? input["path"] as? String ?? input["command"] as? String
    }
}
