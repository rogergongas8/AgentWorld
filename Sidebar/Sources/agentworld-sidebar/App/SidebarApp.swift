import AgentWorldKit
import Darwin
import Foundation
import TerminalUI

/// Set from signal handlers; checked once per frame.
nonisolated(unsafe) private var quitRequested: sig_atomic_t = 0

/// The main loop: one thread, no timers. Each iteration waits for input for
/// at most one frame, then polls whatever is due and renders.
final class SidebarApp {
    private let options: Options
    private let feed: SessionFeed
    private let scanner: ProviderScanner
    private let demo: DemoSession?
    private var config: AgentConfiguration
    private var viewState = ViewState()
    private let explorer = Explorer()
    private var footerHit: FooterHit?

    private var nextTranscriptPoll = Date.distantPast
    private var nextLocate = Date.distantPast
    private var nextConfigScan = Date.distantPast

    init(options: Options) throws {
        self.options = options
        if options.demo {
            let demo = try DemoSession()
            self.demo = demo
            feed = SessionFeed(cwd: demo.projectURL.path, projectsRoot: demo.projectsRoot, sessionId: demo.sessionId)
            scanner = ProviderScanner(projectURL: demo.projectURL, homeURL: demo.homeURL)
        } else {
            demo = nil
            feed = SessionFeed(
                cwd: options.cwd,
                projectsRoot: options.projectsRoot ?? ProjectSlug.defaultProjectsRoot,
                sessionId: options.sessionId
            )
            scanner = ProviderScanner(provider: options.provider, projectURL: URL(fileURLWithPath: options.cwd, isDirectory: true))
        }
        config = scanner.scan()
    }

    /// Only Claude Code's transcripts can be followed live.
    private var followsSessions: Bool { demo != nil || options.provider.followsLiveSessions }

    private var projectName: String {
        URL(fileURLWithPath: demo?.projectURL.path ?? options.cwd).lastPathComponent
    }

    // MARK: - Modes

    /// Prints a single frame (after replaying the session so far) and returns.
    func renderOnce() {
        if followsSessions {
            feed.locate()
            repeat { feed.poll() } while feed.isCatchingUp
        }
        let size = options.size ?? Terminal.size()
        let canvas = frame(width: size.columns, height: size.rows, now: Date()).canvas
        let screen = Screen(colorMode: ColorMode.detect()) { Terminal.write($0) }
        // Plain rows, no cursor addressing, so the output can be piped/diffed.
        for y in 0..<canvas.height {
            Terminal.write(screen.encode(canvas.row(y)) + "\n")
        }
        demo?.cleanUp()
    }

    func run() {
        installSignalHandlers()
        Terminal.enterFullscreen(mouse: true)
        defer {
            Terminal.exitFullscreen()
            demo?.cleanUp()
        }

        let screen = Screen(colorMode: ColorMode.detect())
        let frameInterval = 1 / options.fps

        while quitRequested == 0 {
            let frameStart = Date()
            let keys = Terminal.readKeys(timeout: frameInterval)
            if !handle(keys, screen: screen) { break }

            let now = Date()
            tick(now: now)
            let size = options.size ?? Terminal.size()
            let rendered = frame(width: size.columns, height: size.rows, now: now)
            footerHit = rendered.footer
            screen.present(rendered.canvas)

            // Keypresses return early from `readKeys`; keep the frame rate steady.
            let spent = Date().timeIntervalSince(frameStart)
            if spent < frameInterval / 2 { usleep(UInt32((frameInterval / 2 - spent) * 1_000_000)) }
        }
    }

    // MARK: - Per-frame work

    private func tick(now: Date) {
        demo?.advance(now: now)
        if now >= nextLocate, followsSessions {
            feed.locate()
            nextLocate = now.addingTimeInterval(1)
        }
        if now >= nextTranscriptPoll, followsSessions {
            feed.poll()
            // Replaying a long transcript: keep going every frame until caught up.
            nextTranscriptPoll = feed.isCatchingUp ? now : now.addingTimeInterval(0.2)
        }
        if now >= nextConfigScan {
            config = scanner.scan()
            nextConfigScan = now.addingTimeInterval(10)
        }
    }

    private func frame(width: Int, height: Int, now: Date) -> (canvas: Canvas, footer: FooterHit?) {
        let snapshot = SidebarSnapshot(
            provider: demo == nil ? options.provider : .claude,
            store: feed.store,
            config: config,
            connection: followsSessions ? feed.connection : .configOnly,
            projectName: projectName,
            cwd: demo?.projectURL.path ?? options.cwd,
            now: now
        )
        return SidebarView(snapshot: snapshot, viewState: viewState, explorer: explorer).render(width: width, height: height)
    }

    /// Returns false to quit.
    private func handle(_ keys: [Key], screen: Screen) -> Bool {
        for key in keys {
            // Footer tabs are clickable in every mode.
            if case .mouse(let event) = key, event.action == .press, let footer = footerHit, event.y == footer.row {
                if let tab = footer.tabs.first(where: { $0.range.contains(event.x) }) { select(tab.mode) }
                continue
            }
            // The explorer gets first pick (it needs letters while searching).
            if viewState.mode == .explore, explorer.handle(key) { continue }

            switch key {
            case .character("q"), .character("Q"):
                return false
            case .character(let digit) where ("1"..."3").contains(digit):
                select(ViewMode(rawValue: Int(String(digit))! - 1) ?? .explore)
            case .tab:
                select(ViewMode(rawValue: (viewState.mode.rawValue + 1) % ViewMode.allCases.count)!)
            case .backTab:
                select(ViewMode(rawValue: (viewState.mode.rawValue + ViewMode.allCases.count - 1) % ViewMode.allCases.count)!)
            case .character("s"):
                viewState.showsStage.toggle()
            case .up, .character("k"):
                viewState.scrollOffset += viewState.mode == .activity ? 1 : -1
                viewState.scrollOffset = max(0, viewState.scrollOffset)
            case .mouse(let event) where event.action == .scrollUp:
                viewState.scrollOffset += viewState.mode == .activity ? 1 : -1
                viewState.scrollOffset = max(0, viewState.scrollOffset)
            case .down, .character("j"):
                viewState.scrollOffset += viewState.mode == .activity ? -1 : 1
                viewState.scrollOffset = max(0, viewState.scrollOffset)
            case .mouse(let event) where event.action == .scrollDown:
                viewState.scrollOffset += viewState.mode == .activity ? -1 : 1
                viewState.scrollOffset = max(0, viewState.scrollOffset)
            case .character("r"), .character("R"):
                screen.invalidate()
            default:
                break
            }
        }
        return true
    }

    private func select(_ mode: ViewMode) {
        viewState.mode = mode
        viewState.scrollOffset = 0
    }

    private func installSignalHandlers() {
        for signalNumber in [SIGINT, SIGTERM, SIGHUP] {
            signal(signalNumber) { _ in quitRequested = 1 }
        }
    }
}
