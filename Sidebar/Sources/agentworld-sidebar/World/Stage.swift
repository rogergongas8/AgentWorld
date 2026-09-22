import AgentWorldKit
import Foundation
import TerminalUI

/// The animated scene at the top of the sidebar: Claude on the left, one crew
/// member per subagent walking in when spawned and out when finished, a
/// grassy ground and a sky that follows the local time of day.
struct Stage {
    struct Label {
        let x: Int
        let text: String
        let color: RGB
    }

    struct Output {
        let pixels: PixelCanvas
        let labels: [Label]
    }

    static let walkDuration: TimeInterval = 1.2
    static let farewellDuration: TimeInterval = Animator.celebrateFor + walkDuration

    let store: SessionStore
    let now: Date
    let hour: Int

    func render(width: Int, rows: Int) -> Output {
        var pixels = PixelCanvas(width: width, height: rows * 2)
        let ground = pixels.height - 3
        let t = now.timeIntervalSinceReferenceDate

        drawSky(on: &pixels, t: t)
        drawGround(on: &pixels, ground: ground)

        var labels: [Label] = []
        let claudeX = 2
        CharacterPainter.drawClaude(on: &pixels, x: claudeX, ground: ground, pose: claudePose(t: t))
        labels.append(Label(x: claudeX + 5, text: "Claude", color: Theme.claude))

        // Crew slots to the right of Claude.
        let firstSlot = claudeX + CharacterPainter.claudeSize.width + 5
        let spacing = CharacterPainter.crewSize.width + 4
        let slotCount = max(0, (width - firstSlot + 2) / spacing)
        let visible = store.subagents.filter { isOnStage($0) }
        for (index, subagent) in visible.prefix(slotCount).enumerated() {
            let slotX = firstSlot + index * spacing
            let (x, pose) = crewPlacement(subagent, slotX: slotX, width: width, t: t, seed: index + 1)
            let look = CharacterLook(name: subagent.type)
            CharacterPainter.drawCrew(on: &pixels, look: look, x: x, ground: ground, pose: pose)
            if x < width - 2 {
                labels.append(Label(x: max(x - 1, slotX - 1), text: String(subagent.type.prefix(spacing - 1)), color: look.body))
            }
        }
        if visible.count > slotCount, slotCount > 0 {
            labels.append(Label(x: width - 3, text: "+\(visible.count - slotCount)", color: Theme.muted))
        }
        return Output(pixels: pixels, labels: labels)
    }

    // MARK: - Actors

    private func claudePose(t: TimeInterval) -> Pose {
        var status = store.main.status
        var elapsed = now.timeIntervalSince(store.main.since)
        // A session that stopped writing mid-action (crashed, killed) shouldn't
        // animate forever.
        if status.isBusy, let last = store.lastEventAt, now.timeIntervalSince(last) > 600 {
            status = .idle
            elapsed = now.timeIntervalSince(last)
        }
        if status == .thinking, !store.runningSubagents.isEmpty {
            status = .delegating
        }
        return Animator.pose(status: status, elapsed: elapsed, t: t, seed: 0, recentError: recentError)
    }

    private var recentError: Bool {
        store.lastErrorAt.map { now.timeIntervalSince($0) < 1.2 } ?? false
    }

    private func isOnStage(_ subagent: Subagent) -> Bool {
        guard let finished = subagent.finishedAt else { return true }
        return now.timeIntervalSince(finished) < Self.farewellDuration
    }

    private func crewPlacement(_ subagent: Subagent, slotX: Int, width: Int, t: TimeInterval, seed: Int) -> (Int, Pose) {
        let frame = Int(t * 10)
        let sinceStart = now.timeIntervalSince(subagent.startedAt)
        if sinceStart < Self.walkDuration {
            let progress = max(0, sinceStart) / Self.walkDuration
            return (Int(Double(width) + (Double(slotX) - Double(width)) * progress), Animator.walking(frame: frame))
        }

        if let finished = subagent.finishedAt {
            let sinceEnd = now.timeIntervalSince(finished)
            if sinceEnd < Animator.celebrateFor {
                return (slotX, Animator.pose(status: subagent.state.status, elapsed: sinceEnd, t: t, seed: seed, recentError: false))
            }
            let progress = (sinceEnd - Animator.celebrateFor) / Self.walkDuration
            return (slotX + Int(Double(width - slotX + 2) * progress), Animator.walking(frame: frame))
        }

        let pose = Animator.pose(
            status: subagent.state.status,
            elapsed: now.timeIntervalSince(subagent.state.since),
            t: t,
            seed: seed,
            recentError: false
        )
        return (slotX, pose)
    }

    // MARK: - Scenery

    private var isNight: Bool { hour < 7 || hour >= 20 }

    private func drawSky(on pixels: inout PixelCanvas, t: TimeInterval) {
        let skyHeight = pixels.height - 6
        if isNight {
            // Twinkling stars at fixed pseudo-random spots.
            for index in 0..<(pixels.width / 5) {
                let seed = CharacterPainter.scramble(index * 97 + 13)
                let x = seed % max(1, pixels.width)
                let y = (seed / 131) % max(1, skyHeight - 4)
                let twinkle = (Int(t * 2) + index) % 7
                if twinkle != 0 { pixels[x, y] = twinkle < 3 ? Theme.faint : Theme.muted }
            }
            // Crescent moon.
            let moonX = pixels.width - 7
            pixels.rect(x: moonX, y: 1, width: 3, height: 4, RGB(hex: 0xF4F1DE))
            pixels.rect(x: moonX + 1, y: 1, width: 2, height: 3, nil)
            pixels[moonX + 1, 1] = RGB(hex: 0xF4F1DE)
        } else {
            let sun = RGB(hex: 0xF2C94C)
            let sunX = pixels.width - 7
            pixels.rect(x: sunX, y: 2, width: 4, height: 2, sun)
            pixels.rect(x: sunX + 1, y: 1, width: 2, height: 4, sun)
        }

        // Two slow clouds drifting right to left.
        let cloud = isNight ? RGB(hex: 0x3B4048) : RGB(hex: 0xC9D1D9)
        for index in 0..<2 {
            let span = pixels.width + 12
            let x = span - 1 - Int(t / Double(3 + index * 2) + Double(index * span / 2)) % span
            let y = 2 + index * 3
            pixels.rect(x: x, y: y, width: 7, height: 1, cloud)
            pixels.rect(x: x + 2, y: y - 1, width: 3, height: 1, cloud)
        }
    }

    private func drawGround(on pixels: inout PixelCanvas, ground: Int) {
        let grass = RGB(hex: 0x3FA34D)
        let dirt = RGB(hex: 0x6B4F3A)
        for x in 0..<pixels.width {
            let seed = CharacterPainter.scramble(x * 31 + 7)
            pixels[x, ground] = seed % 5 == 0 ? grass.lighter(0.2) : grass
            pixels[x, ground + 1] = seed % 7 == 0 ? dirt.darker(0.3) : dirt
            pixels[x, ground + 2] = seed % 3 == 0 ? dirt.darker(0.15) : dirt.darker(0.3)
            // Occasional tufts and flowers poking above the grass.
            if seed % 11 == 0 { pixels[x, ground - 1] = grass.darker(0.1) }
            if seed % 29 == 0 { pixels[x, ground - 1] = [RGB(hex: 0xF778BA), RGB(hex: 0xF2C94C), RGB(hex: 0xFFFFFF)][seed % 3] }
        }
    }
}
