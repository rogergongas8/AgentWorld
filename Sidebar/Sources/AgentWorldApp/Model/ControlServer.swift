import AgentWorldKit
import AppKit
import Foundation

/// Answers `agentworld-ctl` from the app's own terminals: an agent can list
/// the panes, open another CLI beside itself, hand it a task, wait for it,
/// read its answer, and talk to you through its stage. See `help`.
@MainActor
enum ControlServer {
    static let socketPath = ControlSocket.path()

    static func start(model: AppModel) {
        let fd: Int32
        do {
            fd = try ControlSocket.listen(at: socketPath)
        } catch {
            NSLog("AgentWorld: control socket off: \(error)")
            return
        }
        atexit { unlink(ControlSocket.path()) }
        if Preferences.shared.installsSkill { AgentWorldSkill.install() }
        let thread = Thread {
            while true {
                let client = ControlSocket.accept(fd)
                guard client >= 0 else { continue }
                guard let request = ControlSocket.readRequest(client) else {
                    ControlSocket.reply(ControlReply(ok: false, output: "unreadable request"), to: client)
                    continue
                }
                Task { @MainActor [weak model] in
                    let reply = if let model { await handle(request, model: model) } else { ControlReply(ok: false, output: "closing") }
                    DispatchQueue.global().async { ControlSocket.reply(reply, to: client) }
                }
            }
        }
        thread.name = "agentworld-control"
        thread.start()
    }

    static let help = """
    agentworld-ctl — drive AgentWorld from one of its terminals

      panes                          list open panes: #n, CLI, status, folder (* = you)
      clis                           the CLIs installed here, for `open`
      open <cli> [--tab] [--prompt TEXT]
                                     open a CLI (claude, codex, gemini, terminal…)
                                     beside you (or in a new --tab); with --prompt
                                     it gets that task as soon as it's up. Prints #n.
      send <#n> <text…>              type text into pane #n and press return
      wait <#n> [seconds]            block until #n stops working (default 900s)
      read <#n> [lines]              the last lines on #n's screen (default 60)
      focus <#n>                     show #n to the user
      close <#n>                     close pane #n
      say <text…>                    show a line on your character's stage
      notify <text…>                 macOS notification for the user
    """

    // MARK: - Commands

    static func handle(_ request: ControlRequest, model: AppModel) async -> ControlReply {
        let args = request.arguments
        let caller = request.caller.flatMap { number in model.allSessions.first { $0.number == number } }
        func fail(_ text: String) -> ControlReply { ControlReply(ok: false, output: text) }
        func ok(_ text: String) -> ControlReply { ControlReply(ok: true, output: text) }
        func pane(_ reference: String?) -> TerminalSession? {
            guard let reference else { return nil }
            if reference == "me" { return caller }
            return Int(reference.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).flatMap { number in
                model.allSessions.first { $0.number == number }
            }
        }

        switch request.command {
        case "help", "--help":
            return ok(help)

        case "panes":
            let lines = model.allSessions.map { session in
                let mark = session === caller ? "*" : " "
                return "\(mark)#\(session.number)  \(session.label)  [\(session.provider.id)]  \(session.status.text)  — \(session.folderName)"
            }
            return ok(lines.isEmpty ? "no panes" : lines.joined(separator: "\n"))

        case "clis":
            let installed = model.profiles.filter { model.executable(for: $0) != nil }
            return ok(installed.map { "\($0.isCustom ? $0.name : $0.provider.id)  — \($0.isCustom ? $0.provider.name : $0.provider.tagline)" }
                .joined(separator: "\n"))

        case "open":
            guard let name = args.first else { return fail("usage: open <cli> [--tab] [--prompt TEXT]") }
            guard let profile = model.profiles.first(where: { $0.name.lowercased() == name.lowercased() })
                ?? model.profiles.first(where: { !$0.isCustom && ($0.provider.id == name.lowercased() || $0.provider.command == name) })
            else { return fail("no CLI called \(name) — see `agentworld-ctl clis`") }
            guard model.executable(for: profile) != nil else {
                return fail("\(profile.provider.name) isn't installed here" + (profile.provider.installHint.map { " (install: \($0))" } ?? ""))
            }
            let prompt = value(after: "--prompt", in: args)
            let folder = caller?.folder ?? model.selectedFolder
            let wantsTab = args.contains("--tab")
            if !wantsTab, let caller, let tab = model.tabs.first(where: { $0.sessions.contains { $0 === caller } }),
               let session = model.addPane(profile, to: tab, focus: false) {
                if let prompt { session.sendWhenReady(prompt, submit: true) }
                return ok("#\(session.number)")
            }
            guard let session = model.launch(profile, in: folder, typing: prompt, submitTyping: true) else {
                return fail("couldn't open \(profile.provider.name)")
            }
            return ok("#\(session.number)" + (wantsTab || caller == nil ? "" : " (in a new tab: no room beside you)"))

        case "send":
            guard let target = pane(args.first), args.count > 1 else { return fail("usage: send <#n> <text…>") }
            guard target.health == .running else { return fail("#\(target.number) has ended") }
            target.send(args.dropFirst().joined(separator: " "), submit: true)
            return ok("")

        case "wait":
            guard let target = pane(args.first) else { return fail("usage: wait <#n> [seconds]") }
            let timeout = args.dropFirst().first.flatMap(TimeInterval.init) ?? 900
            let finished = await waitUntilQuiet(target, timeout: timeout)
            return finished ? ok("#\(target.number) \(target.label): \(target.status.text)")
                : fail("#\(target.number) still working after \(Int(timeout))s")

        case "read":
            guard let target = pane(args.first) else { return fail("usage: read <#n> [lines]") }
            return ok(target.screenText(lines: args.dropFirst().first.flatMap(Int.init) ?? 60))

        case "focus":
            guard let target = pane(args.first) else { return fail("usage: focus <#n>") }
            model.reveal(target)
            return ok("")

        case "close":
            guard let target = pane(args.first) else { return fail("usage: close <#n>") }
            guard target !== caller else { return fail("won't close the pane you're in") }
            model.close(target)
            return ok("")

        case "say":
            guard let caller else { return fail("say only works from an AgentWorld terminal") }
            caller.saying = .init(text: args.joined(separator: " "), at: Date())
            return ok("")

        case "notify":
            model.notifier?.post(title: caller?.label ?? "AgentWorld", body: args.joined(separator: " "), session: caller)
            return ok("")

        default:
            return fail("unknown command \(request.command) — see `agentworld-ctl help`")
        }
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    /// Done when the pane isn't working and its screen has stopped changing
    /// for a few seconds (CLIs animate a spinner while they work).
    private static func waitUntilQuiet(_ session: TerminalSession, timeout: TimeInterval) async -> Bool {
        let start = Date()
        var last = session.screenText(lines: 80)
        var quietSince = Date()
        while Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if session.health != .running { return true }
            let screen = session.screenText(lines: 80)
            if screen != last {
                last = screen
                quietSince = Date()
            }
            let quiet = Date().timeIntervalSince(quietSince)
            if Date().timeIntervalSince(start) >= 4, session.status.tone != .busy, quiet >= 4 { return true }
        }
        return false
    }
}
