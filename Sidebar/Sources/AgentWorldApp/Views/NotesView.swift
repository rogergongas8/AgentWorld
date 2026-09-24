import AgentWorldKit
import AppKit
import SwiftUI

/// The shared memory, inside the app (⌘⇧O): every note your agents wrote,
/// read as Markdown with `[[links]]` you can follow, what links back, who
/// wrote it, and a graph of how the notes connect. Edit in place, or open
/// the same files in Obsidian.
struct NotesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @AppStorage("notesScope") private var scopeFilter = "here"
    @AppStorage("notesMode") private var mode = "note"
    @State private var editing = false
    @State private var draft = ""
    @State private var draftDescription = ""
    /// A note being created: its name and scope, until it's saved.
    @State private var creating: (name: String, scope: String)?
    @State private var newName = ""
    @State private var naming = false
    @State private var confirmDelete = false
    @State private var message: String?
    @FocusState private var searchFocused: Bool
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Palette.border).frame(height: 1)
            HStack(spacing: 0) {
                list.frame(width: 250)
                Rectangle().fill(Palette.border).frame(width: 1)
                Group {
                    if mode == "graph" {
                        NotesGraph(notes: shown, selected: selectedNote?.id) { select($0) }
                    } else if editing {
                        editor
                    } else if let note = selectedNote {
                        reader(note)
                    } else {
                        empty
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let note = selectedNote, !editing {
                    Rectangle().fill(Palette.border).frame(width: 1)
                    info(note).frame(width: 250)
                }
            }
        }
        .background(Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .onExitCommand {
            if editing { cancelEditing() } else if naming { naming = false } else { model.showsNotes = false }
        }
        .onAppear {
            if model.openNoteID == nil { model.openNoteID = shown.first?.id }
        }
        .onChange(of: model.openNoteID) { _ in
            if editing, creating == nil { cancelEditing() }
            confirmDelete = false
        }
    }

    // MARK: - Data

    /// The notes the list shows: this workspace's and the global ones, or
    /// every project's; narrowed by the search.
    private var shown: [MemoryNote] {
        let pool = scopeFilter == "all" ? model.memoryNotes : model.workspaceMemory
        let words = search.lowercased().split(separator: " ")
        guard !words.isEmpty else { return pool }
        return pool.filter { note in
            let text = [note.name, note.description, note.tags.joined(separator: " "), note.body].joined(separator: " ").lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }

    private var selectedNote: MemoryNote? { model.memoryNote(model.openNoteID) }

    private func select(_ id: String) {
        model.openNoteID = id
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain").foregroundStyle(Palette.claude)
            Text("Memory").font(.mono(14, .bold)).foregroundStyle(Palette.cream)
            Text("\(shown.count) notes · shared by every CLI").font(.mono(11)).foregroundStyle(Palette.muted)
            if let message {
                Text(message).font(.mono(10.5)).foregroundStyle(Palette.warning).lineLimit(1)
            }
            Spacer()
            Picker("Notes", selection: $scopeFilter) {
                Text(model.memoryScope == MemoryVault.globalScope ? "Global" : model.workspaceName(model.selectedFolder)).tag("here")
                Text("All projects").tag("all")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)
            .help("This workspace's notes and the global ones, or every project's")
            Picker("View", selection: $mode) {
                Image(systemName: "doc.text").tag("note")
                Image(systemName: "point.3.filled.connected.trianglepath.dotted").tag("graph")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 80)
            .help("A note, or the graph of how notes link")
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Palette.muted)
                TextField("Search notes", text: $search)
                    .textFieldStyle(.plain)
                    .font(.mono(11.5))
                    .focused($searchFocused)
                    .frame(width: 150)
                    .onSubmit { if let first = shown.first { select(first.id) } }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.panel))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(searchFocused ? Palette.claude.opacity(0.6) : Palette.border))
            ChromeButton(symbol: "square.and.pencil", help: "New note") {
                naming = true
                newName = ""
                DispatchQueue.main.async { nameFocused = true }
            }
            ChromeButton(symbol: "arrow.up.forward.app", help: Obsidian.isInstalled ? "Open in Obsidian" : "Obsidian isn't installed") {
                openInObsidian(selectedNote)
            }
            ChromeButton(symbol: "folder", help: "Show the vault in Finder") {
                try? model.memoryVault.prepare()
                NSWorkspace.shared.activateFileViewerSelecting([model.memoryVault.root])
            }
            ChromeButton(symbol: "xmark", help: "Close (esc)") { model.showsNotes = false }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Palette.panel)
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if naming {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.badge.plus").foregroundStyle(Palette.claude).font(.system(size: 11))
                            TextField("name of the note ↩", text: $newName)
                                .textFieldStyle(.plain)
                                .font(.mono(11.5))
                                .focused($nameFocused)
                                .onSubmit { startCreating() }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Palette.raised))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.claude.opacity(0.6)))
                        .padding(.bottom, 4)
                    }
                    if shown.isEmpty, !naming {
                        Text(search.isEmpty
                             ? "No notes yet. Agents write here when they learn something worth keeping, or press ✎ to write one."
                             : "Nothing matches \"\(search)\".")
                            .font(.mono(11)).foregroundStyle(Palette.faint)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(10)
                    }
                    ForEach(groups, id: \.scope) { group in
                        Text(group.scope == MemoryVault.globalScope ? "GLOBAL · every project" : group.scope.uppercased())
                            .font(.mono(9.5, .semibold))
                            .foregroundStyle(group.scope == MemoryVault.globalScope ? Palette.skill : Palette.agent)
                            .padding(.horizontal, 8)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                        ForEach(group.notes) { note in
                            NoteRow(note: note, selected: note.id == model.openNoteID) { select(note.id) }
                                .id(note.id)
                        }
                    }
                }
                .padding(8)
            }
            .onChange(of: model.openNoteID) { id in
                if let id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) } }
            }
        }
        .background(Palette.panel.opacity(0.5))
    }

    private var groups: [(scope: String, notes: [MemoryNote])] {
        var order: [String] = []
        var byScope: [String: [MemoryNote]] = [:]
        for note in shown {
            if byScope[note.scope] == nil { order.append(note.scope) }
            byScope[note.scope, default: []].append(note)
        }
        // The workspace's own notes first, global after, then other projects.
        let here = model.memoryScope
        order.sort { rank($0, here) < rank($1, here) }
        return order.map { ($0, byScope[$0] ?? []) }
    }

    private func rank(_ scope: String, _ here: String) -> Int {
        scope == here ? 0 : scope == MemoryVault.globalScope ? 1 : 2
    }

    // MARK: - Reading

    private func reader(_ note: MemoryNote) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(note.name).font(.mono(18, .bold)).foregroundStyle(Palette.cream).textSelection(.enabled)
                    Spacer()
                    Button { startEditing(note) } label: { Label("Edit", systemImage: "pencil") }
                        .buttonStyle(.borderless).font(.mono(11))
                }
                if MemoryVault.firstLine(of: note.description) != MemoryVault.firstLine(of: note.body) {
                    Text(note.description).font(.mono(12)).foregroundStyle(Palette.muted).textSelection(.enabled)
                }
                Rectangle().fill(Palette.border).frame(height: 1)
                NoteMarkdown(text: note.body) { target in
                    model.resolveLink(target, from: note)
                } open: { select($0.id) }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "brain").font(.system(size: 30)).foregroundStyle(Palette.faint)
            Text("Pick a note, or write one").font(.mono(12)).foregroundStyle(Palette.muted)
            Text("Agents add notes with agentworld-ctl memory or the agentworld-memory MCP tools.")
                .font(.mono(10.5)).foregroundStyle(Palette.faint)
        }
    }

    // MARK: - Editing

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(creating.map { $0.scope + "/" + $0.name } ?? selectedNote?.id ?? "")
                    .font(.mono(14, .bold)).foregroundStyle(Palette.cream)
                Spacer()
                Button("Cancel") { cancelEditing() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut("s", modifiers: .command)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            TextField("One line: what this note is about (optional)", text: $draftDescription)
                .textFieldStyle(.plain)
                .font(.mono(11.5))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.panel))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.border))
            TextEditor(text: $draft)
                .font(.mono(12.5))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.panel))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.border))
            Text("Markdown. Link other notes with [[name]]. ⌘S saves, esc cancels.")
                .font(.mono(10)).foregroundStyle(Palette.faint)
        }
        .padding(18)
    }

    private func startCreating() {
        let name = MemoryVault.slug(newName)
        guard !name.isEmpty else { naming = false; return }
        naming = false
        creating = (name, model.memoryScope)
        draft = ""
        draftDescription = ""
        mode = "note"
        editing = true
    }

    private func startEditing(_ note: MemoryNote) {
        creating = nil
        draft = note.body
        draftDescription = MemoryVault.firstLine(of: note.description) == MemoryVault.firstLine(of: note.body) ? "" : note.description
        editing = true
    }

    private func cancelEditing() {
        editing = false
        creating = nil
    }

    private func save() {
        let target = creating ?? selectedNote.map { ($0.name, $0.scope) }
        guard let (name, scope) = target else { return }
        do {
            let note = try model.memoryVault.write(name: name, body: draft, scope: scope,
                                                   description: draftDescription.isEmpty ? nil : draftDescription, agent: "you")
            editing = false
            creating = nil
            message = nil
            model.openNoteID = note.id
            model.refreshMemory()
        } catch {
            message = "\(error)"
        }
    }

    // MARK: - Info

    private func info(_ note: MemoryNote) -> some View {
        let backlinks = model.backlinks(note)
        let target = model.noteTarget
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("Written by") {
                    if note.agents.isEmpty {
                        Text("unknown").font(.mono(11)).foregroundStyle(Palette.faint)
                    }
                    ForEach(note.agents, id: \.self) { agent in
                        HStack(spacing: 6) {
                            Circle().fill(Provider.named(agent)?.swiftColor ?? Palette.muted).frame(width: 8, height: 8)
                            Text(Provider.named(agent)?.name ?? agent).font(.mono(11)).foregroundStyle(Palette.text)
                        }
                    }
                    Text("updated " + note.updated.formatted(.relative(presentation: .named)))
                        .font(.mono(10)).foregroundStyle(Palette.muted)
                    Text(note.isGlobal ? "global · every project" : "project · \(note.scope)")
                        .font(.mono(10)).foregroundStyle(Palette.muted)
                }
                if !note.tags.isEmpty {
                    section("Tags") {
                        Text(note.tags.map { "#" + $0 }.joined(separator: "  ")).font(.mono(11)).foregroundStyle(Palette.skill)
                    }
                }
                section("Links to") {
                    if note.links.isEmpty { Text("none").font(.mono(11)).foregroundStyle(Palette.faint) }
                    ForEach(note.links, id: \.self) { link in
                        if let linked = model.resolveLink(link, from: note) {
                            linkButton(linked)
                        } else {
                            Text(link + " (not written yet)").font(.mono(11)).foregroundStyle(Palette.faint)
                        }
                    }
                }
                section("Linked from") {
                    if backlinks.isEmpty { Text("none").font(.mono(11)).foregroundStyle(Palette.faint) }
                    ForEach(backlinks) { linkButton($0) }
                }
                VStack(alignment: .leading, spacing: 7) {
                    if let target {
                        Button { model.mention(note, in: target) } label: {
                            Label("Mention in \(target.label)", systemImage: "text.cursor")
                        }
                    }
                    if mode == "graph" {
                        Button { mode = "note" } label: { Label("Read it", systemImage: "doc.text") }
                    }
                    Button { startEditing(note); mode = "note" } label: { Label("Edit", systemImage: "pencil") }
                    Button { openInObsidian(note) } label: { Label("Open in Obsidian", systemImage: "arrow.up.forward.app") }
                        .disabled(!Obsidian.isInstalled)
                    Button { NSWorkspace.shared.activateFileViewerSelecting([note.url]) } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    Button { delete(note) } label: {
                        Label(confirmDelete ? "Click again to delete" : "Delete", systemImage: "trash")
                            .foregroundStyle(confirmDelete ? Palette.error : Palette.text)
                    }
                }
                .buttonStyle(.borderless)
                .font(.mono(11))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.panel.opacity(0.5))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(.mono(9.5, .semibold)).foregroundStyle(Palette.faint)
            content()
        }
    }

    private func linkButton(_ note: MemoryNote) -> some View {
        Button { select(note.id) } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.turn.down.right").font(.system(size: 9))
                Text(note.isGlobal || note.scope == selectedNote?.scope ? note.name : note.id).lineLimit(1)
            }
            .font(.mono(11))
            .foregroundStyle(Palette.claude)
        }
        .buttonStyle(.plain)
        .help(note.description)
    }

    private func delete(_ note: MemoryNote) {
        guard confirmDelete else { confirmDelete = true; return }
        confirmDelete = false
        _ = try? model.memoryVault.delete(name: note.id)
        model.openNoteID = shown.first { $0.id != note.id }?.id
        model.refreshMemory()
    }

    private func openInObsidian(_ note: MemoryNote?) {
        switch Obsidian.open(vault: model.memoryVault.root, file: note?.url) {
        case .opened: message = nil
        case .notInstalled: message = "Obsidian isn't installed (brew install --cask obsidian)"
        case .needsVault: message = "In Obsidian: Open folder as vault › \(model.memoryVault.root.path)"
        }
    }
}

