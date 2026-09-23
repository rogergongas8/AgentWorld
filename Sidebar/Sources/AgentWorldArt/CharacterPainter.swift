import Foundation
import AgentWorldKit
import TerminalUI

/// The rectangle a drawn figure occupies, used to place props around it.
public struct Figure: Sendable {
    public let x: Int
    public let top: Int
    public let width: Int
    public let height: Int

    public var right: Int { x + width }
    public var bottom: Int { top + height }
    public var centerX: Int { x + width / 2 }
}

/// Procedural pixel art for the two character families: Claude (an orange
/// block creature with slit eyes and four little legs) and the crew members
/// that represent subagents (small humanoids with varied headgear).
public enum CharacterPainter {
    public static let claudeSize = (width: 16, height: 10)
    public static let crewSize = (width: 10, height: 13)

    private static let eyeColor = RGB(hex: 0x1B1B1F)

    // MARK: - Claude

    @discardableResult
    public static func drawClaude(on canvas: inout PixelCanvas, x originX: Int, ground: Int, pose: Pose) -> Figure {
        let x = originX + pose.dx
        let top = ground - claudeSize.height + pose.dy
        let base = tinted(Theme.claude, pose.tint)
        let light = base.lighter(0.18)
        let shade = base.darker(0.22)

        // Legs (drawn first so the body overlaps their tops).
        for (index, legX) in [3, 5, 10, 12].enumerated() {
            let lifted = pose.step.map { (index % 2) == $0 } ?? false
            canvas.rect(x: x + legX, y: top + 8, width: 1, height: lifted ? 1 : 2, shade)
        }

        // Body with a highlight on top and shading at the bottom.
        canvas.rect(x: x + 2, y: top, width: 12, height: 8, base)
        canvas.rect(x: x + 2, y: top, width: 12, height: 1, light)
        canvas.rect(x: x + 2, y: top + 7, width: 12, height: 1, shade)

        drawArm(on: &canvas, x: x, y: top, pose: pose.leftArm, color: base, rowForDown: 3, width: 2)
        drawArm(on: &canvas, x: x + 14, y: top, pose: pose.rightArm, color: base, rowForDown: 3, width: 2)

        drawEyes(on: &canvas, positions: [x + 5, x + 10], row: top + 2, eyes: pose.eyes, height: 2, color: eyeColor)

        let figure = Figure(x: x, top: top, width: claudeSize.width, height: claudeSize.height)
        drawProps(pose.props, on: &canvas, around: figure)
        return figure
    }

    // MARK: - Any figure

    public static let ghostSize = (width: 12, height: 13)

    /// Draws whichever figure it is, standing on `ground` at `x`.
    @discardableResult
    public static func draw(_ figure: CharacterFigure, on canvas: inout PixelCanvas, x: Int, ground: Int, pose: Pose) -> Figure {
        switch figure {
        case .claude: drawClaude(on: &canvas, x: x, ground: ground, pose: pose)
        case .crew(let look): drawCrew(on: &canvas, look: look, x: x, ground: ground, pose: pose)
        case .ghost: drawGhost(on: &canvas, x: x, ground: ground, pose: pose)
        }
    }

    // MARK: - Ghost (Kiro)

