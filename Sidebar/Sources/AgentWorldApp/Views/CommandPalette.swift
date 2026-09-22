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
    @State private var selection = 0
    @FocusState private var focused: Bool

    var body: some View {
        let items = PaletteItem.all(model: model).ranked(by: query)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Jump to a terminal, launch a CLI, use a skill…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.mono(14))
                    .foregroundStyle(Palette.cream)
                    .focused($focused)
                    .onSubmit { run(items) }
                    .onChange(of: query) { _ in selection = 0 }
                Text("esc").font(.mono(10)).foregroundStyle(Palette.faint)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.border))
            }
            .padding(14)
            Rectangle().fill(Palette.border).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.prefix(60).enumerated()), id: \.element.id) { index, item in
                            PaletteRow(item: item, selected: index == selection)
                                .id(index)
                                .onTapGesture {
                                    selection = index
                                    run(items)
                                }
                        }
                        if items.isEmpty {
                            Text("Nothing matches “\(query)”.").font(.mono(12)).foregroundStyle(Palette.faint).padding(16)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: selection) { value in proxy.scrollTo(value) }
            }
            .frame(maxHeight: 380)
            Rectangle().fill(Palette.border).frame(height: 1)
            HStack(spacing: 14) {
                hint("↑↓", "move")
                hint("⏎", "do it")
                hint("esc", "close")
                Spacer()
                Text(model.focusedSession.map { "skills go to \($0.label)" } ?? "click a terminal first to send skills to it")
                    .font(.mono(10)).foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 640)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .onAppear {
            focused = true
            model.paletteTarget = model.focusedSession
        }
        .onExitCommand { isPresented = false }
        .background(
            // Arrow keys while the text field has focus.
            KeyCatcher { key in
                switch key {
                case .up: selection = max(0, selection - 1)
                case .down: selection = min(max(0, min(items.count, 60) - 1), selection + 1)
                }
            }
        )
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.mono(10, .semibold)).foregroundStyle(Palette.muted)
            Text(label).font(.mono(10)).foregroundStyle(Palette.faint)
        }
    }

    private func run(_ items: [PaletteItem]) {
        guard items.indices.contains(selection) else { return }
        isPresented = false
        let action = items[selection].action
        DispatchQueue.main.async { action(model) }
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

    @MainActor
    static func all(model: AppModel) -> [PaletteItem] {
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
    enum Key { case up, down }
    let onKey: (Key) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 126: context.coordinator.onKey(.up); return nil
            case 125: context.coordinator.onKey(.down); return nil
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
