import AgentWorldArt
import AgentWorldKit
import SwiftUI
import TerminalUI

/// Beside a lone terminal: a little theater where the CLI's character and
/// your crew act out what's going on. While the CLI works, the scene
/// follows it (thinking, tests, git, a skill being brought over, helpers at
/// work); when it waits for you it waves; when it's idle, short stories
/// take turns — a ball game, a coffee break, a nap under the stars…
struct StoryStage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: TerminalSession

    var body: some View {
        let crew = crewFigures
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let frame = Stories.frame(Stories.Context(session: session, crew: crew, now: context.date))
            VStack(alignment: .leading, spacing: 10) {
                PixelImage(canvas: frame.canvas, scale: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.border))
                VStack(alignment: .leading, spacing: 4) {
                    Text(frame.title.uppercased())
                        .font(.mono(9.5, .semibold))
                        .foregroundStyle(session.provider.swiftColor)
                    Text(frame.line)
                        .font(.mono(11.5))
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                }
                .padding(.horizontal, 4)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(Palette.panel)
    }

    /// The crew that shows up: this CLI's agents (by their looks), or three
    /// regulars when it has none.
    private var crewFigures: [(name: String, figure: CharacterFigure)] {
        let agents = session.provider.isAgent ? model.config(session.provider, in: session.folder).agents.map(\.name) : []
        let names = agents.isEmpty ? ["scout", "tester", "runner"] : Array(agents.prefix(3))
        return names.map { ($0, .crew(CharacterLook(name: $0))) }
    }
}

// MARK: - The stories

/// Pure function of time and state → one frame. Nothing to keep in sync,
/// and the same moment always looks the same.
enum Stories {
    static let width = 76
    static let height = 96
    static let ground = 84

    struct Context {
        let leadName: String
        let lead: CharacterFigure
        let crew: [(name: String, figure: CharacterFigure)]
        let activity: TerminalSession.Activity
        let tone: TerminalSession.Status.Tone
        let action: String?
        /// A skill the CLI reached for in the last few seconds, and when.
        let skill: (name: String, at: Date)?
        /// Helpers (subagents) at work right now.
        let helpers: [(name: String, action: String?, status: ActorStatus)]
        let now: Date

        init(leadName: String, lead: CharacterFigure, crew: [(name: String, figure: CharacterFigure)], activity: TerminalSession.Activity,
             tone: TerminalSession.Status.Tone, action: String?, skill: (name: String, at: Date)?,
             helpers: [(name: String, action: String?, status: ActorStatus)], now: Date) {
            self.leadName = leadName
            self.lead = lead
            self.crew = crew
            self.activity = activity
            self.tone = tone
            self.action = action
            self.skill = skill
            self.helpers = helpers
            self.now = now
        }

        @MainActor
        init(session: TerminalSession, crew: [(name: String, figure: CharacterFigure)], now: Date) {
            leadName = session.provider.isAgent ? session.provider.shortName : "Terminal"
            lead = session.provider.figure
            self.crew = crew
            activity = session.activity
            tone = session.status.tone
            action = session.status.text
            let recent = session.store?.skillUsage.values.max { $0.lastUsed < $1.lastUsed }
            skill = recent.flatMap { now.timeIntervalSince($0.lastUsed) < 9 ? ($0.name, $0.lastUsed) : nil }
            helpers = (session.store?.runningSubagents ?? []).prefix(2).map { ($0.type, $0.state.action, $0.state.status) }
            self.now = now
        }
    }

    struct Frame {
        var canvas: PixelCanvas
        var title: String
        var line: String
    }

    private struct Actor {
        var figure: CharacterFigure
        var x: Double
        var pose: Pose
    }

    private enum Sky { case dusk, night, day }

