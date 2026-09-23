import AgentWorldArt
import AgentWorldKit
import SwiftUI

/// The right panel: the stage (the CLI and its crew, acting out what they
/// do), then one section at a time — Crew, Skills, Tools, Tips — as a list
/// you can walk with the keyboard (⌘E, arrows, return). Rows have fixed
/// heights and the stage never changes size, so nothing jumps.
struct InspectorView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var panel: PanelNavigator
    let session: TerminalSession?
    let folder: String

    var body: some View {
        let provider = model.panelProvider
        let config = model.config(provider, in: folder)
        // A plain shell can't take "use this": show the kit, no actions.
        let agentSession = session?.provider.isAgent == true ? session : nil
        let items = model.panelItems(panel.section)
        VStack(spacing: 0) {
            PanelStage(panel: panel, session: session, agents: config.agents)
                .padding([.horizontal, .top], 12)
            SectionBar(panel: panel, config: config, tipCount: panel.section == .tips ? items.count : nil,
                       session: agentSession, provider: provider)
                .padding(.horizontal, 12)
                .padding(.top, 12)
            if panel.section == .changes {
                MiniMap().padding(.horizontal, 12).padding(.top, 8)
            }
            if panel.searching || !panel.query.isEmpty {
                PanelSearchField(panel: panel)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
            Rectangle().fill(Palette.border).frame(height: 1).padding(.top, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        rows(items, config: config, session: agentSession, provider: provider)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .onChange(of: panel.selection) { selection in
                    if items.indices.contains(selection) { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(items[selection].id) } }
                }
            }
            KeyHintBar(panel: panel)
        }
        .overlay(alignment: .leading) {
            // Where the keys go: a bar down the edge while the panel has them.
            if panel.isFocused { Rectangle().fill(Palette.claude).frame(width: 2) }
        }
    }

    @ViewBuilder
    private func rows(_ items: [PanelItem], config: AgentConfiguration, session: TerminalSession?, provider: Provider) -> some View {
        if items.isEmpty {
            if panel.query.isEmpty {
                EmptySection(section: panel.section, provider: provider)
            } else {
                Text("Nothing here matches \"\(panel.query)\".")
                    .font(.mono(11)).foregroundStyle(Palette.faint).padding(12)
            }
        }
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if panel.section == .skills, case .skill(let skill) = item, isFirstOfCategory(skill, at: index, in: items) {
                Text(skill.category.title)
                    .font(.mono(10, .semibold))
                    .foregroundStyle(Color(rgb: skill.category.color))
                    .padding(.horizontal, 8)
                    .padding(.top, index == 0 ? 2 : 10)
                    .padding(.bottom, 2)
            }
            PanelRow(panel: panel, item: item, index: index, config: config, session: session, provider: provider)
                .id(item.id)
        }
    }

    private func isFirstOfCategory(_ skill: SkillDefinition, at index: Int, in items: [PanelItem]) -> Bool {
        guard index > 0, case .skill(let previous) = items[index - 1] else { return true }
        return previous.category != skill.category
    }
}

// MARK: - Section bar

