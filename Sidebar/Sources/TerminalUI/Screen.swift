import Foundation

/// Presents canvases to the terminal, rewriting only rows that changed since
/// the previous frame. Each frame goes out in a single `write`, wrapped in
/// synchronized-update markers so capable terminals never show a torn frame.
public final class Screen {
    private let colorMode: ColorMode
    private var previousRows: [String] = []
    private var previousSize = (width: -1, height: -1)
    private let output: (String) -> Void

    public init(colorMode: ColorMode, output: @escaping (String) -> Void = Terminal.write) {
        self.colorMode = colorMode
        self.output = output
    }

    /// Forces the next `present` to redraw everything.
    public func invalidate() {
        previousRows = []
    }

    public func present(_ canvas: Canvas) {
        var frame = ANSI.beginSynchronizedUpdate
        if canvas.width != previousSize.width || canvas.height != previousSize.height {
            frame += ANSI.reset + ANSI.clearScreen
            previousRows = []
            previousSize = (canvas.width, canvas.height)
        }

        var rows: [String] = []
        rows.reserveCapacity(canvas.height)
        for y in 0..<canvas.height {
            let encoded = encode(canvas.row(y))
            rows.append(encoded)
            if y >= previousRows.count || previousRows[y] != encoded {
                frame += ANSI.moveTo(row: y + 1, column: 1) + encoded
            }
        }
        previousRows = rows
        frame += ANSI.endSynchronizedUpdate
        output(frame)
    }

    /// One row as a string of SGR sequences + characters, emitting SGR only
    /// when the style changes. Always ends reset so nothing bleeds.
    public func encode(_ cells: ArraySlice<Cell>) -> String {
        var line = ANSI.reset
        var current = Style.plain
        for cell in cells {
            if cell.style != current {
                line += sgr(for: cell.style)
                current = cell.style
            }
            line.append(cell.character)
        }
        return line + ANSI.reset
    }

    private func sgr(for style: Style) -> String {
        var codes = ["0"]
        if style.bold { codes.append("1") }
        if style.dim { codes.append("2") }
        if style.italic { codes.append("3") }
        if let fg = style.fg { codes.append(color(fg, foreground: true)) }
        if let bg = style.bg { codes.append(color(bg, foreground: false)) }
        return "\u{1B}[" + codes.joined(separator: ";") + "m"
    }

    private func color(_ rgb: RGB, foreground: Bool) -> String {
        switch colorMode {
        case .trueColor: "\(foreground ? 38 : 48);2;\(rgb.r);\(rgb.g);\(rgb.b)"
        case .ansi256: "\(foreground ? 38 : 48);5;\(rgb.xterm256)"
        }
    }
}