    static func frame(_ context: Context) -> Frame {
        let t = context.now.timeIntervalSinceReferenceDate
        let elapsed = context.now.timeIntervalSince(context.activity.since)
        var actors: [Actor] = []
        var sky = Sky.dusk
        var extras: [(Int, Int, RGB)] = []
        var scenery: (inout PixelCanvas) -> Void = { _ in }
        var title = ""
        var line = ""
        let leadX = 28.0

        func crew(_ index: Int) -> CharacterFigure {
            context.crew.isEmpty ? .crew(CharacterLook(name: "scout")) : context.crew[index % context.crew.count].figure
        }
        func crewName(_ index: Int) -> String {
            context.crew.isEmpty ? "scout" : context.crew[index % context.crew.count].name
        }

        switch mode(context, elapsed: elapsed) {
        case .skill(let name, let at):
            // A courier brings the skill's book over, hands it in, heads back.
            let p = context.now.timeIntervalSince(at)
            let courier = CharacterFigure.crew(CharacterLook(name: name))
            let arriving = min(1, p / 3)
            let leaving = max(0, (p - 5.5) / 3)
            let x = 80 - (80 - (leadX + 18)) * arriving + (80 - (leadX + 18)) * leaving
            var courierPose = (arriving < 1 || leaving > 0) ? Animator.walking(frame: Int(t * 8)) : Animator.waving(t: t)
            if leaving == 0 { courierPose.props = [.book(pageFlip: false)] }
            var leadPose = Animator.pose(status: context.activity.status, flavor: .skill, elapsed: elapsed, t: t, seed: 1, recentError: false)
            if arriving >= 1, leaving == 0 { leadPose = Pose(leftArm: .up, rightArm: .forward, eyes: .happy, props: [.sparkles(frame: Int(t * 6))]) }
            actors = [Actor(figure: context.lead, x: leadX, pose: leadPose), Actor(figure: courier, x: x, pose: courierPose)]
            title = "A skill arrives"
            line = arriving < 1 ? "\(name) is on its way to \(context.leadName)…" : "\(name) hands \(context.leadName) the \(name) skill."
            scenery = { drawTree(&$0, x: 3) }

        case .helpers:
            // The lead delegates; helpers work beside it, each at its own task.
            actors = [Actor(figure: context.lead, x: 10,
                            pose: Animator.pose(status: .delegating, flavor: .delegate, elapsed: elapsed, t: t, seed: 1, recentError: false))]
            for (index, helper) in context.helpers.enumerated() {
                let pose = Animator.pose(status: helper.status, flavor: Flavor.from(action: helper.action, status: helper.status),
                                         elapsed: elapsed, t: t, seed: index + 3, recentError: false)
                actors.append(Actor(figure: .crew(CharacterLook(name: helper.name)), x: 34 + Double(index) * 20, pose: pose))
            }
            title = "The crew is on it"
            line = context.helpers.map { "\($0.name): \($0.action ?? "working")" }.joined(separator: " · ")

        case .working:
            // The lead acts out the job; the crew keeps it company.
            let flavor = context.activity.flavor
            actors = [Actor(figure: context.lead, x: leadX,
                            pose: Animator.pose(status: context.activity.status, flavor: flavor, elapsed: elapsed, t: t, seed: 1, recentError: false))]
            actors.append(Actor(figure: crew(0), x: 4, pose: Pose(eyes: .open(dx: 1, dy: 0))))
            actors.append(Actor(figure: crew(1), x: 58, pose: sin(t * 2) > 0.6 ? Animator.waving(t: t) : Pose(eyes: .open(dx: -1, dy: 0))))
            title = workTitle(context.activity.status, flavor)
            line = "\(context.leadName): \(context.action ?? "working")"
            if flavor == .tests || flavor == .build { scenery = { drawTable(&$0, x: 46) } }

        case .yourTurn:
            actors = [Actor(figure: context.lead, x: leadX, pose: {
                var pose = Animator.waving(t: t)
                pose.props = [.question(blink: Int(t * 2) % 2 == 0)]
                return pose
            }())]
            actors.append(Actor(figure: crew(0), x: 6, pose: Pose(eyes: .open(dx: 0, dy: 1))))
            actors.append(Actor(figure: crew(1), x: 56, pose: Pose(eyes: .open(dx: 0, dy: 1))))
            title = "Your turn"
            line = "\(context.leadName) is waiting for you. Type in the terminal."

        case .done(let since):
            let p = context.now.timeIntervalSince(since)
            actors = [Actor(figure: context.lead, x: leadX, pose: Animator.celebrate(elapsed: p, frame: Int(t * 8)))]
            actors.append(Actor(figure: crew(0), x: 6, pose: Animator.celebrate(elapsed: p + 0.3, frame: Int(t * 8))))
            actors.append(Actor(figure: crew(1), x: 54, pose: Animator.celebrate(elapsed: p + 0.6, frame: Int(t * 8))))
            title = "Done!"
            line = "\(context.leadName) finished. Everyone's jumping for joy."

        case .ended:
            sky = .night
            var sleeping = Pose(eyes: .closed)
            sleeping.props = [.sleepZ(frame: Int(t * 2))]
            actors = [Actor(figure: context.lead, x: leadX, pose: sleeping)]
            title = "Lights out"
            line = "The session ended. Start it again from the terminal."

        case .idle:
            let story = idleStory(t: t, lead: context.lead)
            let p = t.truncatingRemainder(dividingBy: storyLength)
            switch story {
            case .ball:
                // Two of the crew pass a ball; the lead follows it with its eyes.
                let throwTime = 1.6
                let leg = Int(p / throwTime) % 2
                let q = p.truncatingRemainder(dividingBy: throwTime) / throwTime
                let from = leg == 0 ? 14.0 : 60.0, to = leg == 0 ? 60.0 : 14.0
                let bx = from + (to - from) * q
                let by = Double(ground - 12) - sin(q * .pi) * 14
                extras = ballPixels(x: Int(bx), y: Int(by))
                let catching = q > 0.85 || q < 0.1
                actors = [Actor(figure: crew(0), x: 4, pose: catching && leg == 1 ? Pose(leftArm: .up, rightArm: .up) : Pose(rightArm: .forward)),
                          Actor(figure: context.lead, x: 31, pose: Pose(eyes: .open(dx: leg == 0 ? 1 : -1, dy: -1))),
                          Actor(figure: crew(1), x: 58, pose: catching && leg == 0 ? Pose(leftArm: .up, rightArm: .up) : Pose(leftArm: .forward))]
                title = "Ball game"
                line = "\(crewName(0)) and \(crewName(1)) pass the ball while \(context.leadName) waits for work."
                scenery = { drawTree(&$0, x: 66) }
            case .coffee:
                var sip = Pose(rightArm: .forward)
                sip.props = [.coffee(frame: Int(t * 3))]
                let talking = Int(p / 2) % 2
                actors = [Actor(figure: context.lead, x: 14, pose: talking == 0 ? Pose(leftArm: .forward, eyes: .happy) : sip),
                          Actor(figure: crew(0), x: 48, pose: talking == 1 ? Pose(rightArm: .forward, eyes: .happy) : sip)]
                extras = speechDots(x: talking == 0 ? 20 : 54, y: ground - 22, t: t)
                title = "Coffee break"
                line = "\(context.leadName) and \(crewName(0)) catch up over coffee."
                scenery = { drawTable(&$0, x: 33) }
            case .nap:
                sky = .night
                var sleeping = Pose(eyes: .closed)
                sleeping.props = [.sleepZ(frame: Int(t * 2))]
                let walker = (p / storyLength) * 96 - 16
                actors = [Actor(figure: context.lead, x: leadX, pose: sleeping),
                          Actor(figure: crew(0), x: walker, pose: Animator.walking(frame: Int(t * 4)))]
                title = "Nap time"
                line = "\(context.leadName) naps. \(crewName(0)) tiptoes past."
            case .stars:
                sky = .night
                let look = Pose(eyes: .open(dx: 0, dy: -1))
                actors = [Actor(figure: crew(0), x: 6, pose: look), Actor(figure: context.lead, x: 30, pose: look),
                          Actor(figure: crew(1), x: 56, pose: Int(p) % 7 == 3 ? Pose(leftArm: .up, eyes: .happy) : look)]
                extras = shootingStar(p: p)
                title = "Stargazing"
                line = "Everyone looks up. Make a wish."
            case .reading:
                var read = Pose(eyes: .open(dx: 0, dy: 1))
                read.props = [.book(pageFlip: Int(t) % 3 == 0)]
                actors = [Actor(figure: crew(0), x: 6, pose: read), Actor(figure: context.lead, x: 30, pose: read), Actor(figure: crew(1), x: 54, pose: read)]
                title = "Reading club"
                line = "\(context.leadName) and the crew read up on the project."
                scenery = { drawTree(&$0, x: 68) }
            case .dance:
                actors = [Actor(figure: crew(0), x: 6, pose: Animator.celebrate(elapsed: p, frame: Int(t * 8))),
                          Actor(figure: context.lead, x: 30, pose: Animator.celebrate(elapsed: p + 0.27, frame: Int(t * 8))),
                          Actor(figure: crew(1), x: 54, pose: Animator.celebrate(elapsed: p + 0.53, frame: Int(t * 8)))]
                title = "Dance party"
                line = "Nothing to do, so they dance."
            case .parade:
                let offset = (p / storyLength) * 110 - 30
                actors = [0, 1, 2].map { index in
                    Actor(figure: index == 1 ? context.lead : crew(index), x: offset - Double(index) * 17,
                          pose: Animator.walking(frame: Int(t * 6) + index))
                }
                title = "Morning walk"
                line = "The crew stretches its legs."
                scenery = { drawTree(&$0, x: 36) }
            case .campfire:
                sky = .night
                actors = [Actor(figure: crew(0), x: 4, pose: Pose(eyes: .open(dx: 1, dy: 1))),
                          Actor(figure: context.lead, x: 50, pose: Pose(leftArm: .forward, eyes: .open(dx: -1, dy: 1)))]
                title = "Campfire"
                line = "Stories by the fire while the code rests."
                scenery = { drawFire(&$0, x: 34, t: t) }
            case .idea:
                let gathering = min(1, p / 4)
                var thinker = p < 6 ? Pose(eyes: .open(dx: 1, dy: -1), props: [.thoughtBubble(step: Int(t * 2))])
                    : Pose(leftArm: .up, rightArm: .up, eyes: .happy, props: [.lightbulb(frame: Int(t * 6))])
                thinker.dy = p >= 6 ? -Int((sin(t * 8) + 1)) : 0
                actors = [Actor(figure: context.lead, x: 30, pose: thinker),
                          Actor(figure: crew(0), x: -12 + 26 * gathering, pose: gathering < 1 ? Animator.walking(frame: Int(t * 6)) : Pose(eyes: .happy)),
                          Actor(figure: crew(1), x: 80 - 26 * gathering, pose: gathering < 1 ? Animator.walking(frame: Int(t * 6)) : Pose(eyes: .happy))]
                title = "A bright idea"
                line = p < 6 ? "\(context.leadName) is thinking about something…" : "\(context.leadName) has an idea!"
            case .boo:
                // Kiro's ghost floats over and says boo.
                let approach = min(1, p / 5)
                var ghost = Pose(leftArm: .up, rightArm: .up)
                ghost.dy = -Int((sin(t * 3) + 1) * 1.5)
                let scared = p > 5 && p < 9
                actors = [Actor(figure: context.lead, x: 58 - 30 * approach, pose: ghost),
                          Actor(figure: crew(0), x: 8, pose: scared ? Pose(dy: -3, leftArm: .up, rightArm: .up, props: [.exclamation]) : Pose(eyes: .open(dx: 1, dy: 0)))]
                title = "Boo!"
                line = scared ? "\(crewName(0)) jumps. \(context.leadName) giggles." : "\(context.leadName) floats over, very quietly…"
                sky = .night
            }
        }

        var canvas = PixelCanvas(width: width, height: height)
        drawSky(&canvas, sky, t: t)
        scenery(&canvas)
        drawGround(&canvas)
        for actor in actors.sorted(by: { $0.x < $1.x }) {
            CharacterPainter.draw(actor.figure, on: &canvas, x: Int(actor.x.rounded()), ground: ground, pose: actor.pose)
        }
        for (x, y, color) in extras where x >= 0 && x < width && y >= 0 && y < height { canvas[x, y] = color }
        return Frame(canvas: canvas, title: title, line: line)
    }

