import Foundation
import Testing
@testable import AgentWorldKit

@Suite struct GitChangesTests {
    private func repository() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aw-git-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        GitChanges.run(["init", "-q"], in: url.path)
        GitChanges.run(["config", "user.email", "t@example.com"], in: url.path)
        GitChanges.run(["config", "user.name", "Test"], in: url.path)
        return url
    }

    @Test func parsesPorcelainStatus() {
        let output = " M a.swift\0?? new file.txt\0R  b.swift\0old b.swift\0 D gone.md\0A  added.md\0UU both.txt\0"
        let parsed = GitChanges.parseStatus(output)
        #expect(parsed.map(\.0) == ["a.swift", "new file.txt", "b.swift", "gone.md", "added.md", "both.txt"])
        #expect(parsed.map(\.1) == [.modified, .untracked, .renamed, .deleted, .added, .conflicted])
    }

    @Test func readsChangesWithLineCountsAndDiffs() throws {
        let repo = try repository()
        defer { try? FileManager.default.removeItem(at: repo) }
        try "one\ntwo\nthree\n".write(to: repo.appendingPathComponent("kept.txt"), atomically: true, encoding: .utf8)
        try "bye\n".write(to: repo.appendingPathComponent("gone.txt"), atomically: true, encoding: .utf8)
        GitChanges.run(["add", "."], in: repo.path)
        GitChanges.run(["commit", "-q", "-m", "start"], in: repo.path)

        try "one\n2\nthree\nfour\n".write(to: repo.appendingPathComponent("kept.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: repo.appendingPathComponent("gone.txt"))
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "a\nb\n".write(to: repo.appendingPathComponent("src/new.swift"), atomically: true, encoding: .utf8)

        let result = try #require(GitChanges.read(repo.appendingPathComponent("src").path))
        let byPath = Dictionary(uniqueKeysWithValues: result.changes.map { ($0.path, $0) })
        #expect(byPath["kept.txt"]?.kind == .modified)
        #expect(byPath["kept.txt"]?.added == 2)
        #expect(byPath["kept.txt"]?.removed == 1)
        #expect(byPath["gone.txt"]?.kind == .deleted)
        #expect(byPath["src/new.swift"]?.kind == .untracked)
        #expect(byPath["src/new.swift"]?.added == 2)
        #expect(byPath["src/new.swift"]?.folder == "src")

        let diff = GitChanges.diff(try #require(byPath["kept.txt"]), root: result.root)
        #expect(diff.contains("-two"))
        #expect(diff.contains("+four"))
        #expect(GitChanges.diff(try #require(byPath["src/new.swift"]), root: result.root).contains("+b"))
    }

    @Test func notARepository() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aw-plain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(GitChanges.read(folder.path) == nil)
    }
}
