import Foundation
import Testing
@testable import AgentWorldKit

@Suite struct UsageLedgerTests {
    private func home() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aw-usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let now = ISO8601DateFormatter().date(from: "2026-09-23T12:00:00Z")!

    @Test func claudeCountsEachMessageOnceAndCreditsSubagentsToTheParent() throws {
        let root = try home()
        defer { try? FileManager.default.removeItem(at: root) }
        let usage = #""usage":{"input_tokens":10,"cache_read_input_tokens":100,"cache_creation_input_tokens":5,"output_tokens":20}"#
        let lines = [
            #"{"type":"user","timestamp":"2026-09-23T10:00:00.000Z","message":{"role":"user","content":"hi"}}"#,
            #"{"timestamp":"2026-09-23T10:00:01.000Z","requestId":"r1","message":{"id":"m1","#+usage+#"}}"#,
            #"{"timestamp":"2026-09-23T10:00:01.000Z","requestId":"r1","message":{"id":"m1","#+usage+#"}}"#,
            #"{"timestamp":"2026-09-22T09:00:00.000Z","requestId":"r0","message":{"id":"m0","#+usage+#"}}"#,
        ]
        try write(lines.joined(separator: "\n"), to: root.appendingPathComponent(".claude/projects/-x/abc.jsonl"))
        try write(lines[1], to: root.appendingPathComponent(".claude/projects/-x/abc/subagents/agent-1.jsonl"))

        let files = UsageLedger(home: root, calendar: utc).scan(days: 7, now: now)
        #expect(files.count == 2)
        #expect(files.allSatisfy { $0.sessionID == "abc" && $0.provider == "claude" })
        let today = utc.startOfDay(for: now)
        let main = try #require(files.first { $0.byDay.count == 2 })
        #expect(main.byDay[today] == TokenTotals(input: 10, cacheRead: 100, cacheWrite: 5, output: 20))
        #expect(main.byDay[today]?.total == 135)
    }

    @Test func codexUsesGrowthOfRunningTotalsAndKeepsTheLimit() throws {
        let root = try home()
        defer { try? FileManager.default.removeItem(at: root) }
        func event(_ time: String, input: Int, cached: Int, output: Int, percent: Double) -> String {
            #"{"timestamp":"\#(time)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"output_tokens":\#(output)}},"rate_limits":{"primary":{"used_percent":\#(percent),"resets_at":1790000000}}}}"#
        }
        let lines = [event("2026-09-23T10:00:00.000Z", input: 100, cached: 60, output: 10, percent: 1),
                     event("2026-09-23T10:00:01.000Z", input: 100, cached: 60, output: 10, percent: 1),
                     event("2026-09-23T10:05:00.000Z", input: 250, cached: 150, output: 30, percent: 2.5)]
        let name = "rollout-2026-09-23T10-00-00-01a086e2-89fe-7692-830a-0b041b9ec120.jsonl"
        try write(lines.joined(separator: "\n"), to: root.appendingPathComponent(".codex/sessions/2026/09/23/" + name))

        let files = UsageLedger(home: root, calendar: utc).scan(days: 1, now: now)
        let file = try #require(files.first)
        #expect(file.sessionID == "01a086e2-89fe-7692-830a-0b041b9ec120")
        #expect(file.byDay[utc.startOfDay(for: now)] == TokenTotals(input: 100, cacheRead: 150, output: 30))
        #expect(file.limitUsedPercent == 2.5)
    }

    @Test func geminiChats() throws {
        let root = try home()
        defer { try? FileManager.default.removeItem(at: root) }
        let chat = #"{"sessionId":"g1","messages":[{"type":"user","timestamp":"2026-09-23T10:00:00Z"},{"type":"gemini","timestamp":"2026-09-23T10:00:02.000Z","tokens":{"input":900,"output":29,"cached":400,"thoughts":20,"tool":0,"total":949}}]}"#
        try write(chat, to: root.appendingPathComponent(".gemini/tmp/proj/chats/session-1.json"))

        let file = try #require(UsageLedger(home: root, calendar: utc).scan(days: 1, now: now).first)
        #expect(file.provider == "gemini")
        #expect(file.byDay[utc.startOfDay(for: now)] == TokenTotals(input: 500, cacheRead: 400, output: 49))
    }
}