    // MARK: Modes

    private enum Mode {
        case skill(String, Date)
        case helpers, working, yourTurn, ended, idle
        case done(Date)
    }

    private static func mode(_ context: Context, elapsed: TimeInterval) -> Mode {
        if context.tone == .ended { return .ended }
        if let skill = context.skill { return .skill(skill.name, skill.at) }
        if !context.helpers.isEmpty { return .helpers }
        if context.activity.status == .done, elapsed < 5 { return .done(context.activity.since) }
        if context.tone == .needsYou || context.activity.status == .waitingForUser { return .yourTurn }
        if context.tone == .busy || context.activity.status.isBusy { return .working }
        return .idle
    }

    private static func workTitle(_ status: ActorStatus, _ flavor: Flavor) -> String {
        switch flavor {
        case .tests: return "Testing"
        case .git: return "Git"
        case .install: return "Installing"
        case .build: return "Building"
        case .newFile: return "Writing a new file"
        case .web: return "On the web"
        case .mcp: return "Using a tool"
        case .delegate: return "Delegating"
        case .todo, .plan: return "Planning"
        case .skill: return "Using a skill"
        case .plain:
            switch status {
            case .thinking: return "Thinking"
            case .reading: return "Reading"
            case .editing: return "Editing"
            case .running: return "Running"
            case .browsing: return "Browsing"
            default: return "Working"
            }
        }
    }

