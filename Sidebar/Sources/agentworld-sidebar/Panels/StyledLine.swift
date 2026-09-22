import TerminalUI

/// One row of styled text, built from segments. Panels produce these; the
/// view lays them out and clips them to the pane width.
struct StyledLine {
    struct Segment {
        let text: String
        let style: Style
    }

    private(set) var segments: [Segment] = []
    /// Text pinned to the right edge (durations, counts…).
    private(set) var trailing: Segment?

    init() {}

    init(_ text: String, _ style: Style = .plain) {
        append(text, style)
    }

    var width: Int { segments.reduce(0) { $0 + $1.text.count } }

    mutating func append(_ text: String, _ style: Style = .plain) {
        segments.append(Segment(text: text, style: style))
    }

    func appending(_ text: String, _ style: Style = .plain) -> StyledLine {
        var copy = self
        copy.append(text, style)
        return copy
    }

    func trailing(_ text: String, _ style: Style = .plain) -> StyledLine {
        var copy = self
        copy.trailing = Segment(text: text, style: style)
        return copy
    }

    /// Draws at (x, y) within `width` columns. The trailing segment wins space
    /// over the main text; main text is clipped with an ellipsis.
    func draw(into canvas: inout Canvas, x: Int, y: Int, width: Int) {
        var available = width
        if let trailing, trailing.text.count + 2 <= width {
            available = width - trailing.text.count - 1
            canvas.text(trailing.text, x: x + width - trailing.text.count, y: y, style: trailing.style)
        }

        var column = x
        var remaining = available
        let total = self.width
        for segment in segments where remaining > 0 {
            let text = total > available && segment.text.count >= remaining ? segment.text.fitted(to: remaining) : segment.text
            let end = canvas.text(text, x: column, y: y, style: segment.style, maxWidth: remaining)
            remaining -= end - column
            column = end
        }
    }
}

extension Style {
    static func fg(_ color: RGB, bold: Bool = false, dim: Bool = false, italic: Bool = false) -> Style {
        Style(fg: color, bold: bold, dim: dim, italic: italic)
    }
}
