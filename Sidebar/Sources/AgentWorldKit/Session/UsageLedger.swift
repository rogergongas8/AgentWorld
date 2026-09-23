import Foundation

/// Tokens spent, split the way every CLI can report them.
public struct TokenTotals: Sendable, Equatable {
    /// Fresh input: prompt tokens that weren't served from a cache.
    public var input = 0
    public var cacheRead = 0
    public var cacheWrite = 0
    /// Output, reasoning included.
    public var output = 0

    public init(input: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0, output: Int = 0) {
        self.input = input
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.output = output
    }

    public var total: Int { input + cacheRead + cacheWrite + output }
    public var isEmpty: Bool { total == 0 }

    public static func + (lhs: TokenTotals, rhs: TokenTotals) -> TokenTotals {
        TokenTotals(input: lhs.input + rhs.input, cacheRead: lhs.cacheRead + rhs.cacheRead,
                    cacheWrite: lhs.cacheWrite + rhs.cacheWrite, output: lhs.output + rhs.output)
    }

    public static func += (lhs: inout TokenTotals, rhs: TokenTotals) { lhs = lhs + rhs }
}

/// One transcript's tokens by day, and the conversation it belongs to.
public struct UsageFile: Sendable, Equatable {
    public let provider: String
    /// The id the CLI resumes it by (Claude's session id, Codex's thread id).
    public let sessionID: String?
    public var byDay: [Date: TokenTotals]
    /// Codex's plan window: how much of it is used, as it last reported.
    public var limitUsedPercent: Double?
    public var limitResetsAt: Date?
}

