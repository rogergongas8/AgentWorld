import Foundation
import Testing
@testable import AgentWorldKit

@Suite struct SessionStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func event(_ kind: TranscriptEvent.Kind, at offset: TimeInterval) -> TranscriptEvent {
        TranscriptEvent(timestamp: t0.addingTimeInterval(offset), kind: kind)
    }

    @Test func mainActorFollowsTheTurn() {
        let store = SessionStore(now: t0)
        store.apply(event(.userPrompt("hi"), at: 0))
        #expect(store.main.status == .thinking)
        #expect(store.turns == 1)

        store.apply(event(.toolUse(ToolInvocation(id: "t1", name: "Edit", summary: "A.swift")), at: 1))
        #expect(store.main.status == .editing)
        #expect(store.main.action == "Edit A.swift")

        store.apply(event(.toolResult(id: "t1", isError: false), at: 2))
        #expect(store.main.status == .thinking)

        store.apply(event(.turnEnded, at: 3))
        store.apply(event(.turnEnded, at: 3.1))
        #expect(store.main.status == .waitingForUser)
        #expect(store.log.filter { $0.kind == .turnEnded }.count == 1)
        #expect(store.startedAt == t0)
    }

    @Test func subagentLifecycle() {
        let store = SessionStore(now: t0)
        store.apply(event(.toolUse(ToolInvocation(id: "a1", name: "Agent", subagentType: "Explore", subagentDescription: "Map code")), at: 0))
        #expect(store.runningSubagents.count == 1)
        #expect(store.main.status == .delegating)

        store.apply(event(.toolUse(ToolInvocation(id: "s1", name: "Grep", summary: "TODO")), at: 1), from: .subagent("a1"))
        #expect(store.subagents[0].state.status == .reading)
        #expect(store.subagents[0].toolCalls == 1)
        #expect(store.log.last?.actor == "Explore")

        store.apply(event(.toolResult(id: "a1", isError: false), at: 5))
        #expect(store.runningSubagents.isEmpty)
        #expect(store.subagents[0].state.status == .done)
        #expect(store.subagents[0].finishedAt == t0.addingTimeInterval(5))
    }

    @Test func replayedSubagentWorkIsCountedAndLogStaysChronological() {
        let store = SessionStore(now: t0)
        store.apply(event(.toolUse(ToolInvocation(id: "a1", name: "Task", subagentType: "Plan")), at: 0))
        store.apply(event(.toolResult(id: "a1", isError: false), at: 10))
        // The subagent transcript is read after the main one during replay.
        store.apply(event(.toolUse(ToolInvocation(id: "s1", name: "Read", summary: "x")), at: 5), from: .subagent("a1"))

        #expect(store.subagents[0].toolCalls == 1)
        #expect(store.subagents[0].state.status == .done)
        #expect(store.log.map(\.time) == store.log.map(\.time).sorted())
    }

    @Test func statsForToolsMCPAndSkills() {
        let store = SessionStore(now: t0)
        store.apply(event(.toolUse(ToolInvocation(id: "1", name: "mcp__github__create_issue")), at: 0))
        store.apply(event(.toolUse(ToolInvocation(id: "2", name: "mcp__github__list_prs")), at: 1))
        store.apply(event(.toolUse(ToolInvocation(id: "3", name: "Skill", skillName: "design")), at: 2))
        store.apply(event(.toolUse(ToolInvocation(id: "4", name: "Bash", summary: "make")), at: 3))
        store.apply(event(.toolResult(id: "4", isError: true), at: 4))

        #expect(store.mcpUsage["github"]?.count == 2)
        #expect(store.mcpUsage["github"]?.lastDetail == "list_prs")
        #expect(store.skillUsage["design"]?.count == 1)
        #expect(store.toolStats["Bash"]?.errors == 1)
        #expect(store.lastErrorAt == t0.addingTimeInterval(4))
        #expect(store.totalToolCalls == 4)
    }

    @Test func tokensCountEachMessageOnce() {
        let store = SessionStore(now: t0)
        let usage = TokenUsage(input: 1, cacheRead: 100, cacheCreation: 0, output: 30)
        // Claude Code repeats a message's usage on every content-block line.
        store.apply(event(.usage(messageId: "m1", usage), at: 0))
        store.apply(event(.usage(messageId: "m1", usage), at: 0))
        store.apply(event(.usage(messageId: "m2", usage), at: 1))
        #expect(store.outputTokens == 60)
        #expect(store.lastUsage?.context == 101)
    }

    @Test func taskToolsBuildATodoList() {
        let store = SessionStore(now: t0)
        store.apply(event(.toolUse(ToolInvocation(id: "1", name: "TaskCreate", taskEdit: .create(subject: "A", activeForm: nil))), at: 0))
        store.apply(event(.toolUse(ToolInvocation(id: "2", name: "TaskCreate", taskEdit: .create(subject: "B", activeForm: nil))), at: 1))
        store.apply(event(.toolUse(ToolInvocation(id: "3", name: "TaskUpdate", taskEdit: .update(taskId: "1", state: .completed, subject: nil))), at: 2))
        store.apply(event(.toolUse(ToolInvocation(id: "4", name: "TaskUpdate", taskEdit: .delete(taskId: "2"))), at: 3))
        #expect(store.todos.map(\.content) == ["A"])
        #expect(store.todos.first?.state == .completed)
    }

    @Test func interruptionResetsPendingWork() {
        let store = SessionStore(now: t0)
        store.apply(event(.toolUse(ToolInvocation(id: "a", name: "Agent", subagentType: "Explore")), at: 0))
        store.apply(event(.interrupted, at: 1))
        #expect(store.main.status == .waitingForUser)
        #expect(store.runningSubagents.isEmpty)
    }
}