    // MARK: Idle rotation

    private enum IdleStory: CaseIterable { case ball, coffee, nap, stars, reading, dance, parade, campfire, idea, boo }
    static let storyLength: TimeInterval = 18

    /// Takes turns, a new one every `storyLength` seconds; Kiro gets its boo.
    private static func idleStory(t: TimeInterval, lead: CharacterFigure) -> IdleStory {
        var pool = IdleStory.allCases.filter { $0 != .boo }
        if case .ghost = lead { pool.insert(.boo, at: 2) }
        let turn = Int(t / storyLength)
        // A fixed shuffle, so neighbors differ and the order isn't obvious.
        return pool[(turn * 7 + 3) % pool.count]
    }

    // MARK: Scenery

    private static func drawSky(_ canvas: inout PixelCanvas, _ sky: Sky, t: TimeInterval) {
        let (top, bottom): (RGB, RGB) = switch sky {
        case .night: (RGB(hex: 0x070A1A), RGB(hex: 0x172042))
        case .dusk: (RGB(hex: 0x141B38), RGB(hex: 0x3A3060))
        case .day: (RGB(hex: 0x1D3557), RGB(hex: 0x457B9D))
        }
        for y in 0..<ground {
            canvas.rect(x: 0, y: y, width: width, height: 1, top.mixed(with: bottom, Double(y) / Double(ground)))
        }
        // Stars that twinkle, fewer at dusk.
        let stars = sky == .night ? 16 : 6
        for index in 0..<stars {
            let x = (index * 37 + 11) % width, y = (index * 23 + 5) % (ground - 34)
            let twinkle = sin(t * 2 + Double(index)) > 0.2
            canvas[x, y] = twinkle ? RGB(hex: 0xF4F1DE) : RGB(hex: 0x8D8FB0)
        }
        if sky == .night {
            canvas.rect(x: 60, y: 8, width: 7, height: 7, RGB(hex: 0xF4F1DE))
            canvas.rect(x: 59, y: 9, width: 1, height: 5, RGB(hex: 0xF4F1DE))
            canvas.rect(x: 63, y: 7, width: 5, height: 6, top.mixed(with: bottom, 0.1))
        } else {
            // Two clouds drifting by.
            for (index, speed) in [1.4, 0.9].enumerated() {
                let span = Double(width + 24)
                let cx = Int((t * speed + Double(index) * 47).truncatingRemainder(dividingBy: span)) - 12
                let cy = 12 + index * 14
                let cloud = RGB(hex: 0x5B5486)
                canvas.rect(x: cx, y: cy, width: 12, height: 3, cloud)
                canvas.rect(x: cx + 3, y: cy - 2, width: 6, height: 2, cloud)
            }
        }
    }

