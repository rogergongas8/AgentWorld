import AgentWorldKit
import Foundation
import TerminalUI

enum ViewMode: Int, CaseIterable {
    case explore
    case live
    case activity

    var title: String {
        switch self {
        case .explore: "explore"
        case .live: "live"
        case .activity: "log"
        }
    }
}

/// UI state that belongs to the viewer rather than the session.
struct ViewState {
    var mode = ViewMode.explore
    var showsStage = true
    var scrollOffset = 0
}

/// Where the footer's tabs were drawn, for mouse clicks.
struct FooterHit {
    let row: Int
    let tabs: [(range: Range<Int>, mode: ViewMode)]
}

/// Lays out a whole frame for the current pane size.
struct SidebarView {
    static let stageRows = 11
    /// Below this height the stage is hidden automatically.
    static let minimumRowsForStage = 26

    let snapshot: SidebarSnapshot
    let viewState: ViewState
    let explorer: Explorer

    func render(width: Int, height: Int) -> (canvas: Canvas, footer: FooterHit?) {
        var canvas = Canvas(width: width, height: height)
        var y = 0
        let contentWidth = max(0, width - 1)

        func put(_ lines: [StyledLine]) {
            for line in lines where y < height {
                line.draw(into: &canvas, x: 0, y: y, width: contentWidth)
                y += 1
            }
        }

        put(HeaderSection(snapshot: snapshot).lines(width: contentWidth, maxRows: height >= 30 ? 3 : 2))
        let footerRows = height >= 16 ? 1 : 0

        // Without a live session there's nothing for the live/log views to show.
        let mode = snapshot.connection == .configOnly ? .explore : viewState.mode
        switch mode {
        case .explore:
            explorer.render(into: &canvas, top: y, rows: height - y - footerRows, width: contentWidth, snapshot: snapshot)

        case .live:
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
            put(liveSections(width: contentWidth, rows: height - y - footerRows))

        case .activity:
            put(LogSection(snapshot: snapshot, scrollOffset: viewState.scrollOffset)
                .lines(width: contentWidth, maxRows: height - y - footerRows))
        }

        guard footerRows > 0 else { return (canvas, nil) }
        let (line, tabs) = footer(compact: width < 44)
        line.draw(into: &canvas, x: 0, y: height - 1, width: contentWidth)
        return (canvas, FooterHit(row: height - 1, tabs: tabs))
    }

    /// Fits the live view's sections into `rows`. Each section asks for what
    /// it wants (capped); when space runs short, the lowest-priority sections
    /// shrink or disappear first.
    private func liveSections(width: Int, rows: Int) -> [StyledLine] {
        let sections: [(section: Section, cap: Int)] = [
            (TasksSection(todos: snapshot.store.todos), 10),
            (CrewSection(snapshot: snapshot), 6),
            (MCPSection(snapshot: snapshot), 6),
            (SkillsSection(snapshot: snapshot), 4),
            (ToolsSection(store: snapshot.store), 8),
        ]

        var budget = sections.map { min($0.cap, $0.section.lines(width: width, maxRows: $0.cap).count) }
        // Shrink from the bottom (lowest priority) up; a section needs a
        // header plus at least one line to be worth showing.
        var index = budget.count - 1
        while budget.reduce(0, +) > rows, index >= 0 {
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
        return lines
    }

    /// Compact mode only spells out the selected view's name.
    private func footer(compact: Bool) -> (StyledLine, [(range: Range<Int>, mode: ViewMode)]) {
        var line = StyledLine(" ")
        var tabs: [(range: Range<Int>, mode: ViewMode)] = []
        let modes = snapshot.connection == .configOnly ? [ViewMode.explore] : ViewMode.allCases
        for mode in modes {
            let selected = mode == viewState.mode
            let label = compact && !selected ? "\(mode.rawValue + 1)" : "\(mode.rawValue + 1) \(mode.title)"
            let start = line.width
            line.append(" \(label) ", selected ? Style(fg: Theme.cream, bg: Theme.rule, bold: true) : .fg(Theme.faint))
            tabs.append((start..<line.width, mode))
        }
        let hint: String = switch viewState.mode {
        case .explore: explorer.isSearching ? "esc clear" : (compact ? "/ find" : "←→↑↓ ⏎ · / find")
        case .live: "s stage"
        case .activity: "↑↓ scroll"
        }
        return (line.trailing(hint + " ", .fg(Theme.faint)), tabs)
    }
}
