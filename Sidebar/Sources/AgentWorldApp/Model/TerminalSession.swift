import AgentWorldArt
import AgentWorldKit
import AppKit
import Foundation
import SwiftTerm

/// One CLI running in a real terminal inside the app. The terminal view is
/// created once and kept alive while you switch tabs, like a real terminal.
@MainActor
final class TerminalSession: NSObject, ObservableObject, Identifiable, LocalProcessTerminalViewDelegate {
    enum Health: Equatable {
        case running
        case exited(Int32?)
    }

    /// What the session is doing right now, for dots and status lines.
    struct Status: Equatable {
        enum Tone { case busy, needsYou, idle, ended }
        let text: String
        let tone: Tone
    }

    let id = UUID()
    /// Short, stable handle for `agentworld-ctl` ("#3"), in opening order.
    let number: Int
    private static var nextNumber = 1
    let profile: LaunchProfile
    let folder: String
    let startedAt = Date()
    /// Set for Agent-mode chats: which agent this conversation is with.
    let agentName: String?
    /// Pinned Claude session id, so the app follows exactly this conversation.
    let claudeSessionId: String?

    @Published private(set) var title: String = ""
    @Published private(set) var health = Health.running
    @Published private(set) var status = Status(text: "starting", tone: .idle)
    /// What the character acts out: the activity, its flavor, and since when.
    @Published private(set) var activity = Activity(status: .idle, flavor: .plain, since: Date())

    /// Something the agent said to you through `agentworld-ctl say`, shown
    /// on its stage for a while.
    @Published var saying: Saying?

    struct Saying: Equatable {
        let text: String
        let at: Date
    }

    /// Test hook (DebugControl `act`): pretend to be doing something.
    var forcedActivity: (ActorStatus, String?)?

    struct Activity: Equatable {
        let status: ActorStatus
        let flavor: Flavor
        let since: Date
    }

    let terminal: LocalProcessTerminalView
    private let feed: SessionFeed?
    private let codex: CodexSession?

    var provider: Provider { profile.provider }
    var label: String { agentName ?? (profile.isCustom ? profile.name : provider.name) }
    var folderName: String { URL(fileURLWithPath: folder).lastPathComponent }
    /// The live Claude transcript, once there is one.
    var store: SessionStore? { feed?.connection == .following ? feed?.store : nil }

    init(profile: LaunchProfile, executable: String, folder: String, agentName: String? = nil, typing: String? = nil, submitTyping: Bool = false) {
        number = Self.nextNumber
        Self.nextNumber += 1
        self.profile = profile
        self.folder = folder
        self.agentName = agentName

        var arguments = profile.args
        if profile.provider.kind == .claude, !arguments.contains(where: { ["-c", "--continue", "-r", "--resume", "--session-id"].contains($0) }) {
            let id = UUID().uuidString.lowercased()
            claudeSessionId = id
            arguments = ["--session-id", id] + arguments
        } else {
            claudeSessionId = nil
        }
        feed = claudeSessionId.map { SessionFeed(cwd: folder, projectsRoot: ProjectSlug.defaultProjectsRoot, sessionId: $0) }
        codex = profile.provider.kind == .codex ? CodexSession(cwd: folder, startedAfter: Date()) : nil

        terminal = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        super.init()
        Self.style(terminal)
        terminal.processDelegate = self

        // Through the login shell, so the CLI sees your PATH and settings.
        let shell = ShellEnvironment.shell
        let args: [String]
        if profile.provider.kind == .terminal {
            args = ["-l", "-i"]
        } else {
            let command = ([executable] + arguments).map(ShellEnvironment.quote).joined(separator: " ")
            args = ["-l", "-i", "-c", "exec " + command]
        }
        let control = ["AGENTWORLD_PANE": "\(number)", "AGENTWORLD_SOCKET": ControlServer.socketPath]
        terminal.startProcess(executable: shell, args: args, environment: ShellEnvironment.forTerminal(extra: control),
                              execName: "-" + URL(fileURLWithPath: shell).lastPathComponent, currentDirectory: folder)

        if let typing { sendWhenReady(typing, submit: submitTyping) }
    }

