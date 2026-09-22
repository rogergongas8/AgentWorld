import AgentWorldArt
import AgentWorldKit
import Foundation
import TerminalUI

/// Builds every explorer screen. Pure: the same inputs give the same page.
struct Pages {
    let snapshot: SidebarSnapshot
    let suggestions: [Suggestion]
    let repoSuggestions: [Suggestion]
    let query: String
    let width: Int
    let selection: Int

    private var store: SessionStore { snapshot.store }
    private var config: AgentConfiguration { snapshot.config }
    private var provider: Provider { snapshot.provider }
    private var me: String { provider.shortName }
    private var isLive: Bool { snapshot.connection != .configOnly }
    private var t: TimeInterval { snapshot.now.timeIntervalSinceReferenceDate }

    static let agentColor = Theme.color(for: .agent)
    static let skillColor = Theme.color(for: .skill)
    static let mcpColor = Theme.color(for: .mcp(server: "", tool: ""))
    static let commandColor = Theme.color(for: .shell)
    static let pluginColor = RGB(hex: 0xF2C94C)
    static let repoColor = Theme.claude

    func page(for route: Route) -> Page {
        var builder = PageBuilder(width: width, selection: selection)
        switch route {
        case .home: home(&builder)
        case .leader: leader(&builder)
        case .agents: agents(&builder)
        case .skills: skills(&builder)
        case .plugins: plugins(&builder)
        case .mcpServers: mcpServers(&builder)
        case .commands: commands(&builder)
        case .repository: repository(&builder)
        case .search: search(&builder)
        case .clis: clis(&builder)
        case .agent(let name): agent(name, &builder)
        case .skill(let name): skill(name, &builder)
        case .plugin(let name): plugin(name, &builder)
        case .mcpServer(let name): mcpServer(name, &builder)
        case .command(let name): command(name, &builder)
        case .launch, .window, .folder, .typeFolder, .summon, .hubAction: break  // actions, not pages
        }
        builder.gap()
        return builder.build()
    }

    // MARK: - Home

    private func home(_ b: inout PageBuilder) {
        // A tip first: the one thing most worth using right now.
        let fromPrompt = isLive && !prompts.isEmpty && !suggestions.isEmpty
        let ideas = fromPrompt ? suggestions : repoSuggestions
        if let tip = ideas.first {
            b.header("✧ TIP", badge: fromPrompt ? "for what you asked" : "for this repo", color: Theme.warning)
            suggestionRow(&b, tip, isTip: true)
        }

        let working = store.runningSubagents.count
        b.header("YOUR CREW", badge: "\(config.agents.count) agents" + (working > 0 ? " · \(working) working" : ""), color: Self.agentColor)
        leaderRow(&b)
        // Busy agents first, then yours, then the built-ins.
        let ordered = config.agents.sorted { lhs, rhs in
            let l = runningSubagent(for: lhs) != nil, r = runningSubagent(for: rhs) != nil
            if l != r { return l }
            return (lhs.scope == .builtin ? 1 : 0) < (rhs.scope == .builtin ? 1 : 0)
        }
        for agent in ordered.prefix(5) { agentRow(&b, agent) }
        if config.agents.count > 5 {
            b.item([StyledLine("◆ ", .fg(Self.agentColor)).appending("all \(config.agents.count) agents", .fg(Theme.text)).trailing("→", .fg(Theme.faint))],
                   route: .agents, accent: Self.agentColor)
        }

        if ideas.count > 1 {
            b.header("MORE IDEAS", color: Theme.warning.darker(0.2))
            for suggestion in ideas.dropFirst().prefix(3) { suggestionRow(&b, suggestion, isTip: false) }
        } else if ideas.isEmpty {
            b.gap()
            b.paragraph(isLive ? "Tips appear here as you work: the agents and skills that fit what you ask \(me)." : "Press / to search \(me)'s kit.",
                        style: .fg(Theme.faint, italic: true))
        }

        b.header("BROWSE", color: Theme.muted)
        let usedSkills = store.skillUsage.count
        browseItem(&b, "◆", "Agents", "\(config.agents.count)", Self.agentColor, .agents)
        browseItem(&b, "✦", "Skills", "\(config.skills.count)" + (usedSkills > 0 ? " · \(usedSkills) used" : ""), Self.skillColor, .skills)
        browseItem(&b, "▣", "Plugins", "\(config.plugins.count)", Self.pluginColor, .plugins)
        browseItem(&b, "↯", "MCP servers", "\(MCPSection.entries(snapshot).count)", Self.mcpColor, .mcpServers)
        browseItem(&b, "/", "Commands", "\(config.commands.count)", Self.commandColor, .commands)
        browseItem(&b, "⌂", "This repo", config.repository.stacks.prefix(2).joined(separator: " · "), Self.repoColor, .repository)
        browseItem(&b, "⌕", "Find anything", "/", Theme.cream, .search)
        browseItem(&b, "⊞", "Your CLIs", "Claude · Codex · Kimi…", Theme.live, .clis)
    }

    // MARK: - Compact rows (a small face + what it's for)

    /// The CLI itself: who you're talking to on the left.
    private func leaderRow(_ b: inout PageBuilder) {
        let status = claudeStatus
        let selected = b.nextIsSelected
        let pose = isLive && status.isBusy
            ? Animator.pose(status: status, elapsed: snapshot.now.timeIntervalSince(store.main.since), t: t, seed: 0, recentError: false)
            : selected ? Animator.waving(t: t) : Animator.pose(status: .idle, elapsed: 0, t: t, seed: 0, recentError: false)
        let model = store.context.model.map(Format.model) ?? config.model
        let state = isLive
            ? StyledLine("\(Theme.glyph(for: status)) " + (store.main.action ?? status.title), .fg(Theme.color(for: status)))
            : StyledLine(provider.tagline, .fg(Theme.muted))
        b.row(route: .leader, accent: provider.color,
              pixels: Face.render(provider.figure, pose: pose, background: selected ? PageBuilder.selectionBackground : nil),
              lines: [StyledLine(me, .fg(selected ? Theme.cream : provider.color, bold: true)).trailing(model ?? "", .fg(Theme.faint)),
                      state,
                      StyledLine("the one you talk to", .fg(Theme.faint))])
    }