struct SectionBar: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var panel: PanelNavigator
    let config: AgentConfiguration
    let tipCount: Int?
    let session: TerminalSession?
    let provider: Provider

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PanelNavigator.Section.allCases) { section in
                let selected = panel.section == section
                Button {
                    panel.section = section
                } label: {
                    HStack(spacing: 4) {
                        Text(section.title)
                        // Five sections share 340 points: counts on the one you're in,
                        // or on all of them while searching, where they say where the matches are.
                        if selected || !panel.query.isEmpty, let count = count(section) {
                            Text("\(count)").font(.mono(9.5)).foregroundStyle(count == 0 && !panel.query.isEmpty ? Palette.faint.opacity(0.5) : Palette.faint)
                        }
                    }
                    .font(.mono(11, selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Palette.cream : Palette.muted)
                    .fixedSize()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Palette.selected : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(section.title) (\(section.rawValue + 1) while the panel has the keys)")
            }
            Spacer(minLength: 0)
            ChromeButton(symbol: "magnifyingglass", active: panel.searching, help: "Search agents, skills and tools (⌘F, or / in the panel)") {
                if panel.searching { panel.stopSearching() } else { model.searchPanel() }
            }
            if panel.section == .changes, model.changes[model.selectedFolder]?.files.isEmpty == false {
                ChromeButton(symbol: "smallcircle.filled.circle", help: "Commit these changes (⌘⇧C)") { model.showsCommit = true }
            }
            if panel.section == .changes, let session, model.changes[model.selectedFolder]?.files.isEmpty == false {
                ChromeButton(symbol: "checkmark.seal", help: "Ask \(session.label) to review these changes") {
                    model.leavePanel()
                    session.type("Review the uncommitted changes in this repository (git diff) and point out bugs or anything to fix before I commit.")
                }
            }
            if panel.section == .crew || panel.section == .skills, panel.query.isEmpty {
                NewKitItemButton(kind: panel.section == .crew ? "agent" : "skill", session: session, provider: provider,
                                 config: config, isPresented: $panel.creating)
            }
        }
    }

    private func count(_ section: PanelNavigator.Section) -> Int? {
        if !panel.query.isEmpty { return model.panelItems(section).count }
        switch section {
        case .crew: return config.agents.count
        case .skills: return config.skills.count
        case .tools: return config.mcpServers.count + config.plugins.count + config.commands.count
        case .changes: return model.changes[model.selectedFolder]?.files.count
        case .tips: return nil
        }
    }
}

/// The panel's search, typed through the key router so the arrows and ↩
/// keep moving through the results.
struct PanelSearchField: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var panel: PanelNavigator

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Palette.muted)
            HStack(spacing: 1) {
                if panel.query.isEmpty, panel.searching {
                    Caret()
                    Text("type to filter").foregroundStyle(Palette.faint)
                } else {
                    Text(panel.query).foregroundStyle(Palette.cream)
                    if panel.searching { Caret() }
                }
            }
            .font(.mono(11.5))
            .lineLimit(1)
            Spacer(minLength: 4)
            Button { panel.stopSearching() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.faint)
            }
            .buttonStyle(.plain)
            .help("Clear the search (esc)")
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7).fill(Palette.background))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(panel.searching ? Palette.claude.opacity(0.6) : Palette.border))
        .contentShape(Rectangle())
        .onTapGesture { model.searchPanel() }
    }
}

/// A blinking text cursor.
struct Caret: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            Rectangle()
                .fill(Palette.claude)
                .frame(width: 1.5, height: 13)
                .opacity(Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0 ? 1 : 0)
        }
    }
}

// MARK: - Rows