    /// Waits for the CLI to boot (something on screen, then a quiet moment)
    /// before typing into it; a prompt typed too early gets lost.
    func sendWhenReady(_ text: String, submit: Bool) {
        var last = ""
        var waited: TimeInterval = 0
        func check() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.health == .running else { return }
                waited += 0.5
                let screen = self.screenText(lines: 60)
                let settled = !screen.isEmpty && screen == last && waited >= 1.5
                last = screen
                if settled || waited >= 20 {
                    if submit { self.send(text, submit: true) } else { self.type(text) }
                } else {
                    check()
                }
            }
        }
        check()
    }

    /// The last `lines` lines of the terminal, as plain text.
    func screenText(lines: Int) -> String {
        let text = String(decoding: terminal.getTerminal().getBufferAsData(), as: UTF8.self)
        var rows = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
        while rows.last?.isEmpty == true { rows.removeLast() }
        return rows.suffix(lines).joined(separator: "\n")
    }

    /// Types into the prompt without pressing enter, and focuses the terminal.
    func type(_ text: String) {
        terminal.send(txt: text)
        terminal.window?.makeFirstResponder(terminal)
    }

    /// Types `text` and, with `submit`, presses enter a beat later: agent
    /// CLIs treat text and a return arriving together as a paste.
    func send(_ text: String, submit: Bool) {
        terminal.send(txt: text)
        guard submit else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.terminal.send(txt: "\r")
        }
    }

    var hasFocus: Bool {
        terminal.window?.firstResponder === terminal
    }

    func focus() {
        terminal.window?.makeFirstResponder(terminal)
    }

    func terminate() {
        if health == .running { terminal.terminate() }
    }

    // MARK: - Status

    func refresh(now: Date) {
        feed?.locate()
        feed?.poll()
        codex?.poll(now: now)
        let next = computeStatus(now: now)
        if next != status { status = next }
        let (actor, action) = currentActivity()
        let flavor = Flavor.from(action: action, status: actor)
        if actor != activity.status || flavor != activity.flavor {
            activity = Activity(status: actor, flavor: flavor, since: now)
        }
    }

    /// The live status and action behind `status`, for the animations.
    private func currentActivity() -> (ActorStatus, String?) {
        if let forcedActivity { return forcedActivity }
        if case .exited(let code) = health { return (code == 0 || code == nil ? .done : .failed, nil) }
        if let store {
            if let running = store.runningSubagents.first, !store.main.status.isBusy {
                return (.delegating, running.state.action)
            }
            return (store.main.status, store.main.action)
        }
        if let codex, codex.isFollowing {
            let state = codex.state
            if state.isWorking { return (.running, state.action) }
            if state.turns > 0 { return (.waitingForUser, nil) }
        }
        return (.idle, nil)
    }

    private func computeStatus(now: Date) -> Status {
        if case .exited(let code) = health {
            return Status(text: code == 0 || code == nil ? "ended" : "exited (\(code!))", tone: .ended)
        }
        if let (actor, action) = forcedActivity {
            let tone: Status.Tone = actor.isBusy ? .busy : actor == .waitingForUser ? .needsYou : .idle
            return Status(text: action ?? actor.title.lowercased(), tone: tone)
        }
        if let store {
            if let running = store.runningSubagents.first {
                return Status(text: "\(running.type): \(running.state.action ?? running.description ?? "working")", tone: .busy)
            }
            let stale = store.lastEventAt.map { now.timeIntervalSince($0) > 600 } ?? true
            if store.main.status.isBusy, !stale {
                return Status(text: store.main.action ?? store.main.status.title, tone: .busy)
            }
            let since = now.timeIntervalSince(store.lastEventAt ?? store.main.since)
            if store.main.status == .waitingForUser, since < 900 {
                return Status(text: "your turn · \(Format.duration(since))", tone: .needsYou)
            }
            return Status(text: "idle \(Format.duration(since))", tone: .idle)
        }
        if let codex, codex.isFollowing {
            let state = codex.state
            if state.isWorking { return Status(text: state.action ?? "thinking", tone: .busy) }
            if state.turns > 0 { return Status(text: "your turn", tone: .needsYou) }
        }
        return Status(text: "ready", tone: .idle)
    }

    // MARK: - LocalProcessTerminalViewDelegate

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor in self.title = title }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            self.health = .exited(exitCode)
            self.status = self.computeStatus(now: Date())
        }
    }

    // MARK: - Look

    private static func style(_ view: LocalProcessTerminalView) {
        view.font = NSFont(name: "SF Mono", size: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        // Plain sRGB colors: SwiftUI-bridged ones don't always resolve in AppKit drawing.
        let background = NSColor(rgb: Palette.terminalBackgroundRGB)
        view.nativeBackgroundColor = background
        view.nativeForegroundColor = NSColor(rgb: Theme.text)
        view.caretColor = NSColor(rgb: Theme.claude)
        view.wantsLayer = true
        view.layer?.backgroundColor = background.cgColor
        view.optionAsMetaKey = false
        // Installing a palette recomputes the defaults (to white): set the
        // background and text colors again right after.
        view.installColors(ansiPalette)
        view.nativeBackgroundColor = background
        view.nativeForegroundColor = NSColor(rgb: Theme.text)
    }

    /// The 16 ANSI colors, tuned for the dark background (the defaults' blue
    /// is unreadable on black): normal then bright.
    private static let ansiHex: [UInt32] = [
        0x1B1F24, 0xFF7B72, 0x7EE787, 0xE3B341, 0x79C0FF, 0xD2A8FF, 0x56D4DD, 0xC9D1D9,
        0x6E7681, 0xFFA198, 0xA5F0B0, 0xF2CC60, 0xA5D6FF, 0xE2C5FF, 0x8DE3EA, 0xF0F6FC,
    ]

    private static var ansiPalette: [SwiftTerm.Color] { ansiHex.map(terminalColor) }

    private static func terminalColor(_ hex: UInt32) -> SwiftTerm.Color {
        let red = UInt16((hex >> 16) & 0xFF) * 257
        let green = UInt16((hex >> 8) & 0xFF) * 257
        let blue = UInt16(hex & 0xFF) * 257
        return SwiftTerm.Color(red: red, green: green, blue: blue)
    }
}