    private func agentRow(_ b: inout PageBuilder, _ agent: AgentDefinition) {
        let look = CharacterLook(name: agent.name)
        let running = runningSubagent(for: agent)
        let selected = b.nextIsSelected
        let pose = running.map {
            Animator.pose(status: $0.state.status, elapsed: snapshot.now.timeIntervalSince($0.state.since), t: t, seed: 1, recentError: false)
        } ?? (selected ? Animator.waving(t: t) : Animator.pose(status: .idle, elapsed: 0, t: t, seed: agent.name.count, recentError: false))
        let runs = runs(of: agent).count
        let third: StyledLine
        if let running {
            third = StyledLine("● " + (running.state.action ?? running.description ?? "working"), .fg(Theme.live, bold: true))
        } else if !agent.skills.isEmpty {
            third = StyledLine("carries " + agent.skills.joined(separator: ", "), .fg(Self.skillColor.darker(0.2)))
        } else {
            third = StyledLine(runs > 0 ? "called ×\(runs) this session" : agent.scope == .builtin ? "built in" : agent.scope.rawValue, .fg(Theme.faint))
        }
        b.row(route: .agent(agent.qualifiedName), accent: look.readableColor,
              pixels: Face.render(.crew(look), pose: pose, background: selected ? PageBuilder.selectionBackground : nil),
              lines: [StyledLine(agent.name, .fg(selected ? Theme.cream : look.readableColor, bold: true)).trailing(agent.model ?? "", .fg(Theme.faint)),
                      StyledLine(agent.description.map(SkillCategory.summarize) ?? "no description", .fg(Theme.muted)),
                      third])
    }

    /// A suggestion with its picture and, for the tip, why it fits.
    private func suggestionRow(_ b: inout PageBuilder, _ suggestion: Suggestion, isTip: Bool) {
        let selected = b.nextIsSelected
        let background = selected ? PageBuilder.selectionBackground : nil
        let why = StyledLine("fits: " + suggestion.reasons.joined(separator: " · "), .fg(Theme.faint, italic: true))
            .trailing(selected ? "u use" : "", .fg(Theme.warning))
        switch suggestion.kind {
        case .agent:
            let agent = findAgent(suggestion.name)
            let look = CharacterLook(name: agent?.name ?? suggestion.name)
            b.row(route: .agent(suggestion.name), accent: look.readableColor,
                  pixels: Face.render(.crew(look), pose: selected || isTip ? Animator.waving(t: t) : Pose(), background: background),
                  lines: [StyledLine("Use ", .fg(Theme.muted)).appending(agent?.name ?? suggestion.name, .fg(look.readableColor, bold: true)).appending(" agent", .fg(Theme.muted)),
                          StyledLine(agent?.description.map(SkillCategory.summarize) ?? "", .fg(Theme.text)),
                          why])
        case .skill:
            let skill = findSkill(suggestion.name)
            let color = Icon.color(for: skill?.name ?? suggestion.name)
            b.row(route: .skill(suggestion.name), accent: color,
                  pixels: Face.book(color: color, band: skill?.plugin != nil ? Bookshelf.pluginBand : Theme.cream, background: background, t: t),
                  lines: [StyledLine("Use ", .fg(Theme.muted)).appending("/" + suggestion.name, .fg(color, bold: true)),
                          StyledLine(skill?.summary ?? "", .fg(Theme.text)),
                          why])
        case .command:
            let command = config.commands.first { $0.qualifiedName == suggestion.name }
            b.row(route: .command(suggestion.name), accent: Self.commandColor,
                  pixels: Face.terminal(background: background, t: t),
                  lines: [StyledLine("Run ", .fg(Theme.muted)).appending("/" + suggestion.name, .fg(Self.commandColor, bold: true)),
                          StyledLine(command?.description.map(SkillCategory.summarize) ?? "", .fg(Theme.text)),
                          why])
        }
    }

    // MARK: - CLIs

    /// One character per agent CLI. Inside the hub, opening one starts it in a
    /// new tab for this folder; elsewhere the page explains how to get there.
    private func clis(_ b: inout PageBuilder) {
        let inHub = Workspace.isInsideHub
        b.header("YOUR CLIs", badge: inHub ? "⏎ opens a new tab here" : nil, color: Theme.live)
        b.gap()
        let t = t
        b.cards(Provider.all.enumerated().map { index, provider in
            let installed = InstalledCLIs.path(for: provider) != nil
            return CardSpec(
                figure: provider.figure,
                name: provider.shortName,
                subtitle: provider.kind == self.provider.kind ? "this one" : installed ? "ready" : "not installed",
                subtitleColor: provider.kind == self.provider.kind ? Theme.live : installed ? Theme.muted : Theme.faint,
                pose: { selected in
                    selected ? Animator.waving(t: t)
                        : Animator.pose(status: .idle, elapsed: installed ? 0 : Animator.sleepAfter + 1, t: t, seed: index + 3, recentError: false)
                },
                route: .launch(provider.id)
            )
        })
        b.gap()
        if inHub {
            b.paragraph("Each opens next to this one as a tab, in the same folder, with its own map of skills and tools. The ⌂ home tab has the full picker: folders, your saved profiles and every open terminal.", style: .fg(Theme.muted))
        } else {
            b.line(StyledLine(" To run several side by side, open a terminal and type:", .fg(Theme.muted)))
            b.gap()
            b.line(StyledLine("   $ ", .fg(Theme.faint)).appending("agentworld", .fg(Theme.cream, bold: true)))
            b.gap()
            b.paragraph("You get a picker with these characters. Each one you pick opens as a tab with its CLI on the left and this map on the right, and they keep running when you close the window.", style: .fg(Theme.muted))
        }
    }