/// A row of the notes list.
private struct NoteRow: View {
    let note: MemoryNote
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(note.name).font(.mono(11.5, .semibold)).foregroundStyle(Palette.cream).lineLimit(1)
                Spacer(minLength: 4)
                if let agent = note.agents.first {
                    Circle().fill(Provider.named(agent)?.swiftColor ?? Palette.muted).frame(width: 6, height: 6)
                        .help("by " + note.agents.joined(separator: ", "))
                }
            }
            Text(note.description).font(.mono(10)).foregroundStyle(Palette.muted).lineLimit(2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Palette.selected : hovering ? Palette.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
    }
}

// MARK: - Markdown

/// Enough Markdown for notes: headings, lists, quotes, code blocks and
/// inline marks, with `[[wikilinks]]` you can click (faint when the note
/// doesn't exist yet).
struct NoteMarkdown: View {
    let text: String
    let resolve: (String) -> MemoryNote?
    let open: (MemoryNote) -> Void

    enum Block: Hashable {
        case heading(Int, String)
        case paragraph(String)
        case bullet(String, indent: Int, marker: String)
        case quote(String)
        case code(String)
        case rule
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, block in
                view(block)
            }
        }
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "awnote" else { return .systemAction }
            let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value ?? ""
            if let note = resolve(target) { open(note) }
            return .handled
        })
    }

    @ViewBuilder
    private func view(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(.mono(level == 1 ? 16 : level == 2 ? 14 : 12.5, .bold))
                .foregroundStyle(Palette.cream)
                .padding(.top, level <= 2 ? 6 : 2)
        case .paragraph(let text):
            Text(inline(text)).font(.mono(12.5)).foregroundStyle(Palette.text).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text, let indent, let marker):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker).font(.mono(12.5)).foregroundStyle(Palette.claude)
                Text(inline(text)).font(.mono(12.5)).foregroundStyle(Palette.text).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .quote(let text):
            HStack(spacing: 10) {
                Rectangle().fill(Palette.claude.opacity(0.6)).frame(width: 2)
                Text(inline(text)).font(.mono(12.5)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        case .code(let code):
            Text(code)
                .font(.mono(11.5))
                .foregroundStyle(Palette.cream)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.panel))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.border))
        case .rule:
            Rectangle().fill(Palette.border).frame(height: 1)
        }
    }

    /// Inline Markdown, with `[[name|label]]` turned into links of our own.
    private func inline(_ text: String) -> AttributedString {
        var source = ""
        var rest = text[...]
        while let open = rest.range(of: "[["), let close = rest[open.upperBound...].range(of: "]]") {
            source += rest[..<open.lowerBound]
            let inner = String(rest[open.upperBound..<close.lowerBound])
            let parts = inner.split(separator: "|", maxSplits: 1).map(String.init)
            let target = parts.first?.split(separator: "#").first.map(String.init) ?? inner
            var components = URLComponents()
            components.scheme = "awnote"
            components.host = "note"
            components.queryItems = [URLQueryItem(name: "n", value: target)]
            let label = (parts.count > 1 ? parts[1] : inner).replacingOccurrences(of: "]", with: "")
            source += "[\(label)](\(components.url?.absoluteString ?? ""))"
            rest = rest[close.upperBound...]
        }
        source += rest
        var result = (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        for run in result.runs {
            guard let url = run.link else { continue }
            if url.scheme == "awnote" {
                let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value ?? ""
                result[run.range].foregroundColor = resolve(target) == nil ? Palette.faint : Palette.claude
            } else {
                result[run.range].foregroundColor = Palette.mcp
            }
            result[run.range].underlineStyle = .single
        }
        for run in result.runs where run.inlinePresentationIntent?.contains(.code) == true {
            result[run.range].foregroundColor = Palette.cream
            result[run.range].backgroundColor = Palette.raised
        }
        return result
    }

    static func blocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let open = code {
                    blocks.append(.code(open.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
                continue
            }
            if code != nil { code!.append(raw); continue }
            if line.isEmpty { flush(); continue }
            if line == "---" || line == "***" { flush(); blocks.append(.rule); continue }
            if let hashes = line.firstIndex(where: { $0 != "#" }), line.hasPrefix("#"), line[hashes] == " " {
                flush()
                blocks.append(.heading(line.distance(from: line.startIndex, to: hashes), String(line[hashes...]).trimmingCharacters(in: .whitespaces)))
                continue
            }
            let indent = (raw.prefix { $0 == " " }.count) / 2
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flush()
                var item = String(line.dropFirst(2))
                var marker = "•"
                if item.hasPrefix("[ ] ") { marker = "☐"; item.removeFirst(4) }
                if item.lowercased().hasPrefix("[x] ") { marker = "☑"; item.removeFirst(4) }
                blocks.append(.bullet(item, indent: indent, marker: marker))
                continue
            }
            if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
               line[line.index(after: dot)...].hasPrefix(" ") {
                flush()
                blocks.append(.bullet(String(line[line.index(dot, offsetBy: 2)...]), indent: indent, marker: String(line[...dot])))
                continue
            }
            if line.hasPrefix(">") {
                flush()
                blocks.append(.quote(line.dropFirst().trimmingCharacters(in: .whitespaces)))
                continue
            }
            paragraph.append(line)
        }
        if let code { blocks.append(.code(code.joined(separator: "\n"))) }
        flush()
        return blocks
    }
}

