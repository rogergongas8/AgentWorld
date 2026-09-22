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
    private let scanner: ClaudeConfigScanner
    private let demo: DemoSession?
    private var config: ClaudeConfiguration
    private var viewState = ViewState()

    private var nextTranscriptPoll = Date.distantPast
    private var nextLocate = Date.distantPast
    private var nextConfigScan = Date.distantPast

    init(options: Options) throws {
        self.options = options
        if options.demo {
            let demo = try DemoSession()
            self.demo = demo
            feed = SessionFeed(cwd: demo.projectURL.path, projectsRoot: demo.projectsRoot, sessionId: demo.sessionId)
            scanner = ClaudeConfigScanner(projectURL: demo.projectURL, homeURL: demo.homeURL)
        } else {
            demo = nil
            feed = SessionFeed(
                cwd: options.cwd,
                projectsRoot: options.projectsRoot ?? ProjectSlug.defaultProjectsRoot,
                sessionId: options.sessionId
            )
            scanner = ClaudeConfigScanner(projectURL: URL(fileURLWithPath: options.cwd, isDirectory: true))
        }
        config = scanner.scan()
    }

    private var projectName: String {
        URL(fileURLWithPath: demo?.projectURL.path ?? options.cwd).lastPathComponent
    }

    // MARK: - Modes

    /// Prints a single frame (after replaying the session so far) and returns.
    func renderOnce() {
        feed.locate()
        let size = options.size ?? Terminal.size()
        let canvas = frame(width: size.columns, height: size.rows, now: Date())
        let screen = Screen(colorMode: ColorMode.detect()) { Terminal.write($0) }
        // Plain rows, no cursor addressing, so the output can be piped/diffed.
        for y in 0..<canvas.height {
            Terminal.write(screen.encode(canvas.row(y)) + "\n")
        }
        demo?.cleanUp()
    }

    func run() {
        installSignalHandlers()
        Terminal.enterFullscreen()
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
            screen.present(frame(width: size.columns, height: size.rows, now: now))

            // Keypresses return early from `readKeys`; keep the frame rate steady.
            let spent = Date().timeIntervalSince(frameStart)
            if spent < frameInterval / 2 { usleep(UInt32((frameInterval / 2 - spent) * 1_000_000)) }
        }
    }

    // MARK: - Per-frame work

    private func tick(now: Date) {
        demo?.advance(now: now)
        if now >= nextLocate {
            feed.locate()
            nextLocate = now.addingTimeInterval(1)
        }
        if now >= nextTranscriptPoll {
            feed.poll()
            nextTranscriptPoll = now.addingTimeInterval(0.2)
        }
        if now >= nextConfigScan {
            config = scanner.scan()
            nextConfigScan = now.addingTimeInterval(10)
        }
    }

    private func frame(width: Int, height: Int, now: Date) -> Canvas {
        let snapshot = SidebarSnapshot(
            store: feed.store,
            config: config,
            connection: feed.connection,
            projectName: projectName,
            now: now
        )
        return SidebarView(snapshot: snapshot, viewState: viewState).render(width: width, height: height)
    }

    /// Returns false to quit.
    private func handle(_ keys: [Key], screen: Screen) -> Bool {
        for key in keys {
            switch key {
            case .character("q"), .character("Q"):
                return false
            case .character(let digit) where ("1"..."3").contains(digit):
                select(ViewMode(rawValue: Int(String(digit))! - 1) ?? .world)
            case .tab, .right:
                select(ViewMode(rawValue: (viewState.mode.rawValue + 1) % ViewMode.allCases.count)!)
            case .backTab, .left:
                select(ViewMode(rawValue: (viewState.mode.rawValue + ViewMode.allCases.count - 1) % ViewMode.allCases.count)!)
            case .character("s"):
                viewState.showsStage.toggle()
            case .up, .character("k"):
                viewState.scrollOffset += viewState.mode == .activity ? 1 : -1
                viewState.scrollOffset = max(0, viewState.scrollOffset)
            case .down, .character("j"):
                viewState.scrollOffset += viewState.mode == .activity ? -1 : 1
                viewState.scrollOffset = max(0, viewState.scrollOffset)
            case .character("r"), .character("l"):
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