    private func browseItem(_ b: inout PageBuilder, _ glyph: String, _ title: String, _ detail: String, _ color: RGB, _ route: Route) {
        let selected = b.nextIsSelected
        let line = StyledLine("\(glyph) ", .fg(color, bold: true))
            .appending(title, .fg(selected ? Theme.cream : Theme.text, bold: selected))
            .trailing(detail + (selected ? " →" : "  "), .fg(Theme.faint))
        b.item([line], route: route, accent: color)
    }

    private func suggestionItem(_ b: inout PageBuilder, _ suggestion: Suggestion) {
        let (glyph, color, route, kind): (String, RGB, Route, String) = switch suggestion.kind {
        case .agent: ("◆", Self.agentColor, .agent(suggestion.name), "agent")
        case .skill: ("✦", Self.skillColor, .skill(suggestion.name), "skill")
        case .command: ("/", Self.commandColor, .command(suggestion.name), "command")
        }
        let name = suggestion.kind == .agent ? suggestion.name : "/" + suggestion.name
        let first = StyledLine("\(glyph) ", .fg(color, bold: true)).appending(name, .fg(Theme.cream, bold: true)).trailing(kind, .fg(Theme.faint))
        let second = StyledLine("  matches ", .fg(Theme.faint)).appending(suggestion.reasons.joined(separator: " · "), .fg(Theme.muted, italic: true))
        b.item([first, second], route: route, accent: color)
    }

    // MARK: - Character cards

    // MARK: - Lists

    private func agents(_ b: inout PageBuilder) {
        let groups: [(String, [AgentDefinition])] = [
            ("PROJECT", config.agents.filter { $0.scope == .project }),
            ("YOURS", config.agents.filter { $0.scope == .user || $0.scope == .local }),
            ("FROM PLUGINS", config.agents.filter { $0.scope == .plugin }),
            ("BUILT INTO \(provider.name.uppercased())", config.agents.filter { $0.scope == .builtin }),
        ]
        for (title, agents) in groups where !agents.isEmpty {
            b.header(title, badge: "\(agents.count)", color: Self.agentColor)
            for agent in agents { agentRow(&b, agent) }
        }
        if config.customAgents.isEmpty {
            b.header("MAKE YOUR OWN", color: Theme.muted)
            b.paragraph(provider.kind == .claude
                ? "Custom agents live in .claude/agents/<name>.md (this repo) or ~/.claude/agents (everywhere). Run /agents in Claude to create one: give it a job, a set of tools and a model, and it joins the crew."
                : "\(provider.name) has no subagents set up here. Its skills, MCP servers and commands are in Browse.", style: .fg(Theme.muted))
        }
    }

    /// Skills on shelves by category: one book per skill, the selected one
    /// captioned with its summary.
    private func skills(_ b: inout PageBuilder) {
        guard !config.skills.isEmpty else {
            b.gap()
            b.paragraph("No skills yet. Add one at .claude/skills/<name>/SKILL.md.", style: .fg(Theme.faint, italic: true))
            return
        }
        let shelves = SkillCategory.allCases.map { category in (category, config.skills.filter { $0.category == category }) }
            .filter { !$0.1.isEmpty }
        b.gap()
        b.line(StyledLine(" \(config.skills.count) skills on \(shelves.count) shelves  ", .fg(Theme.muted))
            .appending("▬", .fg(Theme.cream)).appending(" yours ", .fg(Theme.faint))
            .appending("▬", .fg(Bookshelf.projectBand)).appending(" repo ", .fg(Theme.faint))
            .appending("▬", .fg(Bookshelf.pluginBand)).appending(" plugin", .fg(Theme.faint)))
        for (category, skills) in shelves {
            b.header(category.title.uppercased(), badge: "\(skills.count)", color: category.color)
            b.shelf(skills.map { BookSpec(skill: $0, used: skillUsage($0) != nil) }, t: t)
        }
    }

    private func skillItem(_ b: inout PageBuilder, _ skill: SkillDefinition) {
        let usage = skillUsage(skill)
        let color = Icon.color(for: skill.name)
        var first = StyledLine("▌", .fg(color, bold: true)).appending(" " + skill.name, .fg(Theme.cream, bold: usage != nil))
        first = first.trailing(usage.map { "used ×\($0.count)" } ?? skill.category.title.lowercased(), .fg(usage == nil ? skill.category.color.darker(0.2) : Self.skillColor))
        let second = StyledLine("  " + (skill.summary ?? "no description"), .fg(Theme.faint))
        b.item([first, second], route: .skill(skill.qualifiedName), accent: Self.skillColor)
    }

    private func plugins(_ b: inout PageBuilder) {
        b.header("INSTALLED", badge: "\(config.plugins.count)", color: Self.pluginColor)
        if config.plugins.isEmpty {
            b.paragraph(provider.kind == .claude ? "No plugins. Browse marketplaces with /plugin in Claude." : "No plugins or extensions installed for \(provider.name).", style: .fg(Theme.faint, italic: true))
        }
        for plugin in config.plugins {
            var parts: [String] = []
            if !plugin.skills.isEmpty { parts.append("\(plugin.skills.count) skills") }
            if !plugin.agents.isEmpty { parts.append("\(plugin.agents.count) agents") }
            if !plugin.mcpServers.isEmpty { parts.append("mcp") }
            if plugin.hasHooks { parts.append("hooks") }
            let first = StyledLine("▣ ", .fg(Self.pluginColor, bold: true)).appending(plugin.name, .fg(Theme.cream, bold: true))
                .trailing(parts.joined(separator: " · "), .fg(Theme.faint))
            let second = StyledLine("  " + (plugin.description ?? ""), .fg(Theme.faint))
            b.item([first, second], route: .plugin(plugin.name), accent: Self.pluginColor)
        }
    }

