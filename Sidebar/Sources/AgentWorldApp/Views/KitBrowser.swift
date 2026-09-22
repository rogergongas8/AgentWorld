import AgentWorldArt
import AgentWorldKit
import AppKit
import SwiftUI

/// Everything your CLIs can use, in one place: skills, MCP servers, plugins,
/// commands and agents, per CLI, searchable, plus a matrix that shows at a
/// glance which CLI has which MCP server or skill (and which is missing it).
struct KitBrowser: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var provider = Provider.claude
    @State private var section = KitSection.skills
    @State private var query = ""
    @State private var comparing = false

    var body: some View {
        let folder = model.selectedFolder
        VStack(spacing: 0) {
            header
            Rectangle().fill(Palette.border).frame(height: 1)
            HStack(spacing: 0) {
                providerList(folder: folder)
                    .frame(width: 210)
                    .background(Palette.panel)
                Rectangle().fill(Palette.border).frame(width: 1)
                Group {
                    if comparing {
                        KitMatrix(folder: folder, kind: section == .mcp ? .mcp : .skills, query: query)
                    } else {
                        KitList(config: model.config(provider, in: folder), provider: provider, section: section, query: query)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 980, height: 640)
        .background(Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .onExitCommand { isPresented = false }
        .onAppear {
            if let session = model.focusedSession ?? model.selectedTab?.sessions.first, session.provider.isAgent { provider = session.provider }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill").foregroundStyle(Palette.mcp)
            Text("Kit").font(.mono(15, .bold)).foregroundStyle(Palette.cream)
            Text("in " + URL(fileURLWithPath: model.selectedFolder).lastPathComponent).font(.mono(11)).foregroundStyle(Palette.faint)
            Picker("", selection: $section) {
                ForEach(KitSection.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 400)
            .disabled(comparing)
            Toggle(isOn: $comparing) { Label("Compare CLIs", systemImage: "tablecells").font(.mono(11)) }
                .toggleStyle(.button)
                .help("A matrix of MCP servers or skills × CLIs: see what each one is missing.")
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.faint)
                TextField("Filter", text: $query).textFieldStyle(.plain).font(.mono(11.5))
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.terminalBackground))
            Spacer(minLength: 0)
            Button { isPresented = false } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.muted)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Palette.panel)
    }

    private func providerList(folder: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle(title: "CLIs").padding(.bottom, 4)
                ForEach(Provider.all.filter(\.isAgent), id: \.id) { candidate in
                    let config = model.config(candidate, in: folder)
                    let selected = candidate == provider && !comparing
                    Button {
                        provider = candidate
                        comparing = false
                    } label: {
                        HStack(spacing: 10) {
                            FaceView(figure: candidate.figure, scale: 2.2, waving: selected).frame(width: 24, height: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(candidate.name).font(.mono(12, .semibold)).foregroundStyle(selected ? Palette.cream : candidate.swiftColor)
                                Text("\(config.skills.count) skills · \(config.mcpServers.count) MCP · \(config.plugins.count) plugins")
                                    .font(.mono(9.5)).foregroundStyle(Palette.faint)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Palette.selected : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }
}

enum KitSection: String, CaseIterable, Identifiable {
    case skills, mcp, plugins, commands, agents
    var id: String { rawValue }
    var title: String {
        switch self {
        case .skills: "Skills"
        case .mcp: "MCP"
        case .plugins: "Plugins"
        case .commands: "Commands"
        case .agents: "Agents"
        }
    }
}

/// One CLI's kit, one section of it.
struct KitList: View {
    @EnvironmentObject private var model: AppModel
    let config: AgentConfiguration
    let provider: Provider
    let section: KitSection
    let query: String

    var body: some View {
        let entries = self.entries.filter { query.isEmpty || ($0.title + " " + ($0.detail ?? "")).localizedCaseInsensitiveContains(query) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if entries.isEmpty {
                    empty
                }
                ForEach(entries) { entry in KitRow(entry: entry, provider: provider) }
            }
            .padding(16)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(query.isEmpty ? "No \(section.title.lowercased()) for \(provider.name) here yet." : "Nothing matches “\(query)”.")
                .font(.mono(12.5, .semibold)).foregroundStyle(Palette.muted)
            if query.isEmpty, let hint = hint {
                Text(hint).font(.mono(11)).foregroundStyle(Palette.faint).textSelection(.enabled)
            }
        }
        .padding(.vertical, 20)
    }

    private var hint: String? {
        switch (section, provider.kind) {
        case (.mcp, .claude): "Add one with: claude mcp add <name> -- <command>"
        case (.mcp, .codex): "Add one under [mcp_servers.<name>] in ~/.codex/config.toml"
        case (.mcp, .gemini): "Add one under \"mcpServers\" in ~/.gemini/settings.json"
        case (.skills, .claude): "Skills live in .claude/skills/<name>/SKILL.md (this repo) or ~/.claude/skills."
        case (.plugins, .claude): "Browse plugins with /plugin inside Claude Code."
        case (.agents, .claude): "Make one with /agents inside Claude Code, or .claude/agents/<name>.md."
        default: nil
        }
    }

    private var entries: [KitEntry] {
        switch section {
        case .skills:
            config.skills.map { KitEntry(id: "s:" + $0.qualifiedName, title: "/" + $0.qualifiedName, detail: $0.summary,
                                         badge: $0.category.title, scope: $0.scope, path: $0.path, invocation: "/" + $0.qualifiedName + " ",
                                         color: Color(rgb: Icon.color(for: $0.name))) }
        case .mcp:
            config.mcpServers.map { KitEntry(id: "m:" + $0.name, title: $0.name, detail: "\($0.transport) server" + ($0.plugin.map { " from \($0)" } ?? ""),
                                             badge: $0.transport, scope: $0.scope, path: nil, invocation: nil, color: Palette.mcp) }
        case .plugins:
            config.plugins.map { plugin in
                let parts = [plugin.skills.isEmpty ? nil : "\(plugin.skills.count) skills", plugin.agents.isEmpty ? nil : "\(plugin.agents.count) agents",
                             plugin.commands.isEmpty ? nil : "\(plugin.commands.count) commands", plugin.mcpServers.isEmpty ? nil : "\(plugin.mcpServers.count) MCP",
                             plugin.hasHooks ? "hooks" : nil].compactMap { $0 }
                return KitEntry(id: "p:" + plugin.name, title: plugin.name, detail: plugin.description.map(SkillCategory.summarize),
                                badge: plugin.version.map { "v" + $0 }, scope: .plugin, path: nil, invocation: nil, color: Palette.claude,
                                extra: parts.joined(separator: " · "))
            }
        case .commands:
            config.commands.map { KitEntry(id: "c:" + $0.qualifiedName, title: "/" + $0.qualifiedName, detail: $0.description.map(SkillCategory.summarize),
                                           badge: nil, scope: $0.scope, path: nil, invocation: "/" + $0.qualifiedName + " ", color: Palette.mcp) }
        case .agents:
            config.agents.map { agent in
                KitEntry(id: "a:" + agent.qualifiedName, title: agent.name, detail: agent.description.map(SkillCategory.summarize),
                         badge: agent.model.map(Format.model), scope: agent.scope, path: agent.path,
                         invocation: "Use the \(agent.qualifiedName) agent to ", color: Color(rgb: CharacterLook(name: agent.name).readableColor),
                         figure: .crew(CharacterLook(name: agent.name)),
                         extra: agent.tools.isEmpty ? "all tools" : agent.tools.prefix(6).joined(separator: " · "))
            }
        }
    }
}

struct KitEntry: Identifiable {
    let id: String
    let title: String
    let detail: String?
    let badge: String?
    let scope: ConfigScope
    let path: String?
    /// Typed into a terminal by "Use".
    let invocation: String?
    let color: Color
    var figure: CharacterFigure? = nil
    var extra: String? = nil
}

struct KitRow: View {
    @EnvironmentObject private var model: AppModel
    let entry: KitEntry
    let provider: Provider
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let figure = entry.figure {
                FaceView(figure: figure, scale: 2.4, waving: hovering).frame(width: 26, height: 16)
            } else {
                RoundedRectangle(cornerRadius: 2).fill(entry.color).frame(width: 4, height: 30)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(entry.title).font(.mono(12.5, .semibold)).foregroundStyle(entry.color)
                    if let badge = entry.badge {
                        Text(badge).font(.mono(9.5)).foregroundStyle(Palette.muted)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(Capsule().stroke(Palette.border))
                    }
                    Text(entry.scope.rawValue).font(.mono(9.5)).foregroundStyle(Palette.faint)
                }
                if let detail = entry.detail {
                    Text(detail).font(.mono(11)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                }
                if let extra = entry.extra, !extra.isEmpty {
                    Text(extra).font(.mono(10)).foregroundStyle(Palette.faint)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                if let invocation = entry.invocation {
                    let target = model.focusedSession ?? model.selectedTab?.sessions.first { $0.provider == provider }
                    Button("Use") {
                        model.showsKit = false
                        target?.type(invocation)
                    }
                    .disabled(target == nil)
                    .help(target.map { "Type \(invocation.trimmingCharacters(in: .whitespaces)) into \($0.label)" } ?? "Open a \(provider.shortName) terminal first")
                }
                if let path = entry.path {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    } label: { Image(systemName: "folder") }
                    .help("Show in Finder: \(path)")
                }
            }
            .controlSize(.small)
            .opacity(hovering ? 1 : 0.55)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Palette.hover : Palette.raised))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
        .onHover { hovering = $0 }
    }
}

