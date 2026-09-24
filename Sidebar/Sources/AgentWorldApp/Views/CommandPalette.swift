import AgentWorldArt
import AgentWorldKit
import AppKit
import SwiftUI

/// ⌘K: one box to do anything. Jump to a terminal, launch a CLI (or a whole
/// crew), switch workspace, chat with an agent, or drop a skill / slash
/// command into the terminal you're in.
struct CommandPalette: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var scope = PaletteScope.all
    @State private var selection = 0
    @FocusState private var focused: Bool

    /// Rows as shown: in All with nothing typed, grouped under headers.
    private struct Row: Identifiable {
        let id: String
        let header: String?
        let item: PaletteItem
    }

    var body: some View {
        let (effectiveScope, text) = PaletteScope.parse(query, default: scope)
        let all = PaletteItem.all(model: model, includeFiles: effectiveScope == .files || !text.isEmpty)
        let ranked = all.filter { effectiveScope == .all || $0.scope == effectiveScope }.ranked(by: text)
        let rows = rows(ranked, scope: effectiveScope, grouped: text.isEmpty)
        let counts = Dictionary(grouping: all.ranked(by: text), by: \.scope).mapValues(\.count)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: effectiveScope.symbol).foregroundStyle(Palette.muted).frame(width: 16)
                TextField(effectiveScope.placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.mono(14))
                    .foregroundStyle(Palette.cream)
                    .focused($focused)
                    .onSubmit { run(rows) }
                    .onChange(of: query) { _ in selection = 0 }
                Text("esc").font(.mono(10)).foregroundStyle(Palette.faint)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.border))
            }
            .padding(14)
            scopeBar(active: effectiveScope, counts: counts, total: all.ranked(by: text).count)
            Rectangle().fill(Palette.border).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    // Plain VStack: at most 80 rows, and a lazy one kept stale rows
                    // when the section changed under it.
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if let header = row.header {
                                HStack {
                                    Text(header.uppercased()).font(.mono(9.5, .semibold)).foregroundStyle(Palette.muted)
                                    Spacer()
                                    if let more = moreCount(header, counts: counts) {
                                        Text("\(more) more · tab").font(.mono(9.5)).foregroundStyle(Palette.faint)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.top, index == 0 ? 4 : 12)
                                .padding(.bottom, 3)
                            }
                            PaletteRow(item: row.item, selected: index == selection)
                                .onTapGesture {
                                    selection = index
                                    run(rows)
                                }
                        }
                        if rows.isEmpty {
                            Text(emptyText(effectiveScope, text: text)).font(.mono(12)).foregroundStyle(Palette.faint).padding(16)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: selection) { value in
                    if rows.indices.contains(value) { proxy.scrollTo(rows[value].id) }
                }
            }
            .frame(maxHeight: 420)
            Rectangle().fill(Palette.border).frame(height: 1)
            HStack(spacing: 14) {
                hint("↑↓", "move")
                hint("⏎", "do it")
                hint("tab", "section")
                hint(">", "actions")
                hint("@", "files")
                hint("#", "terminals")
                Spacer()
                Text(model.paletteTarget.map { "→ \($0.label)" } ?? "no terminal picked")
                    .font(.mono(10)).foregroundStyle(Palette.faint).lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 680)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .onAppear {
            focused = true
            model.paletteTarget = model.focusedSession ?? model.panelSession
            model.loadProjectFiles(model.selectedFolder)
            if let seed = model.paletteSeed {
                query = seed
                model.paletteSeed = nil
            }
        }
        .onExitCommand { isPresented = false }
        .background(
            // Arrows and tab while the text field has focus.
            KeyCatcher { key in
                switch key {
                case .up: selection = max(0, selection - 1)
                case .down: selection = min(max(0, rows.count - 1), selection + 1)
                case .tab, .backTab:
                    // A typed prefix picks the section; tab moves on from it.
                    let (current, rest) = PaletteScope.parse(query, default: scope)
                    if current != scope { query = rest }
                    scope = current.next(key == .tab ? 1 : -1)
                    selection = 0
                }
            }
        )
    }

    private func scopeBar(active: PaletteScope, counts: [PaletteScope: Int], total: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(PaletteScope.allCases) { item in
                    let selected = item == active
                    let count = item == .all ? total : counts[item] ?? 0
                    Button {
                        scope = item
                        if PaletteScope.parse(query, default: scope).0 != scope { query = PaletteScope.parse(query, default: scope).1 }
                        selection = 0
                        focused = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: item.symbol).font(.system(size: 10))
                            Text(item.title)
                            if count > 0, item != .all { Text("\(count)").font(.mono(9.5)).foregroundStyle(Palette.faint) }
                        }
                        .font(.mono(11, selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Palette.cream : count == 0 && item != .all ? Palette.faint : Palette.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Palette.selected : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
        }
        .padding(.bottom, 8)
    }

    private func rows(_ items: [PaletteItem], scope: PaletteScope, grouped: Bool) -> [Row] {
        guard scope == .all, grouped else {
            return items.prefix(80).map { Row(id: $0.id, header: nil, item: $0) }
        }
        var rows: [Row] = []
        for section in PaletteScope.allCases where section != .all {
            let inSection = items.filter { $0.scope == section }.prefix(section.shownInAll)
            for (index, item) in inSection.enumerated() {
                rows.append(Row(id: item.id, header: index == 0 ? section.title : nil, item: item))
            }
        }
        return rows
    }

    private func moreCount(_ header: String, counts: [PaletteScope: Int]) -> Int? {
        guard let section = PaletteScope.allCases.first(where: { $0.title == header }) else { return nil }
        let more = (counts[section] ?? 0) - section.shownInAll
        return more > 0 ? more : nil
    }

    private func emptyText(_ scope: PaletteScope, text: String) -> String {
        if scope == .files, model.files(in: model.selectedFolder).isEmpty { return "Reading the project's files…" }
        return text.isEmpty ? "Nothing here yet." : "Nothing in \(scope.title) matches “\(text)”."
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.mono(10, .semibold)).foregroundStyle(Palette.muted)
            Text(label).font(.mono(10)).foregroundStyle(Palette.faint)
        }
    }

    private func run(_ rows: [Row]) {
        guard rows.indices.contains(selection) else { return }
        isPresented = false
        let action = rows[selection].item.action
        DispatchQueue.main.async { action(model) }
    }
}

