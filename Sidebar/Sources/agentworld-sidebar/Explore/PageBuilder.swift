import TerminalUI

/// A rectangle on a page that can be selected and opened.
struct Target {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let route: Route

    var centerX: Int { x + width / 2 }

    func contains(x px: Int, y py: Int) -> Bool {
        px >= x && px < x + width && py >= y && py < y + height
    }
}

struct CardSpec {
    let figure: CharacterCard.Figure
    let name: String
    let subtitle: String
    let subtitleColor: RGB
    let pose: (_ selected: Bool) -> Pose
    let route: Route
}

/// A rendered explorer screen: content taller than the pane, scrolled by the
/// explorer, plus the selectable targets on it.
struct Page {
    let canvas: Canvas
    let targets: [Target]
}

/// Draws a page top to bottom. Each selectable element registers a target;
/// the builder knows which target index is selected so it can highlight it
/// while drawing.
struct PageBuilder {
    static let selectionBackground = RGB(hex: 0x2A3039)

    let width: Int
    let selection: Int
    private(set) var canvas: Canvas
    private(set) var targets: [Target] = []
    private(set) var y = 0

    init(width: Int, selection: Int) {
        self.width = width
        self.selection = selection
        canvas = Canvas(width: width, height: 64)
    }

    /// Whether the next registered target will be the selected one.
    var nextIsSelected: Bool { targets.count == selection }

    func build() -> Page {
        var cropped = Canvas(width: width, height: max(1, y))
        cropped.blit(canvas, x: 0, y: 0, rows: y)
        return Page(canvas: cropped, targets: targets)
    }

    // MARK: - Space

    mutating func reserve(_ rows: Int) {
        guard y + rows > canvas.height else { return }
        var grown = Canvas(width: width, height: max(canvas.height * 2, y + rows + 16))
        grown.blit(canvas, x: 0, y: 0)
        canvas = grown
    }

    mutating func gap(_ rows: Int = 1) {
        reserve(rows)
        y += rows
    }

    mutating func advance(_ rows: Int) {
        y += rows
    }

    mutating func register(x: Int, y: Int, width: Int, height: Int, route: Route) {
        targets.append(Target(x: x, y: y, width: width, height: height, route: route))
    }

    /// Direct access for custom drawing at the current row.
    mutating func draw(_ body: (inout Canvas, Int) -> Void) {
        body(&canvas, y)
    }

    // MARK: - Lines

    mutating func line(_ line: StyledLine, x: Int = 0) {
        reserve(1)
        line.draw(into: &canvas, x: x, y: y, width: width - x)
        y += 1
    }

    mutating func header(_ title: String, badge: String? = nil, color: RGB) {
        gap()
        line(sectionHeader(title, badge: badge, color: color, width: width))
    }

    /// Word-wrapped paragraph.
    mutating func paragraph(_ text: String, style: Style = .fg(Theme.text), indent: Int = 1, maxLines: Int = .max) {
        let lines = Self.wrap(text, width: width - indent - 1)
        for (index, text) in lines.prefix(maxLines).enumerated() {
            let clipped = index == maxLines - 1 && lines.count > maxLines ? text.dropLast() + "…" : text
            line(StyledLine(clipped, style), x: indent)
        }
    }

    /// A selectable row (one or more lines). The selected one gets a tinted
    /// background and an accent bar on the left.
    mutating func item(_ lines: [StyledLine], route: Route, accent: RGB) {
        let selected = nextIsSelected
        reserve(lines.count)
        register(x: 0, y: y, width: width, height: lines.count, route: route)
        for (index, line) in lines.enumerated() {
            if selected {
                canvas.fill(x: 0, y: y + index, width: width, height: 1, cell: Cell(" ", Style(bg: Self.selectionBackground)))
            }
            line.draw(into: &canvas, x: 1, y: y + index, width: width - 2)
            if selected {
                canvas.tint(x: 0, y: y + index, width: width, background: Self.selectionBackground)
                canvas[0, y + index] = Cell("▌", Style(fg: accent, bg: Self.selectionBackground))
            }
        }
        y += lines.count
    }

    /// Chips that wrap across lines ("Read  Grep  Bash").
    mutating func chips(_ labels: [String], color: RGB, indent: Int = 1) {
        var current = StyledLine()
        for label in labels {
            let chip = " \(label) "
            if current.width + chip.count + 1 > width - indent - 1, current.width > 0 {
                line(current, x: indent)
                current = StyledLine()
            }
            current.append(chip, Style(fg: color, bg: RGB(hex: 0x252A31)))
            current.append(" ")
        }
        if current.width > 0 { line(current, x: indent) }
    }

    /// Character cards laid out left to right, wrapping into rows. `pose`
    /// gets whether that card is selected (selected characters wave).
    mutating func cards(_ specs: [CardSpec]) {
        var x = 1
        reserve(CharacterCard.height)
        for spec in specs {
            let cardWidth = CharacterCard.width(for: spec.figure)
            if x + cardWidth > width, x > 1 {
                advance(CharacterCard.height)
                reserve(CharacterCard.height)
                x = 1
            }
            let selected = nextIsSelected
            let cardX = x
            let pose = spec.pose(selected)
            draw { canvas, y in
                CharacterCard.draw(on: &canvas, x: cardX, y: y, figure: spec.figure, name: spec.name, subtitle: spec.subtitle,
                                   subtitleColor: spec.subtitleColor, pose: pose, selected: selected)
            }
            register(x: cardX, y: y, width: cardWidth, height: CharacterCard.height, route: spec.route)
            x += cardWidth + 1
        }
        if !specs.isEmpty { advance(CharacterCard.height) }
    }

    static func wrap(_ text: String, width: Int) -> [String] {
        guard width > 4 else { return [text] }
        var lines: [String] = []
        for paragraph in text.split(separator: "\n", omittingEmptySubsequences: true) {
            var current = ""
            for word in paragraph.split(separator: " ") {
                var word = String(word)
                while word.count > width {
                    if !current.isEmpty { lines.append(current); current = "" }
                    lines.append(String(word.prefix(width)))
                    word = String(word.dropFirst(width))
                }
                if current.isEmpty {
                    current = word
                } else if current.count + 1 + word.count <= width {
                    current += " " + word
                } else {
                    lines.append(current)
                    current = word
                }
            }
            if !current.isEmpty { lines.append(current) }
        }
        return lines
    }
}
