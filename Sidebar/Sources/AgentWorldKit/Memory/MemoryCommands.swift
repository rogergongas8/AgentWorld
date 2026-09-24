import Foundation

/// What `agentworld-ctl memory …` and the MCP tools do, as text for an
/// agent to read. Runs anywhere: the vault is files, the app needn't be up.
public struct MemoryCommands {
    public let vault: MemoryVault
    /// The project the agent works in (`global` outside one).
    public let project: String
    /// Who is writing: claude, codex, gemini…, or "you".
    public let agent: String?

    public init(vault: MemoryVault, folder: String, agent: String?) {
        self.vault = vault
        self.project = MemoryVault.scope(for: folder)
        self.agent = agent
    }

    public struct Result {
        public var ok: Bool
        public var output: String
        /// The note written or deleted, to tell the app.
        public var changed: MemoryNote?

        public init(ok: Bool, output: String, changed: MemoryNote? = nil) {
            self.ok = ok
            self.output = output
            self.changed = changed
        }
    }

    public static let help = """
    agentworld-ctl memory — the shared memory every agent CLI here can use

      memory                          this project's notes and the global ones
      memory search <words…>          notes that mention all these words, best first
      memory read <name>              a note (name, or scope/name)
      memory write <name> [text…]     create or replace a note (text from stdin if none)
          --append                    add to the end instead of replacing
          --global                    for every project (default: this project)
          --description TEXT          one line: what the note is about
          --kind KIND                 context, howto, decision, gotcha or preference
          --tags a,b                  a few words to find it by
      memory delete <name>            remove a note that's wrong or no longer true
      memory path                     where the vault lives (an Obsidian vault)

    One fact or topic per note. Search before writing: update what exists
    rather than adding a near-copy. Link notes with [[other-note]].
    """

    /// The scopes an agent sees: its project and global (or everything).
    public func scopes(_ which: String?) -> [String]? {
        switch which?.lowercased() {
        case "all": nil
        case "global": [MemoryVault.globalScope]
        case "project": [project]
        default: project == MemoryVault.globalScope ? [project] : [project, MemoryVault.globalScope]
        }
    }

    // MARK: - Commands

    public func list(scope: String? = nil) -> Result {
        let notes = vault.notes(in: scopes(scope))
        guard !notes.isEmpty else {
            return Result(ok: true, output: "No notes yet for \(project). Write one with `agentworld-ctl memory write <name> …`.")
        }
        return Result(ok: true, output: grouped(notes, snippetFor: nil))
    }