/// The palette's sections, each with a tab and (some) a prefix you can type.
enum PaletteScope: String, CaseIterable, Identifiable, Hashable {
    case all, terminals, launch, workspaces, agents, skills, files, git, actions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .terminals: "Terminals"
        case .launch: "Launch"
        case .workspaces: "Workspaces"
        case .agents: "Agents"
        case .skills: "Skills"
        case .files: "Files"
        case .git: "Git"
        case .actions: "Actions"
        }
    }

    var symbol: String {
        switch self {
        case .all: "magnifyingglass"
        case .terminals: "terminal"
        case .launch: "play.fill"
        case .workspaces: "folder"
        case .agents: "person.2"
        case .skills: "book.closed"
        case .files: "doc.text"
        case .git: "plusminus"
        case .actions: "command"
        }
    }

    var placeholder: String {
        switch self {
        case .all: "Jump to a terminal, launch a CLI, find a file…"
        case .terminals: "Jump to a terminal…"
        case .launch: "Open a CLI or a saved crew…"
        case .workspaces: "Switch workspace…"
        case .agents: "Chat with an agent…"
        case .skills: "Use a skill or slash command…"
        case .files: "Find a file to mention in the terminal…"
        case .git: "Changes and diffs…"
        case .actions: "Run an action…"
        }
    }

    /// Typed first to jump straight to a section, like VS Code's > and @.
    var prefix: Character? {
        switch self {
        case .actions: ">"
        case .files: "@"
        case .terminals: "#"
        case .skills: "/"
        default: nil
        }
    }

    /// Rows per section in the grouped All view.
    var shownInAll: Int {
        switch self {
        case .terminals: 6
        case .files: 0
        default: 4
        }
    }

    func next(_ delta: Int) -> PaletteScope {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + delta + all.count) % all.count]
    }

    /// The section a query asks for (by its prefix) and the text after it.
    static func parse(_ query: String, default scope: PaletteScope) -> (PaletteScope, String) {
        guard let first = query.first, let match = allCases.first(where: { $0.prefix == first }) else { return (scope, query) }
        // "/" alone is a skill search; "/foo" too.
        return (match, String(query.dropFirst()).trimmingCharacters(in: .whitespaces))
    }
}

