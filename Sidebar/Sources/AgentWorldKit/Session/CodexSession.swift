import Foundation

/// Follows a Codex session live from its rollout file
/// (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`): whether it's working on
/// a turn, the tool call in flight, and how many turns it has run. Codex
/// writes `session_meta` (with the cwd) first, then `task_started` /
/// `task_complete` around each turn and one `response_item` per tool call.
public final class CodexSession {
    public struct State: Equatable, Sendable {
        public var isWorking = false
        /// "$ rg --files", "apply_patch"…
        public var action: String?
        public var turns = 0
        public var toolCalls = 0
        public var lastEventAt: Date?
    }

    public private(set) var state = State()
    public private(set) var fileURL: URL?

    private let cwd: String
    private let startedAfter: Date
    private let sessionsRoot: URL
    private let tailer = TranscriptTailer()
    private var nextSearch = Date.distantPast

    /// Follows the first session in `cwd` that started after `startedAfter`
    /// (the moment its terminal was opened).
    public init(cwd: String, startedAfter: Date, sessionsRoot: URL? = nil) {
        self.cwd = cwd
        self.startedAfter = startedAfter
        self.sessionsRoot = sessionsRoot
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    public var isFollowing: Bool { fileURL != nil }

    public func poll(now: Date = Date()) {
        if fileURL == nil {
            guard now >= nextSearch else { return }
            nextSearch = now.addingTimeInterval(2)
            guard let file = findRollout(now: now) else { return }
            fileURL = file
            tailer.attach(to: file, fromStart: true)
        }
        for line in tailer.poll() { apply(line) }
    }

    // MARK: - Parsing

    func apply(_ line: String) {
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        if let stamp = object["timestamp"] as? String, let date = Self.date(stamp) { state.lastEventAt = date }
        let payload = object["payload"] as? [String: Any] ?? [:]
        switch (object["type"] as? String, payload["type"] as? String) {
        case ("event_msg", "task_started"):
            state.isWorking = true
            state.turns += 1
            state.action = nil
        case ("event_msg", "task_complete"), ("event_msg", "turn_aborted"):
            state.isWorking = false
            state.action = nil
        case ("response_item", "custom_tool_call"), ("response_item", "function_call"), ("response_item", "local_shell_call"):
            state.toolCalls += 1
            state.action = Self.summary(of: payload)
        default:
            break
        }
    }

    /// A short label for a tool call: the shell command when there is one.
    static func summary(of call: [String: Any]) -> String {
        let name = call["name"] as? String ?? "tool"
        let input = call["input"] as? String ?? call["arguments"] as? String ?? ""
        if let range = input.range(of: #""(cmd|command)"\s*:\s*"((?:[^"\\]|\\.)*)""#, options: .regularExpression) {
            let match = String(input[range])
            if let start = match.range(of: #":\s*""#, options: .regularExpression) {
                let command = match[start.upperBound...].dropLast()
                    .replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\'", with: "'")
                return "$ " + command
            }
        }
        return name
    }

    // MARK: - Finding the rollout

    /// Today's and yesterday's rollouts, newest first; the first whose
    /// `session_meta` is for our folder and started after the terminal did.
    private func findRollout(now: Date) -> URL? {
        let calendar = Calendar.current
        var candidates: [URL] = []
        for dayOffset in [0, -1] {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            let folder = sessionsRoot
                .appendingPathComponent(String(format: "%04d", parts.year ?? 0))
                .appendingPathComponent(String(format: "%02d", parts.month ?? 0))
                .appendingPathComponent(String(format: "%02d", parts.day ?? 0))
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            candidates += files.filter { $0.pathExtension == "jsonl" }
        }
        let recent = candidates
            .map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            .filter { $0.1 >= startedAfter.addingTimeInterval(-5) }
            .sorted { $0.1 > $1.1 }
        for (file, _) in recent {
            guard let meta = Self.sessionMeta(of: file), meta.cwd == cwd,
                  meta.started >= startedAfter.addingTimeInterval(-10) else { continue }
            return file
        }
        return nil
    }

    private static func sessionMeta(of file: URL) -> (cwd: String, started: Date)? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
        for line in data.split(separator: 0x0A) {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  object["type"] as? String == "session_meta",
                  let payload = object["payload"] as? [String: Any],
                  let cwd = payload["cwd"] as? String else { continue }
            let stamp = payload["timestamp"] as? String ?? object["timestamp"] as? String ?? ""
            return (cwd, date(stamp) ?? .distantPast)
        }
        return nil
    }

    static func date(_ string: String) -> Date? {
        fractionalFormatter.date(from: string) ?? plainFormatter.date(from: string)
    }

    nonisolated(unsafe) private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let plainFormatter = ISO8601DateFormatter()
}
