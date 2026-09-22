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

    @Test func sessionDirectoryResolvesPrivateTmp() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // Claude Code saw the real path; the shell may report the /tmp alias.
        let dir = root.appendingPathComponent(ProjectSlug.slug(forCwd: "/private/tmp"), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(ProjectSlug.sessionDirectory(forCwd: "/tmp", projectsRoot: root) == dir)
        #expect(ProjectSlug.sessionDirectory(forCwd: "/private/tmp", projectsRoot: root) == dir)
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

        let config = ProviderScanner(projectURL: project, homeURL: home).scan()
        #expect(config.customAgents.map(\.name) == ["reviewer", "helper"])
        #expect(config.agents[0].scope == .project)
        #expect(config.agents[0].description == "Reviews code")
        #expect(config.agents[0].tools == ["Read"])
        #expect(config.agents.contains { $0.name == "Explore" && $0.scope == .builtin })
        #expect(config.skills.map(\.name) == ["lint"])
        #expect(config.mcpServers.map(\.name) == ["github", "local-db", "sentry"])
        #expect(config.mcpServers.map(\.scope) == [.project, .local, .user])
        #expect(config.mcpServers[2].transport == "http")
    }

    @Test func frontMatterRequiresFences() {
        #expect(FrontMatter.parse("name: x").isEmpty)
        #expect(FrontMatter.parse("---\nname: x\n").isEmpty)
    }

    @Test func frontMatterReadsBlocksAndLists() {
        let meta = FrontMatter.parse("---\nname: x\ndescription: >\n  a long\n  text\ntools: Read, Grep\nskills:\n  - lint\n  - \"docs\"\n---\nbody")
        #expect(meta["description"] == "a long text")
        #expect(meta.list("tools") == ["Read", "Grep"])
        #expect(meta.list("skills") == ["lint", "docs"])
        #expect(FrontMatter.parse("---\ndescription: \"**MUST** use `x`\"\n---").description == "MUST use x")
    }

    @Test func scansPluginsAndCommands() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let fm = FileManager.default
        let plugin = home.appendingPathComponent(".claude/plugins/synced/account/figma", isDirectory: true)
        let disabled = home.appendingPathComponent("installs/off", isDirectory: true)
        for directory in [
            plugin.appendingPathComponent(".claude-plugin"), plugin.appendingPathComponent("skills/figma-use"),
            plugin.appendingPathComponent("agents"), plugin.appendingPathComponent("commands"),
            disabled.appendingPathComponent(".claude-plugin"), disabled.appendingPathComponent("skills/hidden"),
            home.appendingPathComponent(".claude/commands/git"), project,
        ] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try #"{"name":"figma","version":"2.0","author":{"name":"Figma"},"description":"Design"}"#
            .write(to: plugin.appendingPathComponent(".claude-plugin/plugin.json"), atomically: true, encoding: .utf8)
        try "---\ndescription: Use Figma\n---".write(to: plugin.appendingPathComponent("skills/figma-use/SKILL.md"), atomically: true, encoding: .utf8)
        try "---\nname: designer\n---".write(to: plugin.appendingPathComponent("agents/designer.md"), atomically: true, encoding: .utf8)
        try "---\ndescription: Sync\n---".write(to: plugin.appendingPathComponent("commands/sync.md"), atomically: true, encoding: .utf8)
        try #"{"mcpServers":{"figma-mcp":{"type":"http"}}}"#.write(to: plugin.appendingPathComponent(".mcp.json"), atomically: true, encoding: .utf8)
        try #"{"name":"off"}"#.write(to: disabled.appendingPathComponent(".claude-plugin/plugin.json"), atomically: true, encoding: .utf8)
        try "---\n---".write(to: disabled.appendingPathComponent("skills/hidden/SKILL.md"), atomically: true, encoding: .utf8)
        try #"{"plugins":{"off@market":[{"installPath":"\#(disabled.path)"}]}}"#
            .write(to: home.appendingPathComponent(".claude/plugins/installed_plugins.json"), atomically: true, encoding: .utf8)
        try #"{"enabledPlugins":{"off@market":false},"hooks":{"Stop":[]}}"#
            .write(to: home.appendingPathComponent(".claude/settings.json"), atomically: true, encoding: .utf8)
        try "hi".write(to: home.appendingPathComponent(".claude/commands/git/ship.md"), atomically: true, encoding: .utf8)
        try "{}".write(to: project.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "# My App\n\nA tool.\n".write(to: project.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)

        let config = ProviderScanner(projectURL: project, homeURL: home).scan()
        #expect(config.plugins.map(\.name) == ["figma"])
        #expect(config.plugins[0].author == "Figma")
        #expect(config.plugins[0].mcpServers == ["figma-mcp"])
        #expect(config.skills.map(\.qualifiedName) == ["figma:figma-use"])
        #expect(config.customAgents.map(\.qualifiedName) == ["figma:designer"])
        #expect(config.commands.map(\.qualifiedName).sorted() == ["figma:sync", "git:ship"])
        #expect(config.mcpServers.map(\.name) == ["figma-mcp"])
        #expect(config.repository.stacks == ["swift"])
        #expect(config.repository.instructionsTitle == "My App")
        #expect(config.repository.instructionsExcerpt == ["A tool."])
        #expect(config.repository.hookEvents == ["Stop"])
    }
}