struct PaletteRow: View {
    let item: PaletteItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let figure = item.figure {
                    FaceView(figure: figure, scale: 2, waving: selected).frame(width: 22, height: 13)
                } else {
                    Image(systemName: item.symbol).foregroundStyle(item.color).frame(width: 22)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.mono(12.5, .semibold)).foregroundStyle(selected ? Palette.cream : Palette.text).lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.mono(10.5)).foregroundStyle(Palette.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(item.kind).font(.mono(9.5)).foregroundStyle(item.color.opacity(0.9))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(item.color.opacity(0.12)))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Palette.selected : .clear))
        .contentShape(Rectangle())
    }
}

/// One thing the palette can do.
struct PaletteItem: Identifiable {
    let id: String
    let kind: String
    let title: String
    var subtitle: String? = nil
    var symbol = "circle"
    var figure: CharacterFigure? = nil
    var color: Color = Palette.muted
    /// Extra words it answers to.
    var keywords = ""
    /// Tie-breaker: higher shows first when the query is empty.
    var weight = 0
    let action: @MainActor (AppModel) -> Void

    var scope: PaletteScope {
        switch kind {
        case "terminal": .terminals
        case "launch", "split", "crew": .launch
        case "workspace": .workspaces
        case "agent": .agents
        case "skill", "command": .skills
        case "file", "note": .files
        case "git", "diff": .git
        default: .actions
        }
    }

