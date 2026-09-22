import TerminalUI

/// Selection and scroll over a page's targets: 2D arrow-key movement (for
/// card grids and lists alike), paging, and keeping the selection in view.
/// Shared by the explorer and the hub's picker.
struct Focus {
    var selection = 0
    var scroll = 0
    /// Keyboard moves keep the selection in view; the mouse wheel doesn't.
    var followsSelection = true

    /// Up/down: the nearest target in the next row that has one, preferring
    /// the same column; with nothing that way, scroll the text instead.
    mutating func move(vertical direction: Int, in targets: [Target], rows: Int) {
        followsSelection = true
        guard selection < targets.count else {
            scroll += direction
            return
        }
        let current = targets[selection]
        let candidates = targets.indices.filter { direction < 0 ? targets[$0].y < current.y : targets[$0].y > current.y }
        let nearestRow = direction < 0 ? candidates.map { targets[$0].y }.max() : candidates.map { targets[$0].y }.min()
        guard let nearestRow,
              let best = candidates.filter({ targets[$0].y == nearestRow })
                .min(by: { abs(targets[$0].centerX - current.centerX) < abs(targets[$1].centerX - current.centerX) }) else {
            scroll += direction
            followsSelection = false
            return
        }
        // Skip far jumps over long text: scroll toward it first.
        if abs(targets[best].y - current.y) > rows / 2, !isVisible(targets[best], rows: rows) {
            scroll += direction * max(1, rows / 3)
            followsSelection = false
        } else {
            selection = best
        }
    }

    /// Left/right within a row of cards. Returns false when there's nothing
    /// that way, so the caller can go back / open instead.
    mutating func move(horizontal direction: Int, in targets: [Target]) -> Bool {
        guard selection < targets.count else { return false }
        let current = targets[selection]
        let sameRow = targets.indices.filter {
            targets[$0].y == current.y && (direction < 0 ? targets[$0].x < current.x : targets[$0].x > current.x)
        }
        guard let next = sameRow.min(by: { abs(targets[$0].x - current.x) < abs(targets[$1].x - current.x) }) else { return false }
        selection = next
        followsSelection = true
        return true
    }

    mutating func page(_ direction: Int, in targets: [Target], rows: Int) {
        scroll = max(0, scroll + direction * max(1, rows - 2))
        // Select the first target now in view, if any.
        if let index = targets.firstIndex(where: { isVisible($0, rows: rows) }) { selection = index }
        followsSelection = true
    }

    mutating func wheel(_ direction: Int) {
        followsSelection = false
        scroll += direction * 3
    }

    mutating func select(_ index: Int) {
        selection = index
        followsSelection = true
    }

    /// Clamps selection and scroll to a freshly built page; returns whether
    /// the selection changed (the page must then be rebuilt to highlight it).
    mutating func settle(on page: Page, rows: Int) -> Bool {
        var changed = false
        if !page.targets.isEmpty, selection >= page.targets.count {
            selection = page.targets.count - 1
            changed = true
        }
        if followsSelection, selection < page.targets.count {
            let target = page.targets[selection]
            // Show the section header above the first item too.
            if target.y - 2 < scroll { scroll = max(0, target.y - 2) }
            if target.y + target.height > scroll + rows { scroll = target.y + target.height - rows }
        }
        scroll = min(max(0, scroll), max(0, page.canvas.height - rows))
        return changed
    }

    func isVisible(_ target: Target, rows: Int) -> Bool {
        target.y >= scroll && target.y + target.height <= scroll + rows
    }

    /// Index of the target under a click at content coordinates.
    static func hit(_ targets: [Target], x: Int, y: Int) -> Int? {
        targets.firstIndex { $0.contains(x: x, y: y) }
    }
}

/// A thin scrollbar on the right edge when the content is taller than the view.
func drawScrollbar(into canvas: inout Canvas, x: Int, top: Int, rows: Int, contentHeight: Int, scroll: Int) {
    guard contentHeight > rows, rows > 2 else { return }
    let thumb = max(1, rows * rows / contentHeight)
    let start = (rows - thumb) * scroll / max(1, contentHeight - rows)
    for row in 0..<rows {
        let inThumb = row >= start && row < start + thumb
        canvas[x, top + row] = Cell(inThumb ? "┃" : "│", .fg(inThumb ? Theme.muted : Theme.barEmpty))
    }
}
