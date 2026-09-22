import AgentWorldArt
import Foundation

/// `--demo`: a throwaway project + transcript directory that a scripted,
/// looping "session" writes into over time, in Claude Code's real on-disk
/// format. The sidebar follows it through exactly the same code path as a
/// real session, so the demo doubles as an end-to-end smoke test.
final class DemoSession {
    let root: URL
    let projectURL: URL
    let projectsRoot: URL
    let sessionId = UUID().uuidString.lowercased()

    private var transcript: URL
    private var startedAt = Date()
    private var nextStep = 0
    private var loop = 0

    init() throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory.appendingPathComponent("agentworld-demo-\(getpid())", isDirectory: true)
        projectURL = root.appendingPathComponent("home/dark-mode-app", isDirectory: true)
        projectsRoot = root.appendingPathComponent("home/.claude/projects", isDirectory: true)

        let claudeDir = projectURL.appendingPathComponent(".claude", isDirectory: true)
        try fileManager.createDirectory(at: claudeDir.appendingPathComponent("agents"), withIntermediateDirectories: true)
        let agents = [
            ("code-reviewer", "Reviews diffs for bugs and style", "sonnet"),
            ("test-runner", "Runs the test suite and triages failures", "haiku"),
        ]
        for (name, description, model) in agents {
            try "---\nname: \(name)\ndescription: \(description)\nmodel: \(model)\n---\nYou are \(name).\n"
                .write(to: claudeDir.appendingPathComponent("agents/\(name).md"), atomically: true, encoding: .utf8)
        }
        for (name, description) in [("design", "Premium UI/UX guidance"), ("release-notes", "Drafts release notes"), ("swiftui-patterns", "House SwiftUI conventions")] {
            let dir = claudeDir.appendingPathComponent("skills/\(name)", isDirectory: true)
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            try "---\nname: \(name)\ndescription: \(description)\n---\n".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        try #"{"mcpServers":{"figma":{"type":"http","url":"https://example.invalid"},"github":{"command":"gh-mcp"},"sentry":{"type":"sse","url":"https://example.invalid"}}}"#
            .write(to: projectURL.appendingPathComponent(".mcp.json"), atomically: true, encoding: .utf8)

        // Same slug rule as Claude Code (and ProjectSlug).
        let slug = String(projectURL.path.map { $0.isLetter || $0.isNumber ? $0 : "-" })
        let sessionDir = projectsRoot.appendingPathComponent(slug, isDirectory: true)
        try fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        transcript = sessionDir.appendingPathComponent("\(sessionId).jsonl")
        fileManager.createFile(atPath: transcript.path, contents: nil)
    }

    var homeURL: URL { root.appendingPathComponent("home", isDirectory: true) }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Writes every step whose time has come. Call once per frame.
    func advance(now: Date = Date()) {
        while nextStep < script.count, now.timeIntervalSince(startedAt) >= script[nextStep].at {
            perform(script[nextStep].action, now: now)
            nextStep += 1
        }
        if nextStep == script.count {
            nextStep = 0
            loop += 1
            startedAt = now
        }
    }

    // MARK: - Script

    private enum Action {
        case prompt(String)
        case thinking
        case text(String, endTurn: Bool)
        case tool(id: String, name: String, input: [String: Any])
        case result(id: String, error: Bool)
        case subagentTool(agent: String, id: String, name: String, input: [String: Any])
        case subagentResult(agent: String, id: String)
        case turnDuration
    }

    private let script: [(at: TimeInterval, action: Action)] = [
        (0.5, .prompt("Add a dark mode toggle to the settings screen")),
        (1.5, .thinking),
        (3, .tool(id: "todo1", name: "TodoWrite", input: ["todos": DemoSession.todos(active: 0)])),
        (4, .result(id: "todo1", error: false)),
        (4.5, .tool(id: "read1", name: "Read", input: ["file_path": "Sources/Settings/SettingsView.swift"])),
        (6.5, .result(id: "read1", error: false)),
        (7, .tool(id: "grep1", name: "Grep", input: ["pattern": "ColorScheme"])),
        (8.5, .result(id: "grep1", error: false)),
        (9, .tool(id: "agent1", name: "Agent", input: ["subagent_type": "Explore", "description": "Map existing theme tokens"])),
        (10, .subagentTool(agent: "agent1", id: "s1", name: "Glob", input: ["pattern": "**/*Theme*.swift"])),
        (11, .tool(id: "skill1", name: "Skill", input: ["skill": "design"])),
        (11.5, .subagentTool(agent: "agent1", id: "s2", name: "Read", input: ["file_path": "Sources/Theme/Palette.swift"])),
        (12, .result(id: "skill1", error: false)),
        (13, .tool(id: "mcp1", name: "mcp__figma__get_design_context", input: ["nodeId": "12:345"])),
        (14, .subagentTool(agent: "agent1", id: "s3", name: "WebFetch", input: ["url": "https://developer.apple.com/design"])),
        (15.5, .result(id: "mcp1", error: false)),
        (17, .result(id: "agent1", error: false)),
        (18, .tool(id: "todo2", name: "TodoWrite", input: ["todos": DemoSession.todos(active: 1)])),
        (18.5, .result(id: "todo2", error: false)),
        (19, .tool(id: "edit1", name: "Edit", input: ["file_path": "Sources/Settings/SettingsView.swift"])),
        (21, .result(id: "edit1", error: false)),
        (21.5, .tool(id: "write1", name: "Write", input: ["file_path": "Sources/Theme/DarkPalette.swift"])),
        (23, .result(id: "write1", error: false)),
        (23.5, .tool(id: "todo3", name: "TodoWrite", input: ["todos": DemoSession.todos(active: 2)])),
        (24, .result(id: "todo3", error: false)),
        (24.5, .tool(id: "bash1", name: "Bash", input: ["command": "swift test"])),
        (27, .result(id: "bash1", error: true)),
        (28, .thinking),
        (29, .tool(id: "edit2", name: "Edit", input: ["file_path": "Tests/SettingsTests.swift"])),
        (30.5, .result(id: "edit2", error: false)),
        (31, .tool(id: "agent2", name: "Agent", input: ["subagent_type": "test-runner", "description": "Run tests and triage"])),
        (31.5, .tool(id: "agent3", name: "Agent", input: ["subagent_type": "code-reviewer", "description": "Review the dark mode diff"])),
        (32.5, .subagentTool(agent: "agent2", id: "s4", name: "Bash", input: ["command": "swift test --parallel"])),
        (33, .subagentTool(agent: "agent3", id: "s5", name: "Read", input: ["file_path": "Sources/Settings/SettingsView.swift"])),
        (35, .subagentTool(agent: "agent3", id: "s6", name: "Grep", input: ["pattern": "Color\\("])),
        (36, .tool(id: "mcp2", name: "mcp__github__create_pull_request", input: ["title": "Dark mode toggle"])),
        (37.5, .result(id: "mcp2", error: false)),
        (38, .result(id: "agent2", error: false)),
        (40, .result(id: "agent3", error: false)),
        (41, .tool(id: "todo4", name: "TodoWrite", input: ["todos": DemoSession.todos(active: 4)])),
        (41.5, .result(id: "todo4", error: false)),
        (42, .text("Dark mode is in: a toggle in Settings, a DarkPalette, and green tests.", endTurn: true)),
        (42.2, .turnDuration),
        (58, .text("", endTurn: false)),
    ]