    /// A round-topped ghost that floats a pixel above the ground, its wavy
    /// hem rippling as it moves, with little arms and big eyes.
    @discardableResult
    public static func drawGhost(on canvas: inout PixelCanvas, x originX: Int, ground: Int, pose: Pose) -> Figure {
        let x = originX + pose.dx
        let top = ground - ghostSize.height + pose.dy - 1
        let body = tinted(RGB(hex: 0xF1EEFF), pose.tint)
        let shade = tinted(RGB(hex: 0xC9BEF5), pose.tint)
        let eyes = RGB(hex: 0x3B2494)
        // Head: a rounded dome.
        canvas.rect(x: x + 4, y: top, width: 4, height: 1, body)
        canvas.rect(x: x + 2, y: top + 1, width: 8, height: 1, body)
        canvas.rect(x: x + 1, y: top + 2, width: 10, height: 1, body)
        canvas.rect(x: x, y: top + 3, width: 12, height: 8, body)
        canvas.rect(x: x, y: top + 9, width: 12, height: 2, shade)
        // The hem: three scallops that shift with each step.
        let phase = (pose.step ?? 0) % 2
        for scallop in 0..<3 {
            let sx = x + scallop * 4 + (phase == 0 ? 0 : 1)
            canvas.rect(x: sx, y: top + 11, width: 3, height: 1, shade)
            canvas[sx + 1, top + 12] = shade
        }
        // Little arms at the sides.
        switch pose.leftArm {
        case .up: canvas.rect(x: x - 1, y: top + 3, width: 1, height: 3, body)
        case .forward: canvas.rect(x: x - 1, y: top + 6, width: 1, height: 2, body)
        case .down: canvas.rect(x: x - 1, y: top + 6, width: 1, height: 2, shade)
        }
        switch pose.rightArm {
        case .up: canvas.rect(x: x + 12, y: top + 3, width: 1, height: 3, body)
        case .forward: canvas.rect(x: x + 12, y: top + 6, width: 1, height: 2, body)
        case .down: canvas.rect(x: x + 12, y: top + 6, width: 1, height: 2, shade)
        }
        drawEyes(on: &canvas, positions: [x + 3, x + 8], row: top + 4, eyes: pose.eyes, height: 2, color: eyes)
        let figure = Figure(x: x, top: top, width: ghostSize.width, height: ghostSize.height)
        drawProps(pose.props, on: &canvas, around: figure)
        return figure
    }

    // MARK: - Crew

    @discardableResult
    public static func drawCrew(on canvas: inout PixelCanvas, look: CharacterLook, x originX: Int, ground: Int, pose: Pose) -> Figure {
        let x = originX + pose.dx
        let top = ground - crewSize.height + pose.dy
        let body = tinted(look.body, pose.tint)
        let hair = tinted(look.hair, pose.tint)
        let skin = tinted(look.skin, pose.tint)
        let pants = hair.darker(0.25)

        // Legs.
        for (index, legX) in [3, 6].enumerated() {
            let lifted = pose.step.map { index == $0 } ?? false
            canvas.rect(x: x + legX, y: top + 11, width: 1, height: lifted ? 1 : 2, pants)
        }

        // Torso with a belt and an emblem.
        canvas.rect(x: x + 2, y: top + 6, width: 6, height: 5, body)
        canvas.rect(x: x + 2, y: top + 6, width: 6, height: 1, body.lighter(0.15))
        canvas.rect(x: x + 2, y: top + 9, width: 6, height: 1, body.darker(0.3))
        canvas[x + 4, top + 7] = look.accent
        canvas[x + 5, top + 7] = look.accent

        drawArm(on: &canvas, x: x + 1, y: top + 3, pose: pose.leftArm, color: body, rowForDown: 4, width: 1)
        drawArm(on: &canvas, x: x + 8, y: top + 3, pose: pose.rightArm, color: body, rowForDown: 4, width: 1)

        // Head.
        canvas.rect(x: x + 1, y: top + 1, width: 8, height: 5, skin)
        canvas.rect(x: x + 1, y: top + 1, width: 8, height: 1, hair)
        canvas[x + 1, top + 2] = hair
        canvas[x + 8, top + 2] = hair

        switch look.face {
        case .skin:
            drawEyes(on: &canvas, positions: [x + 3, x + 6], row: top + 3, eyes: pose.eyes, height: 1, color: eyeColor)
            canvas[x + 4, top + 5] = skin.darker(0.25)
            canvas[x + 5, top + 5] = skin.darker(0.25)
        case .visor:
            canvas.rect(x: x + 2, y: top + 3, width: 6, height: 1, RGB(hex: 0x22262E))
            drawEyes(on: &canvas, positions: [x + 3, x + 6], row: top + 3, eyes: pose.eyes, height: 1, color: look.accent)
        }

        drawHeadgear(look.headgear, on: &canvas, x: x, top: top, look: look)

        let figure = Figure(x: x, top: top, width: crewSize.width, height: crewSize.height)
        drawProps(pose.props, on: &canvas, around: figure)
        return figure
    }

