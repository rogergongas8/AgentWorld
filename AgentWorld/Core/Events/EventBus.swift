import Combine
import Foundation

/// Shared stream of runtime events, decoupling `ClaudeRuntime` from whatever reacts to it.
@MainActor
final class EventBus: ObservableObject {
    private let subject = PassthroughSubject<AgentEvent, Never>()

    var publisher: AnyPublisher<AgentEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    func publish(_ kind: AgentEventKind) {
        subject.send(AgentEvent(kind: kind))
    }
}
