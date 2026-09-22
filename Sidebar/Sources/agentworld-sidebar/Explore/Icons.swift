import AgentWorldArt
import Foundation
import TerminalUI

/// A character card: a framed portrait with the agent's name and a subtitle.
/// The selected card gets a bright frame and its character waves.
enum CharacterCard {
    static let height = 12
    static let portraitRows = 8

    typealias Figure = CharacterFigure

    static func width(for figure: Figure) -> Int {
        switch figure {
        case .claude: CharacterPainter.claudeSize.width + 4
        case .crew: CharacterPainter.crewSize.width + 4
        }
    }

    static func draw(
        on canvas: inout Canvas,
        x: Int,
        y: Int,
        figure: Figure,
        name: String,
        subtitle: String,
        subtitleColor: RGB,
        pose: Pose,
        selected: Bool,
        badges: [RGB] = []
    ) {
        let width = width(for: figure)
        let accent: RGB = switch figure {
        case .claude: Theme.claude
        // Dark outfits would make the name unreadable; use the accent then.
        case .crew(let look): look.body.luminance < 0.3 ? look.accent : look.body
        }
        let frameStyle = Style(fg: selected ? accent : Theme.rule, bold: selected)
        let background = selected ? PageBuilder.selectionBackground : nil

        // Frame.
        canvas.text("╭" + String(repeating: "─", count: width - 2) + "╮", x: x, y: y, style: frameStyle)
        for row in 1..<(height - 1) {
            canvas[x, y + row] = Cell("│", frameStyle)
            canvas[x + width - 1, y + row] = Cell("│", frameStyle)
            if let background {
                canvas.fill(x: x + 1, y: y + row, width: width - 2, height: 1, cell: Cell(" ", Style(bg: background)))
            }
        }
        canvas.text("╰" + String(repeating: "─", count: width - 2) + "╯", x: x, y: y + height - 1, style: frameStyle)
        // The skills it carries, as little books sitting on the bottom edge.
        for (index, color) in badges.prefix(width - 4).enumerated() {
            canvas[x + 2 + index, y + height - 1] = Cell("▮", Style(fg: color, bold: true))
        }

        // Portrait, standing on a little strip of floor.
        var pixels = PixelCanvas(width: width - 2, height: portraitRows * 2)
        let ground = pixels.height - 1
        pixels.rect(x: 0, y: ground, width: pixels.width, height: 1, selected ? accent.darker(0.55) : Theme.barEmpty)
        switch figure {
        case .claude:
            CharacterPainter.drawClaude(on: &pixels, x: 1, ground: ground, pose: pose)
        case .crew(let look):
            CharacterPainter.drawCrew(on: &pixels, look: look, x: 1, ground: ground, pose: pose)
        }
        if let background {
            // Transparent pixels would show the terminal background; paint the
            // selection color behind them instead.
            for px in 0..<pixels.width {
                for py in 0..<pixels.height where pixels[px, py] == nil { pixels[px, py] = background }
            }
        }
        pixels.render(into: &canvas, column: x + 1, row: y + 1)

        let inner = width - 2
        let nameStyle = Style(fg: selected ? Theme.cream : accent, bg: background, bold: true)
        canvas.text(centered(name, inner), x: x + 1, y: y + 1 + portraitRows, style: nameStyle)
        canvas.text(centered(subtitle, inner), x: x + 1, y: y + 2 + portraitRows, style: Style(fg: subtitleColor, bg: background))
    }

    /// The card's portrait on its own (detail pages).
    static func portrait(_ figure: Figure, pose: Pose) -> PixelCanvas {
        var pixels = PixelCanvas(width: width(for: figure) - 2, height: portraitRows * 2)
        let ground = pixels.height - 1
        pixels.rect(x: 0, y: ground, width: pixels.width, height: 1, Theme.barEmpty)
        switch figure {
        case .claude: CharacterPainter.drawClaude(on: &pixels, x: 1, ground: ground, pose: pose)
        case .crew(let look): CharacterPainter.drawCrew(on: &pixels, look: look, x: 1, ground: ground, pose: pose)
        }
        return pixels
    }

    private static func centered(_ text: String, _ width: Int) -> String {
        let clipped = text.fitted(to: width)
        let left = (width - clipped.count) / 2
        return String(repeating: " ", count: left) + clipped + String(repeating: " ", count: width - left - clipped.count)
    }
}