    private func mcpServers(_ b: inout PageBuilder) {
        let entries = MCPSection.entries(snapshot)
        b.header("MCP SERVERS", badge: "\(entries.count)", color: Self.mcpColor)
        if entries.isEmpty {
            b.paragraph("No MCP servers configured. Add one with `claude mcp add`.", style: .fg(Theme.faint, italic: true))
        }
        for entry in entries {
            var first = StyledLine(entry.usage == nil ? "○ " : "● ", .fg(entry.usage == nil ? Theme.faint : Self.mcpColor, bold: true))
                .appending(entry.name, .fg(Theme.cream, bold: entry.usage != nil))
            if let usage = entry.usage { first = first.trailing("×\(usage.count)", .fg(Self.mcpColor)) }
            let origin = entry.definition.map { definition in
                definition.plugin.map { "\(definition.transport) · plugin \($0)" } ?? "\(definition.transport) · \(definition.scope.rawValue)"
            } ?? "claude.ai connector"
            let detail = entry.usage?.lastDetail.map { origin + " · last: " + $0 } ?? origin
            b.item([first, StyledLine("  " + detail, .fg(Theme.faint))], route: .mcpServer(entry.name), accent: Self.mcpColor)
        }
    }

    private func commands(_ b: inout PageBuilder) {
        b.header("SLASH COMMANDS", badge: "\(config.commands.count)", color: Self.commandColor)
        if config.commands.isEmpty {
            b.paragraph("No custom commands. Add .claude/commands/<name>.md to create one.", style: .fg(Theme.faint, italic: true))
        }
        for command in config.commands {
            let first = StyledLine("/", .fg(Self.commandColor, bold: true)).appending(command.qualifiedName, .fg(Theme.cream, bold: true))
                .trailing(command.plugin ?? command.scope.rawValue, .fg(Theme.faint))
            b.item([first, StyledLine("  " + (command.description ?? ""), .fg(Theme.faint))], route: .command(command.qualifiedName), accent: Self.commandColor)
        }
    }

    // MARK: - Details

    private func agent(_ name: String, _ b: inout PageBuilder) {
        guard let agent = findAgent(name) else { return missing(&b, "agent", name) }
        let look = CharacterLook(name: agent.name)
        let running = runningSubagent(for: agent)
        let pose = running.map {
            Animator.pose(status: $0.state.status, elapsed: snapshot.now.timeIntervalSince($0.state.since), t: t, seed: 1, recentError: false)
        } ?? Animator.waving(t: t)

        var lines = [StyledLine(agent.name, .fg(look.body, bold: true))]
        lines.append(StyledLine(agent.plugin.map { "plugin · \($0)" } ?? agent.scope.rawValue + " agent", .fg(Theme.muted)))
        lines.append(StyledLine("model ", .fg(Theme.faint)).appending(agent.model ?? "same as \(me)", .fg(Theme.text)))
        if let running {
            lines.append(StyledLine("● ", .fg(Theme.live, bold: true)).appending(running.state.action ?? running.state.status.title, .fg(Theme.live)))
        } else {
            let runs = runs(of: agent)
            lines.append(StyledLine(runs.isEmpty ? "not called yet" : "called ×\(runs.count) this session", .fg(runs.isEmpty ? Theme.faint : Self.agentColor)))
        }
        b.hero(pixels: CharacterCard.portrait(.crew(look), pose: pose), lines: lines)

        b.header("SUMMON", color: look.body)
        summonButton(&b, "Use \(agent.name)", .agent(agent.qualifiedName), accent: look.body)
        for name in agent.skills {
            summonButton(&b, "Use \(agent.name) with \(name)", .agentWithSkill(agent: agent.qualifiedName, skill: name), accent: Icon.color(for: name))
        }

        b.header("WHAT IT DOES", color: Self.agentColor)
        b.paragraph(agent.description ?? "No description in its front matter.")

        b.header("TOOLS", badge: agent.tools.isEmpty ? nil : "\(agent.tools.count)", color: Self.agentColor)
        if agent.tools.isEmpty {
            b.paragraph("Inherits every tool \(me) has, MCP servers included.", style: .fg(Theme.muted))
        } else {
            b.chips(agent.tools, color: Theme.text)
        }

        b.header("SKILLS", badge: agent.skills.isEmpty ? nil : "\(agent.skills.count)", color: Self.skillColor)
        if agent.skills.isEmpty {
            b.paragraph("None preloaded. It can still load any of your \(config.skills.count) skills when a task calls for one.", style: .fg(Theme.muted))
        }
        for name in agent.skills {
            if let skill = findSkill(name) {
                skillItem(&b, skill)
            } else {
                b.line(StyledLine(" ✦ \(name)", .fg(Theme.faint)))
            }
        }

        let runs = runs(of: agent)
        if !runs.isEmpty {
            b.header("THIS SESSION", badge: "\(runs.count) runs", color: Self.agentColor)
            for run in runs.suffix(4).reversed() {
                let mark = run.isRunning ? "▸" : (run.state.status == .failed ? "✗" : "✓")
                let color = run.isRunning ? Theme.warning : (run.state.status == .failed ? Theme.error : Theme.live)
                let took = (run.finishedAt ?? snapshot.now).timeIntervalSince(run.startedAt)
                b.line(StyledLine(" \(mark) ", .fg(color, bold: true)).appending(run.description ?? "task", .fg(Theme.text))
                    .trailing("\(Format.duration(took)) · \(run.toolCalls) tools", .fg(Theme.faint)))
            }
        }

        b.gap()
        b.paragraph("\(me) also sends it work on its own when a task matches what it does.", style: .fg(Theme.faint, italic: true))
        if let path = agent.path { b.line(StyledLine(" " + abbreviated(path), .fg(Theme.faint))) }
        if let plugin = agent.plugin { pluginLink(&b, plugin) }
    }