    private static func drawGround(_ canvas: inout PixelCanvas) {
        canvas.rect(x: 0, y: ground, width: width, height: 1, RGB(hex: 0x3FA34D))
        canvas.rect(x: 0, y: ground + 1, width: width, height: 1, RGB(hex: 0x2F7A3A))
        canvas.rect(x: 0, y: ground + 2, width: width, height: height - ground - 2, RGB(hex: 0x6B4F3A))
        for x in stride(from: 3, to: width, by: 9) { canvas[x, ground + 4] = RGB(hex: 0x57412F) }
    }

    private static func drawTree(_ canvas: inout PixelCanvas, x: Int) {
        canvas.rect(x: x + 3, y: ground - 10, width: 2, height: 10, RGB(hex: 0x6B4F3A))
        canvas.rect(x: x, y: ground - 20, width: 8, height: 10, RGB(hex: 0x2F7A3A))
        canvas.rect(x: x + 1, y: ground - 22, width: 6, height: 2, RGB(hex: 0x3FA34D))
        canvas[x + 2, ground - 17] = RGB(hex: 0xE66767)
        canvas[x + 5, ground - 14] = RGB(hex: 0xE66767)
    }

    private static func drawTable(_ canvas: inout PixelCanvas, x: Int) {
        canvas.rect(x: x, y: ground - 7, width: 11, height: 2, RGB(hex: 0x8B5E3C))
        canvas.rect(x: x + 1, y: ground - 5, width: 1, height: 5, RGB(hex: 0x6B4F3A))
        canvas.rect(x: x + 9, y: ground - 5, width: 1, height: 5, RGB(hex: 0x6B4F3A))
    }

