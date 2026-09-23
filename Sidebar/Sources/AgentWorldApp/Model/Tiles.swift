import AgentWorldKit
import AppKit
import Foundation

/// How the panes of a tab share the space.
enum TileLayout: String, CaseIterable, Identifiable {
    /// As square as possible: 2 → side by side, 4 → 2×2, 6 → 3×2.
    case grid
    /// All side by side.
    case columns
    /// All stacked.
    case rows
    /// The focused pane big on the left, the rest stacked on the right.
    case main

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: "Grid"
        case .columns: "Columns"
        case .rows: "Rows"
        case .main: "One big"
        }
    }

    var symbol: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .columns: "rectangle.split.3x1"
        case .rows: "rectangle.split.1x2"
        case .main: "rectangle.leadinghalf.inset.filled"
        }
    }

    /// Rows of pane indices for `count` panes; `columns` fixes the grid's
    /// width (a tab opened from the grid picker keeps the shape you picked).
    func rows(for count: Int, columns: Int? = nil) -> [[Int]] {
        guard count > 0 else { return [] }
        let all = Array(0..<count)
        switch self {
        case .columns, .main: return [all]
        case .rows: return all.map { [$0] }
        case .grid:
            // 3 → one row of 3; 5 → 3 over 2; 9 → 3×3; otherwise two rows.
            let perRow = columns.map { max(1, $0) }
                ?? (count <= 3 ? count : count == 9 ? 3 : Int((Double(count) / 2).rounded(.up)))
            return stride(from: 0, to: count, by: perRow).map { Array(all[$0..<min($0 + perRow, count)]) }
        }
    }
}

extension AppModel {
    /// Panes per tab: a 3×3 grid, the most that still reads on a big screen.
    static let maxPanes = 9

    /// The grid picker: `rows` × `columns` of the same CLI, tiled in one tab
    /// in exactly that shape.
    func launchGrid(_ profile: LaunchProfile, rows: Int, columns: Int, in folder: String) {
        let count = min(rows * columns, Self.maxPanes)
        launchTogether(Array(repeating: profile, count: count), in: folder)
        guard let tab = selectedTab else { return }
        if rows == 1 {
            tab.layout = .columns
        } else if columns == 1 {
            tab.layout = .rows
        } else {
            tab.layout = .grid
            tab.gridColumns = columns
        }
    }

    /// Opens another CLI next to the ones already in `tab`.
    @discardableResult
    func addPane(_ profile: LaunchProfile, to tab: TerminalTab, focus: Bool = true) -> TerminalSession? {
        guard tab.sessions.count < Self.maxPanes, let executable = executable(for: profile) else { return nil }
        let session = TerminalSession(profile: profile, executable: executable, folder: tab.folder)
        tab.sessions.append(session)
        tab.zoomedID = nil
        tab.gridColumns = nil
        objectWillChange.send()
        if focus { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { session.focus() } }
        return session
    }

    /// Types the same prompt into every running pane of `tab`: ask Claude,
    /// Codex and Gemini the same thing and compare.
    func broadcast(_ text: String, to tab: TerminalTab, submit: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        for session in tab.sessions where session.health == .running {
            session.send(trimmed, submit: submit)
        }
    }

    /// The pane holding the keyboard right now, if it's one of ours.
    var focusedSession: TerminalSession? {
        guard let responder = NSApp.keyWindow?.firstResponder else { return nil }
        return allSessions.first { $0.terminal === responder }
    }
}
