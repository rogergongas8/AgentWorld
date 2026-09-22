import AgentWorldKit
import Foundation

/// Glues the transcript plumbing together: finds the session, tails it and
/// its subagents, and feeds parsed events into a `SessionStore`. Swaps in a
/// fresh store whenever the followed transcript changes (new session, /clear).
final class SessionFeed {
    private(set) var store = SessionStore()
    private let locator: SessionLocator
    private let tailer = TranscriptTailer()
    private let subagents = SubagentWatcher()
    private let parser: TranscriptParser

    init(cwd: String, projectsRoot: URL, sessionId: String?) {
        locator = SessionLocator(cwd: cwd, projectsRoot: projectsRoot, pinnedSessionId: sessionId)
        parser = TranscriptParser(cwd: cwd)
    }

    var connection: SidebarSnapshot.Connection {
        if locator.current != nil { return .following }
        return locator.isProjectDirectoryFound ? .waitingForSession : .noProjectHistory
    }

    /// Checks whether a different transcript should be followed. Existing
    /// history is replayed so tasks, tool counts and tokens are complete even
    /// when the sidebar starts mid-session (e.g. `claude --resume`).
    func locate() {
        guard let file = locator.poll() else { return }
        store = SessionStore()
        tailer.attach(to: file, fromStart: true)
        subagents.attach(toSessionTranscript: file, replayExisting: true)
        poll()
    }

    func poll() {
        // Main transcript first so subagents exist before their own events land.
        for line in tailer.poll() {
            for event in parser.parse(line: line) { store.apply(event) }
        }
        subagents.discover()
        for batch in subagents.poll() {
            for line in batch.lines {
                for event in parser.parse(line: line) { store.apply(event, from: .subagent(batch.toolUseId)) }
            }
        }
    }
}