    @MainActor
    static func all(model: AppModel, includeFiles: Bool = false) -> [PaletteItem] {
        var items: [PaletteItem] = []
        let folder = model.selectedFolder
        let folderName = URL(fileURLWithPath: folder).lastPathComponent

        // Terminals you have open.
        for session in model.allSessions {
            items.append(PaletteItem(id: "session:\(session.id)", kind: "terminal", title: session.label,
                                     subtitle: "\(session.folderName) · \(session.status.text)", figure: session.provider.figure,
                                     color: session.status.tone.color, keywords: "go jump open switch", weight: 30) { $0.reveal(session) })
        }

        // Launch a CLI here.
        for profile in model.profiles where model.executable(for: profile) != nil {
            let name = profile.isCustom ? profile.name : profile.provider.name
            items.append(PaletteItem(id: "launch:\(profile.id)", kind: "launch", title: "New \(name)", subtitle: "in \(folderName)",
                                     figure: profile.provider.figure, color: Palette.claude, keywords: "start run open new tab", weight: 20) {
                $0.launch(profile, in: folder)
            })
            if let tab = model.selectedTab, tab.folder == folder, tab.sessions.count < AppModel.maxPanes, !model.showsLauncher {
                items.append(PaletteItem(id: "pane:\(profile.id)", kind: "split", title: "Add \(name) to this tab",
                                         subtitle: "next to \(tab.title)", symbol: "plus.rectangle.on.rectangle", color: Palette.claude,
                                         keywords: "split pane side tile", weight: 12) { $0.addPane(profile, to: tab) })
            }
        }

        // Crews: several at once.
        if let tab = model.selectedTab, tab.sessions.count > 1, !model.showsLauncher {
            items.append(PaletteItem(id: "crew:save", kind: "crew", title: "Save this tab as a crew",
                                     subtitle: Crew.summary(tab.sessions.map(\.profile)) + " · relaunch it in one go later",
                                     symbol: "square.and.arrow.down", color: Palette.live, keywords: "preset remember", weight: 4) { _ in
                Crew.save(Crew(name: Crew.summary(tab.sessions.map(\.profile)), members: tab.sessions.map(\.profile.name)))
            })
        }
        for crew in Crew.presets(model: model) {
            items.append(PaletteItem(id: "crew:\(crew.name)", kind: "crew", title: crew.name, subtitle: crew.summary,
                                     symbol: "square.grid.2x2", color: Palette.live, keywords: "together tile compare many several all", weight: 15) {
                $0.launchTogether(crew.profiles, in: folder)
            })
        }

        // Workspaces.
        for other in model.folders where other != folder {
            items.append(PaletteItem(id: "folder:\(other)", kind: "workspace", title: URL(fileURLWithPath: other).lastPathComponent,
                                     subtitle: other, symbol: "folder", color: Palette.claude, keywords: "folder project repo cd", weight: 8) {
                $0.select(folder: other)
            })
        }

        // Agents to chat with.
        for (provider, agent) in model.agents(in: folder) {
            items.append(PaletteItem(id: "agent:\(provider.id)|\(agent.qualifiedName)", kind: "agent", title: "Chat with \(agent.name)",
                                     subtitle: agent.description.map(SkillCategory.summarize), figure: .crew(CharacterLook(name: agent.name)),
                                     color: Palette.agent, keywords: "subagent talk", weight: 6) {
                $0.startChat(with: agent, provider: provider, in: folder)
            })
        }

        // Skills and commands, typed into the terminal you're in.
        let target = model.paletteTarget
        let provider = target?.provider.isAgent == true ? target!.provider : .claude
        let config = model.config(provider, in: folder)
        for skill in config.skills {
            items.append(PaletteItem(id: "skill:\(skill.qualifiedName)", kind: "skill", title: "/" + skill.qualifiedName,
                                     subtitle: skill.description.map(SkillCategory.summarize), symbol: "book.closed.fill",
                                     color: Palette.skill, keywords: "use skill", weight: 3) { model in
                model.paletteTarget?.type("/" + skill.qualifiedName + " ")
            })
        }
        for command in config.commands {
            items.append(PaletteItem(id: "command:\(command.qualifiedName)", kind: "command", title: "/" + command.qualifiedName,
                                     subtitle: command.description.map(SkillCategory.summarize), symbol: "command",
                                     color: Palette.mcp, keywords: "slash command", weight: 2) { model in
                model.paletteTarget?.type("/" + command.qualifiedName + " ")
            })
        }

        // App actions.
        items.append(PaletteItem(id: "act:inspector", kind: "view", title: model.showsInspector ? "Hide tips & kit" : "Show tips & kit",
                                 symbol: "sidebar.right", keywords: "inspector panel right", weight: 1) { $0.showsInspector.toggle() })
        items.append(PaletteItem(id: "act:kit", kind: "view", title: "Browse the kit", subtitle: "every skill, MCP server, plugin and command, per CLI",
                                 symbol: "shippingbox", color: Palette.mcp, keywords: "mcp plugins skills commands library", weight: 1) { $0.showsKit = true })
        items.append(PaletteItem(id: "act:sidebar", kind: "view", title: model.showsSidebar ? "Hide workspaces" : "Show workspaces",
                                 symbol: "sidebar.left", keywords: "sidebar left column folders", weight: 1) { $0.showsSidebar.toggle() })
        items.append(PaletteItem(id: "act:map", kind: "view", title: "Project map", subtitle: "every file as a dot, linked to the ones it uses",
                                 symbol: "point.3.connected.trianglepath.dotted", color: Palette.claude,
                                 keywords: "graph dependencies imports files structure architecture", weight: 2) { $0.openProjectMap() })
        items.append(PaletteItem(id: "act:memory", kind: "view", title: "Memory", subtitle: "the notes every agent CLI shares, with links and a graph",
                                 symbol: "brain", color: Palette.claude,
                                 keywords: "notes vault knowledge remember wiki obsidian", weight: 2) { $0.openNotes() })
        for note in model.workspaceMemory.prefix(40) {
            items.append(PaletteItem(id: "note:\(note.id)", kind: "note", title: note.name, subtitle: note.description,
                                     symbol: "note.text", color: note.isGlobal ? Palette.skill : Palette.agent,
                                     keywords: "memory note " + note.tags.joined(separator: " "), weight: 2) { $0.openNotes(note.id) })
        }
        items.append(PaletteItem(id: "act:settings", kind: "app", title: "Settings…", subtitle: "font, notifications, CLIs, profiles",
                                 symbol: "gearshape", keywords: "preferences options config", weight: 1) { $0.openSettings() })
        if let changes = model.changes[model.selectedFolder], !changes.files.isEmpty {
            items.append(PaletteItem(id: "act:changes", kind: "git", title: "Changes: \(changes.files.count) files",
                                     subtitle: "+\(changes.added) −\(changes.removed) uncommitted, and who touched them",
                                     symbol: "plusminus", color: Palette.warning, keywords: "git diff status modified", weight: 3) { model in
                model.showsInspector = true
                model.panel.section = .changes
                model.enterPanel()
            })
            for change in changes.files.prefix(30) {
                items.append(PaletteItem(id: "diff:\(change.path)", kind: "diff", title: change.name,
                                         subtitle: (change.folder.isEmpty ? "" : change.folder + " · ") + change.kind.rawValue,
                                         symbol: "doc.text.magnifyingglass", color: Palette.warning, keywords: "diff git " + change.path, weight: 2) { model in
                    model.openDiff(change, in: model.selectedFolder)
                })
            }
        }
        if includeFiles {
            let folder = model.selectedFolder
            for path in model.files(in: folder) {
                let name = (path as NSString).lastPathComponent
                let directory = (path as NSString).deletingLastPathComponent
                items.append(PaletteItem(id: "file:" + path, kind: "file", title: name, subtitle: directory.isEmpty ? nil : directory,
                                         symbol: "doc.text", color: Palette.text, keywords: path.lowercased(), weight: 0) { model in
                    let full = URL(fileURLWithPath: folder).appendingPathComponent(path).path
                    if let target = model.paletteTarget {
                        model.reveal(target)
                        model.mention(full, in: target)
                    } else {
                        NSWorkspace.shared.open(URL(fileURLWithPath: full))
                    }
                })
            }
        }
        if let tab = model.selectedTab, tab.sessions.count > 1 {
            for layout in TileLayout.allCases {
                items.append(PaletteItem(id: "layout:\(layout.rawValue)", kind: "layout", title: "Layout: \(layout.title)",
                                         symbol: layout.symbol, keywords: "arrange tile grid", weight: 0) { _ in
                    tab.layout = layout
                    tab.zoomedID = nil
                })
            }
        }
        return items
    }
}

