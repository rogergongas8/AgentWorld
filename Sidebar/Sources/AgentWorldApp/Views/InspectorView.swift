import AgentWorldArt
import AgentWorldKit
import SwiftUI

/// The right column: the terminal's character acting out what it's doing,
/// one tip for what you're doing, then the agents and skills this CLI has here. Everything explains itself on hover
/// and a click hands it to the terminal ("Use the X agent to ▌").
struct InspectorView: View {
    @EnvironmentObject private var model: AppModel
    let session: TerminalSession?
    let folder: String

    var body: some View {
        let terminal = session
        let provider = session?.provider.isAgent == true ? session!.provider : .claude
        let config = model.config(provider, in: folder)
        // A plain shell can't take "use this agent": show the kit, no actions.
        let session = session?.provider.isAgent == true ? session : nil
        GeometryReader { geometry in
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let terminal {
                    HeroStage(session: terminal, compact: geometry.size.height < 620)
                }
                if let tip = model.tips(for: session, in: folder).first {
                    TipCard(tip: tip, config: config, session: session, fromPrompt: session?.store?.log.contains { $0.kind == .prompt } == true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(title: "Your crew", color: Palette.claude, trailing: AnyView(HStack(spacing: 8) {
                        Text("\(config.agents.count)").font(.mono(10)).foregroundStyle(Palette.faint)
                        NewKitItemButton(kind: "agent", session: session, provider: provider, config: config)
                    }))
                    ForEach(config.agents, id: \.qualifiedName) { agent in
                        KitAgentRow(agent: agent, session: session, provider: provider)
                    }
                }

                SkillShelves(config: config, session: session, provider: provider)

                if !config.mcpServers.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionTitle(title: "Connected to", color: Palette.mcp)
                        FlowChips(items: config.mcpServers.map(\.name), color: Palette.mcp)
                    }
                    .help("MCP servers: tools from other services \(provider.shortName) can call")
                }
            }
            .padding(14)
        }
        }
    }
}

struct TipCard: View {
    let tip: Suggestion
    let config: AgentConfiguration
    let session: TerminalSession?
    let fromPrompt: Bool

    var body: some View {
        let (title, summary, color, figure) = describe()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text(fromPrompt ? "TIP · for what you asked" : "TIP · for this repo")
            }
            .font(.mono(10.5, .semibold))
            .foregroundStyle(Palette.warning)
            HStack(alignment: .top, spacing: 10) {
                if let figure {
                    FaceView(figure: figure, scale: 2.4, waving: true).frame(width: 24, height: 15)
                } else {
                    Image(systemName: "book.closed.fill").foregroundStyle(color).font(.system(size: 18))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.mono(12.5, .semibold)).foregroundStyle(color)
                    Text(summary).font(.mono(11)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                    Text("fits: " + tip.reasons.joined(separator: " · ")).font(.mono(10)).foregroundStyle(Palette.faint)
                }
            }
            if let session {
                Button {
                    session.type(invocation)
                } label: {
                    Label("Use it", systemImage: "arrow.turn.down.left").font(.mono(11, .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.warning.opacity(0.85))
                .controlSize(.small)
                .help("Types \"\(invocation)\" into \(session.label) for you to finish")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.warning.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.warning.opacity(0.35)))
    }

    private var invocation: String {
        switch tip.kind {
        case .agent: "Use the \(tip.name) agent to "
        case .skill: session?.provider.kind == .claude ? "/\(tip.name) " : "Use the \(tip.name) skill to "
        case .command: "/\(tip.name) "
        }
    }

    private func describe() -> (String, String, Color, CharacterFigure?) {
        switch tip.kind {
        case .agent:
            let agent = config.agents.first { $0.qualifiedName == tip.name }
            let look = CharacterLook(name: agent?.name ?? tip.name)
            return ("Use the \(agent?.name ?? tip.name) agent", agent?.description.map(SkillCategory.summarize) ?? "", Color(rgb: look.readableColor), .crew(look))
        case .skill:
            let skill = config.skills.first { $0.qualifiedName == tip.name }
            return ("/" + tip.name, skill?.summary ?? "", Color(rgb: Icon.color(for: skill?.name ?? tip.name)), nil)
        case .command:
            return ("/" + tip.name, config.commands.first { $0.qualifiedName == tip.name }?.description ?? "", Palette.warning, nil)
        }
    }
}

