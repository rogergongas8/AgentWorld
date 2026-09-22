import Foundation
import TerminalUI

/// Pixel-art icons for the explorer's detail pages. Each is 12×12 pixels
/// (12 columns × 6 rows) and drawn from rectangles so colors can vary per item.
enum Icon {
    static let size = (width: 12, height: 12)

    case skill(RGB)
    case plugin
    case mcp(RGB)
    case command
    case repository

    /// A stable per-name hue, so every skill's tome has its own color.
    static func color(for name: String) -> RGB {
        let hash = CharacterLook.stableHash(name.lowercased())
        return RGB.hsv(Double(hash % 1000) / 1000, 0.55, 0.85)
    }

    func render(t: TimeInterval) -> PixelCanvas {
        var p = PixelCanvas(width: Self.size.width, height: Self.size.height)
        let glow = sin(t * 3) > 0
        switch self {
        case .skill(let cover):
            // A tome: dark spine, colored cover, cream page edges, star emblem.
            p.rect(x: 2, y: 1, width: 8, height: 10, cover)
            p.rect(x: 2, y: 1, width: 8, height: 1, cover.lighter(0.25))
            p.rect(x: 1, y: 1, width: 1, height: 10, cover.darker(0.45))
            p.rect(x: 10, y: 2, width: 1, height: 9, Theme.cream)
            p.rect(x: 2, y: 10, width: 9, height: 1, Theme.cream.darker(0.2))
            let star = glow ? RGB(hex: 0xFFF3B0) : RGB(hex: 0xF2C94C)
            p.rect(x: 5, y: 4, width: 2, height: 3, star)
            p.rect(x: 4, y: 5, width: 4, height: 1, star)

        case .plugin:
            // A treasure chest: wooden box, gold band and lock.
            let wood = RGB(hex: 0x8B5A2B)
            let gold = RGB(hex: 0xF2C94C)
            p.rect(x: 1, y: 3, width: 10, height: 3, wood.lighter(0.15))
            p.rect(x: 1, y: 6, width: 10, height: 5, wood)
            p.rect(x: 1, y: 6, width: 10, height: 1, gold)
            p.rect(x: 1, y: 3, width: 1, height: 8, gold.darker(0.2))
            p.rect(x: 10, y: 3, width: 1, height: 8, gold.darker(0.2))
            p.rect(x: 5, y: 6, width: 2, height: 3, glow ? gold.lighter(0.4) : gold)
            p.rect(x: 1, y: 10, width: 10, height: 1, wood.darker(0.35))

        case .mcp(let color):
            // A portal ring with a pulsing core.
            p.rect(x: 3, y: 1, width: 6, height: 1, color)
            p.rect(x: 3, y: 10, width: 6, height: 1, color)
            p.rect(x: 1, y: 3, width: 1, height: 6, color)
            p.rect(x: 10, y: 3, width: 1, height: 6, color)
            p[2, 2] = color; p[9, 2] = color; p[2, 9] = color; p[9, 9] = color
            let core = glow ? color.lighter(0.5) : color.darker(0.2)
            p.rect(x: 4, y: 4, width: 4, height: 4, core)
            p.rect(x: 5, y: 3, width: 2, height: 6, core)
            p.rect(x: 3, y: 5, width: 6, height: 2, core)

        case .command:
            // A tiny terminal window with a "/" prompt and blinking cursor.
            let frame = RGB(hex: 0x9DA5B4)
            p.rect(x: 0, y: 1, width: 12, height: 10, frame)
            p.rect(x: 1, y: 3, width: 10, height: 7, RGB(hex: 0x1B1F24))
            p.rect(x: 1, y: 2, width: 10, height: 1, frame.darker(0.3))
            let green = Theme.live
            p[2, 8] = green; p[3, 7] = green; p[4, 6] = green; p[5, 5] = green
            if glow { p.rect(x: 7, y: 8, width: 2, height: 1, Theme.cream) }

        case .repository:
            // A little house: roof, walls, door, window with light.
            let roof = Theme.claude
            for row in 0..<4 {
                p.rect(x: 5 - row, y: 1 + row, width: 2 + row * 2, height: 1, roof.darker(Double(row) * 0.05))
            }
            p.rect(x: 1, y: 5, width: 10, height: 1, roof.darker(0.3))
            p.rect(x: 2, y: 6, width: 8, height: 5, Theme.cream.darker(0.1))
            p.rect(x: 3, y: 8, width: 2, height: 3, RGB(hex: 0x6B4F3A))
            p.rect(x: 6, y: 7, width: 3, height: 2, glow ? RGB(hex: 0xF2C94C) : RGB(hex: 0xE3B341).darker(0.2))
            p.rect(x: 0, y: 11, width: 12, height: 1, RGB(hex: 0x3FA34D))
        }
        return p
    }
}

/// A character card: a framed portrait with the agent's name and a subtitle.
/// The selected card gets a bright frame and its character waves.
enum CharacterCard {
    static let height = 12
    static let portraitRows = 8

    enum Figure {
        case claude
        case crew(CharacterLook)
    }

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
        selected: Bool
    ) {
        let width = width(for: figure)
        let accent: RGB = switch figure {
        case .claude: Theme.claude
        case .crew(let look): look.body
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

    private static func centered(_ text: String, _ width: Int) -> String {
        let clipped = text.fitted(to: width)
        let left = (width - clipped.count) / 2
        return String(repeating: " ", count: left) + clipped + String(repeating: " ", count: width - left - clipped.count)
    }
}

extension Animator {
    /// A friendly wave for the selected character.
    static func waving(t: TimeInterval) -> Pose {
        let frame = Int(t * 6)
        var pose = Pose()
        pose.eyes = .happy
        pose.rightArm = frame % 2 == 0 ? .up : .forward
        pose.dy = frame % 4 == 0 ? -1 : 0
        return pose
    }
}
