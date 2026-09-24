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

    /// The "## Gemini Added Memories" list in `~/.gemini/GEMINI.md`, as one global note.
    static func gemini(home: URL) -> [MemoryNote] {
        let url = home.appendingPathComponent(".gemini/GEMINI.md")
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let heading = text.range(of: "## Gemini Added Memories") else { return [] }
        var items: [String] = []
        for line in text[heading.upperBound...].split(separator: "\n", omittingEmptySubsequences: false).dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.hasPrefix("<!--") { break }
            if trimmed.hasPrefix("- ") { items.append(trimmed) }
        }
        guard !items.isEmpty else { return [] }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        return [MemoryNote(name: "gemini-memories", scope: MemoryVault.globalScope, description: "What Gemini CLI was asked to remember",
                           kind: "preference", agents: ["gemini"], tags: [], created: nil, updated: modified,
                           body: items.joined(separator: "\n"), url: url, source: "gemini")]
    }
}
