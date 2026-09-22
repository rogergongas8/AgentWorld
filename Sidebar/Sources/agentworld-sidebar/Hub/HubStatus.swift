import AgentWorldKit
import Foundation
import TerminalUI

/// Live status of the hub's terminals. Claude Code panes are followed through
/// their transcripts (the same feed the sidebar uses), so the hub knows what
/// each one is doing and which agents are at work; Codex panes through their
/// rollout files; other CLIs fall back to tmux's activity clock.
final class HubStatus {
    struct Line {
        let text: String
        let color: RGB
        let isBusy: Bool
        let needsYou: Bool
    }

    private var feeds: [String: SessionFeed] = [:]
    private var codex: [String: CodexSession] = [:]
    private var nextLocate = Date.distantPast

    /// Follows the Claude panes that exist now, forgets closed ones.
    func sync(_ panes: [Workspace.Pane]) {
        let wanted = panes.filter { $0.provider?.kind == .claude && $0.sessionId != nil && $0.cwd != nil }
        let ids = Set(wanted.map(\.id))
        feeds = feeds.filter { ids.contains($0.key) }
        for pane in wanted where feeds[pane.id] == nil {
            feeds[pane.id] = SessionFeed(cwd: pane.cwd!, projectsRoot: ProjectSlug.defaultProjectsRoot, sessionId: pane.sessionId)
        }

        let codexPanes = panes.filter { $0.provider?.kind == .codex && $0.cwd != nil && $0.startedAt != nil }
        let codexIds = Set(codexPanes.map(\.id))
        codex = codex.filter { codexIds.contains($0.key) }
        for pane in codexPanes where codex[pane.id] == nil {
            codex[pane.id] = CodexSession(cwd: pane.cwd!, startedAfter: pane.startedAt!)
        }
    }

    func poll(now: Date) {
        let locate = now >= nextLocate
        for feed in feeds.values {
            if locate { feed.locate() }
            feed.poll()
        }
        for session in codex.values { session.poll(now: now) }
        if locate { nextLocate = now.addingTimeInterval(1) }
    }

    func store(for pane: Workspace.Pane) -> SessionStore? {
        guard let feed = feeds[pane.id], feed.connection == .following else { return nil }
        return feed.store
    }

    func line(for pane: Workspace.Pane, now: Date) -> Line {
        if pane.provider?.kind == .claude {
            guard let store = store(for: pane) else {
                return Line(text: "ready", color: Theme.muted, isBusy: false, needsYou: false)
            }
            let status = store.main.status
            let stale = store.lastEventAt.map { now.timeIntervalSince($0) > 600 } ?? true
            if let running = store.runningSubagents.first {
                return Line(text: "\(running.type): \(running.state.action ?? running.description ?? "working")", color: Theme.live, isBusy: true, needsYou: false)
            }
            if status.isBusy, !stale {
                return Line(text: store.main.action ?? status.title, color: Theme.live, isBusy: true, needsYou: false)
            }
            let since = now.timeIntervalSince(store.lastEventAt ?? store.main.since)
            if status == .waitingForUser, since < 900 {
                return Line(text: "your turn · \(Format.duration(since))", color: Theme.warning, isBusy: false, needsYou: true)
            }
            return Line(text: "idle \(Format.duration(since))", color: Theme.faint, isBusy: false, needsYou: false)
        }
        if let session = codex[pane.id], session.isFollowing {
            let state = session.state
            if state.isWorking { return Line(text: state.action ?? "thinking", color: Theme.live, isBusy: true, needsYou: false) }
            let since = now.timeIntervalSince(state.lastEventAt ?? now)
            if state.turns > 0, since < 900 {
                return Line(text: "your turn · \(Format.duration(since))", color: Theme.warning, isBusy: false, needsYou: true)
            }
            return Line(text: state.turns == 0 ? "ready" : "idle \(Format.duration(since))", color: Theme.faint, isBusy: false, needsYou: false)
        }
        guard let last = pane.lastActivity else { return Line(text: "open", color: Theme.muted, isBusy: false, needsYou: false) }
        let since = now.timeIntervalSince(last)
        if since < 4 { return Line(text: "working", color: Theme.live, isBusy: true, needsYou: false) }
        return Line(text: "idle \(Format.duration(since))", color: Theme.faint, isBusy: false, needsYou: false)
    }

    /// Where an agent (subagent type) is working right now, or last worked.
    func activity(ofAgent name: String, panes: [Workspace.Pane], now: Date) -> Line? {
        var lastRun: (Date, String)?
        for pane in panes {
            guard let store = store(for: pane) else { continue }
            for run in store.subagents where run.type.caseInsensitiveCompare(name) == .orderedSame
                || run.type.hasSuffix(":" + name) {
                if run.isRunning {
                    return Line(text: "working in \(pane.folderName): \(run.state.action ?? run.description ?? "…")", color: Theme.live, isBusy: true, needsYou: false)
                }
                let finished = run.finishedAt ?? run.startedAt
                if lastRun == nil || finished > lastRun!.0 { lastRun = (finished, pane.folderName) }
            }
        }
        return lastRun.map { Line(text: "done \(Format.duration(now.timeIntervalSince($0.0))) ago in \($0.1)", color: Theme.muted, isBusy: false, needsYou: false) }
    }
}