extension Array where Element == PaletteItem {
    /// Fuzzy: every query word must appear (in order of letters) somewhere.
    func ranked(by query: String) -> [PaletteItem] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return sorted { $0.weight > $1.weight } }
        return compactMap { item -> (PaletteItem, Int)? in
            let title = item.title.lowercased()
            let haystack = [title, item.subtitle?.lowercased() ?? "", item.kind, item.keywords].joined(separator: " ")
            var score = item.weight
            for word in words {
                if title.hasPrefix(word) || title.contains(" " + word) || title.contains("/" + word) { score += 100 }
                else if title.contains(word) { score += 60 }
                else if haystack.contains(word) { score += 25 }
                else if Self.isSubsequence(word, of: title) { score += 10 }
                else { return nil }
            }
            return (item, score)
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var index = haystack.startIndex
        for character in needle {
            guard let found = haystack[index...].firstIndex(of: character) else { return false }
            index = haystack.index(after: found)
        }
        return true
    }
}

/// Up and down arrows, even while a text field holds the keyboard.
struct KeyCatcher: NSViewRepresentable {
    enum Key { case up, down, tab, backTab }
    let onKey: (Key) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 126: context.coordinator.onKey(.up); return nil
            case 125: context.coordinator.onKey(.down); return nil
            case 48: context.coordinator.onKey(event.modifierFlags.contains(.shift) ? .backTab : .tab); return nil
            default: return event
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.onKey = onKey }

    func makeCoordinator() -> Coordinator { Coordinator(onKey: onKey) }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
    }

    final class Coordinator {
        var onKey: (Key) -> Void
        var monitor: Any?
        init(onKey: @escaping (Key) -> Void) { self.onKey = onKey }
    }
}
