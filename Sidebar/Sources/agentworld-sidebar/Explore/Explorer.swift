import AgentWorldKit
import Foundation
import TerminalUI

/// The navigable explorer: a stack of screens with a focus (selection and
/// scroll) each. Arrow keys move between targets (in 2D for character grids),
/// → / enter open, ← / esc go back, `/` searches, and the mouse can click and
/// scroll.
final class Explorer {
    private struct Entry {
        var route: Route
        var focus = Focus()
    }

    private var stack = [Entry(route: .home)]
    private(set) var query = ""

    // Geometry and content of the last frame, for key handling and hit-testing.
    private var lastPage: Page?
    private var pageTop = 0
    private var pageRows = 0
    private var breadcrumbRow = -1

    private var suggestionCache: (key: Int, config: AgentConfiguration, prompt: [Suggestion], repo: [Suggestion])?

    var route: Route { stack[stack.count - 1].route }
    var isSearching: Bool { route == .search }

    private var focus: Focus {
        get { stack[stack.count - 1].focus }
        set { stack[stack.count - 1].focus = newValue }
    }

    // MARK: - Rendering

    func render(into canvas: inout Canvas, top: Int, rows: Int, width: Int, snapshot: SidebarSnapshot) {
        guard rows > 2 else { return }
        breadcrumbRow = top
        breadcrumb(width: width, provider: snapshot.provider).draw(into: &canvas, x: 0, y: top, width: width)

        pageTop = top + 1
        pageRows = rows - 1
        let (promptSuggestions, repoSuggestions) = suggestions(for: snapshot)
        func build() -> Page {
            Pages(snapshot: snapshot, suggestions: promptSuggestions, repoSuggestions: repoSuggestions,
                  query: query, width: width, selection: focus.selection).page(for: route)
        }
        var page = build()
        // The list shrank (config rescan, search): re-render with a valid selection.
        if focus.settle(on: page, rows: pageRows) { page = build() }
        lastPage = page

        canvas.blit(page.canvas, x: 0, y: pageTop, sourceY: focus.scroll, rows: pageRows)
        drawScrollbar(into: &canvas, x: width, top: pageTop, rows: pageRows, contentHeight: page.canvas.height, scroll: focus.scroll)
    }

    private func breadcrumb(width: Int, provider: Provider) -> StyledLine {
        var line = StyledLine(stack.count > 1 ? " ‹ " : " ◆ ", .fg(stack.count > 1 ? Theme.cream : provider.color, bold: true))
        let names = stack.map { $0.route == .leader ? provider.shortName.lowercased() : $0.route.title }
        // Drop leading crumbs when the trail is too long for the pane.
        var shown = names
        while shown.count > 1, shown.joined(separator: " › ").count + 4 > width {
            shown.removeFirst()
        }
        if shown.count < names.count { line.append("… › ", .fg(Theme.faint)) }
        for (index, name) in shown.enumerated() {
            let last = index == shown.count - 1
            line.append(name, .fg(last ? Theme.cream : Theme.muted, bold: last))
            if !last { line.append(" › ", .fg(Theme.faint)) }
        }
        return line
    }

    private func suggestions(for snapshot: SidebarSnapshot) -> ([Suggestion], [Suggestion]) {
        let log = snapshot.store.log
        let key = log.count &* 31 &+ (log.last.map { Int($0.time.timeIntervalSinceReferenceDate) } ?? 0)
        if let cache = suggestionCache, cache.key == key, cache.config == snapshot.config {
            return (cache.prompt, cache.repo)
        }
        let prompts = log.filter { $0.kind == .prompt }.map(\.text)
        let files = log.compactMap { entry -> String? in
            guard case .tool(let kind) = entry.kind, kind == .edit || kind == .read else { return nil }
            return entry.text.split(separator: " ").last.map(String.init)
        }.suffix(20)
        let fromPrompt = prompts.isEmpty ? [] : Recommender.suggest(config: snapshot.config, prompts: prompts, files: Array(files))
        let fromRepo = Recommender.suggest(config: snapshot.config, prompts: [], files: Array(files))
        suggestionCache = (key, snapshot.config, fromPrompt, fromRepo)
        return (fromPrompt, fromRepo)
    }

    // MARK: - Input

    /// Returns true when the key was used here (the app handles the rest).
    func handle(_ key: Key) -> Bool {
        if isSearching, handleSearchInput(key) { return true }
        switch key {
        case .up, .character("k"): focus.move(vertical: -1, in: targets, rows: pageRows)
        case .down, .character("j"): focus.move(vertical: 1, in: targets, rows: pageRows)
        case .left, .character("h"): if !focus.move(horizontal: -1, in: targets) { back() }
        case .right, .character("l"): if !focus.move(horizontal: 1, in: targets) { open() }
        case .enter, .character(" "): open()
        case .escape, .backspace, .character("b"): back()
        case .character("/"): push(.search)
        case .character("g"), .home: home()
        case .pageUp: focus.page(-1, in: targets, rows: pageRows)
        case .pageDown: focus.page(1, in: targets, rows: pageRows)
        case .end: focus.select(max(0, targets.count - 1))
        case .mouse(let event): handle(event)
        default: return false
        }
        return true
    }

    private func handleSearchInput(_ key: Key) -> Bool {
        switch key {
        case .character(let character):
            query.append(character)
            focus = Focus()
            return true
        case .backspace:
            if query.isEmpty { back() } else { query.removeLast() }
            return true
        case .escape:
            if query.isEmpty { back() } else { query = "" }
            return true
        default:
            return false
        }
    }

    private func handle(_ event: MouseEvent) {
        switch event.action {
        case .scrollUp, .scrollDown:
            guard event.y >= pageTop else { return }
            focus.wheel(event.action == .scrollUp ? -1 : 1)
        case .press:
            if event.y == breadcrumbRow, event.x < 4 {
                back()
                return
            }
            guard event.y >= pageTop, event.y < pageTop + pageRows,
                  let index = Focus.hit(targets, x: event.x, y: event.y - pageTop + focus.scroll) else { return }
            focus.select(index)
            open()
        }
    }

    // MARK: - Navigation

    private var targets: [Target] { lastPage?.targets ?? [] }

    private func push(_ route: Route) {
        if route == .search { query = "" }
        stack.append(Entry(route: route))
    }

    private func open() {
        guard focus.selection < targets.count else { return }
        let destination = targets[focus.selection].route
        guard destination != route else { return }
        push(destination)
    }

    private func back() {
        guard stack.count > 1 else { return }
        stack.removeLast()
        focus.followsSelection = true
    }

    private func home() {
        stack = [stack[0]]
        focus.followsSelection = true
    }
}