    private static func drawHeadgear(_ headgear: CharacterLook.Headgear, on canvas: inout PixelCanvas, x: Int, top: Int, look: CharacterLook) {
        let metal = RGB(hex: 0x9DA5B4)
        switch headgear {
        case .antenna:
            canvas[x + 5, top] = metal
            canvas[x + 5, top - 1] = look.accent
        case .cap:
            canvas.rect(x: x + 1, y: top, width: 8, height: 2, look.accent)
            canvas.rect(x: x + 8, y: top + 1, width: 2, height: 1, look.accent.darker(0.3))
        case .crown:
            let gold = RGB(hex: 0xF2C94C)
            canvas.rect(x: x + 2, y: top, width: 6, height: 1, gold)
            canvas[x + 2, top - 1] = gold
            canvas[x + 5, top - 1] = gold
            canvas[x + 7, top - 1] = gold
            canvas[x + 4, top] = RGB(hex: 0xEB5757)
        case .headphones:
            canvas.rect(x: x + 2, y: top, width: 6, height: 1, metal)
            canvas.rect(x: x, y: top + 2, width: 1, height: 2, look.accent)
            canvas.rect(x: x + 9, y: top + 2, width: 1, height: 2, look.accent)
        case .bare:
            canvas.rect(x: x + 3, y: top, width: 3, height: 1, look.hair)
        case .horns:
            canvas[x + 1, top] = Theme.cream
            canvas[x + 8, top] = Theme.cream
            canvas[x + 1, top - 1] = Theme.cream
            canvas[x + 8, top - 1] = Theme.cream
        }
    }

    // MARK: - Shared parts

    private static func drawArm(on canvas: inout PixelCanvas, x: Int, y top: Int, pose: Pose.Arm, color: RGB, rowForDown: Int, width: Int) {
        switch pose {
        case .down: canvas.rect(x: x, y: top + rowForDown, width: width, height: 2, color)
        case .forward: canvas.rect(x: x, y: top + rowForDown + 1, width: width, height: 2, color.darker(0.1))
        case .up: canvas.rect(x: x, y: top + rowForDown - 3, width: width, height: 3, color)
        }
    }

    private static func drawEyes(on canvas: inout PixelCanvas, positions: [Int], row: Int, eyes: Pose.Eyes, height: Int, color: RGB) {
        for eyeX in positions {
            switch eyes {
            case .open(let dx, let dy):
                canvas.rect(x: eyeX + dx, y: row + max(0, dy), width: 1, height: height, color)
            case .closed:
                canvas.rect(x: eyeX - 1, y: row + height - 1, width: 2, height: 1, color)
            case .happy:
                canvas[eyeX - 1, row + height - 1] = color
                canvas[eyeX, row + height - 2] = color
                canvas[eyeX + 1, row + height - 1] = color
            }
        }
    }

    // MARK: - Props