struct KitAgentRow: View {
    @EnvironmentObject private var model: AppModel
    let agent: AgentDefinition
    let session: TerminalSession?
    let provider: Provider
    @State private var hovering = false
    @State private var showsDetail = false

    var body: some View {
        let look = CharacterLook(name: agent.name)
        let working = session?.store?.runningSubagents.first { $0.type == agent.name || $0.type.hasSuffix(":" + agent.name) }
        HStack(alignment: .top, spacing: 12) {
            FaceView(figure: .crew(look), scale: 5, waving: hovering, busy: working != nil, seed: agent.name.count)
                .frame(width: 50, height: 30)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent.name).font(.mono(12.5, .semibold)).foregroundStyle(Color(rgb: look.readableColor)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(agent.model ?? "").font(.mono(10)).foregroundStyle(Palette.faint)
                }
                Text(working.map { "● " + ($0.state.action ?? "working") } ?? agent.description.map(SkillCategory.summarize) ?? "no description")
                    .font(.mono(10.5))
                    .foregroundStyle(working == nil ? Palette.muted : Palette.live)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !agent.skills.isEmpty {
                    Text("carries " + agent.skills.joined(separator: ", ")).font(.mono(10)).foregroundStyle(Palette.skill).lineLimit(1)
                } else if agent.scope == .builtin {
                    Text("built in").font(.mono(10)).foregroundStyle(Palette.faint)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Palette.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { showsDetail = true }
        .popover(isPresented: $showsDetail, arrowEdge: .leading) {
            KitDetailCard(item: .agent(agent), session: session, provider: provider, use: use, isPresented: $showsDetail)
                .environmentObject(model)
        }
        .help((agent.description.map(SkillCategory.summarize) ?? agent.name) + "\nClick for details, to use it or to change it.")
    }

    private func use() {
        if let session {
            session.type("Use the \(agent.qualifiedName) agent to ")
        } else {
            model.startChat(with: agent, provider: provider, in: model.selectedFolder)
        }
    }
}

/// Skills grouped by what they're for, as small colored book chips.
struct SkillShelves: View {
    let config: AgentConfiguration
    let session: TerminalSession?
    let provider: Provider

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Skills", color: Palette.skill, trailing: AnyView(HStack(spacing: 8) {
                Text("\(config.skills.count)").font(.mono(10)).foregroundStyle(Palette.faint)
                NewKitItemButton(kind: "skill", session: session, provider: provider, config: config)
            }))
            ForEach(SkillCategory.allCases, id: \.self) { category in
                let skills = config.skills.filter { $0.category == category }
                if !skills.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(category.title).font(.mono(10, .semibold)).foregroundStyle(Color(rgb: category.color))
                        WrapLayout(spacing: 5) {
                            ForEach(skills, id: \.qualifiedName) { skill in
                                SkillChip(skill: skill, session: session, provider: provider)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct SkillChip: View {
    @EnvironmentObject private var model: AppModel
    let skill: SkillDefinition
    let session: TerminalSession?
    let provider: Provider
    @State private var hovering = false
    @State private var showsDetail = false

    var body: some View {
        let color = Color(rgb: Icon.color(for: skill.name))
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 5, height: 12)
            Text(skill.name).font(.mono(10.5)).foregroundStyle(hovering ? Palette.cream : Palette.text).lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Palette.hover : Palette.raised))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(hovering ? color.opacity(0.7) : Palette.border))
        .onHover { hovering = $0 }
        .onTapGesture { showsDetail = true }
        .popover(isPresented: $showsDetail, arrowEdge: .leading) {
            KitDetailCard(item: .skill(skill), session: session, provider: provider,
                          use: session.map { session in { session.type(provider.kind == .claude ? "/\(skill.qualifiedName) " : "Use the \(skill.name) skill to ") } },
                          isPresented: $showsDetail)
                .environmentObject(model)
        }
        .help((skill.summary ?? skill.name) + (skill.plugin.map { "\nFrom plugin \($0)" } ?? "") + "\nClick for details, to use it or to change it.")
    }
}

struct FlowChips: View {
    let items: [String]
    let color: Color

    var body: some View {
        WrapLayout(spacing: 5) {
            ForEach(items, id: \.self) { item in
                Text(item).font(.mono(10.5)).foregroundStyle(color)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Palette.raised))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Palette.border))
            }
        }
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
