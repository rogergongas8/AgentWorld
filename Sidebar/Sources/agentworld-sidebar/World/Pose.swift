import AgentWorldKit
import Foundation
import TerminalUI

/// A character's body configuration for one frame, plus the props around it.
struct Pose {
    enum Arm {
        case down, up, forward
    }

    enum Eyes {
        case open(dx: Int, dy: Int)
        case closed
        case happy
    }

    enum Prop {
        case thoughtBubble(step: Int)
        case book(pageFlip: Bool)
        case sparkles(frame: Int)
        case terminal(cursorOn: Bool, frame: Int)
        case magnifier(offset: Int)
        case energy(frame: Int)
        case sleepZ(frame: Int)
        case stars(frame: Int)
        case exclamation
        case question(blink: Bool)
    }

    var dx = 0
    var dy = 0
    var leftArm = Arm.down
    var rightArm = Arm.down
    var eyes = Eyes.open(dx: 0, dy: 0)
    /// Leg animation: nil = standing, otherwise alternates each step.
    var step: Int?
    /// Blended over the whole figure (error flash).
    var tint: RGB?
    var props: [Prop] = []
}

/// Status → pose. Pure function of time so animation never drifts or piles
/// up state; `t` is wall-clock seconds, `elapsed` is time in the status.
enum Animator {
    static let sleepAfter: TimeInterval = 120
    static let celebrateFor: TimeInterval = 2.5

    static func pose(status: ActorStatus, elapsed: TimeInterval, t: TimeInterval, seed: Int, recentError: Bool) -> Pose {
        let frame = Int(t * 10) + seed * 7
        var pose = Pose()
        let blinking = (Int(t * 10) + seed * 13) % 45 < 2

        switch status {
        case .idle, .waitingForUser:
            if status == .waitingForUser, elapsed < celebrateFor {
                pose = celebrate(elapsed: elapsed, frame: frame)
            } else if elapsed > sleepAfter {
                pose.eyes = .closed
                pose.dy = (frame / 12) % 2
                pose.props = [.sleepZ(frame: frame)]
            } else {
                pose.dy = sin(t * 2.2 + Double(seed)) > 0.55 ? -1 : 0
                pose.eyes = blinking ? .closed : .open(dx: 0, dy: 0)
                if status == .waitingForUser {
                    pose.props = [.question(blink: (frame / 6) % 2 == 0)]
                }
            }

        case .thinking:
            pose.eyes = blinking ? .closed : .open(dx: 1, dy: -1)
            pose.rightArm = (frame / 8) % 2 == 0 ? .forward : .down
            pose.props = [.thoughtBubble(step: (frame / 4) % 4)]

        case .reading:
            pose.leftArm = .forward
            pose.rightArm = .forward
            pose.eyes = .open(dx: (frame / 5) % 3 - 1, dy: 1)
            pose.props = [.book(pageFlip: (frame / 3) % 12 == 0)]

        case .editing:
            pose.rightArm = (frame / 2) % 2 == 0 ? .up : .forward
            pose.eyes = .open(dx: 1, dy: 0)
            pose.dy = (frame / 2) % 2 == 0 ? 0 : -1
            pose.props = [.sparkles(frame: frame)]

        case .running:
            pose.leftArm = (frame / 2) % 2 == 0 ? .forward : .down
            pose.rightArm = (frame / 2) % 2 == 0 ? .down : .forward
            pose.eyes = .open(dx: 1, dy: 0)
            pose.props = [.terminal(cursorOn: (frame / 4) % 2 == 0, frame: frame)]

        case .browsing:
            pose.rightArm = .forward
            let offset = Int((sin(t * 3) * 2).rounded())
            pose.eyes = .open(dx: offset > 0 ? 1 : (offset < 0 ? -1 : 0), dy: 0)
            pose.props = [.magnifier(offset: offset)]

        case .usingTool:
            pose.leftArm = .up
            pose.rightArm = .up
            pose.eyes = .open(dx: 0, dy: -1)
            pose.dy = (frame / 3) % 2 == 0 ? 0 : -1
            pose.props = [.energy(frame: frame)]

        case .delegating:
            pose.rightArm = .up
            pose.eyes = .open(dx: 1, dy: 0)
            pose.props = [.exclamation]

        case .done:
            pose = elapsed < celebrateFor ? celebrate(elapsed: elapsed, frame: frame) : Pose(eyes: .happy)

        case .failed:
            pose.eyes = .closed
            pose.leftArm = .up
            pose.rightArm = .up
            pose.tint = Theme.error
        }

        if recentError {
            pose.dx = frame % 2 == 0 ? -1 : 1
            pose.tint = Theme.error
        }
        return pose
    }

    /// A little jump with arms up and stars.
    static func celebrate(elapsed: TimeInterval, frame: Int) -> Pose {
        let hop = elapsed.truncatingRemainder(dividingBy: 0.8) / 0.8
        var pose = Pose()
        pose.dy = -Int((sin(hop * .pi) * 3).rounded())
        pose.leftArm = .up
        pose.rightArm = .up
        pose.eyes = .happy
        pose.props = [.stars(frame: frame)]
        return pose
    }

    static func walking(frame: Int) -> Pose {
        var pose = Pose()
        pose.step = (frame / 2) % 2
        pose.dy = pose.step == 0 ? 0 : -1
        pose.leftArm = pose.step == 0 ? .forward : .down
        pose.rightArm = pose.step == 0 ? .down : .forward
        return pose
    }
}