/// One row, the same height whatever it holds; selected by keyboard or click.
struct PanelRow: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var panel: PanelNavigator
    let item: PanelItem
    let index: Int
    let config: AgentConfiguration
    let session: TerminalSession?
    let provider: Provider
    @State private var hovering = false

    var body: some View {
        let selected = panel.selection == index
        HStack(alignment: .center, spacing: 10) {
            icon.frame(width: 32, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.mono(12, .semibold)).foregroundStyle(titleColor).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(badge).font(.mono(9.5)).foregroundStyle(Palette.faint).lineLimit(1)
                }
                Text(subtitle).font(.mono(10.5)).foregroundStyle(Palette.muted).lineLimit(1)
                if let extra {
                    Text(extra).font(.mono(10)).foregroundStyle(extraColor).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: extra == nil ? 44 : 56)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected && panel.isFocused ? Palette.selected : hovering ? Palette.hover : .clear))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected && panel.isFocused ? Palette.claude.opacity(0.6) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            panel.selection = index
            model.activate(item, detail: true)
        }
        .popover(isPresented: detailBinding, arrowEdge: .leading) {
            if let kitItem = item.kitItem {
                KitDetailCard(item: kitItem, session: session, provider: provider, use: use, isPresented: detailBinding,
                              startEditing: panel.editing)
                    .environmentObject(model)
            }
        }
        .help(help)
    }

    private var detailBinding: Binding<Bool> {
        Binding(get: { panel.openDetail == item.id },
                set: { if !$0, panel.openDetail == item.id { panel.openDetail = nil } })
    }

    private var use: (() -> Void)? {
        switch item {
        case .agent: { model.activate(item, detail: false) }
        case .skill: session == nil ? nil : { model.activate(item, detail: false) }
        default: nil
        }
    }

    // MARK: Content

    @ViewBuilder private var icon: some View {
        switch item {
        case .agent(let agent):
            let working = session?.store?.runningSubagents.contains { $0.type == agent.name || $0.type.hasSuffix(":" + agent.name) } ?? false
            FaceView(figure: .crew(CharacterLook(name: agent.name)), scale: 3, waving: hovering || panel.openDetail == item.id,
                     busy: working, seed: agent.name.count)
                .frame(width: 30, height: 18)
        case .skill(let skill):
            RoundedRectangle(cornerRadius: 2).fill(Color(rgb: Icon.color(for: skill.name))).frame(width: 6, height: 26)
        case .server:
            Image(systemName: "powerplug.fill").foregroundStyle(Palette.mcp)
        case .plugin:
            Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(Palette.agent)
        case .command:
            Text("/").font(.mono(16, .bold)).foregroundStyle(Palette.warning)
        case .change(let change):
            ChangeBadge(kind: change.kind)
        case .tip:
            Image(systemName: "sparkles").foregroundStyle(Palette.warning)
        }
    }

    private var title: String {
        switch item {
        case .agent(let agent): agent.name
        case .skill(let skill): skill.name
        case .server(let server): server.name
        case .plugin(let plugin): plugin.name
        case .command(let command): "/" + command.qualifiedName
        case .change(let change): change.name
        case .tip(let tip):
            switch tip.kind {
            case .agent: "Use the \(tip.name) agent"
            case .skill, .command: "/" + tip.name
            }
        }
    }

    private var titleColor: Color {
        switch item {
        case .agent(let agent): Color(rgb: CharacterLook(name: agent.name).readableColor)
        case .skill: Palette.cream
        case .server: Palette.mcp
        case .plugin: Palette.agent
        case .command, .tip: Palette.warning
        case .change(let change): change.kind == .deleted ? Palette.muted : Palette.cream
        }
    }

    private var badge: String {
        switch item {
        case .agent(let agent): agent.model ?? (agent.scope == .builtin ? "built in" : "")
        case .skill(let skill): skill.plugin ?? (skill.scope == .user ? "yours" : skill.scope == .project ? "project" : "")
        case .server(let server): server.transport
        case .plugin(let plugin): plugin.version.map { "v" + $0 } ?? ""
        case .command(let command): command.plugin ?? ""
        case .change(let change): [change.added.map { "+\($0)" }, change.removed.flatMap { $0 > 0 ? "−\($0)" : nil }]
            .compactMap { $0 }.joined(separator: " ")
        case .tip: ""
        }
    }

    private var subtitle: String {
        switch item {
        case .agent(let agent):
            if let working = session?.store?.runningSubagents.first(where: { $0.type == agent.name || $0.type.hasSuffix(":" + agent.name) }) {
                return "● " + (working.state.action ?? "working")
            }
            return agent.description.map(SkillCategory.summarize) ?? "no description"
        case .skill(let skill): return skill.summary ?? "no description"
        case .server(let server): return "\(provider.shortName) can use its tools · \(server.scope.rawValue)"
        case .plugin(let plugin): return plugin.description ?? pluginContents(plugin)
        case .command(let command): return command.description ?? "a slash command"
        case .change(let change):
            return (change.folder.isEmpty ? "" : change.folder + " · ") + change.kind.rawValue
        case .tip(let tip):
            switch tip.kind {
            case .agent: return config.agents.first { $0.qualifiedName == tip.name }?.description.map(SkillCategory.summarize) ?? ""
            case .skill: return config.skills.first { $0.qualifiedName == tip.name }?.summary ?? ""
            case .command: return config.commands.first { $0.qualifiedName == tip.name }?.description ?? ""
            }
        }
    }

    private var extra: String? {
        switch item {
        case .agent(let agent): return agent.skills.isEmpty ? nil : "carries " + agent.skills.joined(separator: ", ")
        case .plugin(let plugin): return plugin.description == nil ? nil : pluginContents(plugin)
        case .tip(let tip): return "fits: " + tip.reasons.joined(separator: " · ")
        case .change(let change):
            let who = model.sessions(touching: change.path, in: model.selectedFolder).map(\.label)
            return who.isEmpty ? nil : "by " + who.joined(separator: ", ")
        default: return nil
        }
    }

    private var extraColor: Color {
        if case .agent = item { return Palette.skill }
        if case .change = item { return Palette.agent }
        return Palette.faint
    }

    private func pluginContents(_ plugin: PluginDefinition) -> String {
        var parts: [String] = []
        if !plugin.skills.isEmpty { parts.append("\(plugin.skills.count) skills") }
        if !plugin.agents.isEmpty { parts.append("\(plugin.agents.count) agents") }
        if !plugin.commands.isEmpty { parts.append("\(plugin.commands.count) commands") }
        if !plugin.mcpServers.isEmpty { parts.append("\(plugin.mcpServers.count) MCP") }
        return parts.isEmpty ? "plugin" : parts.joined(separator: " · ")
    }

    private var help: String {
        switch item {
        case .agent, .skill: "Click (or ↩) for its card: what it does, use it, change it."
        case .tip: "Click to type it into the terminal."
        case .command: "Click to type it into the terminal."
        case .change: "Click (or ↩) for its diff; u types its path into the terminal; m shows it on the map."
        case .server: "An MCP server: tools from another service the CLI can call."
        case .plugin: "A plugin: a bundle of skills, agents, commands or servers."
        }
    }
}

