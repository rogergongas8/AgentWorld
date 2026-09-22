import TerminalUI

/// A launcher button: the character's face, a title, a subtitle and a hint.
struct ButtonSpec {
    let figure: CharacterCard.Figure
    let title: String
    let subtitle: String
    let hint: String
    let accent: RGB
    /// Not installed: drawn faded.
    let dimmed: Bool
    let pose: (_ selected: Bool) -> Pose
    let route: Route
}

extension PageBuilder {
    static let buttonHeight = 5

    mutating func centered(_ text: StyledLine) {
        line(text, x: max(0, (width - text.width) / 2))
    }

    /// A selectable row with a pixel face on the left and lines of text next
    /// to it, followed by a blank spacer row.
    mutating func row(route: Route, accent: RGB, pixels: PixelCanvas, lines: [StyledLine]) {
        let height = max(pixels.height / 2, lines.count)
        let selected = nextIsSelected
        reserve(height + 1)
        register(x: 0, y: y, width: width, height: height, route: route)
        let width = width
        let textX = pixels.width + 3
        draw { canvas, top in
            if selected {
                canvas.fill(x: 0, y: top, width: width, height: height, cell: Cell(" ", Style(bg: PageBuilder.selectionBackground)))
            }
            pixels.render(into: &canvas, column: 1, row: top)
            for (index, line) in lines.enumerated() {
                line.draw(into: &canvas, x: textX, y: top + index, width: width - textX - 1)
                if selected { canvas.tint(x: textX, y: top + index, width: width - textX, background: PageBuilder.selectionBackground) }
            }
            if selected {
                for row in 0..<height { canvas[0, top + row] = Cell("▌", Style(fg: accent, bg: PageBuilder.selectionBackground)) }
            }
        }
        advance(height + 1)
    }

    /// Launcher buttons in a centered grid (1–3 columns by width).
    mutating func buttons(_ specs: [ButtonSpec]) {
        guard !specs.isEmpty else { return }
        let columns = width >= 100 ? 3 : width >= 62 ? 2 : 1
        let gutter = 2
        let buttonWidth = min(38, (width - 2 - (columns - 1) * gutter) / columns)
        let gridWidth = columns * buttonWidth + (columns - 1) * gutter
        let left = max(0, (width - gridWidth) / 2)
        let height = Self.buttonHeight

        for start in stride(from: 0, to: specs.count, by: columns) {
            reserve(height)
            for (column, spec) in specs[start..<min(specs.count, start + columns)].enumerated() {
                let x = left + column * (buttonWidth + gutter)
                let selected = nextIsSelected
                let face = Face.render(spec.figure, pose: spec.pose(selected), background: selected ? PageBuilder.selectionBackground : nil)
                draw { canvas, top in
                    Self.drawButton(spec, face: face, selected: selected, into: &canvas, x: x, y: top, width: buttonWidth)
                }
                register(x: x, y: y, width: buttonWidth, height: height, route: spec.route)
            }
            advance(height)
        }
    }

    private static func drawButton(_ spec: ButtonSpec, face: PixelCanvas, selected: Bool, into canvas: inout Canvas, x: Int, y: Int, width: Int) {
        let border = Style(fg: selected ? spec.accent : spec.dimmed ? Theme.barEmpty : Theme.rule, bold: selected)
        let background: RGB? = selected ? PageBuilder.selectionBackground : nil
        canvas.text("╭" + String(repeating: "─", count: width - 2) + "╮", x: x, y: y, style: border)
        for row in 1...3 {
            canvas[x, y + row] = Cell("│", border)
            canvas[x + width - 1, y + row] = Cell("│", border)
            if let background { canvas.fill(x: x + 1, y: y + row, width: width - 2, height: 1, cell: Cell(" ", Style(bg: background))) }
        }
        canvas.text("╰" + String(repeating: "─", count: width - 2) + "╯", x: x, y: y + 4, style: border)

        face.render(into: &canvas, column: x + 2, row: y + 1)
        let textX = x + 2 + Face.width + 2
        let textWidth = x + width - 2 - textX
        let titleColor = spec.dimmed ? Theme.muted : selected ? Theme.cream : spec.accent
        canvas.text(spec.title.fitted(to: textWidth), x: textX, y: y + 1, style: Style(fg: titleColor, bg: background, bold: true))
        canvas.text(spec.subtitle.fitted(to: textWidth), x: textX, y: y + 2, style: Style(fg: spec.dimmed ? Theme.faint : Theme.muted, bg: background))
        canvas.text(spec.hint.fitted(to: textWidth), x: textX, y: y + 3, style: Style(fg: selected ? spec.accent : Theme.faint, bg: background))
    }
}