    private func skill(_ name: String, _ b: inout PageBuilder) {
        guard let skill = findSkill(name) else { return missing(&b, "skill", name) }
        let usage = skillUsage(skill)
        var lines = [StyledLine(skill.name, .fg(Theme.cream, bold: true))]
        lines.append(StyledLine("/" + skill.qualifiedName, .fg(Self.skillColor)))
        lines.append(StyledLine(skill.plugin.map { "plugin · \($0)" } ?? skill.scope.rawValue + " skill", .fg(Theme.muted)))
        lines.append(StyledLine(usage.map { "used ×\($0.count) this session" } ?? "not used yet", .fg(usage == nil ? Theme.faint : Self.skillColor)))
        b.hero(pixels: Icon.skill(Icon.color(for: skill.name)).render(t: t), lines: lines)

        let holders = config.agents.filter { agent in agent.skills.contains { $0.caseInsensitiveCompare(skill.name) == .orderedSame } }
        b.header("SUMMON", color: Icon.color(for: skill.name))
        summonButton(&b, "Use \(skill.name)", .skill(qualifiedName: skill.qualifiedName, name: skill.name), accent: Icon.color(for: skill.name))
        for agent in holders {
            summonButton(&b, "\(agent.name) with \(skill.name)", .agentWithSkill(agent: agent.qualifiedName, skill: skill.name), accent: CharacterLook(name: agent.name).body)
        }

        b.header("IN SHORT", color: skill.category.color)
        b.paragraph(skill.summary ?? "No description in SKILL.md.")
        b.header("WHAT IT DOES", badge: skill.category.title.lowercased(), color: Self.skillColor)
        b.paragraph(skill.description ?? "No description in SKILL.md.", style: .fg(Theme.muted))

        b.gap()
        b.paragraph("\(me) also loads it by itself when a request matches what it does.", style: .fg(Theme.faint, italic: true))

        if !holders.isEmpty {
            b.header("AGENTS THAT CARRY IT", color: Self.agentColor)
            for agent in holders { agentItem(&b, agent) }
        }
        if let plugin = skill.plugin { pluginLink(&b, plugin) }
        if let path = skill.path { b.gap(); b.line(StyledLine(" " + abbreviated(path), .fg(Theme.faint))) }
    }

    private func plugin(_ name: String, _ b: inout PageBuilder) {
        guard let plugin = config.plugins.first(where: { $0.name == name }) else { return missing(&b, "plugin", name) }
        var lines = [StyledLine(plugin.name, .fg(Theme.cream, bold: true))]
        if let version = plugin.version { lines.append(StyledLine("v" + version, .fg(Self.pluginColor))) }
        if let author = plugin.author { lines.append(StyledLine("by " + author, .fg(Theme.muted))) }
        lines.append(StyledLine("\(plugin.skills.count) skills · \(plugin.agents.count) agents", .fg(Theme.faint)))
        b.hero(pixels: Icon.plugin.render(t: t), lines: lines)

        if let description = plugin.description {
            b.header("WHAT IT ADDS", color: Self.pluginColor)
            b.paragraph(description)
        }
        let agents = config.agents.filter { $0.plugin == plugin.name }
        if !agents.isEmpty {
            b.header("AGENTS", badge: "\(agents.count)", color: Self.agentColor)
            for agent in agents { agentRow(&b, agent) }
        }
        let skills = config.skills.filter { $0.plugin == plugin.name }
        if !skills.isEmpty {
            b.header("SKILLS", badge: "\(skills.count)", color: Self.skillColor)
            b.shelf(skills.map { BookSpec(skill: $0, used: skillUsage($0) != nil) }, t: t)
        }
        let commands = config.commands.filter { $0.plugin == plugin.name }
        if !commands.isEmpty {
            b.header("COMMANDS", badge: "\(commands.count)", color: Self.commandColor)
            for command in commands {
                b.item([StyledLine("/" + command.qualifiedName, .fg(Theme.cream))], route: .command(command.qualifiedName), accent: Self.commandColor)
            }
        }
        if !plugin.mcpServers.isEmpty {
            b.header("MCP SERVERS", color: Self.mcpColor)
            for server in plugin.mcpServers {
                b.item([StyledLine("↯ ", .fg(Self.mcpColor)).appending(server, .fg(Theme.cream))], route: .mcpServer(server), accent: Self.mcpColor)
            }
        }
        if plugin.hasHooks {
            b.header("HOOKS", color: Theme.muted)
            b.paragraph("Runs its own hooks on \(provider.name) events (notifications, checks…).", style: .fg(Theme.muted))
        }
    }

    private func mcpServer(_ name: String, _ b: inout PageBuilder) {
        let entry = MCPSection.entries(snapshot).first { $0.name == name }
        var lines = [StyledLine(name, .fg(Theme.cream, bold: true))]
        if let definition = entry?.definition {
            lines.append(StyledLine(definition.transport + " server", .fg(Self.mcpColor)))
            lines.append(StyledLine(definition.plugin.map { "plugin · \($0)" } ?? definition.scope.rawValue + " config", .fg(Theme.muted)))
        } else {
            lines.append(StyledLine("claude.ai connector", .fg(Self.mcpColor)))
        }
        if let usage = entry?.usage {
            lines.append(StyledLine("called ×\(usage.count)", .fg(Self.mcpColor)))
        } else {
            lines.append(StyledLine("not called yet", .fg(Theme.faint)))
        }
        b.hero(pixels: Icon.mcp(Self.mcpColor).render(t: t), lines: lines)

        b.header("WHAT IT IS", color: Self.mcpColor)
        b.paragraph("An MCP server gives \(me) extra tools from another service. \(me) picks them up when a request needs it; you can also ask for it by name.", style: .fg(Theme.muted))
        if let detail = entry?.usage?.lastDetail {
            b.header("LAST CALL", color: Self.mcpColor)
            b.line(StyledLine(" ↯ " + detail, .fg(Theme.text)))
        }
        if let plugin = entry?.definition?.plugin { pluginLink(&b, plugin) }
    }

