import AgentWorldKit
import Foundation
import TerminalUI

enum ViewMode: Int, CaseIterable {
    case world
    case inventory
    case activity

    var title: String {
        switch self {
        case .world: "world"
        case .inventory: "inventory"
        case .activity: "activity"
        }
    }
}

/// UI state that belongs to the viewer rather than the session.
struct ViewState {
    var mode = ViewMode.world
    var showsStage = true
    var scrollOffset = 0
}

/// Lays out a whole frame for the current pane size.
struct SidebarView {
    static let stageRows = 11
    /// Below this height the stage is hidden automatically.
    static let minimumRowsForStage = 26

    let snapshot: SidebarSnapshot
    let viewState: ViewState

    func render(width: Int, height: Int) -> Canvas {
        var canvas = Canvas(width: width, height: height)
        var y = 0
        let contentWidth = max(0, width - 1)

        func put(_ lines: [StyledLine]) {
            for line in lines where y < height {
                line.draw(into: &canvas, x: 0, y: y, width: contentWidth)
                y += 1
            }
        }

        put(HeaderSection(snapshot: snapshot).lines(width: contentWidth, maxRows: 3))
        let footerRows = height >= 20 ? 1 : 0

        switch viewState.mode {
        case .world:
            if viewState.showsStage, height >= Self.minimumRowsForStage {
                y += 1
                let stage = Stage(store: snapshot.store, now: snapshot.now, hour: Calendar.current.component(.hour, from: snapshot.now))
                    .render(width: width, rows: Self.stageRows)
                stage.pixels.render(into: &canvas, column: 0, row: y)
                y += Self.stageRows
                for label in stage.labels {
                    canvas.text(label.text, x: max(0, label.x), y: y, style: .fg(label.color, bold: true))
                }
                y += 1
            }
            put(CaptionSection(snapshot: snapshot).lines(width: contentWidth, maxRows: 1))
            put(worldSections(width: contentWidth, rows: height - y - footerRows))

        case .inventory:
            let lines = InventorySection(snapshot: snapshot).lines(width: contentWidth, maxRows: .max)
            let rows = height - y - footerRows
            let start = min(viewState.scrollOffset, max(0, lines.count - rows))
            put(Array(lines.dropFirst(start).prefix(rows)))

        case .activity:
            put(LogSection(snapshot: snapshot, scrollOffset: viewState.scrollOffset)
                .lines(width: contentWidth, maxRows: height - y - footerRows))
        }

        if footerRows > 0 { footer(compact: width < 48).draw(into: &canvas, x: 0, y: height - 1, width: contentWidth) }
        return canvas
    }

    /// Fits the world view's sections into `rows`. Each section asks for what
    /// it wants (capped); when space runs short, the lowest-priority sections
    /// shrink or disappear first, and the activity log always takes whatever
    /// is left.
    private func worldSections(width: Int, rows: Int) -> [StyledLine] {
        let sections: [(section: Section, cap: Int)] = [
            (TasksSection(todos: snapshot.store.todos), 8),
            (CrewSection(snapshot: snapshot), 5),
            (MCPSection(snapshot: snapshot), 6),
            (SkillsSection(snapshot: snapshot), 4),
            (ToolsSection(store: snapshot.store), 6),
        ]
        let minimumLogRows = 5

        var budget = sections.map { min($0.cap, $0.section.lines(width: width, maxRows: $0.cap).count) }
        // Shrink from the bottom (lowest priority) up; a section needs a
        // header plus at least one line to be worth showing.
        var index = budget.count - 1
        while budget.reduce(0, +) + minimumLogRows > rows, index >= 0 {
            if budget[index] > 2 {
                budget[index] -= 1
            } else {
                budget[index] = 0
                index -= 1
            }
        }

        var lines: [StyledLine] = []
        for (entry, rowsForSection) in zip(sections, budget) where rowsForSection > 0 {
            lines += entry.section.lines(width: width, maxRows: rowsForSection)
        }
        let logRows = rows - lines.count
        if logRows >= 2 {
            lines += LogSection(snapshot: snapshot).lines(width: width, maxRows: logRows)
        }
        return lines
    }

    /// Compact mode only spells out the selected view's name.
    private func footer(compact: Bool) -> StyledLine {
        var line = StyledLine(" ")
        for mode in ViewMode.allCases {
            let selected = mode == viewState.mode
            let label = compact && !selected ? "\(mode.rawValue + 1)" : "\(mode.rawValue + 1) \(mode.title)"
            line.append(" \(label) ", selected ? Style(fg: Theme.cream, bg: Theme.rule, bold: true) : .fg(Theme.faint))
        }
        let hint = viewState.mode == .world ? "s stage" : "↑↓ scroll"
        return line.trailing(hint + " ", .fg(Theme.faint))
    }
}

/// The "what's available" view: every agent, skill, MCP server and tool with
/// descriptions — the reference companion to the live world view.
struct InventorySection: Section {
    let snapshot: SidebarSnapshot

    func lines(width: Int, maxRows: Int) -> [StyledLine] {
        let store = snapshot.store
        let config = snapshot.config
        var lines: [StyledLine] = []

        lines.append(sectionHeader("AGENTS", badge: "\(config.agents.count)", color: Theme.color(for: .agent), width: width))
        if config.agents.isEmpty {
            lines.append(StyledLine(" none in .claude/agents or ~/.claude/agents", .fg(Theme.faint, italic: true)))
        }
        for agent in config.agents {
            let look = CharacterLook(name: agent.name)
            var line = StyledLine(" ◆ ", .fg(look.body)).appending(agent.name, .fg(look.body, bold: true))
            if let model = agent.model { line.append("  \(model)", .fg(Theme.faint)) }
            lines.append(line.trailing(agent.scope.rawValue, .fg(Theme.faint)))
            if let description = agent.description {
                lines.append(StyledLine("   " + description, .fg(Theme.muted)))
            }
        }

        let accent = Theme.color(for: .skill)
        lines.append(sectionHeader("SKILLS", badge: "\(config.skills.count)", color: accent, width: width))
        for skill in config.skills {
            let usage = store.skillUsage[skill.name]
            var line = StyledLine(" ✦ ", .fg(usage == nil ? Theme.faint : accent)).appending(skill.name, .fg(Theme.text, bold: true))
            line = usage.map { line.trailing("×\($0.count)", .fg(accent)) } ?? line.trailing(skill.scope.rawValue, .fg(Theme.faint))
            lines.append(line)
            if let description = skill.description {
                lines.append(StyledLine("   " + description, .fg(Theme.muted)))
            }
        }

        let mcpAccent = Theme.color(for: .mcp(server: "", tool: ""))
        let servers = MCPSection.entries(snapshot)
        lines.append(sectionHeader("MCP SERVERS", badge: "\(servers.count)", color: mcpAccent, width: width))
        for server in servers {
            var line = StyledLine(server.usage == nil ? " ○ " : " ● ", .fg(server.usage == nil ? Theme.faint : mcpAccent))
            line.append(server.name, .fg(Theme.text, bold: true))
            if let definition = server.definition {
                line.append("  \(definition.transport) · \(definition.scope.rawValue)", .fg(Theme.faint))
            } else {
                line.append("  connector", .fg(Theme.faint))
            }
            lines.append(server.usage.map { line.trailing("×\($0.count)", .fg(mcpAccent)) } ?? line)
        }

        lines += ToolsSection(store: store).lines(width: width, maxRows: .max)
        return Array(lines.prefix(maxRows))
    }
}