struct EmptySection: View {
    let section: PanelNavigator.Section
    let provider: Provider

    var body: some View {
        Text(text)
            .font(.mono(11))
            .foregroundStyle(Palette.faint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
    }

    private var text: String {
        switch section {
        case .crew: "No agents yet. \"+ New\" describes one and \(provider.shortName) writes it."
        case .skills: "No skills yet. \"+ New\" describes one and \(provider.shortName) writes it."
        case .tools: "No MCP servers, plugins or commands for \(provider.shortName) here."
        case .changes: "No uncommitted changes. What your agents edit shows up here, with who did it."
        case .tips: "Tips show up as you work: they follow what you ask."
        }
    }
}

// MARK: - Key hints

/// What the keys do right now, at the foot of the panel.
struct KeyHintBar: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var panel: PanelNavigator

    var body: some View {
        HStack(spacing: 10) {
            if panel.isFocused, panel.searching {
                hint("type", "filter")
                hint("↑↓", "move")
                hint("↩", "open")
                hint("esc", "clear")
            } else if panel.isFocused {
                // The rest (e, n, 1-5) are on the ⌘/ sheet.
                hint("↑↓", "move")
                hint("↩", "open")
                hint("u", "use")
                hint("/", "search")
                hint("esc", "back")
            } else {
                Button {
                    model.enterPanel()
                } label: {
                    HStack(spacing: 10) {
                        hint("⌃Tab", "switch terminal")
                        hint("⌘1-9", "tabs")
                        hint("⌘/", "all keys")
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Palette.background.opacity(0.6))
        .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .fixedSize()
                .font(.mono(9.5, .semibold))
                .foregroundStyle(Palette.cream)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(Palette.raised))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Palette.border))
            Text(label).font(.mono(9.5)).foregroundStyle(Palette.muted).fixedSize()
        }
    }
}