// MARK: - Graph

/// The notes as a graph, the way Obsidian draws one: a dot per note (bigger
/// with more links, colored by project), a line per `[[link]]`.
struct NotesGraph: View {
    @EnvironmentObject private var model: AppModel
    let notes: [MemoryNote]
    let selected: String?
    let select: (String) -> Void
    @State private var positions: [String: CGPoint] = [:]
    @State private var laidOut: [String] = []
    @State private var hovered: String?

    var body: some View {
        let edges = links
        let degree = edges.reduce(into: [String: Int]()) { counts, edge in counts[edge.0, default: 0] += 1; counts[edge.1, default: 0] += 1 }
        let scopes = Array(Set(notes.map(\.scope))).sorted()
        let focus = hovered ?? selected
        let neighbors = focus.map { focus in Set(edges.filter { $0.0 == focus || $0.1 == focus }.flatMap { [$0.0, $0.1] } + [focus]) }
        GeometryReader { geometry in
            let place = { (id: String) -> CGPoint in
                let point = positions[id] ?? CGPoint(x: 500, y: 500)
                let scale = min(geometry.size.width, geometry.size.height) / 1100
                return CGPoint(x: geometry.size.width / 2 + (point.x - 500) * scale, y: geometry.size.height / 2 + (point.y - 500) * scale)
            }
            Canvas { graphics, _ in
                for edge in edges {
                    var path = Path()
                    path.move(to: place(edge.0))
                    path.addLine(to: place(edge.1))
                    let lit = focus.map { edge.0 == $0 || edge.1 == $0 } ?? false
                    graphics.stroke(path, with: .color((lit ? Palette.claude : Palette.muted).opacity(lit ? 0.8 : 0.25)), lineWidth: lit ? 1.5 : 0.8)
                }
                for note in notes {
                    let center = place(note.id)
                    let radius = 5 + min(9, CGFloat(degree[note.id] ?? 0) * 1.5)
                    let dimmed = neighbors.map { !$0.contains(note.id) } ?? false
                    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    graphics.fill(Path(ellipseIn: rect), with: .color(color(note, scopes).opacity(dimmed ? 0.2 : 1)))
                    if note.id == selected {
                        graphics.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(Palette.cream), lineWidth: 1.5)
                    }
                    let label = Text(note.name).font(.mono(note.id == focus ? 11 : 9.5, note.id == focus ? .semibold : .regular))
                        .foregroundColor(dimmed ? Palette.faint : note.id == focus ? Palette.cream : Palette.text)
                    graphics.draw(label, at: CGPoint(x: center.x, y: center.y + radius + 8), anchor: .center)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hovered = notes.min { distance(place($0.id), location) < distance(place($1.id), location) }
                        .flatMap { distance(place($0.id), location) < 24 ? $0.id : nil }
                case .ended: hovered = nil
                }
            }
            .onTapGesture { if let hovered { select(hovered) } }
        }
        .overlay(alignment: .bottomLeading) { legend(scopes).padding(12) }
        .overlay {
            if notes.isEmpty { Text("No notes to draw yet.").font(.mono(11)).foregroundStyle(Palette.faint) }
        }
        .onAppear(perform: layout)
        .onChange(of: notes.map(\.id)) { _ in layout() }
    }

    /// Resolved `[[links]]` between the notes on screen, both ways once.
    private var links: [(String, String)] {
        let ids = Set(notes.map(\.id))
        var seen = Set<String>()
        var result: [(String, String)] = []
        for note in notes {
            for link in note.links {
                guard let target = model.resolveLink(link, from: note)?.id, ids.contains(target), target != note.id else { continue }
                let key = [note.id, target].sorted().joined(separator: "→")
                if seen.insert(key).inserted { result.append((note.id, target)) }
            }
        }
        return result
    }

    private func layout() {
        let ids = notes.map(\.id)
        guard ids != laidOut else { return }
        laidOut = ids
        let index = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        let scopes = Array(Set(notes.map(\.scope))).sorted()
        let points = GraphLayout.layout(nodes: ids.count, edges: links.compactMap { edge in
            guard let a = index[edge.0], let b = index[edge.1] else { return nil }
            return (a, b)
        }, groups: notes.map { scopes.firstIndex(of: $0.scope) ?? 0 })
        // Fit the layout into a 1000-point square around the middle.
        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1, minY = ys.min() ?? 0, maxY = ys.max() ?? 1
        let span = max(maxX - minX, maxY - minY, 1)
        // A handful of notes stays a small cluster in the middle, not spread to the corners.
        let size = min(900, 180 * sqrt(Double(max(ids.count, 1))))
        positions = Dictionary(uniqueKeysWithValues: zip(ids, points).map { id, point in
            (id, CGPoint(x: 500 + (point.x - (minX + maxX) / 2) / span * size, y: 500 + (point.y - (minY + maxY) / 2) / span * size))
        })
    }

    private func color(_ note: MemoryNote, _ scopes: [String]) -> Color { color(scope: note.scope, scopes) }

    private func color(scope: String, _ scopes: [String]) -> Color {
        if scope == MemoryVault.globalScope { return Palette.skill }
        let index = scopes.filter { $0 != MemoryVault.globalScope }.firstIndex(of: scope) ?? 0
        return ProjectMapView.groupColors[index % ProjectMapView.groupColors.count]
    }

    private func legend(_ scopes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(scopes, id: \.self) { scope in
                HStack(spacing: 6) {
                    Circle().fill(color(scope: scope, scopes))
                        .frame(width: 8, height: 8)
                    Text(scope == MemoryVault.globalScope ? "global" : scope).font(.mono(10)).foregroundStyle(Palette.text)
                }
            }
            Text("a line per [[link]] · click a note").font(.mono(9)).foregroundStyle(Palette.faint).padding(.top, 2)
        }
        .padding(10)
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.panel.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}
