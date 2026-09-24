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
        // No note has every word: any of them, by stem ("deployment" finds "deploy").
        #expect(vault.search("deployment schedule").map(\.name).first == "deploy")
    }

    @Test func readsWhatEachCLIRemembersOnItsOwn() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("aw-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appendingPathComponent("proj").path
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let memory = home.appendingPathComponent(".claude/projects/" + ProjectSlug.slug(forCwd: folder) + "/memory")
        try FileManager.default.createDirectory(at: memory, withIntermediateDirectories: true)
        try "---\nname: user-favorite-number\ndescription: The user's favorite number is 6.\nmetadata:\n  type: user\n---\n\nIt's 6.\n"
            .write(to: memory.appendingPathComponent("user_favorite_number.md"), atomically: true, encoding: .utf8)
        try "- [x](x.md)\n".write(to: memory.appendingPathComponent("MEMORY.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".gemini"), withIntermediateDirectories: true)
        try "# Mine\n\n## Gemini Added Memories\n- Prefers tabs\n- Lives in Barcelona\n"
            .write(to: home.appendingPathComponent(".gemini/GEMINI.md"), atomically: true, encoding: .utf8)
        let notes = NativeMemories.notes(forFolder: folder, home: home)
        #expect(notes.map(\.id).sorted() == ["claude:proj/user-favorite-number", "gemini:global/lives-in-barcelona", "gemini:global/prefers-tabs"])
        #expect(notes.first { $0.source == "claude" }?.description == "The user's favorite number is 6.")
        #expect(notes.first { $0.source == "claude" }?.kind == "preference")
        #expect(MemoryVault.rank(notes, by: "número favorito").first?.source == "claude")

        // Edited in place: Claude's header stays, Gemini's line changes, the rest of GEMINI.md too.
        let claude = try #require(notes.first { $0.source == "claude" })
        try NativeMemories.update(claude, body: "It's 7 now.", description: "The user's favorite number is 7.")
        let file = try String(contentsOf: claude.url, encoding: .utf8)
        #expect(file.contains("name: user-favorite-number") && file.contains("type: user"))
        #expect(file.contains("description: \"The user's favorite number is 7.\"") && file.hasSuffix("It's 7 now.\n"))
        let gemini = NativeMemories.notes(forFolder: folder, home: home).filter { $0.source == "gemini" }
        #expect(gemini.map(\.body) == ["Prefers tabs", "Lives in Barcelona"])
        try NativeMemories.update(gemini[0], body: "Prefers spaces")
        try NativeMemories.delete(gemini[1])
        let geminiFile = try String(contentsOf: home.appendingPathComponent(".gemini/GEMINI.md"), encoding: .utf8)
        #expect(geminiFile == "# Mine\n\n## Gemini Added Memories\n- Prefers spaces\n")
        // Deleting Claude's memory also drops its line from MEMORY.md.
        try "- [Favorite](user_favorite_number.md) — 6\n- [Other](other.md) — x\n"
            .write(to: memory.appendingPathComponent("MEMORY.md"), atomically: true, encoding: .utf8)
        let commands = MemoryCommands(vault: MemoryVault(root: home.appendingPathComponent("vault")), folder: folder, agent: "kiro", home: home)
        #expect(commands.run(["delete", "claude:user-favorite-number"], stdin: { nil }).ok)
        #expect(!FileManager.default.fileExists(atPath: claude.url.path))
        #expect(try String(contentsOf: memory.appendingPathComponent("MEMORY.md"), encoding: .utf8) == "- [Other](other.md) — x\n")
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

    @Test func kindsAreKeptAndGroupTheIndex() throws {
        let vault = try vault()
        defer { try? FileManager.default.removeItem(at: vault.root) }
        #expect(MemoryVault.kind("How-to") == "howto")
        #expect(MemoryVault.kind("Decisions") == "decision")
        #expect(MemoryVault.kind("whatever") == nil)
        try vault.write(name: "deploy", body: "make release", scope: "p", kind: "howto")
        try vault.write(name: "why-swift", body: "Native app.", scope: "p", kind: "decision")
        try vault.write(name: "loose", body: "Something.", scope: "p")
        // Rewriting without a kind keeps the one it had.
        try vault.write(name: "deploy", body: "make release", scope: "p", description: "How to deploy")
        let rewritten = try vault.write(name: "deploy", body: "make release, then tag", scope: "p")
        #expect(rewritten.kind == "howto")
        #expect(rewritten.description == "How to deploy")
        #expect(vault.note(named: "p/deploy")?.kind == "howto")
        let index = try String(contentsOf: vault.root.appendingPathComponent("p/index.md"), encoding: .utf8)
        let howTo = try #require(index.range(of: "## How to"))
        let decisions = try #require(index.range(of: "## Decisions"))
        let other = try #require(index.range(of: "## Other"))
        #expect(howTo.lowerBound < decisions.lowerBound && decisions.lowerBound < other.lowerBound)
        let commands = MemoryCommands(vault: vault, folder: "/tmp/p", agent: "codex")
        #expect(!commands.run(["write", "x", "--kind", "nonsense", "text"], stdin: { nil }).ok)
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
        #expect(tools.contains(#""name":"memory""#) && tools.contains(#""name":"team""#))
        #expect(!tools.contains("memory_write"))
        let write = try #require(server.handle(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"memory","arguments":{"action":"write","name":"a","content":"Hello"}}}"#))
        #expect(write.contains(#""isError":false"#))
        #expect(vault.note(named: "proj/a")?.agents == ["codex"])
        #expect(changed == ["saved proj/a"])
        let found = try #require(server.handle(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"memory","arguments":{"action":"search","query":"hello"}}}"#))
        #expect(found.contains("proj/a") || found.contains("  a —"))
        // The older one-tool-per-action names still work.
        let old = try #require(server.handle(#"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"memory_read","arguments":{"name":"a"}}}"#))
        #expect(old.contains("Hello"))
        let team = try #require(server.handle(#"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"team","arguments":{"action":"board"}}}"#))
        #expect(team.contains("Not running inside AgentWorld"))
        let unknown = try #require(server.handle(#"{"jsonrpc":"2.0","id":4,"method":"nope"}"#))
        #expect(unknown.contains("-32601"))
    }
}
