import Foundation

/// One note in the shared memory: a Markdown file with front matter, one
/// fact (or one topic) per note, written by any agent CLI.
public struct MemoryNote: Identifiable, Hashable, Sendable {
    /// The file name without `.md`: what agents read and write it by.
    public var name: String
    /// `global`, or the project it belongs to (the folder's name).
    public var scope: String
    public var description: String
    /// What sort of knowledge it is (see `MemoryVault.kinds`), if said.
    public var kind: String?
    /// Who wrote it, latest first (claude, codex, gemini…, "you").
    public var agents: [String]
    public var tags: [String]
    public var created: Date?
    public var updated: Date
    public var body: String
    public var url: URL
    /// Nil for the shared vault's notes; "claude" or "gemini" for what that
    /// CLI remembers on its own (edited in place, see `NativeMemories`).
    public var source: String? = nil
    /// For a Gemini memory: its line in GEMINI.md, to edit or remove it.
    public var nativeLine: String? = nil

    public var id: String { (source.map { $0 + ":" } ?? "") + scope + "/" + name }
    /// Kept by a CLI in its own format rather than in the vault.
    public var isNative: Bool { source != nil }
    public var isGlobal: Bool { scope == MemoryVault.globalScope }

    /// The notes it links to with `[[wikilinks]]`.
    public var links: [String] {
        var found: [String] = []
        var rest = body[...]
        while let open = rest.range(of: "[["), let close = rest[open.upperBound...].range(of: "]]") {
            let inner = rest[open.upperBound..<close.lowerBound]
            // [[name|label]] and [[name#heading]] link to `name`.
            let target = inner.split(whereSeparator: { $0 == "|" || $0 == "#" }).first.map(String.init) ?? ""
            if !target.isEmpty, !found.contains(target) { found.append(target) }
            rest = rest[close.upperBound...]
        }
        return found
    }
}

/// The shared memory: a folder of Markdown notes every agent CLI reads and
/// writes (through `agentworld-ctl memory` or its MCP server), and that is
/// plain Markdown any editor opens. One folder per project plus `global/`, each with
/// an `index.md` kept up to date; `Home.md` at the top links them.
public struct MemoryVault: Sendable {
    public static let globalScope = "global"
    static let indexName = "index"

    /// The sorts of knowledge a project's notes are grouped by, in order.
    public static let kinds: [(id: String, title: String, meaning: String)] = [
        ("context", "Context", "what the project is, how it's laid out"),
        ("howto", "How to", "build, test, run, deploy, release"),
        ("decision", "Decisions", "a choice made and why"),
        ("gotcha", "Gotchas", "traps, surprises, things that break"),
        ("preference", "Preferences", "how the user likes things done"),
    ]

