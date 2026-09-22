import Foundation
import Testing
@testable import AgentWorldKit

@Suite struct TranscriptFilesTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aw-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func slugMatchesClaudeCode() {
        #expect(ProjectSlug.slug(forCwd: "/Users/me/Developer/AgentWorld") == "-Users-me-Developer-AgentWorld")
        #expect(ProjectSlug.slug(forCwd: "/tmp/my.app_v2") == "-tmp-my-app-v2")
    }

    @Test func tailerBuffersPartialLinesAndHandlesTruncation() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("s.jsonl")
        try "one\ntw".write(to: file, atomically: true, encoding: .utf8)

        let tailer = TranscriptTailer()
        tailer.attach(to: file, fromStart: true)
        #expect(tailer.poll() == ["one"])

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("o\nthree\n".utf8))
        try handle.close()
        #expect(tailer.poll() == ["two", "three"])

        try "new\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(tailer.poll() == ["new"])
    }

    @Test func tailerCanSkipExistingContent() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("s.jsonl")
        try "old\n".write(to: file, atomically: true, encoding: .utf8)
        let tailer = TranscriptTailer()
        tailer.attach(to: file, fromStart: false)
        #expect(tailer.poll().isEmpty)
    }

    @Test func pinnedLocatorWaitsForItsSession() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cwd = "/work/app"
        let dir = root.appendingPathComponent(ProjectSlug.slug(forCwd: cwd), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "x\n".write(to: dir.appendingPathComponent("other.jsonl"), atomically: true, encoding: .utf8)

        let locator = SessionLocator(cwd: cwd, projectsRoot: root, pinnedSessionId: "mine")
        #expect(locator.poll() == nil)
        #expect(locator.isProjectDirectoryFound)

        let mine = dir.appendingPathComponent("mine.jsonl")
        try "x\n".write(to: mine, atomically: true, encoding: .utf8)
        #expect(locator.poll()?.lastPathComponent == "mine.jsonl")
        #expect(locator.poll() == nil)
    }

    @Test func unpinnedLocatorFollowsNewestTranscript() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cwd = "/work/app"
        let dir = root.appendingPathComponent(ProjectSlug.slug(forCwd: cwd), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = dir.appendingPathComponent("old.jsonl")
        let new = dir.appendingPathComponent("new.jsonl")
        try "x\n".write(to: old, atomically: true, encoding: .utf8)
        try "x\n".write(to: new, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: old.path)

        let locator = SessionLocator(cwd: cwd, projectsRoot: root, pinnedSessionId: nil)
        #expect(locator.poll()?.lastPathComponent == "new.jsonl")
    }

    @Test func configScannerReadsAgentsSkillsAndMCP() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: project.appendingPathComponent(".claude/agents"), withIntermediateDirectories: true)
        try fm.createDirectory(at: project.appendingPathComponent(".claude/skills/lint"), withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent(".claude/agents"), withIntermediateDirectories: true)

        try "---\nname: reviewer\ndescription: \"Reviews code\"\nmodel: sonnet\ntools:\n  - Read\n---\nbody".write(to: project.appendingPathComponent(".claude/agents/reviewer.md"), atomically: true, encoding: .utf8)
        try "---\nname: reviewer\n---\n".write(to: home.appendingPathComponent(".claude/agents/reviewer.md"), atomically: true, encoding: .utf8)
        try "---\nname: helper\n---\n".write(to: home.appendingPathComponent(".claude/agents/helper.md"), atomically: true, encoding: .utf8)
        try "---\ndescription: Lints\n---\n".write(to: project.appendingPathComponent(".claude/skills/lint/SKILL.md"), atomically: true, encoding: .utf8)
        try #"{"mcpServers":{"github":{"command":"gh"}}}"#.write(to: project.appendingPathComponent(".mcp.json"), atomically: true, encoding: .utf8)
        try #"{"mcpServers":{"sentry":{"type":"http"}},"projects":{"\#(project.standardizedFileURL.path)":{"mcpServers":{"local-db":{"type":"stdio"}}}}}"#
            .write(to: home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)

        let config = ClaudeConfigScanner(projectURL: project, homeURL: home).scan()
        #expect(config.agents.map(\.name) == ["reviewer", "helper"])
        #expect(config.agents[0].scope == .project)
        #expect(config.agents[0].description == "Reviews code")
        #expect(config.skills.map(\.name) == ["lint"])
        #expect(config.mcpServers.map(\.name) == ["github", "local-db", "sentry"])
        #expect(config.mcpServers.map(\.scope) == [.project, .local, .user])
        #expect(config.mcpServers[2].transport == "http")
    }

    @Test func frontMatterRequiresFences() {
        #expect(FrontMatter.parse("name: x").isEmpty)
        #expect(FrontMatter.parse("---\nname: x\n").isEmpty)
        #expect(FrontMatter.parse("---\nname: x\ndescription: >\n  long\n---")["description"] == nil)
    }
}