/// Rows: every MCP server (or skill) any CLI has. Columns: the CLIs. A dot
/// where it's set up; a hollow ring where it's missing.
struct KitMatrix: View {
    @EnvironmentObject private var model: AppModel
    enum Kind { case mcp, skills }
    let folder: String
    let kind: Kind
    let query: String

    var body: some View {
        let providers = Provider.all.filter(\.isAgent)
        let sets: [Set<String>] = providers.map { provider in
            let config = model.config(provider, in: folder)
            return Set(kind == .mcp ? config.mcpServers.map { $0.name.lowercased() } : config.skills.map { $0.name.lowercased() })
        }
        let names = sets.reduce(Set<String>()) { $0.union($1) }
            .filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
            .sorted { lhs, rhs in
                let l = sets.filter { $0.contains(lhs) }.count, r = sets.filter { $0.contains(rhs) }.count
                return l == r ? lhs < rhs : l > r
            }
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text(kind == .mcp ? "MCP server" : "Skill").font(.mono(10.5, .semibold)).foregroundStyle(Palette.muted)
                        .frame(width: 260, alignment: .leading)
                    ForEach(providers, id: \.id) { provider in
                        VStack(spacing: 3) {
                            FaceView(figure: provider.figure, scale: 1.8).frame(width: 20, height: 12)
                            Text(provider.shortName).font(.mono(9.5)).foregroundStyle(provider.swiftColor).lineLimit(1)
                        }
                        .frame(width: 78)
                    }
                }
                .padding(.vertical, 8)
                Rectangle().fill(Palette.border).frame(height: 1)
                if names.isEmpty {
                    Text("None yet.").font(.mono(11)).foregroundStyle(Palette.faint).padding(.vertical, 16)
                }
                ForEach(Array(names.enumerated()), id: \.element) { index, name in
                    HStack(spacing: 0) {
                        Text(name).font(.mono(11.5)).foregroundStyle(Palette.text).lineLimit(1)
                            .frame(width: 260, alignment: .leading)
                        ForEach(Array(providers.enumerated()), id: \.element.id) { column, provider in
                            let has = sets[column].contains(name)
                            Image(systemName: has ? "circle.fill" : "circle")
                                .font(.system(size: has ? 8 : 7))
                                .foregroundStyle(has ? provider.swiftColor : Palette.border)
                                .frame(width: 78)
                                .help(has ? "\(provider.name) has \(name)" : "\(provider.name) doesn't have \(name)")
                        }
                    }
                    .padding(.vertical, 6)
                    .background(index % 2 == 0 ? Palette.panel.opacity(0.5) : .clear)
                }
            }
            .padding(16)
        }
    }
}
