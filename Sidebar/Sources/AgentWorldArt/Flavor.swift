import AgentWorldKit
import Foundation
import TerminalUI

/// What exactly an agent is up to, read from its action text ("Bash swift
/// test", "Write Tiles.swift", "github · create_issue"), so a character can
/// act it out: a bubbling flask for tests, a branch for git, a parcel for an
/// install, a paper plane when it hands work to a subagent…
public enum Flavor: String, Sendable, CaseIterable {
    case plain
    case tests
    case git
    case install
    case build
    case newFile
    case web
    case mcp
    case delegate
    case todo
    case plan
    case skill

    public static func from(action: String?, status: ActorStatus) -> Flavor {
        let text = (action ?? "").lowercased()
        let words = Set(text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" }).map(String.init))
        func has(_ any: String...) -> Bool { any.contains { words.contains($0) } }

        switch status {
        case .delegating: return .delegate
        case .browsing: return .web
        default: break
        }
        if text.contains(" · ") { return .mcp }
        if text.hasPrefix("skill ") { return .skill }
        if text.hasPrefix("todowrite") || text.hasPrefix("task") && has("create", "update") { return .todo }
        if text.hasPrefix("exitplanmode") || text.hasPrefix("enterplanmode") { return .plan }
        if text.hasPrefix("write ") { return .newFile }
        if text.hasPrefix("websearch") || text.hasPrefix("webfetch") { return .web }
        if status == .running || text.hasPrefix("bash") {
            if has("test", "tests", "pytest", "jest", "vitest", "rspec", "xctest") || text.contains("go test") || text.contains("cargo test") { return .tests }
            if has("git", "gh") { return .git }
            if has("install", "add", "brew", "pip", "pip3", "npm", "pnpm", "yarn", "bun", "uv", "cargo") && has("install", "add", "i", "sync") { return .install }
            if has("build", "make", "compile", "tsc", "xcodebuild", "webpack", "vite") { return .build }
        }
        return .plain
    }

    /// The prop that acts this flavor out, or nil to keep the status's own.
    public func prop(frame: Int) -> Pose.Prop? {
        switch self {
        case .plain: nil
        case .tests: .flask(frame: frame)
        case .git: .branch(frame: frame)
        case .install: .parcel(frame: frame)
        case .build: .hammer(frame: frame)
        case .newFile: .pencil(frame: frame)
        case .web: .globe(frame: frame)
        case .mcp: .plug(frame: frame)
        case .delegate: .paperPlane(frame: frame)
        case .todo: .checklist(frame: frame)
        case .plan: .lightbulb(frame: frame)
        case .skill: nil
        }
    }
}

extension Animator {
    /// `pose(status:…)` with the flavor's prop in place of the generic one.
    /// Doing nothing, it plays with a ball and has a coffee, in turns, until
    /// it falls asleep.
    public static func pose(status: ActorStatus, flavor: Flavor, elapsed: TimeInterval, t: TimeInterval, seed: Int, recentError: Bool) -> Pose {
        var pose = pose(status: status, elapsed: elapsed, t: t, seed: seed, recentError: recentError)
        let frame = Int(t * 10) + seed * 7
        if status.isBusy, let prop = flavor.prop(frame: frame) {
            pose.props = [prop]
            switch flavor {
            case .build:
                pose.rightArm = (frame / 3) % 2 == 0 ? .up : .forward
            case .newFile, .todo:
                pose.rightArm = .forward
                pose.eyes = .open(dx: 1, dy: 1)
            case .delegate:
                pose.rightArm = (frame / 6) % 2 == 0 ? .up : .forward
            default:
                break
            }
        } else if status == .idle, elapsed > 20, elapsed < sleepAfter {
            if Int((elapsed - 20) / 15) % 2 == 0 {
                pose.props = [.ball(frame: frame)]
                let hit = (frame / 2) % 8 == 7
                pose.leftArm = hit ? .up : .down
                pose.rightArm = hit ? .up : .down
                pose.eyes = .open(dx: 0, dy: -1)
                pose.dy = hit ? -1 : 0
            } else {
                pose.props = [.coffee(frame: frame)]
                pose.rightArm = .forward
            }
        }
        return pose
    }
}

extension CharacterPainter {
    /// Props added for flavors; drawn beside the figure like the originals.
    static func drawFlavorProp(_ prop: Pose.Prop, on canvas: inout PixelCanvas, around figure: Figure) {
        let x = figure.right + 1
        let y = figure.top + 1
        switch prop {
        case .flask(let frame):
            // A round-bottom flask with green liquid and rising bubbles.
            let glass = RGB(hex: 0xC9D1D9)
            let liquid = Theme.live
            canvas.rect(x: x + 2, y: y, width: 3, height: 1, glass)
            canvas.rect(x: x + 3, y: y + 1, width: 1, height: 2, glass)
            canvas.rect(x: x + 1, y: y + 3, width: 5, height: 1, glass)
            canvas.rect(x: x, y: y + 4, width: 7, height: 3, glass)
            canvas.rect(x: x + 1, y: y + 5, width: 5, height: 2, liquid)
            canvas.rect(x: x + 1, y: y + 7, width: 5, height: 1, glass)
            for index in 0..<2 {
                let rise = (frame / 2 + index * 3) % 6
                canvas[x + 2 + index * 2, y + 4 - rise] = liquid.lighter(0.5)
            }

        case .branch(let frame):
            // Two commit dots on a trunk and a branch that grows a new commit.
            let trunk = Theme.muted
            let branch = RGB(hex: 0xF0883E)
            canvas.rect(x: x + 1, y: y, width: 1, height: 8, trunk)
            canvas.rect(x: x, y: y + 1, width: 3, height: 1, Theme.cream)
            canvas.rect(x: x, y: y + 6, width: 3, height: 1, Theme.cream)
            let grow = (frame / 3) % 6
            canvas[x + 2, y + 5] = branch
            for step in 0..<min(grow, 3) { canvas[x + 3 + step, y + 4 - step] = branch }
            if grow >= 4 { canvas.rect(x: x + 5, y: y + 1, width: 2, height: 2, frame % 4 < 2 ? branch.lighter(0.4) : branch) }

        case .parcel(let frame):
            // A cardboard box that bounces down and lands.
            let hop = [0, -1, -2, -2, -1, 0, 0, 0][(frame / 2) % 8]
            let box = RGB(hex: 0xC08A52)
            canvas.rect(x: x, y: y + 3 + hop, width: 7, height: 5, box)
            canvas.rect(x: x, y: y + 3 + hop, width: 7, height: 1, box.lighter(0.25))
            canvas.rect(x: x + 3, y: y + 3 + hop, width: 1, height: 5, RGB(hex: 0xE8D5A8))

        case .hammer(let frame):
            // A hammer striking an anvil, with a spark on impact.
            let up = (frame / 3) % 2 == 0
            let handle = RGB(hex: 0x8B5A2B)
            let head = RGB(hex: 0x8B949E)
            canvas.rect(x: x, y: y + 6, width: 7, height: 2, RGB(hex: 0x3B4048))
            if up {
                canvas.rect(x: x + 1, y: y, width: 3, height: 2, head)
                canvas.rect(x: x + 2, y: y + 2, width: 1, height: 3, handle)
            } else {
                canvas.rect(x: x + 2, y: y + 4, width: 3, height: 2, head)
                canvas.rect(x: x, y: y + 4, width: 2, height: 1, handle)
                canvas[x + 5, y + 3] = RGB(hex: 0xF2C94C)
                canvas[x + 6, y + 5] = RGB(hex: 0xFFFFFF)
            }

        case .pencil(let frame):
            // A page filling with lines as a pencil moves along.
            let page = RGB(hex: 0xF5F5F0)
            canvas.rect(x: x, y: y, width: 7, height: 8, page)
            let written = (frame / 2) % 14
            for line in 0..<3 {
                let length = max(0, min(5, written - line * 5))
                if length > 0 { canvas.rect(x: x + 1, y: y + 2 + line * 2, width: length, height: 1, Theme.faint) }
            }
            let line = min(2, written / 5)
            let tip = x + 1 + min(5, written - line * 5)
            canvas[tip, y + 1 + line * 2] = RGB(hex: 0xF2C94C)
            canvas[tip + 1, y + line * 2] = RGB(hex: 0xF2C94C)

        case .globe(let frame):
            // A spinning globe: the land band slides across.
            let ocean = Theme.color(for: .web)
            let land = Theme.live
            canvas.rect(x: x + 1, y: y, width: 5, height: 7, ocean)
            canvas.rect(x: x, y: y + 1, width: 7, height: 5, ocean)
            for row in 1..<6 {
                let shift = (frame / 2 + row) % 7
                canvas[x + shift, y + row] = land
                if row % 2 == 0 { canvas[x + (shift + 1) % 7, y + row] = land }
            }

        case .plug(let frame):
            // A plug reaching a socket, sparks when it connects.
            let color = Theme.color(for: .mcp(server: "", tool: ""))
            let reach = [0, 1, 2, 2, 2, 1][(frame / 2) % 6]
            canvas.rect(x: x + 5, y: y + 2, width: 2, height: 5, RGB(hex: 0x3B4048))
            canvas.rect(x: x + reach, y: y + 3, width: 3, height: 3, color)
            canvas[x + reach + 3, y + 3] = Theme.cream
            canvas[x + reach + 3, y + 5] = Theme.cream
            if reach == 2 {
                canvas[x + 7, y + 1] = RGB(hex: 0xF2C94C)
                canvas[x + 7, y + 7] = RGB(hex: 0xF2C94C)
            }

        case .paperPlane(let frame):
            // A paper plane flying off to the right and up.
            let fly = (frame / 2) % 8
            let px = x + fly, py = y + 4 - fly / 2
            let paper = RGB(hex: 0xF5F5F0)
            canvas.rect(x: px, y: py, width: 4, height: 1, paper)
            canvas.rect(x: px + 1, y: py - 1, width: 2, height: 1, paper)
            canvas[px + 1, py + 1] = paper.darker(0.2)
            if fly > 0 { canvas[px - 2, py + 1] = Theme.faint }

        case .checklist(let frame):
            // Three boxes ticking themselves.
            let ticked = (frame / 4) % 4
            for row in 0..<3 {
                canvas.rect(x: x, y: y + row * 3, width: 2, height: 2, row < ticked ? Theme.live : Theme.muted)
                canvas.rect(x: x + 3, y: y + row * 3, width: 4, height: 1, Theme.faint)
            }

        case .lightbulb(let frame):
            let on = (frame / 5) % 2 == 0
            let bulb = on ? RGB(hex: 0xF2C94C) : RGB(hex: 0x8B7A3A)
            canvas.rect(x: x + 1, y: y - 3, width: 4, height: 4, bulb)
            canvas.rect(x: x + 2, y: y + 1, width: 2, height: 2, RGB(hex: 0x8B949E))
            if on {
                canvas[x - 1, y - 3] = bulb.lighter(0.4)
                canvas[x + 6, y - 3] = bulb.lighter(0.4)
                canvas[x + 3, y - 5] = bulb.lighter(0.4)
            }

        case .coffee(let frame):
            // A mug with a wisp of steam.
            let mug = Theme.cream
            canvas.rect(x: x, y: y + 4, width: 4, height: 4, mug)
            canvas.rect(x: x + 1, y: y + 4, width: 2, height: 1, RGB(hex: 0x6B4F3A))
            canvas[x + 4, y + 5] = mug
            canvas[x + 4, y + 6] = mug
            let wisp = (frame / 4) % 3
            canvas[x + 1 + wisp % 2, y + 2 - wisp] = Theme.faint
            canvas[x + 2 - wisp % 2, y + 1 - wisp] = Theme.faint

        case .ball(let frame):
            // Bounced off the head: up, a hang at the top, back down.
            let heights = [1, 3, 5, 6, 6, 5, 3, 1]
            let rise = heights[(frame / 2) % heights.count]
            let bx = figure.centerX - 1, by = figure.top - 1 - rise
            let ball = RGB(hex: 0xE5534B)
            canvas.rect(x: bx, y: by - 1, width: 3, height: 3, ball)
            canvas[bx + 1, by - 1] = Theme.cream
            canvas[bx, by] = ball.lighter(0.3)

        default:
            break
        }
    }
}