    private static func drawFire(_ canvas: inout PixelCanvas, x: Int, t: TimeInterval) {
        canvas.rect(x: x - 1, y: ground - 1, width: 9, height: 1, RGB(hex: 0x6B4F3A))
        let flicker = Int(t * 8) % 3
        canvas.rect(x: x + 1, y: ground - 5 - flicker, width: 5, height: 4 + flicker, RGB(hex: 0xF77F00))
        canvas.rect(x: x + 2, y: ground - 7 + flicker, width: 3, height: 5 - flicker, RGB(hex: 0xFCBF49))
        canvas[x + 3, ground - 9 - flicker] = RGB(hex: 0xFFF3B0)
        // Sparks drifting up.
        for index in 0..<3 {
            let rise = (t * 6 + Double(index) * 5).truncatingRemainder(dividingBy: 18)
            canvas[x + 1 + index * 2, ground - 10 - Int(rise)] = RGB(hex: 0xFCBF49)
        }
    }

    private static func ballPixels(x: Int, y: Int) -> [(Int, Int, RGB)] {
        let white = RGB(hex: 0xF4F1DE), red = RGB(hex: 0xE66767)
        return [(x, y, red), (x + 1, y, white), (x, y + 1, white), (x + 1, y + 1, red)]
    }

    private static func speechDots(x: Int, y: Int, t: TimeInterval) -> [(Int, Int, RGB)] {
        let shown = Int(t * 3) % 4
        return (0..<shown).map { (x + $0 * 2, y, RGB(hex: 0xF4F1DE)) }
    }

    private static func shootingStar(p: TimeInterval) -> [(Int, Int, RGB)] {
        let q = p.truncatingRemainder(dividingBy: 6) / 1.2
        guard q < 1 else { return [] }
        let x = Int(8 + q * 50), y = Int(4 + q * 14)
        return [(x, y, RGB(hex: 0xFFFFFF)), (x - 1, y - 1, RGB(hex: 0xB9C4FF)), (x - 2, y - 1, RGB(hex: 0x6B75C9)), (x - 3, y - 2, RGB(hex: 0x3A4080))]
    }
}

extension Stories {
    /// Every idle story and working scene for a few CLIs on one sheet
    /// (`render-stories <png>`), to look at them all at once.
    static func contactSheet() -> PixelCanvas {
        let crew: [(name: String, figure: CharacterFigure)] = ["Explore", "Plan", "general-purpose"].map { ($0, .crew(CharacterLook(name: $0))) }
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var frames: [PixelCanvas] = []
        // Idle: one frame from each story in turn (Kiro's lead, so Boo! shows up).
        for turn in 0..<11 {
            let lead: Provider = turn % 2 == 0 ? .kiro : .claude
            let now = base.addingTimeInterval(Double(turn) * storyLength + 7.3)
            frames.append(frame(Context(leadName: lead.shortName, lead: lead.figure, crew: crew,
                                        activity: .init(status: .idle, flavor: .plain, since: base), tone: .idle, action: "idle",
                                        skill: nil, helpers: [], now: now)).canvas)
        }
        // Working, your turn, a skill arriving, helpers, for different CLIs.
        let cases: [(Provider, ActorStatus, Flavor, TerminalSession.Status.Tone, (String, Date)?, [(String, String?, ActorStatus)])] = [
            (.claude, .thinking, .plain, .busy, nil, []),
            (.codex, .running, .tests, .busy, nil, []),
            (.gemini, .running, .git, .busy, nil, []),
            (.kimi, .waitingForUser, .plain, .needsYou, nil, []),
            (.claude, .usingTool, .skill, .busy, ("design", base.addingTimeInterval(-4)), []),
            (.claude, .delegating, .delegate, .busy, nil, [("Explore", "Grep TODO", .reading), ("Plan", "Write plan.md", .editing)]),
        ]
        for (provider, status, flavor, tone, skill, helpers) in cases {
            frames.append(frame(Context(leadName: provider.shortName, lead: provider.figure, crew: crew,
                                        activity: .init(status: status, flavor: flavor, since: base.addingTimeInterval(-3)), tone: tone,
                                        action: "working", skill: skill, helpers: helpers, now: base)).canvas)
        }
        let columns = 6
        let rows = (frames.count + columns - 1) / columns
        var sheet = PixelCanvas(width: columns * (width + 2), height: rows * (height + 2))
        for (index, canvas) in frames.enumerated() {
            let ox = (index % columns) * (width + 2), oy = (index / columns) * (height + 2)
            for y in 0..<height { for x in 0..<width { if let pixel = canvas[x, y] { sheet[ox + x, oy + y] = pixel } } }
        }
        return sheet
    }
}
