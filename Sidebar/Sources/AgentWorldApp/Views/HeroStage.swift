import AgentWorldArt
import AgentWorldKit
import SwiftUI
import TerminalUI

/// The top of the right panel, always the same height: the terminal's CLI,
/// big, acting out what it's doing (tests, git, reading…), with your crew
/// standing beside it full-body. Each crew member potters about on its own
/// (bobs, plays ball, has a coffee) and, when the CLI sends it out as a
/// subagent, acts out that work instead. Click one to see its card.
struct PanelStage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var panel: PanelNavigator
    let session: TerminalSession?
    let agents: [AgentDefinition]

    static let sceneHeight: CGFloat = 112
    private static let maxCrew = 5
    /// How long a line from `agentworld-ctl say` stays up.
    private static let sayingFor: TimeInterval = 120

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 8) {
                scene(now: now)
                    .frame(height: Self.sceneHeight)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(colors: [Palette.background, accent.opacity(0.12)], startPoint: .top, endPoint: .bottom)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topLeading) { bubble(now: now) }
                caption(now: now)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.raised))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.25)))
    }

    private var accent: Color { session?.provider.swiftColor ?? Palette.claude }

    // MARK: - Scene

    @ViewBuilder private func scene(now: Date) -> some View {
        let t = now.timeIntervalSinceReferenceDate
        let helpers = session?.store?.runningSubagents ?? []
        ZStack(alignment: .bottom) {
            // Grass over earth.
            VStack(spacing: 0) {
                Rectangle().fill(Color(rgb: RGB(hex: 0x3FA34D))).frame(height: 3)
                Rectangle().fill(Color(rgb: RGB(hex: 0x6B4F3A))).frame(height: 7)
            }
            HStack(alignment: .bottom, spacing: 2) {
                PixelImage(canvas: mainCanvas(now: now, t: t), scale: 3)
                    .help(session.map { "\($0.label): \($0.status.text)" } ?? "Pick a CLI to start")
                // The panes it opened with agentworld-ctl, beside it.
                ForEach(paneHelpers) { helper in
                    let arriving = now.timeIntervalSince(helper.startedAt)
                    PixelImage(canvas: helperCanvas(helper, now: now, t: t), scale: 2)
                        .offset(x: arriving < Self.walkIn ? CGFloat(1 - arriving / Self.walkIn) * 160 : 0)
                        .overlay(alignment: .bottom) {
                            Text("#\(helper.number)").font(.mono(8.5, .semibold)).foregroundStyle(Palette.cream.opacity(0.8)).offset(y: 9)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { model.reveal(helper) }
                        .help("#\(helper.number) \(helper.label), helping: \(helper.status.text). Click to see its pane.")
                }
                Spacer(minLength: 4)
                ForEach(Array(crew.enumerated()), id: \.element.qualifiedName) { index, agent in
                    let working = helpers.first { $0.type == agent.name || $0.type.hasSuffix(":" + agent.name) }
                    let selected = panel.section == .crew && panel.openDetail == "agent:" + agent.qualifiedName
                    PixelImage(canvas: crewCanvas(agent, index: index, working: working, now: now, t: t, waving: selected), scale: 2)
                        .overlay(alignment: .bottom) {
                            if selected { Rectangle().fill(Palette.cream).frame(width: 12, height: 2).offset(y: 5) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            panel.section = .crew
                            panel.selection = agents.firstIndex { $0.qualifiedName == agent.qualifiedName } ?? 0
                            panel.openDetail = "agent:" + agent.qualifiedName
                        }
                        .help("\(agent.name)\(working.map { " — working: \($0.state.action ?? "on it")" } ?? ""). Click for its card.")
                }
                if agents.count > Self.maxCrew {
                    Text("+\(agents.count - Self.maxCrew)").font(.mono(10)).foregroundStyle(Palette.muted).padding(.bottom, 14)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    /// Working helpers first, then the rest, up to what fits beside the pane helpers.
    private var crew: [AgentDefinition] {
        let working = Set((session?.store?.runningSubagents ?? []).map(\.type))
        let sorted = agents.filter { working.contains($0.name) } + agents.filter { !working.contains($0.name) }
        return Array(sorted.prefix(max(1, Self.maxCrew - paneHelpers.count * 2)))
    }

    /// Up to two panes this one opened, newest last.
    private var paneHelpers: [TerminalSession] {
        guard let session else { return [] }
        return Array(model.helpers(of: session).suffix(2))
    }

    /// How long a new helper takes to walk over.
    private static let walkIn: TimeInterval = 2.4
    /// How long a lead and helper celebrate once the helper is done.
    private static let partyFor: TimeInterval = 5

    private func justFinished(_ helper: TerminalSession, now: Date) -> Bool {
        helper.finishedAt.map { now.timeIntervalSince($0) < Self.partyFor } ?? false
    }

    private func helperCanvas(_ helper: TerminalSession, now: Date, t: TimeInterval) -> PixelCanvas {
        let arriving = now.timeIntervalSince(helper.startedAt)
        let pose: Pose
        if arriving < Self.walkIn {
            pose = Animator.walking(frame: Int(t * 8))
        } else if justFinished(helper, now: now) {
            pose = Animator.celebrate(elapsed: now.timeIntervalSince(helper.finishedAt ?? now), frame: Int(t * 8))
        } else {
            let activity = helper.activity
            pose = Animator.pose(status: activity.status, flavor: activity.flavor, elapsed: now.timeIntervalSince(activity.since),
                                 t: t, seed: helper.number, recentError: false)
        }
        return StageActor.canvas(helper.provider.figure, pose: pose)
    }

    private func mainCanvas(now: Date, t: TimeInterval) -> PixelCanvas {
        let figure = session?.provider.figure ?? Provider.claude.figure
        let pose: Pose
        if let done = paneHelpers.first(where: { justFinished($0, now: now) }) {
            // A helper just delivered: the lead celebrates with it.
            pose = Animator.celebrate(elapsed: now.timeIntervalSince(done.finishedAt ?? now), frame: Int(t * 8))
        } else if let session {
            let activity = session.activity
            pose = Animator.pose(status: activity.status, flavor: activity.flavor, elapsed: now.timeIntervalSince(activity.since),
                                 t: t, seed: session.label.count, recentError: false)
        } else {
            pose = Animator.waving(t: t)
        }
        return StageActor.canvas(figure, pose: pose)
    }

    /// A crew member: acting out its subagent work, else pottering about on a
    /// cycle of its own (offset by name, so they never all do the same thing).
    private func crewCanvas(_ agent: AgentDefinition, index: Int, working: Subagent?, now: Date, t: TimeInterval, waving: Bool) -> PixelCanvas {
        let seed = agent.name.count + index * 7
        let pose: Pose
        if let working {
            let status = working.state.status
            pose = Animator.pose(status: status, flavor: Flavor.from(action: working.state.action, status: status),
                                 elapsed: now.timeIntervalSince(working.state.since), t: t, seed: seed, recentError: false)
        } else if waving {
            pose = Animator.waving(t: t)
        } else {
            let cycle = (t + Double(seed) * 17).truncatingRemainder(dividingBy: 80)
            pose = Animator.pose(status: .idle, flavor: .plain, elapsed: cycle, t: t, seed: seed, recentError: false)
        }
        var canvas = PixelCanvas(width: CharacterPainter.crewSize.width + 5, height: CharacterPainter.crewSize.height + 9)
        CharacterPainter.drawCrew(on: &canvas, look: CharacterLook(name: agent.name), x: 1, ground: canvas.height - 1, pose: pose)
        return canvas
    }

    // MARK: - Words

    @ViewBuilder private func bubble(now: Date) -> some View {
        if let saying = session?.saying, now.timeIntervalSince(saying.at) < Self.sayingFor {
            SpeechBubble(text: saying.text, color: accent)
                .lineLimit(3)
                .padding(8)
        }
    }

    /// Fixed-height lines: the panel below never moves when the words change.
    @ViewBuilder private func caption(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                StatusDot(tone: session?.status.tone ?? .idle)
                Text(headline(now: now))
                    .font(.mono(13.5, .semibold))
                    .foregroundStyle(accent)
                Spacer(minLength: 0)
                Text(session?.label ?? "").font(.mono(10)).foregroundStyle(Palette.faint)
            }
            .lineLimit(1)
            .frame(height: 18)
            Text(detail(now: now))
                .font(.mono(10.5))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: 14, alignment: .leading)
            SessionMeta(store: session?.store, now: now)
                .frame(height: 30)
        }
    }

    private func headline(now: Date) -> String {
        guard let session else { return "Pick a CLI to start" }
        if let done = paneHelpers.last(where: { justFinished($0, now: now) }) { return "#\(done.number) \(done.label) is done!" }
        if let arriving = paneHelpers.last(where: { now.timeIntervalSince($0.startedAt) < Self.walkIn }) {
            return "#\(arriving.number) \(arriving.label) joins"
        }
        let activity = session.activity
        let elapsed = now.timeIntervalSince(activity.since)
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

    private func detail(now: Date) -> String {
        guard let session else { return "Your crew is waiting. Open a CLI and they get to work." }
        let elapsed = now.timeIntervalSince(session.activity.since)
        var text: String
        switch session.activity.status {
        case .idle where session.status.tone != .ended:
            text = elapsed < 5 ? "Type in the terminal to give it a task" : "Nothing to do for \(Format.duration(elapsed)) · type to wake it"
        case .thinking:
            text = "Working out what to do next"
        default:
            text = session.status.text
        }
        let helpers = session.store?.runningSubagents.map(\.type) ?? []
        if !helpers.isEmpty { text += " · with " + helpers.joined(separator: ", ") }
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
        .background(RoundedRectangle(cornerRadius: 7).fill(Palette.panel.opacity(0.95)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.5)))
    }
}

/// Model, branch, time, prompts, and how full the context is: what the
/// terminal sidebar shows in its header. Keeps its height when empty.
struct SessionMeta: View {
    let store: SessionStore?
    let now: Date

    var body: some View {
        if let store {
            let used = store.lastUsage?.context ?? 0
            let window = (store.context.model?.contains("[1m]") ?? false) || used > 200_000 ? 1_000_000 : 200_000
            let fraction = min(1, Double(used) / Double(window))
            let color = fraction > 0.8 ? Palette.error : fraction > 0.6 ? Palette.warning : Palette.live
            VStack(alignment: .leading, spacing: 5) {
                Text(parts(store).joined(separator: " · "))
                    .font(.mono(10))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("ctx").font(.mono(9.5)).foregroundStyle(Palette.faint)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(Color(rgb: Theme.barEmpty))
                            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: geometry.size.width * fraction)
                        }
                    }
                    .frame(height: 6)
                    Text("\(Format.tokens(used))/\(Format.tokens(window))").font(.mono(9.5)).foregroundStyle(Palette.muted)
                }
                .help("How much of the conversation's memory (context window) is used. Near full, the CLI starts forgetting early details.")
            }
        } else {
            Text("Session details show up after the first prompt.")
                .font(.mono(10))
                .foregroundStyle(Palette.faint)
                .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func parts(_ store: SessionStore) -> [String] {
        var parts: [String] = []
        if let model = store.context.model { parts.append(Format.model(model)) }
        if let branch = store.context.gitBranch { parts.append("git:\(branch)") }
        if let started = store.startedAt { parts.append(Format.duration(now.timeIntervalSince(started))) }
        if store.turns > 0 { parts.append("\(store.turns) prompt\(store.turns == 1 ? "" : "s")") }
        return parts
    }
}
