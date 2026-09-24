import Foundation
import Testing
@testable import AgentWorldKit

@Suite struct MemoryTests {
    private func vault() throws -> MemoryVault {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aw-memory-\(UUID().uuidString)", isDirectory: true)
        return MemoryVault(root: url)
    }

    @Test func writesReadsAndIndexes() throws {
        let vault = try vault()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        try vault.write(name: "Run Tests", body: "Run `swift test`. See [[build-app]].", scope: "sidebar", tags: ["Swift"], agent: "claude")
        let note = try #require(vault.note(named: "run-tests", preferring: "sidebar"))
        #expect(note.name == "run-tests")
        #expect(note.description == "Run `swift test`. See build-app.")
        #expect(note.agents == ["claude"])
        #expect(note.tags == ["swift"])
        #expect(note.links == ["build-app"])
        let index = try String(contentsOf: vault.root.appendingPathComponent("sidebar/index.md"), encoding: .utf8)
        #expect(index.contains("- [[run-tests]] — Run `swift test`. See build-app."))
        #expect(FileManager.default.fileExists(atPath: vault.root.appendingPathComponent("Home.md").path))
        // The index isn't a note.
        #expect(vault.notes().map(\.name) == ["run-tests"])
    }

    @Test func appendKeepsTextAndCreditsEachWriter() throws {
        let vault = try vault()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        try vault.write(name: "gotchas", body: "First.", scope: "p", description: "Things that bite", agent: "claude")
        let note = try vault.write(name: "gotchas", body: "Second.", scope: "p", agent: "codex", append: true)
        #expect(note.body == "First.\n\nSecond.")
        #expect(note.description == "Things that bite")
        #expect(note.agents == ["codex", "claude"])
        let reread = try #require(vault.note(named: "p/gotchas"))
        #expect(reread.body == note.body)
        #expect(reread.agents == ["codex", "claude"])
    }

    @Test func searchRanksNamesFirstAndNeedsEveryWord() throws {
        let vault = try vault()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        try vault.write(name: "deploy", body: "Push to main, then tag.", scope: "p")
        try vault.write(name: "release-notes", body: "Mention the deploy date.", scope: "p")
        #expect(vault.search("deploy").map(\.name) == ["deploy", "release-notes"])
        #expect(vault.search("deploy tag").map(\.name) == ["deploy"])
        #expect(vault.search("nothing-like-this").isEmpty)
    }

    @Test func readFallsBackToGlobalThenAnywhere() throws {
        let vault = try vault()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        try vault.write(name: "style", body: "Global style.", scope: MemoryVault.globalScope)
        try vault.write(name: "style", body: "Project style.", scope: "a")
        try vault.write(name: "only-b", body: "B.", scope: "b")
        #expect(vault.note(named: "style", preferring: "a")?.body == "Project style.")
        #expect(vault.note(named: "style", preferring: "c")?.body == "Global style.")
        #expect(vault.note(named: "only-b", preferring: "a")?.scope == "b")
    }

    @Test func deleteRemovesItFromTheIndex() throws {
        let vault = try vault()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        try vault.write(name: "old", body: "Stale.", scope: "p")
        try vault.delete(name: "old", preferring: "p")
        #expect(vault.note(named: "old") == nil)
        let index = try String(contentsOf: vault.root.appendingPathComponent("p/index.md"), encoding: .utf8)
        #expect(!index.contains("[[old]]"))
        #expect(throws: MemoryVault.Failure.self) { try vault.delete(name: "old") }
    }

    @Test func refusesEmptyNotesAndTheIndexName() throws {
        let vault = try vault()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        #expect(throws: MemoryVault.Failure.self) { try vault.write(name: "x", body: "  ", scope: "p") }
        #expect(throws: MemoryVault.Failure.self) { try vault.write(name: "index", body: "x", scope: "p") }
        #expect(throws: MemoryVault.Failure.self) { try vault.write(name: "!!", body: "x", scope: "p") }
    }

    @Test func slugsAndScopes() throws {
        #expect(MemoryVault.slug("How to Run: Tests!") == "how-to-run-tests")
        #expect(MemoryVault.slug("../escape") == "escape")
        #expect(MemoryVault.scope(for: FileManager.default.homeDirectoryForCurrentUser.path) == MemoryVault.globalScope)
        let repo = FileManager.default.temporaryDirectory.appendingPathComponent("My Repo \(UUID().uuidString.prefix(4))")
        let nested = repo.appendingPathComponent("src/deep")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }
        #expect(MemoryVault.scope(for: nested.path) == MemoryVault.slug(repo.lastPathComponent))
    }

    @Test func commandLineWritesFromStdinAndGlobal() throws {
        let vault = try vault()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        let commands = MemoryCommands(vault: vault, folder: "/tmp/proj", agent: "gemini")
        let written = commands.run(["write", "tone", "--global", "--tags", "style,voice"]) { "Short answers." }
        #expect(written.ok)
        #expect(written.changed?.scope == MemoryVault.globalScope)
        #expect(commands.run(["search", "short"], stdin: { nil }).output.contains("tone"))
        #expect(!commands.run(["read", "missing"], stdin: { nil }).ok)
    }

    @Test func mcpServerSpeaksJSONRPC() throws {
        let vault = try vault()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        var changed: [String] = []
        let server = MemoryMCPServer(vault: vault, folder: "/tmp/proj", agent: nil) { note, action in changed.append(action + " " + note.id) }
        let hello = try #require(server.handle(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"codex-mcp-client"}}}"#))
        #expect(hello.contains(#""protocolVersion":"2025-03-26""#))
        #expect(server.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        let tools = try #require(server.handle(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        for name in ["memory_search", "memory_list", "memory_read", "memory_write", "memory_delete"] { #expect(tools.contains(name)) }
        let write = try #require(server.handle(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"memory_write","arguments":{"name":"a","content":"Hello"}}}"#))
        #expect(write.contains(#""isError":false"#))
        #expect(vault.note(named: "proj/a")?.agents == ["codex"])
        #expect(changed == ["saved proj/a"])
        let unknown = try #require(server.handle(#"{"jsonrpc":"2.0","id":4,"method":"nope"}"#))
        #expect(unknown.contains("-32601"))
    }
}
