import Foundation
import Testing
@testable import AgentWorldKit

@Suite struct CodexSessionTests {
    private func line(_ type: String, _ payload: [String: Any], at time: String = "2026-09-22T10:00:00.000Z") -> String {
        let object: [String: Any] = ["timestamp": time, "type": type, "payload": payload]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    @Test func followsTurnsAndToolCalls() {
        let session = CodexSession(cwd: "/p", startedAfter: .distantPast)
        session.apply(line("event_msg", ["type": "task_started"]))
        #expect(session.state.isWorking)
        #expect(session.state.turns == 1)

        session.apply(line("response_item", ["type": "custom_tool_call", "name": "exec",
                                             "input": #"const r = await tools.exec_command({"cmd":"rg --files -g '*.md'","workdir":"/p"})"#]))
        #expect(session.state.action == "$ rg --files -g '*.md'")
        session.apply(line("response_item", ["type": "function_call", "name": "apply_patch", "arguments": "{}"]))
        #expect(session.state.action == "apply_patch")
        #expect(session.state.toolCalls == 2)

        session.apply(line("event_msg", ["type": "task_complete"], at: "2026-09-22T10:01:00.500Z"))
        #expect(!session.state.isWorking)
        #expect(session.state.action == nil)
        #expect(session.state.lastEventAt == CodexSession.date("2026-09-22T10:01:00.500Z"))
    }

    @Test func findsTheRolloutForItsFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aw-codex-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let day = root.appendingPathComponent(String(format: "%04d/%02d/%02d", parts.year!, parts.month!, parts.day!))
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: now)
        let other = [line("session_meta", ["cwd": "/elsewhere", "timestamp": stamp])].joined(separator: "\n") + "\n"
        let mine = [line("session_meta", ["cwd": "/p", "timestamp": stamp]), line("event_msg", ["type": "task_started"])]
            .joined(separator: "\n") + "\n"
        try other.write(to: day.appendingPathComponent("rollout-a.jsonl"), atomically: true, encoding: .utf8)
        try mine.write(to: day.appendingPathComponent("rollout-b.jsonl"), atomically: true, encoding: .utf8)

        let session = CodexSession(cwd: "/p", startedAfter: now.addingTimeInterval(-60), sessionsRoot: root)
        session.poll(now: now)
        #expect(session.fileURL?.lastPathComponent == "rollout-b.jsonl")
        #expect(session.state.isWorking)
    }
}