    public func search(_ query: String, scope: String? = nil) -> Result {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return list(scope: scope) }
        let found = vault.search(query, in: scopes(scope))
        guard !found.isEmpty else {
            let elsewhere = scope == "all" ? [] : vault.search(query, in: nil)
            return Result(ok: true, output: "Nothing about \"\(query)\" in \(scopeNames(scope))."
                + (elsewhere.isEmpty ? "" : " Other projects have \(elsewhere.count): search with scope all."))
        }
        return Result(ok: true, output: grouped(Array(found.prefix(20)), snippetFor: query))
    }

    public func read(_ name: String) -> Result {
        guard let note = vault.note(named: name, preferring: project) else {
            let near = vault.search(name.replacingOccurrences(of: "-", with: " "), in: nil).prefix(5).map(\.id)
            return Result(ok: false, output: "No note called \(name)." + (near.isEmpty ? "" : " Close: " + near.joined(separator: ", ")))
        }
        // A description that's only the note's first line would say it twice.
        let saysMore = note.description != MemoryVault.summary(of: note.body)
        var header = "# \(note.id)\n" + (saysMore ? note.description + "\n" : "")
        var facts: [String] = []
        if !note.agents.isEmpty { facts.append("by " + note.agents.joined(separator: ", ")) }
        facts.append("updated " + Self.relative(note.updated))
        if let kind = note.kind { facts.append(kind) }
        if !note.tags.isEmpty { facts.append("tags: " + note.tags.joined(separator: ", ")) }
        header += "(" + facts.joined(separator: " · ") + ")\n\n"
        return Result(ok: true, output: header + note.body)
    }

    public func write(name: String, body: String, global: Bool = false, description: String? = nil,
                      kind: String? = nil, tags: [String] = [], append: Bool = false) -> Result {
        if let kind, MemoryVault.kind(kind) == nil {
            return Result(ok: false, output: "unknown kind \(kind): use " + MemoryVault.kinds.map(\.id).joined(separator: ", "))
        }
        do {
            let existed = vault.note(named: name, preferring: global ? MemoryVault.globalScope : project)
                .map { $0.scope == (global ? MemoryVault.globalScope : project) } ?? false
            let note = try vault.write(name: name, body: body, scope: global ? MemoryVault.globalScope : project,
                                       description: description, kind: kind, tags: tags, agent: agent, append: append)
            let verb = append && existed ? "added to" : existed ? "replaced" : "saved"
            return Result(ok: true, output: "\(verb) \(note.id) — \(note.description)", changed: note)
        } catch {
            return Result(ok: false, output: "\(error)")
        }
    }

    public func delete(_ name: String) -> Result {
        do {
            let note = try vault.delete(name: name, preferring: project)
            return Result(ok: true, output: "deleted \(note.id)", changed: note)
        } catch {
            return Result(ok: false, output: "\(error)")
        }
    }

    // MARK: - Command line

    /// `agentworld-ctl memory <arguments>`; `stdin` gives a note's text when
    /// the arguments don't.
    public func run(_ arguments: [String], stdin: () -> String?) -> Result {
        var args = arguments
        let command = args.isEmpty ? "list" : args.removeFirst()
        func flag(_ name: String) -> Bool {
            guard let index = args.firstIndex(of: name) else { return false }
            args.remove(at: index)
            return true
        }
        func option(_ name: String) -> String? {
            guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return nil }
            let value = args[index + 1]
            args.removeSubrange(index...(index + 1))
            return value
        }
        switch command {
        case "help", "--help", "-h":
            return Result(ok: true, output: Self.help)
        case "list", "ls":
            let scope = flag("--global") ? "global" : flag("--all") ? "all" : option("--scope")
            return list(scope: scope)
        case "search", "find":
            let scope = flag("--global") ? "global" : flag("--all") ? "all" : option("--scope")
            return search(args.joined(separator: " "), scope: scope)
        case "read", "show", "cat":
            guard let name = args.first else { return Result(ok: false, output: "usage: memory read <name>") }
            return read(name)
        case "write", "save", "add":
            let global = flag("--global")
            let append = flag("--append")
            let description = option("--description")
            let kind = option("--kind")
            let tags = option("--tags")?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
            guard !args.isEmpty else { return Result(ok: false, output: "usage: memory write <name> [text…] (or the text on stdin)") }
            let name = args.removeFirst()
            let text = args.isEmpty || args == ["-"] ? stdin() ?? "" : args.joined(separator: " ")
            return write(name: name, body: text, global: global, description: description, kind: kind, tags: tags, append: append)
        case "delete", "rm", "forget":
            guard let name = args.first else { return Result(ok: false, output: "usage: memory delete <name>") }
            return delete(name)
        case "path", "where":
            return Result(ok: true, output: vault.root.path)
        default:
            return Result(ok: false, output: "unknown memory command \(command)\n\n" + Self.help)
        }
    }

    // MARK: - Formatting

    private func grouped(_ notes: [MemoryNote], snippetFor query: String?) -> String {
        var sections: [String] = []
        var order: [String] = []
        var byScope: [String: [MemoryNote]] = [:]
        for note in notes {
            if byScope[note.scope] == nil { order.append(note.scope) }
            byScope[note.scope, default: []].append(note)
        }
        for scope in order {
            let title = scope == MemoryVault.globalScope ? "global (every project)" : scope
            let lines = byScope[scope, default: []].map { note -> String in
                var line = "  \(note.name)" + (note.kind.map { " (\($0))" } ?? "") + " — \(note.description)"
                let who = note.agents.first.map { "\($0), " } ?? ""
                line += "  [\(who)\(Self.relative(note.updated))]"
                if let query, let snippet = MemoryVault.snippet(of: note, for: query), snippet != note.description {
                    line += "\n      " + snippet
                }
                return line
            }
            sections.append(title + ":\n" + lines.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    private func scopeNames(_ scope: String?) -> String {
        (scopes(scope) ?? ["any project"]).joined(separator: " or ")
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<90: return "just now"
        case ..<3600: return "\(Int(seconds / 60)) min ago"
        case ..<86400: return "\(Int(seconds / 3600)) h ago"
        case ..<(86400 * 60): return "\(Int(seconds / 86400)) d ago"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        }
    }
}
