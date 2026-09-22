import AgentWorldArt
import AgentWorldKit
import SwiftUI
import TerminalUI

/// The top of the right column: the focused terminal's character, big, acting
/// out what it's doing right now (thinking, running tests, reading…), with the
/// subagents it sent out working beside it. With nothing to do it plays with a
/// ball, has a coffee, and eventually falls asleep.
struct HeroStage: View {
    @ObservedObject var session: TerminalSession
    /// Short windows: a smaller scene, no room for subagents.
    var compact = false

    private static let maxHelpers = 2
    /// How long a line from `agentworld-ctl say` stays up.
    private static let sayingFor: TimeInterval = 120

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let now = context.date
            let activity = session.activity
            let elapsed = now.timeIntervalSince(activity.since)
            let helpers = compact ? [] : session.store?.runningSubagents ?? []
            VStack(alignment: .leading, spacing: 10) {
                PixelImage(canvas: scene(t: now.timeIntervalSinceReferenceDate, elapsed: elapsed, now: now, helpers: helpers),
                           scale: compact ? 3 : 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, compact ? 4 : 10)
                    .background(
                        LinearGradient(colors: [Palette.background, session.provider.swiftColor.opacity(0.10)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        StatusDot(tone: session.status.tone)
                        Text(headline(elapsed: elapsed))
                            .font(.mono(compact ? 12 : 13.5, .semibold))
                            .foregroundStyle(session.provider.swiftColor)
                        Spacer(minLength: 0)
                        Text(session.label).font(.mono(10)).foregroundStyle(Palette.faint).lineLimit(1)
                    }
                    Text(detail(elapsed: elapsed, helpers: helpers))
                        .font(.mono(10.5))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let saying = session.saying, now.timeIntervalSince(saying.at) < Self.sayingFor {
                    SpeechBubble(text: saying.text, color: session.provider.swiftColor)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.raised))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(session.provider.swiftColor.opacity(0.25)))
        .help("What \(session.label) is doing right now. It acts out each tool: a flask for tests, a branch for git, a book while reading.")
    }

    // MARK: - Scene

    private func scene(t: TimeInterval, elapsed: TimeInterval, now: Date, helpers: [Subagent]) -> PixelCanvas {
        var canvas = PixelCanvas(width: 62, height: 27)
        let ground = canvas.height - 3
        let activity = session.activity
        let pose = Animator.pose(status: activity.status, flavor: activity.flavor, elapsed: elapsed, t: t,
                                 seed: session.label.count, recentError: false)
        switch session.provider.figure {
        case .claude: CharacterPainter.drawClaude(on: &canvas, x: 6, ground: ground, pose: pose)
        case .crew(let look): CharacterPainter.drawCrew(on: &canvas, look: look, x: 8, ground: ground, pose: pose)
        }
        for (index, helper) in helpers.prefix(Self.maxHelpers).enumerated() {
            let status = helper.state.status
            let helperPose = Animator.pose(status: status, flavor: Flavor.from(action: helper.state.action, status: status),
                                           elapsed: now.timeIntervalSince(helper.state.since), t: t,
                                           seed: helper.type.count + index, recentError: false)
            CharacterPainter.drawCrew(on: &canvas, look: CharacterLook(name: helper.type), x: 34 + index * 14, ground: ground, pose: helperPose)
        }
        // Grass over earth.
        canvas.rect(x: 0, y: ground, width: canvas.width, height: 1, RGB(hex: 0x3FA34D))
        canvas.rect(x: 0, y: ground + 1, width: canvas.width, height: 2, RGB(hex: 0x6B4F3A))
        for tuft in stride(from: 3, to: canvas.width, by: 9) { canvas[tuft, ground - 1] = RGB(hex: 0x3FA34D) }
        return canvas
    }

    // MARK: - Words

    /// What it's doing, in two or three words. Idle phases follow the
    /// animation: `Animator.pose(status:flavor:…)` plays, then has a coffee.
    private func headline(elapsed: TimeInterval) -> String {
        let activity = session.activity
        if session.status.tone == .ended { return "Finished" }
        switch activity.status {
        case .idle:
            if elapsed > Animator.sleepAfter { return "Asleep" }
            if elapsed > 20 { return Int((elapsed - 20) / 15) % 2 == 0 ? "Playing" : "Coffee break" }
            return "Ready"
        case .waitingForUser: return "Your turn"
        case .done: return "Done!"
        case .failed: return "Something failed"
        default: break
        }
        switch activity.flavor {
        case .tests: return "Running tests"
        case .git: return "Using git"
        case .install: return "Installing"
        case .build: return "Building"
        case .newFile: return "Writing a file"
        case .web: return "On the web"
        case .mcp: return "Using a connected tool"
        case .delegate: return "Sending out a helper"
        case .todo, .plan: return "Planning"
        case .skill, .plain: return activity.status.title
        }
    }

    private func detail(elapsed: TimeInterval, helpers: [Subagent]) -> String {
        var text: String
        switch session.activity.status {
        case .idle where session.status.tone != .ended:
            text = elapsed < 5 ? "Type in the terminal to give it a task" : "Nothing to do for \(Format.duration(elapsed)) · type to wake it"
        case .thinking:
            text = "Working out what to do next"
        default:
            text = session.status.text
        }
        if !helpers.isEmpty {
            let names = helpers.map(\.type)
            let shown = names.prefix(Self.maxHelpers).joined(separator: ", ")
            let more = names.count > Self.maxHelpers ? " +\(names.count - Self.maxHelpers)" : ""
            text += " · helping: \(shown)\(more)"
        }
        return text
    }
}

/// A line the agent said to you, in its color.
struct SpeechBubble: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "quote.opening").font(.system(size: 9, weight: .bold)).foregroundStyle(color)
            Text(text)
                .font(.mono(11))
                .foregroundStyle(Palette.cream)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(color.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.35)))
    }
}
