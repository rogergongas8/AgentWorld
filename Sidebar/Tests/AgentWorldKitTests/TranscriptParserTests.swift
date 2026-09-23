import Foundation
import Testing
@testable import AgentWorldKit

@Suite struct TranscriptParserTests {
    let parser = TranscriptParser(cwd: "/work/app")

    private func kinds(_ line: String) -> [TranscriptEvent.Kind] {
        parser.parse(line: line).map(\.kind).filter {
            if case .context = $0 { return false }
            return true
        }
    }

    @Test func toolUseIsSummarizedRelativeToCwd() throws {
        let line = #"{"type":"assistant","timestamp":"2026-09-22T10:00:00.123Z","message":{"id":"m1","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/work/app/Sources/A.swift"}}],"usage":{"input_tokens":3,"cache_read_input_tokens":1000,"cache_creation_input_tokens":20,"output_tokens":50}}}"#
        let events = parser.parse(line: line)
        #expect(events.first?.timestamp != nil)

        guard case .context(let context) = events.first?.kind else { Issue.record("missing context"); return }
        #expect(context.model == "claude-opus-5-5")

        guard case .toolUse(let tool) = kinds(line).first else { Issue.record("missing tool use"); return }
        #expect(tool.name == "Read")
        #expect(tool.kind == .read)
        #expect(tool.summary == "Sources/A.swift")

        guard case .usage(let messageId, let usage) = kinds(line).last else { Issue.record("missing usage"); return }
        #expect(messageId == "m1")
        #expect(usage.context == 1023)
        #expect(usage.output == 50)
    }

    @Test func editsKeepTheirFullPathAndTheStoreCollectsThem() {
        let line = #"{"type":"assistant","timestamp":"2026-09-22T10:00:00.123Z","message":{"id":"m2","content":[{"type":"tool_use","id":"e1","name":"Edit","input":{"file_path":"/work/app/Sources/A.swift","old_string":"a","new_string":"b"}},{"type":"tool_use","id":"r1","name":"Read","input":{"file_path":"/work/app/B.swift"}},{"type":"tool_use","id":"w1","name":"Write","input":{"file_path":"/work/app/C.md","content":"x"}}]}}"#
        let store = SessionStore()
        for event in parser.parse(line: line) { store.apply(event) }
        #expect(store.editedFiles == ["/work/app/Sources/A.swift", "/work/app/C.md"])
    }

    @Test func agentAndSkillAndMCPCalls() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"a","name":"Agent","input":{"subagent_type":"Explore","description":"Find tokens"}},{"type":"tool_use","id":"s","name":"Skill","input":{"skill":"design"}},{"type":"tool_use","id":"m","name":"mcp__claude_ai_Google_Drive__search","input":{"query":"specs"}}]}}"#
        let tools = kinds(line).compactMap { kind -> ToolInvocation? in
            if case .toolUse(let tool) = kind { return tool }
            return nil
        }
        #expect(tools.count == 3)
        #expect(tools[0].subagentType == "Explore")
        #expect(tools[0].subagentDescription == "Find tokens")
        #expect(tools[1].skillName == "design")
        #expect(tools[2].kind == .mcp(server: "Google Drive", tool: "search"))
        #expect(tools[2].summary == "specs")
    }

    @Test func todoWriteIsParsed() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"TodoWrite","input":{"todos":[{"content":"A","activeForm":"Doing A","status":"completed"},{"content":"B","status":"in_progress"}]}}]}}"#
        guard case .toolUse(let tool) = kinds(line).first, let todos = tool.todos else { Issue.record("no todos"); return }
        #expect(todos.map(\.state) == [.completed, .inProgress])
        #expect(todos[0].activeForm == "Doing A")
    }

    @Test func userLinesDistinguishPromptsResultsAndNoise() {
        #expect(kinds(#"{"type":"user","message":{"content":"Fix the bug\nplease"}}"#).count == 1)
        if case .userPrompt(let text) = kinds(#"{"type":"user","message":{"content":"Fix the bug\nplease"}}"#).first {
            #expect(text == "Fix the bug")
        } else {
            Issue.record("expected prompt")
        }

        let result = kinds(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":true,"content":"boom"}]}}"#)
        guard case .toolResult(let id, let isError) = result.first else { Issue.record("expected result"); return }
        #expect(id == "t1")
        #expect(isError)

        #expect(kinds(#"{"type":"user","isMeta":true,"message":{"content":"caveat"}}"#).isEmpty)
        if case .interrupted = kinds(#"{"type":"user","message":{"content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#).first {} else {
            Issue.record("expected interruption")
        }
    }

    @Test func turnEndSignals() {
        let endTurn = kinds(#"{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"Done"}]}}"#)
        #expect(endTurn.contains { if case .turnEnded = $0 { true } else { false } })
        let duration = kinds(#"{"type":"system","subtype":"turn_duration"}"#)
        #expect(duration.contains { if case .turnEnded = $0 { true } else { false } })
    }

    @Test func ignoresGarbageAndBookkeeping() {
        #expect(parser.parse(line: "not json").isEmpty)
        #expect(kinds(#"{"type":"file-history-snapshot","snapshot":{}}"#).isEmpty)
        #expect(kinds(#"{"type":"attachment","attachment":{"type":"date"}}"#).isEmpty)
    }
}
