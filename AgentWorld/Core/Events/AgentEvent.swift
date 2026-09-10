import Foundation

enum AgentEventKind {
    case status(AgentStatus)
    case activity(ClaudeRuntimeActivity)
    case agentActivated(name: String)
}

struct AgentEvent: Identifiable {
    let id = UUID()
    let kind: AgentEventKind
    let timestamp = Date()
}