    /// A kind as given by an agent ("how-to", "Decisions"…), or nil if unknown.
    public static func kind(_ text: String?) -> String? {
        guard let text else { return nil }
        let plain = text.lowercased().filter(\.isLetter)
        return kinds.first { plain == $0.id || plain == $0.id + "s" || plain == $0.title.lowercased().filter(\.isLetter) }?.id
    }

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    // MARK: - Where it lives

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("AgentWorld/Memory", isDirectory: true)
    }

    /// Remembers the vault's folder for `agentworld-ctl` (which may run
    /// outside the app, launched by a CLI as an MCP server).
    static var settingFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/agentworld/memory-folder")
    }

    /// `$AGENTWORLD_MEMORY`, else the folder the app was told to use, else `~/AgentWorld/Memory`.
    public static func configured(environment: [String: String] = ProcessInfo.processInfo.environment) -> MemoryVault {
        if let path = environment["AGENTWORLD_MEMORY"], !path.isEmpty { return MemoryVault(root: URL(fileURLWithPath: path, isDirectory: true)) }
        if let saved = try? String(contentsOf: settingFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !saved.isEmpty {
            return MemoryVault(root: URL(fileURLWithPath: (saved as NSString).expandingTildeInPath, isDirectory: true))
        }
        return MemoryVault(root: defaultRoot)
    }

    public static func saveConfigured(_ root: URL) {
        try? FileManager.default.createDirectory(at: settingFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (root.path + "\n").write(to: settingFile, atomically: true, encoding: .utf8)
    }

    /// A project's scope: the name of its repository (or folder). Home and
    /// the root folder have none: notes there are global.
    public static func scope(for folder: String) -> String {
        var url = URL(fileURLWithPath: folder, isDirectory: true).standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        guard url.path != home, url.path != "/" else { return globalScope }
        var probe = url
        while probe.path != "/", probe.path != home {
            if FileManager.default.fileExists(atPath: probe.appendingPathComponent(".git").path) {
                url = probe
                break
            }
            probe.deleteLastPathComponent()
        }
        let scope = slug(url.lastPathComponent)
        return scope.isEmpty ? globalScope : scope
    }

    /// A file-safe name: lowercase words joined by dashes.
    public static func slug(_ text: String) -> String {
        var result = ""
        for character in text.lowercased() {
            if character.isLetter || character.isNumber || character == "_" || character == "." {
                result.append(character)
            } else if !result.isEmpty, result.last != "-" {
                result.append("-")
            }
        }
        while result.last == "-" || result.last == "." { result.removeLast() }
        while result.first == "." || result.first == "-" { result.removeFirst() }
        return result
    }

    // MARK: - Reading

    /// The scopes that have a folder, `global` first.
    public func scopes() -> [String] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let names = folders.filter { url in
            !url.lastPathComponent.hasPrefix(".") && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.map(\.lastPathComponent).sorted()
        return names.filter { $0 == Self.globalScope } + names.filter { $0 != Self.globalScope }
    }

    /// Every note in these scopes (all of them when nil), newest first.
    public func notes(in scopes: [String]? = nil) -> [MemoryNote] {
        (scopes ?? self.scopes()).flatMap { scope -> [MemoryNote] in
            let folder = root.appendingPathComponent(scope, isDirectory: true)
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            return files.filter { $0.pathExtension == "md" && $0.deletingPathExtension().lastPathComponent != Self.indexName }
                .compactMap { Self.load($0, scope: scope) }
        }
        .sorted { $0.updated > $1.updated }
    }

    /// A note by name (or `scope/name`): in `preferring` first, then global, then anywhere.
    public func note(named reference: String, preferring scope: String? = nil) -> MemoryNote? {
        let parts = reference.split(separator: "/", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return Self.load(file(Self.slug(parts[1]), in: Self.slug(parts[0])), scope: Self.slug(parts[0]))
        }
        let name = Self.slug(reference.hasSuffix(".md") ? String(reference.dropLast(3)) : reference)
        let order = [scope, Self.globalScope].compactMap { $0 } + scopes()
        for candidate in order {
            if let note = Self.load(file(name, in: candidate), scope: candidate) { return note }
        }
        return nil
    }

    /// Notes matching every word of `query` (in the name, tags, description
    /// or text), the best first: name and tags count most.
    public func search(_ query: String, in scopes: [String]? = nil) -> [MemoryNote] {
        Self.rank(notes(in: scopes), by: query)
    }

    /// `notes` matching every word of `query`, the best first.
    public static func rank(_ notes: [MemoryNote], by query: String) -> [MemoryNote] {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init)
        guard !words.isEmpty else { return notes }
        let strict = score(notes, words, needsAll: true)
        if !strict.isEmpty { return strict }
        // Nothing has every word: any of them, by stem too, so "favorito"
        // finds "favorite" (agents write in one language, ask in another).
        let stems = words.filter { $0.count >= 4 }.map { String($0.prefix(max(4, Int((Double($0.count) * 0.6).rounded(.up))))) }
        return score(notes, Array(Set(words + stems)), needsAll: false)
    }

    private static func score(_ notes: [MemoryNote], _ words: [String], needsAll: Bool) -> [MemoryNote] {
        let scored = notes.compactMap { note -> (MemoryNote, Int)? in
            let name = note.name.lowercased().replacingOccurrences(of: "-", with: " ")
            let tags = note.tags.joined(separator: " ").lowercased()
            let description = note.description.lowercased()
            let body = note.body.lowercased()
            var score = 0
            for word in words {
                let inName = name.contains(word), inTags = tags.contains(word), inDescription = description.contains(word)
                let inBody = body.components(separatedBy: word).count - 1
                guard inName || inTags || inDescription || inBody > 0 else {
                    if needsAll { return nil } else { continue }
                }
                score += (inName ? 6 : 0) + (inTags ? 4 : 0) + (inDescription ? 3 : 0) + min(inBody, 5)
            }
            return score > 0 ? (note, score) : nil
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.updated > $1.0.updated }.map(\.0)
    }

    /// The line of the note where `query` first shows up, for search results.
    public static func snippet(of note: MemoryNote, for query: String) -> String? {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace })
        let line = note.body.split(separator: "\n").first { line in
            let lower = line.lowercased()
            return words.contains { lower.contains($0) }
        }
        return line.map { String($0.trimmingCharacters(in: .whitespaces).prefix(140)) }
    }

    // MARK: - Writing

    public enum Failure: Error, CustomStringConvertible {
        case badName
        case empty
        case notFound(String)

        public var description: String {
            switch self {
            case .badName: "a note needs a name made of letters or digits"
            case .empty: "nothing to write: give the note some text"
            case .notFound(let name): "no note called \(name)"
            }
        }
    }

    /// Creates or replaces a note, or adds to the end of it (`append`).
    /// Keeps who wrote it, when, and the scope's index.
    @discardableResult
    public func write(name rawName: String, body rawBody: String, scope rawScope: String, description: String? = nil,
                      kind: String? = nil, tags: [String] = [], agent: String? = nil, append: Bool = false,
                      now: Date = Date()) throws -> MemoryNote {
        let name = Self.slug(rawName.hasSuffix(".md") ? String(rawName.dropLast(3)) : rawName)
        let scope = Self.slug(rawScope).isEmpty ? Self.globalScope : Self.slug(rawScope)
        guard !name.isEmpty, name != Self.indexName else { throw Failure.badName }
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw Failure.empty }

        return try locked {
            try prepare()
            let url = file(name, in: scope)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let existing = Self.load(url, scope: scope)
            // A description someone wrote on purpose (not just the first line) outlives a rewrite.
            let chosenDescription = existing.map { $0.description != Self.summary(of: $0.body) } ?? false
            var note = existing ?? MemoryNote(name: name, scope: scope, description: "", kind: nil, agents: [], tags: [],
                                              created: now, updated: now, body: "", url: url)
            if let kind = Self.kind(kind) { note.kind = kind }
            note.body = append && existing != nil ? note.body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + body : body
            note.updated = now
            if let description, !description.trimmingCharacters(in: .whitespaces).isEmpty {
                note.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if note.description.isEmpty || (!append && !chosenDescription) {
                note.description = Self.summary(of: note.body)
            }
            for tag in tags.map({ Self.slug($0) }) where !tag.isEmpty && !note.tags.contains(tag) { note.tags.append(tag) }
            if let agent, !agent.isEmpty {
                note.agents.removeAll { $0 == agent }
                note.agents.insert(agent, at: 0)
            }
            try Self.render(note).write(to: url, atomically: true, encoding: .utf8)
            try rebuildIndex(scope)
            return note
        }
    }

    public func delete(name reference: String, preferring scope: String? = nil) throws -> MemoryNote {
        guard let note = note(named: reference, preferring: scope) else { throw Failure.notFound(reference) }
        return try locked {
            try FileManager.default.removeItem(at: note.url)
            try rebuildIndex(note.scope)
            return note
        }
    }

    /// Creates the vault with its `Home.md` and `global/` folder.
    public func prepare() throws {
        let global = root.appendingPathComponent(Self.globalScope, isDirectory: true)
        try FileManager.default.createDirectory(at: global, withIntermediateDirectories: true)
        let home = root.appendingPathComponent("Home.md")
        if !FileManager.default.fileExists(atPath: home.path) {
            try Self.homeText.write(to: home, atomically: true, encoding: .utf8)
        }
        if !FileManager.default.fileExists(atPath: global.appendingPathComponent("index.md").path) {
            try rebuildIndex(Self.globalScope)
        }
    }

    static let homeText = """
    # Shared memory

    What your agent CLIs (Claude Code, Codex, Gemini…) learned and want the
    others to know, kept by AgentWorld. Every note is plain Markdown: read and
    edit them in AgentWorld (⌘⇧O), in any editor, or ask an agent to.

    - [[global/index|Global]]: facts about you and how you like to work, for every project.
    - Each project has its own folder with an `index` of its notes.

    Agents use `agentworld-ctl memory` (or the `agentworld-memory` MCP server)
    to search, read and write these notes.

    """

    /// `<scope>/index.md`: every note with its description, for a quick look
    /// (agents read it before searching).
    func rebuildIndex(_ scope: String) throws {
        let notes = self.notes(in: [scope]).sorted { $0.name < $1.name }
        let title = scope == Self.globalScope ? "Global memory" : "Memory: \(scope)"
        var lines = ["# \(title)", "", "<!-- Kept by AgentWorld: rewritten whenever a note changes. -->", ""]
        if notes.isEmpty { lines.append("No notes yet.") }
        // Grouped by kind, the ones without a kind last.
        for (id, heading) in Self.kinds.map({ ($0.id as String?, $0.title) }) + [(nil, "Other")] {
            let group = notes.filter { $0.kind == id }
            guard !group.isEmpty else { continue }
            lines += ["## \(heading)", ""] + group.map { "- [[\($0.name)]] — \($0.description)" } + [""]
        }
        let url = root.appendingPathComponent(scope, isDirectory: true).appendingPathComponent(Self.indexName + ".md")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Files

    func file(_ name: String, in scope: String) -> URL {
        root.appendingPathComponent(scope, isDirectory: true).appendingPathComponent(name + ".md")
    }

    /// One writer at a time, across processes (several agents may write at once).
    private func locked<T>(_ work: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fd = open(root.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return try work() }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        return try work()
    }

    static func load(_ url: URL, scope: String) -> MemoryNote? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let front = FrontMatter.parse(text)
        let body = front.isEmpty ? text : stripFrontMatter(text)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        let agents = front.list("agents").isEmpty ? front["agent"].map { [$0] } ?? [] : front.list("agents")
        return MemoryNote(
            name: url.deletingPathExtension().lastPathComponent,
            scope: scope,
            description: front["description"] ?? summary(of: body),
            kind: kind(front["kind"]),
            agents: agents,
            tags: front.list("tags"),
            created: front["created"].flatMap(date),
            // Edited by hand after an agent wrote it: the file is newer.
            updated: max(front["updated"].flatMap(date) ?? .distantPast, modified.addingTimeInterval(-2)),
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            url: url
        )
    }

    static func render(_ note: MemoryNote) -> String {
        var lines = ["---", "description: \(yamlString(note.description))"]
        if let kind = note.kind { lines.append("kind: \(kind)") }
        if !note.agents.isEmpty { lines.append("agents: [\(note.agents.joined(separator: ", "))]") }
        if !note.tags.isEmpty { lines.append("tags: [\(note.tags.joined(separator: ", "))]") }
        if let created = note.created { lines.append("created: \(stamp(created))") }
        lines.append("updated: \(stamp(note.updated))")
        lines += ["---", "", note.body, ""]
        return lines.joined(separator: "\n")
    }

    /// The description a note gets when none is given: its first line.
    public static func firstLine(of body: String) -> String { summary(of: body) }

    /// The first line of text, without Markdown marks, as a description.
    static func summary(of body: String) -> String {
        let line = body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        var plain = line.trimmingCharacters(in: CharacterSet(charactersIn: "#>-*• ")).replacingOccurrences(of: "**", with: "")
        // [[name|label]] reads as "label", [[name]] as "name".
        while let open = plain.range(of: "[["), let close = plain[open.upperBound...].range(of: "]]") {
            let inner = plain[open.upperBound..<close.lowerBound]
            let label = inner.split(separator: "|", maxSplits: 1).last.map(String.init) ?? String(inner)
            plain.replaceSubrange(open.lowerBound..<close.upperBound, with: label)
        }
        return plain.count > 120 ? String(plain.prefix(117)) + "…" : plain
    }

    private static func stripFrontMatter(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return text }
        return lines[(close + 1)...].joined(separator: "\n")
    }

    private static func yamlString(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard flat.contains(":") || flat.contains("#") || flat.hasPrefix("[") || flat.hasPrefix("\"") || flat.hasPrefix("'") else { return flat }
        return "\"" + flat.replacingOccurrences(of: "\"", with: "'") + "\""
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func date(_ text: String) -> Date? {
        ISO8601DateFormatter().date(from: text)
            ?? { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: text) }()
    }
}