    private func command(_ name: String, _ b: inout PageBuilder) {
        guard let command = config.commands.first(where: { $0.qualifiedName == name }) else { return missing(&b, "command", name) }
        let lines = [
            StyledLine("/" + command.qualifiedName, .fg(Theme.cream, bold: true)),
            StyledLine(command.plugin.map { "plugin · \($0)" } ?? command.scope.rawValue + " command", .fg(Theme.muted)),
        ]
        b.hero(pixels: Icon.command.render(t: t), lines: lines)
        b.header("SUMMON", color: Self.commandColor)
        summonButton(&b, "Run /\(command.qualifiedName)", .command(command.qualifiedName), accent: Self.commandColor)
        b.header("WHAT IT DOES", color: Self.commandColor)
        b.paragraph(command.description ?? "No description.")
        if let plugin = command.plugin { pluginLink(&b, plugin) }
    }

    // MARK: - Repository

    private func repository(_ b: inout PageBuilder) {
        let repo = config.repository
        var lines = [StyledLine(snapshot.projectName, .fg(Theme.cream, bold: true))]
        if let branch = store.context.gitBranch { lines.append(StyledLine("git " + branch, .fg(Theme.muted))) }
        lines.append(StyledLine(repo.stacks.isEmpty ? "stack not detected" : repo.stacks.joined(separator: " · "), .fg(Self.repoColor)))
        let file = repo.instructionsFile ?? "instructions"
        lines.append(StyledLine(repo.hasInstructions ? "\(file) · \(repo.instructionsLines) lines" : "no \(file)", .fg(repo.hasInstructions ? Theme.live : Theme.warning)))
        b.hero(pixels: Icon.repository.render(t: t), lines: lines)

        b.header("WHAT \(me.uppercased()) KNOWS", badge: file, color: Self.repoColor)
        if repo.hasInstructions {
            if let title = repo.instructionsTitle { b.line(StyledLine(" " + title, .fg(Theme.cream, bold: true))) }
            for line in repo.instructionsExcerpt { b.paragraph(line, style: .fg(Theme.muted), maxLines: 2) }
        } else {
            b.paragraph("\(me) starts every session knowing nothing about this repo. Write a \(file) with its structure, commands and conventions (most CLIs, \(me) included, can draft it with /init).", style: .fg(Theme.warning))
        }

        if !repo.folders.isEmpty {
            b.header("FOLDERS", badge: "\(repo.folders.count)", color: Theme.muted)
            b.chips(repo.folders, color: Theme.text)
        }

        b.header("SET UP FOR THIS REPO", color: Theme.muted)
        let projectAgents = config.agents.filter { $0.scope == .project }.count
        let projectSkills = config.skills.filter { $0.scope == .project }.count
        let projectCommands = config.commands.filter { $0.scope == .project }.count
        let projectMCP = config.mcpServers.filter { $0.scope == .project || $0.scope == .local }.count
        browseItem(&b, "◆", "Project agents", "\(projectAgents)", Self.agentColor, .agents)
        browseItem(&b, "✦", "Project skills", "\(projectSkills)", Self.skillColor, .skills)
        browseItem(&b, "/", "Project commands", "\(projectCommands)", Self.commandColor, .commands)
        browseItem(&b, "↯", "Project MCP servers", "\(projectMCP)", Self.mcpColor, .mcpServers)
        if !repo.hookEvents.isEmpty {
            b.line(StyledLine(" ⚑ hooks on ", .fg(Theme.muted)).appending(repo.hookEvents.joined(separator: ", "), .fg(Theme.text)))
        }

        if !repoSuggestions.isEmpty {
            b.header("GOOD FIT FOR THIS STACK", color: Theme.warning)
            for suggestion in repoSuggestions { suggestionItem(&b, suggestion) }
        }
    }

    // MARK: - The CLI itself (the crew's leader)

    private func leader(_ b: inout PageBuilder) {
        let status = claudeStatus
        let pose = isLive
            ? Animator.pose(status: status, elapsed: snapshot.now.timeIntervalSince(store.main.since), t: t, seed: 0, recentError: false)
            : Animator.waving(t: t)
        var lines = [StyledLine(provider.name, .fg(provider.color, bold: true)), StyledLine(provider.tagline, .fg(Theme.muted))]
        if let model = store.context.model.map(Format.model) ?? config.model { lines.append(StyledLine("model " + model, .fg(Theme.text))) }
        if isLive {
            lines.append(StyledLine("\(Theme.glyph(for: status)) " + status.title, .fg(Theme.color(for: status), bold: true)))
            if let action = store.main.action { lines.append(StyledLine(action, .fg(Theme.text))) }
        }
        b.hero(pixels: CharacterCard.portrait(provider.figure, pose: pose), lines: lines)
        if !isLive {
            b.gap()
            b.paragraph("Live activity (tasks, subagents, tool calls) is followed for Claude Code sessions; for \(provider.name) this panel maps its setup.", style: .fg(Theme.faint, italic: true))
        }

        let todoLines = TasksSection(todos: store.todos).lines(width: width, maxRows: 10)
        if !todoLines.isEmpty {
            b.gap()
            for line in todoLines { b.line(line) }
        }

        let running = store.runningSubagents
        if !running.isEmpty {
            b.header("WORKING FOR \(me.uppercased())", badge: "\(running.count)", color: Self.agentColor)
            for subagent in running {
                let look = CharacterLook(name: subagent.type)
                let line = StyledLine("\(Theme.glyph(for: subagent.state.status)) ", .fg(Theme.color(for: subagent.state.status), bold: true))
                    .appending(subagent.type, .fg(look.body, bold: true))
                    .appending("  " + (subagent.state.action ?? subagent.description ?? ""), .fg(Theme.text))
                b.item([line], route: .agent(subagent.type), accent: look.body)
            }
        }

        b.header("\(me.uppercased())'S KIT", color: provider.color)
        browseItem(&b, "◆", "Agents it can call", "\(config.agents.count)", Self.agentColor, .agents)
        browseItem(&b, "✦", "Skills it can load", "\(config.skills.count)", Self.skillColor, .skills)
        browseItem(&b, "↯", "MCP servers", "\(MCPSection.entries(snapshot).count)", Self.mcpColor, .mcpServers)

        let usedSkills = store.skillUsage.values.sorted { $0.lastUsed > $1.lastUsed }
        let usedMCP = store.mcpUsage.values.sorted { $0.lastUsed > $1.lastUsed }
        if !usedSkills.isEmpty || !usedMCP.isEmpty {
            b.header("USED THIS SESSION", color: Theme.muted)
            for usage in usedSkills {
                b.item([StyledLine("✦ ", .fg(Self.skillColor)).appending(usage.name, .fg(Theme.text)).trailing("×\(usage.count)", .fg(Self.skillColor))],
                       route: .skill(usage.name), accent: Self.skillColor)
            }
            for usage in usedMCP {
                b.item([StyledLine("↯ ", .fg(Self.mcpColor)).appending(usage.name, .fg(Theme.text)).trailing("×\(usage.count)", .fg(Self.mcpColor))],
                       route: .mcpServer(usage.name), accent: Self.mcpColor)
            }
        }
        if store.totalToolCalls > 0 {
            b.gap()
            b.line(StyledLine(" \(store.turns) turns · \(store.totalToolCalls) tool calls · \(store.subagents.count) subagents", .fg(Theme.faint)))
        }
    }

