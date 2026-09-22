import Combine
import Foundation

/// Watches the real `claude` session already running for a project (in the
/// user's own terminal) by tailing the transcript Claude Code writes to
/// `~/.claude/projects/<slug>/<sessionId>.jsonl` — as opposed to `ClaudeRuntime`,
/// which launches and owns its own subprocess. This is what drives the live
/// character window: it reflects whatever is actually happening in the
/// terminal, not a session the app started itself.
@MainActor
final class LiveSessionObserver: ObservableObject {
    @Published private(set) var status: AgentStatus = .idle
    @Published private(set) var activeAgentName: String?
    @Published private(set) var activities: [ClaudeRuntimeActivity] = []
    @Published private(set) var connectionMessage: String?

    private let parser = ClaudeEventParser()
    private let tailer = TranscriptTailer()
    private var locator: TranscriptLocator?
    private var pollTimer: Timer?
    private var locateTimer: Timer?
    private let activityLimit = 30

    func start(projectURL: URL) {
        stop()
        locator = TranscriptLocator(
            cwd: projectURL.path,
            projectsRoot: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
        )
        connectionMessage = "Buscando la sesión de Claude Code para este proyecto…"

        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollTranscript() }
        }
        locateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollLocator() }
        }
        pollLocator()
    }

    func stop() {
        pollTimer?.invalidate()
        locateTimer?.invalidate()
        pollTimer = nil
        locateTimer = nil
        locator = nil
        activeAgentName = nil
        status = .idle
        connectionMessage = nil
    }

    private func pollTranscript() {
        for line in tailer.pollNewLines() {
            for signal in parser.parse(line: line) {
                apply(signal)
            }
        }
    }

    private func pollLocator() {
        guard let locator else { return }
        if let newFile = locator.pollForChange() {
            activeAgentName = nil
            status = .idle
            tailer.attach(to: newFile, seekToEnd: true)
            connectionMessage = "Conectado a la sesión \(newFile.deletingPathExtension().lastPathComponent.prefix(8))…"
        } else if !locator.isLinkedToProject {
            connectionMessage = "No se encontró ninguna sesión de Claude Code para este proyecto todavía."
        }
    }

    private func apply(_ signal: ClaudeRuntimeSignal) {
        switch signal {
        case .status(let newStatus):
            status = newStatus
        case .activity(let activity):
            activities.insert(activity, at: 0)
            if activities.count > activityLimit {
                activities.removeLast(activities.count - activityLimit)
            }
        case .agentActivated(let name):
            activeAgentName = name
        }
    }
}