    private static func drawProps(_ props: [Pose.Prop], on canvas: inout PixelCanvas, around figure: Figure) {
        for prop in props {
            switch prop {
            case .thoughtBubble(let step):
                let bubble = Theme.cream
                if step >= 1 { canvas[figure.right, figure.top - 1] = bubble }
                if step >= 2 { canvas.rect(x: figure.right + 1, y: figure.top - 3, width: 2, height: 1, bubble) }
                if step >= 3 {
                    canvas.rect(x: figure.right + 2, y: figure.top - 7, width: 5, height: 3, bubble)
                    canvas.rect(x: figure.right + 3, y: figure.top - 8, width: 3, height: 1, bubble)
                    canvas.rect(x: figure.right + 3, y: figure.top - 4, width: 3, height: 1, bubble)
                    for dot in 0..<3 { canvas[figure.right + 3 + dot, figure.top - 6] = Theme.faint }
                }

            case .book(let pageFlip):
                let cover = RGB(hex: 0x4A6FA5)
                let page = RGB(hex: 0xF5F5F0)
                let y = figure.top + figure.height / 2
                canvas.rect(x: figure.centerX - 4, y: y, width: 8, height: 3, cover)
                canvas.rect(x: figure.centerX - 3, y: y, width: 3, height: 2, page)
                canvas.rect(x: figure.centerX, y: y, width: 3, height: 2, page)
                if pageFlip { canvas.rect(x: figure.centerX - 1, y: y - 2, width: 2, height: 2, page) }

            case .sparkles(let frame):
                let colors = [RGB(hex: 0xF2C94C), RGB(hex: 0xFFFFFF), Theme.color(for: .edit)]
                for index in 0..<3 {
                    let seed = scramble(frame + index * 31)
                    canvas[figure.right + seed % 4, figure.top + (seed / 4) % 5] = colors[index]
                }

            case .terminal(let cursorOn, let frame):
                let x = figure.right + 1
                let y = figure.top + 1
                canvas.rect(x: x, y: y, width: 9, height: 7, RGB(hex: 0x3B4048))
                canvas.rect(x: x + 1, y: y + 1, width: 7, height: 5, RGB(hex: 0x0D1117))
                canvas[x + 2, y + 2] = Theme.live
                canvas[x + 3, y + 3] = Theme.live
                canvas[x + 2, y + 4] = Theme.live
                let typed = frame % 4
                if typed > 0 { canvas.rect(x: x + 4, y: y + 4, width: typed, height: 1, Theme.text) }
                if cursorOn { canvas[x + 4 + typed, y + 4] = Theme.live }

            case .magnifier(let offset):
                let x = figure.right + 1 + offset
                let y = figure.top + 2
                let ring = RGB(hex: 0xC9D1D9)
                canvas.rect(x: x + 1, y: y, width: 3, height: 1, ring)
                canvas.rect(x: x + 1, y: y + 4, width: 3, height: 1, ring)
                canvas.rect(x: x, y: y + 1, width: 1, height: 3, ring)
                canvas.rect(x: x + 4, y: y + 1, width: 1, height: 3, ring)
                canvas.rect(x: x + 1, y: y + 1, width: 3, height: 3, Theme.color(for: .web).darker(0.3))
                canvas[x + 5, y + 5] = RGB(hex: 0x8B5A2B)
                canvas[x + 6, y + 6] = RGB(hex: 0x8B5A2B)

            case .energy(let frame):
                let color = Theme.color(for: .mcp(server: "", tool: ""))
                let orbit = [(0, -2), (3, -1), (4, 2), (3, 5), (0, 6), (-3, 5), (-4, 2), (-3, -1)]
                for index in 0..<3 {
                    let (ox, oy) = orbit[(frame + index * 3) % orbit.count]
                    canvas[figure.centerX + ox * 2, figure.top + oy] = index == 0 ? color.lighter(0.4) : color
                }

            case .sleepZ(let frame):
                let rise = (frame / 5) % 6
                drawZ(on: &canvas, x: figure.right, y: figure.top - rise, color: Theme.cream)
                if rise > 2 { drawZ(on: &canvas, x: figure.right + 5, y: figure.top - rise - 5, color: Theme.muted) }

            case .stars(let frame):
                let colors = [RGB(hex: 0xF2C94C), RGB(hex: 0xFFFFFF), Theme.claude.lighter(0.3)]
                for index in 0..<5 {
                    let seed = scramble(frame / 2 + index * 17)
                    let x = figure.x - 3 + seed % (figure.width + 6)
                    let y = figure.top - 4 + (seed / 7) % 5
                    canvas[x, y] = colors[index % colors.count]
                }

            case .exclamation:
                canvas.rect(x: figure.right + 1, y: figure.top - 5, width: 1, height: 3, Theme.warning)
                canvas[figure.right + 1, figure.top - 1] = Theme.warning

            case .question(let blink):
                guard blink else { continue }
                let color = Theme.cream
                let x = figure.right, y = figure.top - 6
                canvas.rect(x: x, y: y, width: 3, height: 1, color)
                canvas[x + 2, y + 1] = color
                canvas[x + 1, y + 2] = color
                canvas[x + 1, y + 4] = color

            case .flask, .branch, .parcel, .hammer, .pencil, .globe, .plug, .paperPlane, .checklist, .lightbulb, .coffee, .ball:
                drawFlavorProp(prop, on: &canvas, around: figure)
            }
        }
    }

    private static func drawZ(on canvas: inout PixelCanvas, x: Int, y: Int, color: RGB) {
        canvas.rect(x: x, y: y, width: 4, height: 1, color)
        canvas[x + 2, y + 1] = color
        canvas[x + 1, y + 2] = color
        canvas.rect(x: x, y: y + 3, width: 4, height: 1, color)
    }

    private static func tinted(_ color: RGB, _ tint: RGB?) -> RGB {
        tint.map { color.mixed(with: $0, 0.55) } ?? color
    }

    /// Cheap deterministic pseudo-random (no global RNG state between frames).
    public static func scramble(_ value: Int) -> Int {
        var x = UInt32(truncatingIfNeeded: value &* 2654435761)
        x ^= x >> 15
        x = x &* 2246822519
        x ^= x >> 13
        return Int(x & 0x7FFF_FFFF)
    }
}