    // MARK: - Search

    private func search(_ b: inout PageBuilder) {
        let cursor = Int(t * 2) % 2 == 0 ? "▌" : " "
        b.gap()
        b.line(StyledLine(" ⌕ ", .fg(Theme.cream, bold: true)).appending(query, .fg(Theme.cream, bold: true)).appending(cursor, .fg(Theme.claude)))
        b.line(StyledLine(" type to filter agents, skills, plugins, MCP, commands", .fg(Theme.faint, italic: true)))
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else { return }

        // Every word must appear in the name or description.
        func matches(_ name: String, _ description: String?) -> Bool {
            let haystack = name.lowercased() + " " + (description?.lowercased() ?? "")
            return words.allSatisfy { haystack.contains($0) }
        }
        let agents = config.agents.filter { matches($0.qualifiedName, $0.description) }
        let skills = config.skills.filter { matches($0.qualifiedName, $0.description) }
        let plugins = config.plugins.filter { matches($0.name, $0.description) }
        let servers = MCPSection.entries(snapshot).filter { matches($0.name, nil) }
        let commands = config.commands.filter { matches($0.qualifiedName, $0.description) }

        if !agents.isEmpty {
            b.header("AGENTS", badge: "\(agents.count)", color: Self.agentColor)
            for agent in agents { agentItem(&b, agent) }
        }
        if !skills.isEmpty {
            b.header("SKILLS", badge: "\(skills.count)", color: Self.skillColor)
            for skill in skills { skillItem(&b, skill) }
        }
        if !plugins.isEmpty {
            b.header("PLUGINS", badge: "\(plugins.count)", color: Self.pluginColor)
            for plugin in plugins { pluginLink(&b, plugin.name, header: false) }
        }
        if !servers.isEmpty {
            b.header("MCP", badge: "\(servers.count)", color: Self.mcpColor)
            for server in servers {
                b.item([StyledLine("↯ ", .fg(Self.mcpColor)).appending(server.name, .fg(Theme.cream))], route: .mcpServer(server.name), accent: Self.mcpColor)
            }
        }
        if !commands.isEmpty {
            b.header("COMMANDS", badge: "\(commands.count)", color: Self.commandColor)
            for command in commands {
                b.item([StyledLine("/" + command.qualifiedName, .fg(Theme.cream))], route: .command(command.qualifiedName), accent: Self.commandColor)
            }
        }
        if agents.isEmpty && skills.isEmpty && plugins.isEmpty && servers.isEmpty && commands.isEmpty {
            b.gap()
            b.line(StyledLine(" nothing matches \"\(query)\"", .fg(Theme.faint, italic: true)))
        }
    }

    // MARK: - Info bar