    private static func todos(active: Int) -> [[String: Any]] {
        let items = [
            ("Inspect the settings screen", "Inspecting the settings screen"),
            ("Add dark palette + toggle", "Adding dark palette + toggle"),
            ("Make the tests pass", "Making the tests pass"),
            ("Open a pull request", "Opening a pull request"),
        ]
        return items.enumerated().map { index, item in
            ["content": item.0, "activeForm": item.1, "status": index < active ? "completed" : index == active ? "in_progress" : "pending"]
        }
    }

    // MARK: - Writing JSONL

    private func perform(_ action: Action, now: Date) {
        let suffix = "-\(loop)"
        switch action {
        case .prompt(let text):
            append(line(type: "user", now: now, message: ["role": "user", "content": text]), to: transcript)
        case .thinking:
            append(assistant(now: now, content: [["type": "thinking", "thinking": "…"]]), to: transcript)
        case .text(let text, let endTurn):
            guard !text.isEmpty else { return }
            append(assistant(now: now, content: [["type": "text", "text": text]], stopReason: endTurn ? "end_turn" : nil), to: transcript)
        case .tool(let id, let name, let input):
            append(assistant(now: now, content: [["type": "tool_use", "id": id + suffix, "name": name, "input": input]], stopReason: "tool_use"), to: transcript)
        case .result(let id, let error):
            append(line(type: "user", now: now, message: ["role": "user", "content": [["type": "tool_result", "tool_use_id": id + suffix, "is_error": error, "content": error ? "1 test failed" : "ok"]]]), to: transcript)
        case .subagentTool(let agent, let id, let name, let input):
            append(assistant(now: now, content: [["type": "tool_use", "id": id + suffix, "name": name, "input": input]], stopReason: "tool_use"), to: subagentTranscript(agent + suffix))
        case .subagentResult(let agent, let id):
            append(line(type: "user", now: now, message: ["role": "user", "content": [["type": "tool_result", "tool_use_id": id + suffix, "content": "ok"]]]), to: subagentTranscript(agent + suffix))
        case .turnDuration:
            var object = base(type: "system", now: now)
            object["subtype"] = "turn_duration"
            append(object, to: transcript)
        }
    }

    private var contextTokens = 18_000

    private func assistant(now: Date, content: [[String: Any]], stopReason: String? = nil) -> [String: Any] {
        contextTokens = contextTokens >= 150_000 ? 18_000 : contextTokens + 3_100
        var message: [String: Any] = [
            "id": "msg_\(UUID().uuidString.prefix(8))",
            "role": "assistant",
            "model": "claude-opus-5-5",
            "content": content,
            "usage": ["input_tokens": 4, "cache_read_input_tokens": contextTokens, "cache_creation_input_tokens": 900, "output_tokens": 240],
        ]
        if let stopReason { message["stop_reason"] = stopReason }
        return line(type: "assistant", now: now, message: message)
    }

    private func line(type: String, now: Date, message: [String: Any]) -> [String: Any] {
        var object = base(type: type, now: now)
        object["message"] = message
        return object
    }

    private func base(type: String, now: Date) -> [String: Any] {
        [
            "type": type,
            "timestamp": ISO8601DateFormatter().string(from: now),
            "sessionId": sessionId,
            "cwd": projectURL.path,
            "gitBranch": "feature/dark-mode",
            "version": "demo",
        ]
    }

    private func subagentTranscript(_ toolUseId: String) -> URL {
        let dir = transcript.deletingPathExtension().appendingPathComponent("subagents", isDirectory: true)
        let file = dir.appendingPathComponent("agent-\(toolUseId).jsonl")
        if !FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? #"{"toolUseId":"\#(toolUseId)"}"#.write(to: dir.appendingPathComponent("agent-\(toolUseId).meta.json"), atomically: true, encoding: .utf8)
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        return file
    }

    private func append(_ object: [String: Any], to url: URL) {
        guard var data = try? JSONSerialization.data(withJSONObject: object),
              let handle = try? FileHandle(forWritingTo: url) else { return }
        data.append(0x0A)
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