/// Reads token usage from the CLIs' own session files: Claude Code's
/// transcripts, Codex's rollouts and Gemini CLI's chats. The other CLIs
/// don't write usage down. Files are cached by size and date, so rereading
/// only parses what changed.
public final class UsageLedger: @unchecked Sendable {
    private let home: URL
    private let calendar: Calendar
    private var cache: [String: (size: Int, modified: Date, file: UsageFile)] = [:]
    private let lock = NSLock()

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, calendar: Calendar = .current) {
        self.home = home
        self.calendar = calendar
    }

    /// Every file touched in the last `days` days (today included).
    public func scan(days: Int, now: Date = Date()) -> [UsageFile] {
        let since = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) ?? now
        var files: [UsageFile] = []
        for (url, provider) in candidates(since: since) {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize, let modified = values.contentModificationDate, modified >= since else { continue }
            lock.lock()
            let cached = cache[url.path]
            lock.unlock()
            if let cached, cached.size == size, cached.modified == modified {
                files.append(cached.file)
                continue
            }
            guard let file = parse(url, provider: provider) else { continue }
            lock.lock()
            cache[url.path] = (size, modified, file)
            lock.unlock()
            files.append(file)
        }
        return files.map { file in
            var trimmed = file
            trimmed.byDay = file.byDay.filter { $0.key >= since }
            return trimmed
        }.filter { !$0.byDay.isEmpty || $0.limitUsedPercent != nil }
    }

    // MARK: - Where

    private func candidates(since: Date) -> [(URL, String)] {
        let fm = FileManager.default
        var result: [(URL, String)] = []
        // Claude: ~/.claude/projects/<slug>/<session>.jsonl, and helpers under <session>/subagents/.
        let projects = home.appendingPathComponent(".claude/projects")
        if let enumerator = fm.enumerator(at: projects, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                result.append((url, "claude"))
            }
        }
        // Codex: ~/.codex/sessions/YYYY/MM/DD/rollout-….jsonl — only the days in range.
        var day = since
        while day <= Date() {
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            let folder = home.appendingPathComponent(String(format: ".codex/sessions/%04d/%02d/%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0))
            for url in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "jsonl" {
                result.append((url, "codex"))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        // A session that started earlier and ran into the range: modified recently, older folder.
        let sessions = home.appendingPathComponent(".codex/sessions")
        if let enumerator = fm.enumerator(at: sessions, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let url as URL in enumerator where url.pathExtension == "jsonl" && !result.contains(where: { $0.0 == url }) {
                if let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, modified >= since {
                    result.append((url, "codex"))
                }
            }
        }
        // Gemini: ~/.gemini/tmp/<project>/chats/session-….json
        let gemini = home.appendingPathComponent(".gemini/tmp")
        for project in (try? fm.contentsOfDirectory(at: gemini, includingPropertiesForKeys: nil)) ?? [] {
            let chats = project.appendingPathComponent("chats")
            for url in (try? fm.contentsOfDirectory(at: chats, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "json" {
                result.append((url, "gemini"))
            }
        }
        return result
    }

    // MARK: - Parsing

    func parse(_ url: URL, provider: String) -> UsageFile? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        switch provider {
        case "claude": return parseClaude(data, url: url)
        case "codex": return parseCodex(data, url: url)
        case "gemini": return parseGemini(data)
        default: return nil
        }
    }

    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        // Formatters aren't thread-safe; scans run one at a time off the main thread.
        return iso.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// Claude writes a message's usage on each of its content blocks: count
    /// each message id once.
    private func parseClaude(_ data: Data, url: URL) -> UsageFile {
        var byDay: [Date: TokenTotals] = [:]
        var seen = Set<String>()
        for line in data.split(separator: UInt8(ascii: "\n")) where line.count > 20 {
            // Most lines have no usage: skip them before parsing JSON.
            guard line.range(of: Data(#""usage""#.utf8)) != nil,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let when = Self.date(object["timestamp"]) else { continue }
            let key = (message["id"] as? String ?? "") + "|" + (object["requestId"] as? String ?? "")
            if key != "|" {
                guard seen.insert(key).inserted else { continue }
            }
            byDay[calendar.startOfDay(for: when), default: TokenTotals()] += TokenTotals(
                input: usage["input_tokens"] as? Int ?? 0,
                cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
                cacheWrite: usage["cache_creation_input_tokens"] as? Int ?? 0,
                output: usage["output_tokens"] as? Int ?? 0)
        }
        // Subagent transcripts live under the parent's folder: credit the parent.
        let isSubagent = url.deletingLastPathComponent().lastPathComponent == "subagents"
        let session = isSubagent ? url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            : url.deletingPathExtension().lastPathComponent
        return UsageFile(provider: "claude", sessionID: session, byDay: byDay)
    }

    /// Codex reports running totals: the day's share is the growth since the
    /// previous report (so repeated reports count once).
    private func parseCodex(_ data: Data, url: URL) -> UsageFile {
        var byDay: [Date: TokenTotals] = [:]
        var previous = TokenTotals()
        var percent: Double?
        var resets: Date?
        for line in data.split(separator: UInt8(ascii: "\n")) where line.range(of: Data("token_count".utf8)) != nil {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let payload = object["payload"] as? [String: Any], payload["type"] as? String == "token_count",
                  let when = Self.date(object["timestamp"]) else { continue }
            if let limits = payload["rate_limits"] as? [String: Any], let primary = limits["primary"] as? [String: Any] {
                percent = primary["used_percent"] as? Double ?? (primary["used_percent"] as? Int).map(Double.init)
                resets = (primary["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
                    ?? (primary["resets_at"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) }
            }
            guard let info = payload["info"] as? [String: Any], let total = info["total_token_usage"] as? [String: Any] else { continue }
            let input = total["input_tokens"] as? Int ?? 0
            let cached = total["cached_input_tokens"] as? Int ?? 0
            let now = TokenTotals(input: max(0, input - cached), cacheRead: cached,
                                  cacheWrite: total["cache_write_input_tokens"] as? Int ?? 0,
                                  output: total["output_tokens"] as? Int ?? 0)
            let delta = TokenTotals(input: max(0, now.input - previous.input), cacheRead: max(0, now.cacheRead - previous.cacheRead),
                                    cacheWrite: max(0, now.cacheWrite - previous.cacheWrite), output: max(0, now.output - previous.output))
            previous = now
            if !delta.isEmpty { byDay[calendar.startOfDay(for: when), default: TokenTotals()] += delta }
        }
        // rollout-2026-09-09T17-56-28-<uuid>.jsonl
        let name = url.deletingPathExtension().lastPathComponent
        return UsageFile(provider: "codex", sessionID: name.count >= 36 ? String(name.suffix(36)) : nil, byDay: byDay,
                         limitUsedPercent: percent, limitResetsAt: resets)
    }

    private func parseGemini(_ data: Data) -> UsageFile? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = object["messages"] as? [[String: Any]] else { return nil }
        var byDay: [Date: TokenTotals] = [:]
        for message in messages {
            guard let tokens = message["tokens"] as? [String: Any], let when = Self.date(message["timestamp"]) else { continue }
            let input = tokens["input"] as? Int ?? 0
            let cached = tokens["cached"] as? Int ?? 0
            byDay[calendar.startOfDay(for: when), default: TokenTotals()] += TokenTotals(
                input: max(0, input - cached), cacheRead: cached,
                output: (tokens["output"] as? Int ?? 0) + (tokens["thoughts"] as? Int ?? 0))
        }
        return UsageFile(provider: "gemini", sessionID: object["sessionId"] as? String, byDay: byDay)
    }
}
