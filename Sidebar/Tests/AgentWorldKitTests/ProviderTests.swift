import Foundation
import Testing
@testable import AgentWorldKit

@Suite struct ProviderTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aw-providers-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func tomlTablesKeysAndQuotedPaths() {
        let toml = TOMLLite.parse("""
        model = "gpt-5" # default
        instructions = \"\"\"
        ignored = "inside a multi-line string"
        \"\"\"
        [plugins."pdf@market"]
        enabled = true
        [mcp_servers.github]
        url = 'https://example.com/mcp'
        [mcp_servers.github.env]
        TOKEN = "x"
        """)
        #expect(toml.value("model") == "gpt-5")
        #expect(toml.value("ignored") == nil)
        #expect(toml.value("enabled", in: ["plugins", "pdf@market"]) == "true")
        #expect(toml.value("url", in: ["mcp_servers", "github"]) == "https://example.com/mcp")
        #expect(toml.value("TOKEN", in: ["mcp_servers", "github", "env"]) == "x")
    }

    @Test func scansCodex() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let project = root.appendingPathComponent("project")
        let codex = home.appendingPathComponent(".codex")
        try write("""
        model = "gpt-5.6"
        [plugins."pdf@bundled"]
        enabled = true
        [plugins."off@bundled"]
        enabled = false
        [mcp_servers.node_repl]
        command = "node"
        [mcp_servers.node_repl.env]
        A = "1"
        [mcp_servers.remote]
        url = "https://x"
        """, to: codex.appendingPathComponent("config.toml"))
        try write("---\ndescription: Review code\n---", to: codex.appendingPathComponent("skills/.system/review/SKILL.md"))
        try write("---\ndescription: Mine\n---", to: codex.appendingPathComponent("skills/mine/SKILL.md"))
        try write(#"{"name":"pdf","description":"PDFs"}"#, to: codex.appendingPathComponent("plugins/cache/bundled/pdf/1.9.0/.codex-plugin/plugin.json"))
        try write(#"{"name":"pdf","description":"old"}"#, to: codex.appendingPathComponent("plugins/cache/bundled/pdf/1.10.0/.codex-plugin/plugin.json"))
        try write("---\n---", to: codex.appendingPathComponent("plugins/cache/bundled/pdf/1.10.0/skills/read-pdf/SKILL.md"))
        try write(#"{"name":"off"}"#, to: codex.appendingPathComponent("plugins/cache/bundled/off/1.0/.codex-plugin/plugin.json"))
        try write("---\ndescription: Ship it\n---", to: codex.appendingPathComponent("prompts/ship.md"))
        try write("# Rules\nBe nice.", to: project.appendingPathComponent("AGENTS.md"))

        let config = ProviderScanner(provider: .codex, projectURL: project, homeURL: home).scan()
        #expect(config.model == "gpt-5.6")
        #expect(config.plugins.map(\.name) == ["pdf"])
        #expect(config.plugins[0].description == "old")  // newest version by numeric order (1.10 > 1.9)
        #expect(Set(config.skills.map(\.qualifiedName)) == ["mine", "review", "pdf:read-pdf"])
        #expect(config.skills.first { $0.name == "review" }?.scope == .builtin)
        #expect(config.mcpServers.map(\.name).sorted() == ["node_repl", "remote"])
        #expect(config.mcpServers.first { $0.name == "remote" }?.transport == "http")
        #expect(config.commands.map(\.name) == ["prompts:ship"])
        #expect(config.agents.isEmpty)
        #expect(config.repository.instructionsFile == "AGENTS.md")
        #expect(config.repository.instructionsTitle == "Rules")
    }

    @Test func scansGeminiWithExtensions() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let project = root.appendingPathComponent("project")
        let gemini = home.appendingPathComponent(".gemini")
        try write(#"{"model":{"name":"gemini-3-pro"},"mcpServers":{"web":{"httpUrl":"https://x"},"local":{"command":"x"}}}"#,
                  to: gemini.appendingPathComponent("settings.json"))
        try write("---\ndescription: React checks\n---", to: gemini.appendingPathComponent("skills/react-doctor/SKILL.md"))
        try write("description = \"Commit and push\"\nprompt = \"\"\"\ndo it\n\"\"\"", to: gemini.appendingPathComponent("commands/git/ship.toml"))
        try write(#"{"name":"cloud","version":"1.0","description":"Cloud tools","mcpServers":{"cloud-mcp":{"command":"c"}}}"#,
                  to: gemini.appendingPathComponent("extensions/cloud/gemini-extension.json"))
        try write("---\n---", to: gemini.appendingPathComponent("extensions/cloud/skills/deploy/SKILL.md"))
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        let config = ProviderScanner(provider: .gemini, projectURL: project, homeURL: home).scan()
        #expect(config.model == "gemini-3-pro")
        #expect(Set(config.mcpServers.map(\.name)) == ["web", "local", "cloud-mcp"])
        #expect(config.mcpServers.first { $0.name == "web" }?.transport == "http")
        #expect(Set(config.skills.map(\.qualifiedName)) == ["react-doctor", "cloud:deploy"])
        #expect(config.commands.map(\.name) == ["git:ship"])
        #expect(config.commands.first?.description == "Commit and push")
        #expect(config.plugins.map(\.name) == ["cloud"])
        #expect(config.repository.instructionsFile == "GEMINI.md")
        #expect(!config.repository.hasInstructions)
    }

    @Test func profilesAddCustomEntriesAfterDefaults() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("profiles.json")
        try write(#"[{"name":"Opus plan","provider":"claude","args":["--model","opus"]},{"name":"bad","provider":"nope"},{"provider":"codex"}]"#, to: file)

        let profiles = LaunchProfile.load(from: file)
        #expect(profiles.count == Provider.all.count + 1)
        #expect(profiles.last?.name == "Opus plan")
        #expect(profiles.last?.args == ["--model", "opus"])
        #expect(profiles.last?.isCustom == true)
        #expect(LaunchProfile.load(from: root.appendingPathComponent("missing.json")) == LaunchProfile.defaults)
    }

    @Test func savedProfilesLoadBack() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("nested/profiles.json")
        let custom = LaunchProfile(name: "Claude yolo", provider: .claude, args: ["--dangerously-skip-permissions"],
                                   env: ["FOO": "bar"], isCustom: true)
        try LaunchProfile.save(LaunchProfile.defaults + [custom], to: file)

        let loaded = LaunchProfile.load(from: file)
        #expect(loaded == LaunchProfile.defaults + [custom])
        try LaunchProfile.save(LaunchProfile.defaults, to: file)
        #expect(LaunchProfile.load(from: file) == LaunchProfile.defaults)
    }

    @Test func splitsArgumentsLikeAShell() {
        #expect(LaunchProfile.splitArguments("--model opus  -p") == ["--model", "opus", "-p"])
        #expect(LaunchProfile.splitArguments(#"--append-system-prompt "be brief" --x 'a b'"#) == ["--append-system-prompt", "be brief", "--x", "a b"])
        #expect(LaunchProfile.splitArguments(#"--empty "" end"#) == ["--empty", "", "end"])
        #expect(LaunchProfile.splitArguments("  ") == [])
        let arguments = ["--model", "opus", "a b", ""]
        #expect(LaunchProfile.splitArguments(LaunchProfile.joinArguments(arguments)) == arguments)
    }

    @Test func locatesExecutablesOnPath() {
        #expect(Provider.locate("sh", environment: ["PATH": "/bin"]) == "/bin/sh")
        #expect(Provider.locate("/bin/sh") == "/bin/sh")
        #expect(Provider.locate("definitely-not-a-real-cli-xyz", environment: ["PATH": "/bin"]) == nil)
    }
}
