import Foundation

/// An agent declared in `.claude/agents`.
struct Agent: Identifiable, Hashable {
    let id: URL
    let name: String
    let description: String?
    let model: String?
    let path: URL
    let source: String
}

enum AgentStatus: String {
    case idle
    case thinking
    case reading
    case working
    case waiting
    case completed
    case error

    var title: String {
        switch self {
        case .idle: "En espera"
        case .thinking: "Pensando"
        case .reading: "Leyendo"
        case .working: "Trabajando"
        case .waiting: "Esperando"
        case .completed: "Completado"
        case .error: "Error"
        }
    }

    var symbolName: String {
        switch self {
        case .idle: "pause.circle.fill"
        case .thinking: "brain.head.profile"
        case .reading: "doc.text.magnifyingglass"
        case .working: "hammer.fill"
        case .waiting: "hourglass"
        case .completed: "checkmark.seal.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }
}
