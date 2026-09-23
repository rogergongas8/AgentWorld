import AgentWorldKit
import Foundation
import TerminalUI

/// Which kind of body a character has: Claude's block creature or a crew member.
public enum CharacterFigure: Sendable, Hashable {
    case claude
    case crew(CharacterLook)
    /// Kiro's little ghost: floats, no legs, a wavy hem.
    case ghost

    /// How much room it takes, standing.
    public var size: (width: Int, height: Int) {
        switch self {
        case .claude: CharacterPainter.claudeSize
        case .crew: CharacterPainter.crewSize
        case .ghost: CharacterPainter.ghostSize
        }
    }
}

/// Pixel-art icons for the explorer's detail pages. Each is 12×12 pixels
/// (12 columns × 6 rows) and drawn from rectangles so colors can vary per item.
public enum Icon {
    public static let size = (width: 12, height: 12)

    case skill(RGB)
    case plugin
    case mcp(RGB)
    case command
    case repository

    /// A stable per-name hue, so every skill's tome has its own color.
    public static func color(for name: String) -> RGB {
        let hash = CharacterLook.stableHash(name.lowercased())
        return RGB.hsv(Double(hash % 1000) / 1000, 0.55, 0.85)
    }

    public func render(t: TimeInterval) -> PixelCanvas {
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

extension Animator {
    /// A friendly wave for the selected character.
    public static func waving(t: TimeInterval) -> Pose {
        let frame = Int(t * 6)
        var pose = Pose()
        pose.eyes = .happy
        pose.rightArm = frame % 2 == 0 ? .up : .forward
        pose.dy = frame % 4 == 0 ? -1 : 0
        return pose
    }
}

extension CharacterLook {
    /// The look's color for text: its body, or its accent when the outfit is
    /// too dark to read on the dark background.
    public var readableColor: RGB { body.luminance < 0.3 ? accent : body }
}

/// Each shelf of skills has its color.
extension SkillCategory {
    public var color: RGB {
        switch self {
        case .design: RGB(hex: 0xF778BA)
        case .documents: RGB(hex: 0x79C0FF)
        case .code: RGB(hex: 0x7EE787)
        case .integrations: RGB(hex: 0xBC8CFF)
        case .data: RGB(hex: 0xFFA657)
        case .workflow: RGB(hex: 0xE3B341)
        case .other: Theme.muted
        }
    }
}