    /// What the highlighted (or hovered) thing is for, for the bar at the
    /// bottom of the sidebar: a title and one sentence.
    func info(for route: Route) -> (title: StyledLine, detail: String)? {
        switch route {
        case .leader:
            return (StyledLine(provider.name, .fg(provider.color, bold: true)), "\(provider.tagline). ⏎ what it's doing and its kit")
        case .agent(let name):
            guard let agent = findAgent(name) else { return nil }
            let look = CharacterLook(name: agent.name)
            return (StyledLine("◆ " + agent.name, .fg(look.readableColor, bold: true)).appending(agent.model.map { "  " + $0 } ?? "", .fg(Theme.faint)),
                    (agent.description.map(SkillCategory.summarize) ?? "An agent") + ". u use it · ⏎ details")
        case .skill(let name):
            guard let skill = findSkill(name) else { return nil }
            return (StyledLine("✦ " + skill.name, .fg(Icon.color(for: skill.name), bold: true)).appending("  " + skill.category.title.lowercased(), .fg(Theme.faint)),
                    (skill.summary ?? "A skill") + ". u use it · ⏎ details")
        case .command(let name):
            let command = config.commands.first { $0.qualifiedName == name }
            return (StyledLine("/" + name, .fg(Self.commandColor, bold: true)), (command?.description.map(SkillCategory.summarize) ?? "A slash command") + ". u runs it")
        case .mcpServer(let name):
            return (StyledLine("↯ " + name, .fg(Self.mcpColor, bold: true)), "Gives \(me) tools from another service; \(me) calls them when a task needs it")
        case .plugin(let name):
            let plugin = config.plugins.first { $0.name == name }
            return (StyledLine("▣ " + name, .fg(Self.pluginColor, bold: true)), plugin?.description ?? "A plugin")
        case .summon(let text):
            return (StyledLine("▶ types into \(me):", .fg(Theme.live, bold: true)), text + "…  (you finish the sentence)")
        case .launch(let id):
            guard let other = Provider.named(id) else { return nil }
            return (StyledLine(other.name, .fg(other.color, bold: true)), other.tagline + (InstalledCLIs.path(for: other) == nil ? ". Not installed" : ""))
        case .agents: return (StyledLine("Agents", .fg(Self.agentColor, bold: true)), "Helpers \(me) can hand work to, each with its own job, tools and model")
        case .skills: return (StyledLine("Skills", .fg(Self.skillColor, bold: true)), "Know-how \(me) loads when a task needs it, on shelves by topic")
        case .plugins: return (StyledLine("Plugins", .fg(Self.pluginColor, bold: true)), "Packs that add skills, agents, commands and MCP servers at once")
        case .mcpServers: return (StyledLine("MCP servers", .fg(Self.mcpColor, bold: true)), "Connections to other services (Figma, Miro, databases…)")
        case .commands: return (StyledLine("Commands", .fg(Self.commandColor, bold: true)), "Your own /shortcuts for prompts you use often")
        case .repository: return (StyledLine("This repo", .fg(Self.repoColor, bold: true)), "What \(me) knows about this project, and what's set up just for it")
        case .search: return (StyledLine("Find", .fg(Theme.cream, bold: true)), "Search every agent, skill, plugin and command by name or purpose")
        case .clis: return (StyledLine("Your CLIs", .fg(Theme.live, bold: true)), "Claude, Codex, Gemini, Kimi… open another one side by side")
        default: return nil
        }
    }

    // MARK: - Summoning

    /// A "▶ …" button that types a request into the CLI next door.
    private func summonButton(_ b: inout PageBuilder, _ label: String, _ target: Summoner.Target, accent: RGB) {
        let selected = b.nextIsSelected
        let line = StyledLine("▶ ", .fg(accent, bold: true))
            .appending(label, .fg(selected ? Theme.cream : Theme.text, bold: true))
            .trailing(selected ? "⏎" : "", .fg(Theme.faint))
        b.item([line], route: .summon(Summoner.text(for: target, provider: provider)), accent: accent)
    }

    // MARK: - Shared rows

    private func agentItem(_ b: inout PageBuilder, _ agent: AgentDefinition) {
        let look = CharacterLook(name: agent.name)
        let first = StyledLine("◆ ", .fg(look.body, bold: true)).appending(agent.name, .fg(Theme.cream, bold: true))
            .trailing(agent.plugin ?? agent.scope.rawValue, .fg(Theme.faint))
        b.item([first, StyledLine("  " + (agent.description ?? ""), .fg(Theme.faint))], route: .agent(agent.qualifiedName), accent: look.body)
    }

    private func pluginLink(_ b: inout PageBuilder, _ name: String, header: Bool = true) {
        if header { b.header("FROM PLUGIN", color: Self.pluginColor) }
        let description = config.plugins.first { $0.name == name }?.description
        var lines = [StyledLine("▣ ", .fg(Self.pluginColor, bold: true)).appending(name, .fg(Theme.cream, bold: true)).trailing("→", .fg(Theme.faint))]
        if let description { lines.append(StyledLine("  " + description, .fg(Theme.faint))) }
        b.item(lines, route: .plugin(name), accent: Self.pluginColor)
    }

    private func missing(_ b: inout PageBuilder, _ kind: String, _ name: String) {
        b.gap()
        b.paragraph("No \(kind) named \"\(name)\" in the current configuration (it may come from a claude.ai connector or was removed).", style: .fg(Theme.faint, italic: true))
    }

    // MARK: - Lookups

    private var claudeStatus: ActorStatus {
        var status = store.main.status
        if status.isBusy, let last = store.lastEventAt, snapshot.now.timeIntervalSince(last) > 600 { status = .idle }
        if status == .thinking, !store.runningSubagents.isEmpty { status = .delegating }
        return status
    }

    private var prompts: [String] {
        store.log.filter { $0.kind == .prompt }.map(\.text)
    }

    private func findAgent(_ name: String) -> AgentDefinition? {
        config.agents.first { $0.qualifiedName.caseInsensitiveCompare(name) == .orderedSame }
            ?? config.agents.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func findSkill(_ name: String) -> SkillDefinition? {
        config.skills.first { $0.qualifiedName.caseInsensitiveCompare(name) == .orderedSame }
            ?? config.skills.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func runs(of agent: AgentDefinition) -> [Subagent] {
        store.subagents.filter {
            $0.type.caseInsensitiveCompare(agent.name) == .orderedSame || $0.type.caseInsensitiveCompare(agent.qualifiedName) == .orderedSame
        }
    }

    private func runningSubagent(for agent: AgentDefinition) -> Subagent? {
        runs(of: agent).last { $0.isRunning }
    }

    private func skillUsage(_ skill: SkillDefinition) -> CapabilityUsage? {
        store.skillUsage[skill.qualifiedName] ?? store.skillUsage[skill.name]
    }

    /// `~/…` and, when it wouldn't fit on one line, `~/.claude/…/figma/skills/x`.
    private func abbreviated(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let short = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        let limit = max(20, width - 3)
        guard short.count > limit else { return short }
        var parts = short.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 4 else { return String(short.suffix(limit - 1)) }
        let head = parts.prefix(2).joined(separator: "/")
        parts = Array(parts.dropFirst(2))
        while parts.count > 1, (head + "/…/" + parts.joined(separator: "/")).count > limit { parts.removeFirst() }
        return head + "/…/" + parts.joined(separator: "/")
    }
}
