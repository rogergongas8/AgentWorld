import AgentWorldKit
import AppKit
import Foundation

/// Agents in the same workspace keeping in touch, whatever their CLI: a
/// board of who's doing what and which files each touched, a warning when
/// two edit the same file, and messages from one agent to another, handed
/// over when the receiver's turn is over (never in the middle of its work).
struct AgentMessage: Identifiable, Equatable {
    let id = UUID()
    /// "#2 Claude Code", or "AgentWorld" for the app's own warnings.
    let from: String
    let fromNumber: Int?
    let text: String
    let at: Date
}

extension AppModel {
    // MARK: - Board

    /// The workspace's agents: number, CLI, status, what it's doing and the
    /// files it touched (as `agentworld-ctl board` prints it).
    func boardText(for folder: String, caller: TerminalSession?) -> String {
        let sessions = allSessions.filter { $0.folder == folder && $0.provider.isAgent }
        guard !sessions.isEmpty else { return "No agents open in \(workspaceName(folder))." }
        let touched = filesTouched(in: folder)
        return sessions.map { session in
            let mark = session === caller ? "*" : " "
            var lines = ["\(mark)#\(session.number)  \(session.label)  [\(session.provider.id)]  \(session.status.text)"]
            if let doing = session.doing ?? session.lastPrompt { lines.append("    doing: \(doing)") }
            let files = touched[session.id] ?? []
            if !files.isEmpty {
                lines.append("    files: " + files.prefix(8).joined(separator: ", ") + (files.count > 8 ? " (+\(files.count - 8))" : ""))
            }
            let waiting = inboxes[session.id]?.count ?? 0
            if waiting > 0 { lines.append("    \(waiting) message\(waiting == 1 ? "" : "s") waiting") }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    /// Uncommitted files each session is known to have edited, by session.
    func filesTouched(in folder: String) -> [UUID: [String]] {
        guard let changes = changes[folder] else { return [:] }
        var result: [UUID: [String]] = [:]
        for (path, ids) in changes.sureBy {
            for id in ids { result[id, default: []].append(path) }
        }
        return result.mapValues { $0.sorted() }
    }

    // MARK: - Messages

    /// Queues `text` for each target; the sender's stage shows it went out.
    /// Agents can't flood each other: 10 messages per sender per 10 minutes.
    func sendMessage(_ text: String, from sender: TerminalSession?, to targets: [TerminalSession]) -> String? {
        let now = Date()
        if let sender {
            sentLog[sender.id] = (sentLog[sender.id] ?? []).filter { now.timeIntervalSince($0) < 600 }
            guard (sentLog[sender.id]?.count ?? 0) < 10 else { return "too many messages in the last 10 minutes: wait, or ask the user" }
            sentLog[sender.id, default: []].append(now)
        }
        let from = sender.map { "#\($0.number) \($0.label)" } ?? "the user"
        for target in targets where target !== sender {
            inboxes[target.id, default: []].append(AgentMessage(from: from, fromNumber: sender?.number, text: text, at: now))
        }
        if let sender {
            let names = targets.filter { $0 !== sender }.map { "#\($0.number)" }.joined(separator: " ")
            sender.saying = .init(text: "→ \(names): \(text)", at: now)
        }
        deliverMessages()
        return nil
    }

    /// Takes the caller's waiting messages (it read them itself).
    func takeInbox(_ session: TerminalSession) -> [AgentMessage] {
        let messages = inboxes[session.id] ?? []
        inboxes[session.id] = nil
        return messages
    }

    static func format(_ messages: [AgentMessage]) -> String {
        messages.map { "From \($0.from): \($0.text)" }.joined(separator: "\n")
    }

    /// Hands waiting messages to agents whose turn is over, by typing them
    /// into their prompt. Only where the CLI's transcript says it's waiting
    /// for you (Claude, Codex), not while you're typing there, and one at a
    /// time; the others keep them until they ask (`agentworld-ctl inbox`).
    func deliverMessages(now: Date = Date()) {
        for session in allSessions where !(inboxes[session.id]?.isEmpty ?? true) {
            guard session.health == .running, session.canTakeMessages,
                  now.timeIntervalSince(session.lastKeyAt) > 20,
                  now.timeIntervalSince(session.lastDeliveryAt) > 20 else { continue }
            let messages = takeInbox(session)
            session.lastDeliveryAt = now
            let senders = Set(messages.compactMap(\.fromNumber)).sorted().map { "'#\($0)'" }
            let reply = senders.isEmpty ? "" : " Reply only if needed: agentworld-ctl message \(senders[0]) \"…\" (or the team_message tool)."
            let text = "[AgentWorld · message\(messages.count == 1 ? "" : "s") from other agents] "
                + messages.map { "\($0.from): \($0.text)" + (".!?".contains($0.text.last ?? ".") ? "" : ".") }.joined(separator: " | ") + reply
            session.send(text, submit: true)
            session.saying = .init(text: "📬 " + messages.map(\.from).joined(separator: ", "), at: now)
        }
    }

    // MARK: - Conflicts

    /// Two open agents sure to have edited the same file: tell both of them
    /// and you, once per file and pair.
    func warnAboutConflicts(in folder: String) {
        guard let changes = changes[folder] else { return }
        let open = Dictionary(uniqueKeysWithValues: allSessions.map { ($0.id, $0) })
        for (path, ids) in changes.sureBy {
            let editors = ids.compactMap { open[$0] }.filter { $0.health == .running }
            guard editors.count >= 2 else { continue }
            let key = path + "|" + editors.map(\.id.uuidString).sorted().joined(separator: ",")
            guard warnedConflicts.insert(key).inserted else { continue }
            let names = editors.map { "#\($0.number) \($0.label)" }
            notifier?.post(title: "Two agents on one file", body: "\(names.joined(separator: " and ")) both edited \(path)", session: editors.first)
            for editor in editors {
                let others = editors.filter { $0 !== editor }.map { "#\($0.number) \($0.label)" }.joined(separator: ", ")
                inboxes[editor.id, default: []].append(AgentMessage(
                    from: "AgentWorld", fromNumber: nil,
                    text: "\(others) also edited \(path). Check with them before changing it further (agentworld-ctl board, agentworld-ctl message).",
                    at: Date()))
                editor.saying = .init(text: "⚠︎ \(path) — also \(others)", at: Date())
            }
        }
    }
}

extension TerminalSession {
    /// Its last prompt, shortened, when the CLI's transcript has one.
    var lastPrompt: String? {
        guard let text = store?.log.last(where: { $0.kind == .prompt })?.text else { return nil }
        let line = text.split(separator: "\n").first.map(String.init) ?? text
        return line.count > 90 ? String(line.prefix(87)) + "…" : line
    }

    /// Whether typing a message into it is safe right now: the transcript
    /// says its turn is over (a permission prompt counts as still working).
    var canTakeMessages: Bool {
        guard provider.isAgent, status.tone != .busy else { return false }
        return status.tone == .needsYou || store != nil || hasCodexTranscript
    }
}
