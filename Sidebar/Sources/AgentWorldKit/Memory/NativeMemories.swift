import Foundation

/// What each CLI remembers on its own, read (never written) alongside the
/// shared vault, so a fact one agent kept "its own way" still reaches the
/// others: Claude Code's auto memory (one Markdown file per memory, per
/// project) and what Gemini's save_memory adds to ~/.gemini/GEMINI.md.
/// Codex keeps its memories in a database of its own; Kiro has none.
public enum NativeMemories {
    /// The notes of these CLIs for a project folder (global ones included).
    public static func notes(forFolder folder: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [MemoryNote] {
        claude(forFolder: folder, home: home) + gemini(home: home)
    }

    // MARK: - Claude Code

    /// `~/.claude/projects/<slug of the folder or its repository>/memory/*.md`.
    static func claude(forFolder folder: String, home: URL) -> [MemoryNote] {
        let projects = home.appendingPathComponent(".claude/projects", isDirectory: true)
        let scope = MemoryVault.scope(for: folder)
        var folders = [folder]
        if let root = repositoryRoot(folder), root != folder { folders.append(root) }
        var seen = Set<String>()
        var notes: [MemoryNote] = []
        for candidate in folders {
            guard let directory = ProjectSlug.sessionDirectory(forCwd: candidate, projectsRoot: projects) else { continue }
            let memory = directory.appendingPathComponent("memory", isDirectory: true)
            let files = (try? FileManager.default.contentsOfDirectory(at: memory, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "md" && file.lastPathComponent != "MEMORY.md" && seen.insert(file.path).inserted {
                guard var note = MemoryVault.load(file, scope: scope) else { continue }
                let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                let front = FrontMatter.parse(text)
                // Claude's own names ("user-favorite-number"); its kind in `type`,
                // at the top or nested under `metadata:`.
                note.name = MemoryVault.slug(front["name"] ?? note.name)
                let type = front["type"] ?? nestedValue("type", in: text)
                note.kind = MemoryVault.kind(type) ?? (["user", "feedback"].contains(type ?? "") ? "preference" : type == "project" ? "context" : nil)
                note.agents = ["claude"]
                note.source = "claude"
                notes.append(note)
            }
        }
        return notes
    }

    /// `key: value` on an indented line of the front matter.
    private static func nestedValue(_ key: String, in text: String) -> String? {
        for line in text.split(separator: "\n").prefix(40) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard line.first?.isWhitespace == true, trimmed.hasPrefix(key + ":") else { continue }
            return trimmed.dropFirst(key.count + 1).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        }
        return nil
    }

    private static func repositoryRoot(_ folder: String) -> String? {
        var url = URL(fileURLWithPath: folder, isDirectory: true).standardizedFileURL
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) { return url.path }
            url.deleteLastPathComponent()
        }
        return nil
    }

    // MARK: - Gemini CLI

    /// Each line of the "## Gemini Added Memories" list in `~/.gemini/GEMINI.md`,
    /// as a global note of its own (so each can be edited or removed).
    static func gemini(home: URL) -> [MemoryNote] {
        let url = home.appendingPathComponent(".gemini/GEMINI.md")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        var names = Set<String>()
        return geminiLines(text).map { line in
            let fact = String(line.trimmingCharacters(in: .whitespaces).dropFirst(2))
            var name = MemoryVault.slug(fact.split(separator: " ").prefix(6).joined(separator: " "))
            if name.isEmpty { name = "memory" }
            var unique = name
            var counter = 2
            while !names.insert(unique).inserted { unique = "\(name)-\(counter)"; counter += 1 }
            var note = MemoryNote(name: unique, scope: MemoryVault.globalScope, description: fact, kind: "preference",
                                  agents: ["gemini"], tags: [], created: nil, updated: modified, body: fact, url: url, source: "gemini")
            note.nativeLine = line
            return note
        }
    }

    /// The bullet lines under "## Gemini Added Memories".
    private static func geminiLines(_ text: String) -> [String] {
        guard let heading = text.range(of: "## Gemini Added Memories") else { return [] }
        var items: [String] = []
        for line in text[heading.upperBound...].split(separator: "\n", omittingEmptySubsequences: false).dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.hasPrefix("<!--") { break }
            if trimmed.hasPrefix("- ") { items.append(String(line)) }
        }
        return items
    }

    // MARK: - Changing them

    public enum Failure: Error, CustomStringConvertible {
        case gone(String)
        case empty

        public var description: String {
            switch self {
            case .gone(let id): "\(id) changed or disappeared meanwhile: reload and try again"
            case .empty: "nothing to write: give the memory some text"
            }
        }
    }

    /// Rewrites a CLI's own memory in its own format: Claude's file keeps
    /// its header (name, type…) with the new description and text; a Gemini
    /// line becomes the new text.
    @discardableResult
    public static func update(_ note: MemoryNote, body rawBody: String, description: String? = nil) throws -> MemoryNote {
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw Failure.empty }
        guard var text = try? String(contentsOf: note.url, encoding: .utf8) else { throw Failure.gone(note.id) }
        var updated = note
        switch note.source {
        case "gemini":
            guard let line = note.nativeLine, let range = text.range(of: line) else { throw Failure.gone(note.id) }
            let fact = body.replacingOccurrences(of: "\n", with: " ")
            let indent = String(line.prefix { $0 == " " })
            text.replaceSubrange(range, with: indent + "- " + fact)
            updated.body = fact
            updated.description = fact
            updated.name = MemoryVault.slug(fact.split(separator: " ").prefix(6).joined(separator: " "))
            updated.nativeLine = indent + "- " + fact
        default:
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var header: [String] = []
            if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
               let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
                header = Array(lines[...close])
            }
            if let description = description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                let quoted = "description: \"" + description.replacingOccurrences(of: "\"", with: "'") + "\""
                if let index = header.firstIndex(where: { $0.hasPrefix("description:") }) {
                    header[index] = quoted
                } else if !header.isEmpty {
                    header.insert(quoted, at: 1)
                }
                updated.description = description
            }
            text = (header.isEmpty ? "" : header.joined(separator: "\n") + "\n\n") + body + "\n"
            updated.body = body
        }
        try text.write(to: note.url, atomically: true, encoding: .utf8)
        updated.updated = Date()
        return updated
    }

    /// Removes a CLI's own memory: Claude's file (and its line in that
    /// folder's MEMORY.md index), or the Gemini line.
    public static func delete(_ note: MemoryNote) throws {
        switch note.source {
        case "gemini":
            guard var text = try? String(contentsOf: note.url, encoding: .utf8), let line = note.nativeLine,
                  let range = text.range(of: line + "\n") ?? text.range(of: line) else { throw Failure.gone(note.id) }
            text.removeSubrange(range)
            try text.write(to: note.url, atomically: true, encoding: .utf8)
        default:
            try FileManager.default.removeItem(at: note.url)
            let index = note.url.deletingLastPathComponent().appendingPathComponent("MEMORY.md")
            if let text = try? String(contentsOf: index, encoding: .utf8) {
                let file = note.url.lastPathComponent
                let kept = text.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.contains("(\(file))") }
                try? kept.joined(separator: "\n").write(to: index, atomically: true, encoding: .utf8)
            }
        }
    }
}
