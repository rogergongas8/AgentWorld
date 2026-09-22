import AgentWorldArt
import AgentWorldKit
import Darwin
import Foundation
import TerminalUI

nonisolated(unsafe) private var hubQuitRequested: sig_atomic_t = 0

/// The hub's home window (`agentworld`): two tabs over a workspace tree.
///
/// - **Code**: the tree lists your folders and the terminals open in each,
///   with live status; the main area launches CLIs into a folder (one, or
///   several tiled together) or shows the highlighted terminal.
/// - **Agents**: the tree lists your agents as characters with what they're
///   doing; the main area is the selected agent's page, with a button to
///   start a session with it or hand it to a running Claude.
final class HubApp {
    enum Tab: CaseIterable {
        case agents, code

        var title: String { self == .agents ? "Agents" : "Code" }
    }

    enum Pane {
        case tree, main
    }

    private let options: Options
    private let workspace: Workspace
    private let status = HubStatus()

    private var tab = Tab.code
    private var active = Pane.tree
    private var treeFocus = Focus()
    private var mainFocus = Focus()
    /// What each pane's selection points at, so it stays put when lists change.
    private var treeRoute: Route?
    private var mainRoute: Route?

    private var directory: String
    private var profiles: [LaunchProfile] = []
    private var panes: [Workspace.Pane] = []
    private var recents: [String] = []
    private var kits: [String: (config: AgentConfiguration, at: Date)] = [:]

    /// Profiles ticked in "launch more than one" mode (nil: mode off).
    private var picked: Set<String>?
    private var pathInput: String?
    private var pendingClose: String?
    private var notice: (text: String, color: RGB, until: Date)?

    // Last frame's geometry, for input.
    private var treePage: Page?
    private var mainPage: Page?
    private var bodyTop = 2
    private var bodyRows = 0
    private var treeWidth = 30

    private var nextPoll = Date.distantPast
    private var nextStatusPoll = Date.distantPast
    private var nextReload = Date.distantPast

    init(options: Options) {
        self.options = options
        directory = options.cwd
        // This same executable, so the hub and its sidebars are always the same version.
        workspace = Workspace(sidebarBinary: Bundle.main.executablePath ?? Provider.locate("agentworld-sidebar") ?? "agentworld-sidebar")
    }

    // MARK: - Loop

    func run() {
        for signalNumber in [SIGINT, SIGTERM, SIGHUP] {
            signal(signalNumber) { _ in hubQuitRequested = 1 }
        }
        Terminal.enterFullscreen(mouse: true)
        defer { Terminal.exitFullscreen() }
        workspace.hideOwnTitleBar()
        workspace.publishTab(tab == .agents ? "agents" : "code")

        let screen = Screen(colorMode: ColorMode.detect())
        let frameInterval = 1 / options.fps
        while hubQuitRequested == 0 {
            let frameStart = Date()
            let keys = Terminal.readKeys(timeout: frameInterval)
            if !handle(keys, screen: screen) { break }
            let now = Date()
            tick(now: now)
            let size = options.size ?? Terminal.size()
            screen.present(render(width: size.columns, height: size.rows, now: now))
            let spent = Date().timeIntervalSince(frameStart)
            if spent < frameInterval / 2 { usleep(UInt32((frameInterval / 2 - spent) * 1_000_000)) }
        }
    }

    func renderOnce() {
        tick(now: Date())
        let size = options.size ?? Terminal.size()
        let canvas = render(width: size.columns, height: size.rows, now: Date())
        let screen = Screen(colorMode: ColorMode.detect()) { Terminal.write($0) }
        for y in 0..<canvas.height { Terminal.write(screen.encode(canvas.row(y)) + "\n") }
    }

    private func tick(now: Date) {
        if now >= nextReload {
            profiles = LaunchProfile.load()
            recents = RecentFolders.load()
            nextReload = now.addingTimeInterval(15)
        }
        if now >= nextPoll {
            panes = workspace.panes()
            status.sync(panes)
            if let requested = workspace.requestedDirectory() {
                workspace.clearRequestedDirectory()
                directory = requested
                say("Workspace: \(Self.abbreviated(requested))", Theme.live)
            }
            nextPoll = now.addingTimeInterval(1)
        }
        if now >= nextStatusPoll {
            status.poll(now: now)
            nextStatusPoll = now.addingTimeInterval(0.5)
        }
    }

    /// Each CLI's configuration for a folder, rescanned every 15 s.
    private func kit(_ provider: Provider, in folder: String) -> AgentConfiguration {
        let key = provider.id + "|" + folder
        if let cached = kits[key], Date().timeIntervalSince(cached.at) < 15 { return cached.config }
        let config = ProviderScanner(provider: provider, projectURL: URL(fileURLWithPath: folder, isDirectory: true)).scan()
        kits[key] = (config, Date())
        return config
    }

    // MARK: - Layout

    private func render(width: Int, height: Int, now: Date) -> Canvas {
        var canvas = Canvas(width: width, height: height)
        header(now: now).draw(into: &canvas, x: 0, y: 0, width: width)
        canvas.horizontalLine(y: 1, character: "─", style: .fg(Theme.rule))

        treeWidth = min(38, max(24, width / 4))
        bodyTop = 2
        bodyRows = max(1, height - 3)
        let mainX = treeWidth + 2
        let mainWidth = max(10, width - mainX - 1)

        // Tree.
        func buildTree() -> Page { treeContent(width: treeWidth - 1, now: now) }
        var tree = buildTree()
        if restore(&treeFocus, route: treeRoute, on: tree) { tree = buildTree() }
        if treeFocus.settle(on: tree, rows: bodyRows) { tree = buildTree() }
        treePage = tree
        treeRoute = route(of: treeFocus, on: tree)
        canvas.blit(tree.canvas, x: 0, y: bodyTop, sourceY: treeFocus.scroll, rows: bodyRows)

        // Divider: bright on the side that has the keyboard.
        for row in bodyTop..<(bodyTop + bodyRows) {
            canvas[treeWidth, row] = Cell("│", .fg(active == .tree ? Theme.claude.darker(0.2) : Theme.rule))
        }

        // Main.
        func buildMain() -> Page { mainContent(width: mainWidth, now: now) }
        var main = buildMain()
        if restore(&mainFocus, route: mainRoute, on: main) { main = buildMain() }
        if mainFocus.settle(on: main, rows: bodyRows) { main = buildMain() }
        mainPage = main
        mainRoute = route(of: mainFocus, on: main)
        canvas.blit(main.canvas, x: mainX, y: bodyTop, sourceY: mainFocus.scroll, rows: bodyRows)
        drawScrollbar(into: &canvas, x: width - 1, top: bodyTop, rows: bodyRows, contentHeight: main.canvas.height, scroll: mainFocus.scroll)

        footer(now: now).draw(into: &canvas, x: 0, y: height - 1, width: width - 1)
        return canvas
    }

    /// The mode and what it's for; the Agent / Code switch itself is in the
    /// tmux bar right above.
    private func header(now: Date) -> StyledLine {
        let line = tab == .code
            ? StyledLine(" CODE ", Style(fg: Theme.cream, bg: Theme.rule, bold: true))
                .appending("  coding CLIs, each with its map of skills and tools", .fg(Theme.muted))
            : StyledLine(" AGENT ", Style(fg: Theme.cream, bg: Theme.rule, bold: true))
                .appending("  chat with one of your agents", .fg(Theme.muted))
        let lines = panes.map { status.line(for: $0, now: now) }
        let busy = lines.filter(\.isBusy).count
        let needsYou = lines.filter(\.needsYou).count
        var parts: [String] = []
        if busy > 0 { parts.append("● \(busy) working") }
        if needsYou > 0 { parts.append("◐ \(needsYou) need\(needsYou == 1 ? "s" : "") you") }
        if parts.isEmpty { parts.append(panes.isEmpty ? "no terminals yet" : "\(panes.count) open") }
        return line.trailing(parts.joined(separator: "  ") + " ", .fg(needsYou > 0 ? Theme.warning : busy > 0 ? Theme.live : Theme.faint, bold: true))
    }

    private func footer(now: Date) -> StyledLine {
        if let input = pathInput {
            let cursor = Int(now.timeIntervalSinceReferenceDate * 2) % 2 == 0 ? "▌" : " "
            return StyledLine(" workspace folder: ", .fg(Theme.muted)).appending(input, .fg(Theme.cream, bold: true)).appending(cursor, .fg(Theme.claude))
                .trailing("⏎ ok · tab complete · esc cancel ", .fg(Theme.faint))
        }
        if let notice, notice.until > now {
            return StyledLine(" " + notice.text, .fg(notice.color, bold: true))
        }
        let other = tab == .code ? "a agent mode" : "c code mode"
        return StyledLine(" ↑↓←→ move · ⏎ open · tab other side · \(other) · d folder · x close · 1-9 jump · q leave (all keeps running)", .fg(Theme.faint))
    }

    // MARK: - Tree

    private func treeContent(width: Int, now: Date) -> Page {
        var b = PageBuilder(width: width, selection: treeFocus.selection)
        switch tab {
        case .code: workspaceTree(&b, now: now)
        case .agents: agentList(&b, now: now)
        }
        b.gap()
        return b.build()
    }

    /// Folders with their open terminals nested under them.
    private func workspaceTree(_ b: inout PageBuilder, now: Date) {
        b.gap()
        b.line(StyledLine(" WORKSPACES", .fg(Theme.muted, bold: true)).trailing("d +", .fg(Theme.faint)))
        b.gap()
        var folders: [String] = []
        for folder in panes.compactMap(\.cwd) + [directory, options.cwd] + recents where !folders.contains(folder) {
            folders.append(folder)
        }
        for folder in folders {
            let open = panes.filter { $0.cwd == folder }
            let current = folder == directory
            let name = URL(fileURLWithPath: folder).lastPathComponent
            var line = StyledLine(current ? "▣ " : "▢ ", .fg(current ? Theme.claude : Theme.faint, bold: true))
                .appending(name, .fg(current ? Theme.cream : Theme.text, bold: current))
            if !open.isEmpty { line = line.trailing("\(open.count)", .fg(Theme.muted)) }
            b.item([line], route: .folder(folder), accent: Theme.claude)
            for pane in open {
                let state = status.line(for: pane, now: now)
                let provider = pane.provider ?? .terminal
                let pulse = state.isBusy && Int(now.timeIntervalSinceReferenceDate * 2) % 2 == 0
                let dot = StyledLine("  \(state.needsYou ? "◐" : "●") ", .fg(pulse ? state.color.lighter(0.4) : state.color, bold: true))
                    .appending(pane.label, .fg(pane.isFocused ? Theme.cream : provider.color, bold: true))
                    .trailing("\(pane.windowIndex)", .fg(Theme.faint))
                let detail = StyledLine("    " + state.text, .fg(state.color))
                b.item([dot, detail], route: .window(pane.id), accent: provider.color)
            }
        }
        b.gap()
        b.item([StyledLine("+ ", .fg(Theme.muted, bold: true)).appending("open a folder…", .fg(Theme.muted))], route: .typeFolder, accent: Theme.muted)
    }

    /// Every agent across the CLIs, as faces with what they're up to.
    private func agentList(_ b: inout PageBuilder, now: Date) {
        b.gap()
        b.line(StyledLine(" AGENTS", .fg(Theme.muted, bold: true)).trailing(URL(fileURLWithPath: directory).lastPathComponent, .fg(Theme.faint)))
        b.gap()
        let t = now.timeIntervalSinceReferenceDate
        let everyone = agents()
        for (index, (provider, agent)) in everyone.enumerated() {
            let look = CharacterLook(name: agent.name)
            let activity = status.activity(ofAgent: agent.name, panes: panes, now: now)
            let selected = b.nextIsSelected
            let pose = activity?.isBusy == true
                ? Animator.pose(status: .running, elapsed: 1, t: t, seed: index, recentError: false)
                : selected ? Animator.waving(t: t) : Animator.pose(status: .idle, elapsed: 0, t: t, seed: index + 1, recentError: false)
            let face = Face.render(.crew(look), pose: pose, background: selected ? PageBuilder.selectionBackground : nil)
            let summary = activity?.text ?? agent.description.map(SkillCategory.summarize) ?? "ready"
            let lines = [
                StyledLine(agent.name, .fg(selected ? Theme.cream : look.readableColor, bold: true))
                    .trailing(activity?.isBusy == true ? "●" : "", .fg(Theme.live, bold: true)),
                StyledLine(summary, .fg(activity?.color ?? Theme.muted)),
                StyledLine(provider.shortName + (agent.model.map { " · \($0)" } ?? "") + (agent.scope == .builtin ? " · built-in" : ""), .fg(Theme.faint)),
            ]
            b.row(route: .agent(provider.id + "|" + agent.qualifiedName), accent: look.readableColor, pixels: face, lines: lines)
        }
        if everyone.allSatisfy({ $0.1.scope == .builtin }) {
            b.gap()
            b.paragraph("Make your own in .claude/agents/<name>.md, or run /agents in Claude.", style: .fg(Theme.faint, italic: true))
        }
    }

    /// Agents from every CLI's config for the current folder, custom first.
    private func agents() -> [(Provider, AgentDefinition)] {
        let all = Provider.all.filter(\.isAgent).flatMap { provider in kit(provider, in: directory).agents.map { (provider, $0) } }
        return all.filter { $0.1.scope != .builtin } + all.filter { $0.1.scope == .builtin }
    }

    // MARK: - Main area

    private func mainContent(width: Int, now: Date) -> Page {
        var b = PageBuilder(width: width, selection: active == .main ? mainFocus.selection : -1)
        switch tab {
        case .code:
            if case .window(let id) = treeRoute, let pane = panes.first(where: { $0.id == id }) {
                terminalPage(&b, pane, now: now)
            } else {
                launcher(&b, now: now)
            }
        case .agents:
            if case .agent(let key) = treeRoute, let (provider, agent) = agent(for: key) {
                agentPage(&b, provider: provider, agent: agent, now: now)
            } else {
                b.gap(2)
                b.paragraph("Pick an agent on the left.", style: .fg(Theme.faint, italic: true))
            }
        }
        b.gap()
        return b.build()
    }

    // MARK: Launcher

    private func launcher(_ b: inout PageBuilder, now: Date) {
        let folderName = URL(fileURLWithPath: directory).lastPathComponent
        b.gap()
        b.line(StyledLine(" ▣ ", .fg(Theme.claude, bold: true)).appending(folderName, .fg(Theme.cream, bold: true))
            .appending("  " + Self.abbreviated(directory), .fg(Theme.faint)))
        b.gap(2)
        b.centered(StyledLine("Start coding in ", .fg(Theme.cream, bold: true)).appending(folderName, .fg(Theme.claude, bold: true)))
        b.centered(StyledLine(picked == nil
            ? "Pick an agent: it opens in a real terminal here."
            : "Tick the agents to open side by side (space), then launch them together.", .fg(Theme.muted)))
        b.gap()

        // Every CLI is on show: the ones you don't have yet doze, and opening
        // one tells you how to install it.
        let installed = profiles.filter { InstalledCLIs.path(forCommand: $0.executable) != nil }
        let missing = profiles.filter { InstalledCLIs.path(forCommand: $0.executable) == nil }
        let shown = installed + missing
        let t = now.timeIntervalSinceReferenceDate
        b.buttons(shown.enumerated().map { index, profile in
            let ready = InstalledCLIs.path(forCommand: profile.executable) != nil
            let config = ready && profile.provider.isAgent ? kit(profile.provider, in: directory) : nil
            var subtitle = ready ? (config?.model.map(Format.model) ?? profile.provider.tagline) : "not installed"
            if profile.isCustom { subtitle = ([profile.executable] + profile.args).joined(separator: " ") }
            let ticked = picked?.contains(profile.id)
            return ButtonSpec(
                figure: profile.provider.figure,
                title: profile.isCustom ? profile.name : profile.provider.name,
                subtitle: subtitle,
                hint: ticked.map { $0 ? "[✓] picked" : "[ ] space" } ?? (ready ? "⏎ open" : "⏎ how to install"),
                accent: profile.provider.color,
                dimmed: !ready,
                pose: { selected in
                    !ready ? Animator.pose(status: .idle, elapsed: Animator.sleepAfter + 1, t: t, seed: index, recentError: false)
                        : selected ? Animator.waving(t: t) : Animator.pose(status: .idle, elapsed: 0, t: t, seed: index + 2, recentError: false)
                },
                route: .launch(profile.id)
            )
        })

        b.gap()
        if let picked {
            b.item([StyledLine("▶ ", .fg(Theme.live, bold: true)).appending(picked.isEmpty ? "Pick some agents above (space)" : "Launch \(picked.count) together, side by side", .fg(Theme.cream, bold: true))],
                   route: .hubAction("go"), accent: Theme.live)
            b.item([StyledLine("  cancel", .fg(Theme.faint))], route: .hubAction("multi"), accent: Theme.muted)
        } else {
            b.item([StyledLine("⊞ ", .fg(Theme.claude, bold: true)).appending("Launch more than one…", .fg(Theme.claude))],
                   route: .hubAction("multi"), accent: Theme.claude)
        }

        // What the highlighted button would do.
        if case .launch(let id) = mainRoute, let profile = profiles.first(where: { $0.id == id }) {
            details(&b, profile)
        }
    }

    private func details(_ b: inout PageBuilder, _ profile: LaunchProfile) {
        let provider = profile.provider
        b.header(profile.name.uppercased(), badge: provider.tagline, color: provider.color)
        b.line(StyledLine(" $ ", .fg(Theme.faint)).appending(([profile.executable] + profile.args).joined(separator: " "), .fg(Theme.cream, bold: true)))
        guard InstalledCLIs.path(forCommand: profile.executable) != nil else {
            b.line(StyledLine(" ✗ ", .fg(Theme.warning, bold: true)).appending("`\(profile.executable)` isn't on your PATH", .fg(Theme.warning)))
            b.line(StyledLine("   install: ", .fg(Theme.faint)).appending(provider.installHint ?? "see its docs; it must provide `\(profile.executable)`", .fg(Theme.text)))
            return
        }
        guard provider.isAgent else {
            b.line(StyledLine(" A plain shell in this folder, as a tab of its own.", .fg(Theme.muted)))
            return
        }
        let config = kit(provider, in: directory)
        var parts = ["\(config.skills.count) skills", "\(config.mcpServers.count) MCP"]
        if !config.plugins.isEmpty { parts.append("\(config.plugins.count) plugins") }
        if !config.customAgents.isEmpty { parts.append("\(config.customAgents.count) agents") }
        var line = StyledLine(" ✓ ", .fg(Theme.live, bold: true)).appending(parts.joined(separator: " · "), .fg(Theme.text))
        if let file = config.repository.instructionsFile {
            line.append(config.repository.hasInstructions ? " · reads \(file)" : " · no \(file) here yet",
                        .fg(config.repository.hasInstructions ? Theme.muted : Theme.warning))
        }
        b.line(line)
    }

    // MARK: Terminal page

    private func terminalPage(_ b: inout PageBuilder, _ pane: Workspace.Pane, now: Date) {
        let provider = pane.provider ?? .terminal
        let state = status.line(for: pane, now: now)
        let t = now.timeIntervalSinceReferenceDate
        let pose = state.isBusy ? Animator.pose(status: .running, elapsed: 1, t: t, seed: 1, recentError: false) : Animator.waving(t: t)
        b.hero(pixels: CharacterCard.portrait(provider.figure, pose: pose), lines: [
            StyledLine(pane.label, .fg(provider.color, bold: true)),
            StyledLine("in " + pane.folderName, .fg(Theme.muted)),
            StyledLine((state.needsYou ? "◐ " : "● ") + state.text, .fg(state.color, bold: true)),
            // tmux's default title is the host name: only show real ones.
            StyledLine(pane.title == ProcessInfo.processInfo.hostName || pane.title.hasSuffix(".local") ? "" : pane.title, .fg(Theme.faint)),
        ])

        b.header("ACTIONS", color: provider.color)
        b.item([StyledLine("▶ ", .fg(Theme.live, bold: true)).appending("Go to this terminal", .fg(Theme.cream, bold: true))
            .trailing("or press \(pane.windowIndex)", .fg(Theme.faint))], route: .hubAction("goto:" + pane.id), accent: Theme.live)
        b.item([StyledLine("+ ", .fg(Theme.claude, bold: true)).appending("Open another agent in \(pane.folderName)", .fg(Theme.text))],
               route: .hubAction("addhere:" + (pane.cwd ?? directory)), accent: Theme.claude)
        b.item([StyledLine("✕ ", .fg(Theme.error, bold: true)).appending(pendingClose == pane.id ? "Press ⏎ again to close it" : "Close it", .fg(pendingClose == pane.id ? Theme.warning : Theme.muted))],
               route: .hubAction("close:" + pane.id), accent: Theme.error)

        guard let store = status.store(for: pane) else { return }
        let tasks = TasksSection(todos: store.todos).lines(width: b.width, maxRows: 10)
        if !tasks.isEmpty {
            b.gap()
            for line in tasks { b.line(line) }
        }
        let working = store.runningSubagents
        if !working.isEmpty {
            b.header("AGENTS AT WORK", badge: "\(working.count)", color: Theme.color(for: .agent))
            for run in working {
                let look = CharacterLook(name: run.type)
                b.row(route: .hubAction("goto:" + pane.id), accent: look.readableColor,
                      pixels: Face.render(.crew(look), pose: Animator.pose(status: run.state.status, elapsed: 1, t: t, seed: 5, recentError: false)),
                      lines: [StyledLine(run.type, .fg(look.readableColor, bold: true)),
                              StyledLine(run.state.action ?? run.description ?? "", .fg(Theme.text)),
                              StyledLine("\(Format.duration(now.timeIntervalSince(run.startedAt))) · \(run.toolCalls) tools", .fg(Theme.faint))])
            }
        }
        b.gap()
        b.line(StyledLine(" \(store.turns) prompts · \(store.totalToolCalls) tool calls · \(store.subagents.count) agent runs", .fg(Theme.faint)))
    }

    // MARK: Agent page

    private func agent(for key: String) -> (Provider, AgentDefinition)? {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let provider = Provider.named(parts[0]) else { return nil }
        return kit(provider, in: directory).agents.first { $0.qualifiedName == parts[1] }.map { (provider, $0) }
    }

    private func agentPage(_ b: inout PageBuilder, provider: Provider, agent: AgentDefinition, now: Date) {
        let look = CharacterLook(name: agent.name)
        let activity = status.activity(ofAgent: agent.name, panes: panes, now: now)
        let t = now.timeIntervalSinceReferenceDate
        let pose = activity?.isBusy == true ? Animator.pose(status: .running, elapsed: 1, t: t, seed: 1, recentError: false) : Animator.waving(t: t)
        b.hero(pixels: CharacterCard.portrait(.crew(look), pose: pose), lines: [
            StyledLine(agent.name, .fg(look.readableColor, bold: true)),
            StyledLine("Powered by \(provider.name)", .fg(Theme.muted)),
            StyledLine("model " + (agent.model ?? "same as \(provider.shortName)"), .fg(Theme.text)),
            StyledLine(activity?.text ?? "ready", .fg(activity?.color ?? Theme.faint, bold: activity?.isBusy == true)),
        ])

        b.header("PUT IT TO WORK", color: look.readableColor)
        b.item([StyledLine("▶ ", .fg(Theme.live, bold: true)).appending("Start a session with \(agent.name)", .fg(Theme.cream, bold: true))
            .trailing("chat in a new tab", .fg(Theme.faint))], route: .hubAction("start"), accent: Theme.live)
        for pane in panes where pane.provider == provider {
            b.item([StyledLine("↳ ", .fg(provider.color, bold: true)).appending("Hand it to \(pane.label) in \(pane.folderName)", .fg(Theme.text))
                .trailing(status.line(for: pane, now: now).text, .fg(Theme.faint))], route: .hubAction("ask:" + pane.id), accent: provider.color)
        }

        b.header("WHAT IT DOES", color: look.readableColor)
        b.paragraph(agent.description ?? "No description in its front matter.")

        let config = kit(provider, in: directory)
        let carried = agent.skills.compactMap { name in config.skills.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
        b.header("SKILLS", badge: carried.isEmpty ? nil : "\(carried.count)", color: Theme.color(for: .skill))
        if carried.isEmpty {
            b.paragraph("None preloaded; it can load any of the \(config.skills.count) skills \(provider.shortName) has here.", style: .fg(Theme.muted))
        } else {
            b.shelf(carried.map { BookSpec(skill: $0, used: false) }, t: t)
        }
        b.header("TOOLS", color: Theme.muted)
        if agent.tools.isEmpty {
            b.paragraph("Every tool \(provider.shortName) has, MCP servers included.", style: .fg(Theme.muted))
        } else {
            b.chips(agent.tools, color: Theme.text)
        }
    }

    // MARK: - Input

    private func handle(_ keys: [Key], screen: Screen) -> Bool {
        for key in keys {
            if pathInput != nil {
                handlePathInput(key)
                continue
            }
            if case .mouse(let event) = key {
                handle(event)
                continue
            }
            let keepsPendingClose: Bool
            switch key {
            case .character("x"), .enter: keepsPendingClose = true
            default: keepsPendingClose = false
            }
            if !keepsPendingClose { pendingClose = nil }

            switch key {
            case .character("q"), .character("Q"):
                if Workspace.isInsideTmux { workspace.detach() } else { return false }
            case .character("a"), .character("A"): switchTab(.agents)
            case .character("c"), .character("C"): switchTab(.code)
            case .tab, .backTab: active = active == .tree ? .main : .tree
            case .up, .character("k"): withFocus { $0.move(vertical: -1, in: $1, rows: bodyRows) }
            case .down, .character("j"): withFocus { $0.move(vertical: 1, in: $1, rows: bodyRows) }
            case .left, .character("h"):
                if active == .main {
                    var moved = false
                    withFocus { moved = $0.move(horizontal: -1, in: $1) }
                    if !moved { active = .tree }
                }
            case .right, .character("l"):
                if active == .tree {
                    active = .main
                } else {
                    withFocus { _ = $0.move(horizontal: 1, in: $1) }
                }
            case .enter: activate()
            case .character(" "):
                if picked != nil, active == .main, case .launch(let id) = mainRoute { toggle(id) } else { activate() }
            case .escape:
                if picked != nil { picked = nil } else if active == .main { active = .tree }
            case .pageUp: withFocus { $0.page(-1, in: $1, rows: bodyRows) }
            case .pageDown: withFocus { $0.page(1, in: $1, rows: bodyRows) }
            case .character("d"), .character("/"): pathInput = Self.abbreviated(directory) + "/"
            case .character("x"): closeSelected()
            case .character(let digit) where ("1"..."9").contains(digit):
                if let pane = panes.first(where: { $0.windowIndex == Int(String(digit)) }) { workspace.focus(pane) }
            case .character("r"):
                screen.invalidate()
                kits = [:]
                nextReload = .distantPast
            default:
                break
            }
        }
        return true
    }

    private func withFocus(_ body: (inout Focus, [Target]) -> Void) {
        if active == .tree {
            body(&treeFocus, treePage?.targets ?? [])
            let newRoute = route(of: treeFocus, on: treePage)
            if newRoute != treeRoute {
                treeRoute = newRoute
                // A different node: the main area starts from its top.
                mainFocus = Focus()
                mainRoute = nil
                if case .folder(let path) = newRoute { directory = path }
            }
        } else {
            body(&mainFocus, mainPage?.targets ?? [])
            mainRoute = route(of: mainFocus, on: mainPage)
        }
    }

    private func handle(_ event: MouseEvent) {
        guard event.y >= bodyTop, event.y < bodyTop + bodyRows else { return }
        let inTree = event.x < treeWidth
        switch event.action {
        case .move:
            // Hovering a button shows its details; the tree only changes on click.
            guard !inTree, let targets = mainPage?.targets,
                  let index = Focus.hit(targets, x: event.x - treeWidth - 2, y: event.y - bodyTop + mainFocus.scroll),
                  index != mainFocus.selection else { return }
            active = .main
            mainFocus.hover(index)
            mainRoute = targets[index].route
        case .scrollUp, .scrollDown:
            let direction = event.action == .scrollUp ? -1 : 1
            if inTree { treeFocus.wheel(direction) } else { mainFocus.wheel(direction) }
        case .press:
            active = inTree ? .tree : .main
            let page = inTree ? treePage : mainPage
            let x = inTree ? event.x : event.x - treeWidth - 2
            let y = event.y - bodyTop + (inTree ? treeFocus.scroll : mainFocus.scroll)
            guard let index = Focus.hit(page?.targets ?? [], x: x, y: y) else { return }
            withFocus { focus, _ in focus.select(index) }
            activate()
        }
    }

    private func switchTab(_ tab: Tab) {
        guard tab != self.tab else { return }
        self.tab = tab
        workspace.publishTab(tab == .agents ? "agents" : "code")
        active = .tree
        treeFocus = Focus()
        mainFocus = Focus()
        treeRoute = nil
        mainRoute = nil
    }

    // MARK: - Actions

    private func activate() {
        let route = active == .tree ? treeRoute : mainRoute
        guard let route else { return }
        switch route {
        case .folder(let path):
            directory = path
            active = .main
        case .window(let id):
            if let pane = panes.first(where: { $0.id == id }) { workspace.focus(pane) }
        case .typeFolder:
            pathInput = Self.abbreviated(directory) + "/"
        case .agent:
            active = .main
        case .launch(let id):
            if picked != nil { toggle(id) } else { launch(id) }
        case .hubAction(let action):
            hubAction(action)
        default:
            break
        }
    }

    private func hubAction(_ action: String) {
        let parts = action.split(separator: ":", maxSplits: 1).map(String.init)
        let argument = parts.count > 1 ? parts[1] : ""
        switch parts[0] {
        case "multi":
            picked = picked == nil ? [] : nil
        case "go":
            launchPicked()
        case "goto":
            if let pane = panes.first(where: { $0.id == argument }) { workspace.focus(pane) }
        case "addhere":
            directory = argument
            treeRoute = .folder(argument)
            mainRoute = nil
            mainFocus = Focus()
            active = .main
        case "close":
            if let pane = panes.first(where: { $0.id == argument }) { close(pane) }
        case "start":
            startAgentSession()
        case "ask":
            askRunning(paneId: argument)
        default:
            break
        }
    }

    private func launch(_ profileID: String) {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return }
        guard let executable = InstalledCLIs.path(forCommand: profile.executable) else {
            say("\(profile.executable) isn't installed" + (profile.provider.installHint.map { ". Install: \($0)" } ?? ""), Theme.warning)
            return
        }
        do {
            try workspace.launch(.init(profile: profile, executable: executable), in: directory)
            RecentFolders.remember(directory)
            nextPoll = .distantPast
        } catch {
            say("\(error)", Theme.error)
        }
    }

    private func toggle(_ profileID: String) {
        guard var set = picked else { return }
        guard let profile = profiles.first(where: { $0.id == profileID }), InstalledCLIs.path(forCommand: profile.executable) != nil else {
            say("That one isn't installed", Theme.warning)
            return
        }
        if set.contains(profileID) { set.remove(profileID) } else { set.insert(profileID) }
        picked = set
    }

    private func launchPicked() {
        guard let set = picked, !set.isEmpty else {
            say("Tick at least one agent first (space)", Theme.warning)
            return
        }
        let launches = profiles.filter { set.contains($0.id) }.compactMap { profile in
            InstalledCLIs.path(forCommand: profile.executable).map { Workspace.Launch(profile: profile, executable: $0) }
        }
        do {
            try workspace.launchTogether(launches, in: directory)
            RecentFolders.remember(directory)
            picked = nil
            nextPoll = .distantPast
        } catch {
            say("\(error)", Theme.error)
        }
    }

    /// A new tab of the agent's CLI with "Use the X agent to " typed in.
    private func startAgentSession() {
        guard case .agent(let key) = treeRoute, let (provider, agent) = agent(for: key) else { return }
        let profile = profiles.first { $0.provider == provider && !$0.isCustom } ?? LaunchProfile(name: provider.name, provider: provider)
        guard let executable = InstalledCLIs.path(forCommand: profile.executable) else {
            say("\(profile.executable) isn't installed", Theme.warning)
            return
        }
        do {
            // Agent mode is a conversation: the CLI full width, no map beside it.
            try workspace.launch(.init(profile: profile, executable: executable), in: directory,
                                 typing: "Use the \(agent.qualifiedName) agent to ", withSidebar: false)
            RecentFolders.remember(directory)
            nextPoll = .distantPast
        } catch {
            say("\(error)", Theme.error)
        }
    }

    private func askRunning(paneId: String) {
        guard case .agent(let key) = treeRoute, let (_, agent) = agent(for: key),
              let pane = panes.first(where: { $0.id == paneId }) else { return }
        workspace.type("Use the \(agent.qualifiedName) agent to ", into: pane.id)
        workspace.focus(pane)
    }

    private func closeSelected() {
        guard case .window(let id) = treeRoute, let pane = panes.first(where: { $0.id == id }) else {
            say("Select a terminal on the left to close it", Theme.muted)
            return
        }
        close(pane)
    }

    /// Two steps: the first asks, the second closes.
    private func close(_ pane: Workspace.Pane) {
        if pendingClose == pane.id {
            workspace.close(pane)
            pendingClose = nil
            nextPoll = .distantPast
            say("Closed \(pane.label) in \(pane.folderName)", Theme.muted)
        } else {
            pendingClose = pane.id
            say("Again to close \(pane.label) in \(pane.folderName): its session ends", Theme.warning)
        }
    }

    private func handlePathInput(_ key: Key) {
        guard var input = pathInput else { return }
        switch key {
        // The top bar's Agent / Code clicks arrive as A / C: leave typing.
        case .character("A"), .character("C"):
            pathInput = nil
            switchTab(key == .character("A") ? .agents : .code)
            return
        case .character(let character): input.append(character)
        case .backspace: if !input.isEmpty { input.removeLast() }
        case .tab: input = Self.complete(input)
        case .escape:
            pathInput = nil
            return
        case .enter:
            let path = URL(fileURLWithPath: (input as NSString).expandingTildeInPath).standardizedFileURL.path
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                pathInput = nil
                directory = path
                RecentFolders.remember(path)
                recents = RecentFolders.load()
                switchTab(.code)
                treeRoute = .folder(path)
                active = .main
            } else {
                say("No folder at \(input)", Theme.error)
            }
            return
        default:
            return
        }
        pathInput = input
    }

    private func say(_ text: String, _ color: RGB) {
        notice = (text, color, Date().addingTimeInterval(4))
    }

    // MARK: - Helpers

    /// Keeps a selection on the same item when the list around it changes.
    private func restore(_ focus: inout Focus, route: Route?, on page: Page) -> Bool {
        guard let route else { return false }
        if focus.selection < page.targets.count, page.targets[focus.selection].route == route { return false }
        guard let index = page.targets.firstIndex(where: { $0.route == route }) else { return false }
        focus.select(index)
        return true
    }

    private func route(of focus: Focus, on page: Page?) -> Route? {
        guard let targets = page?.targets, focus.selection < targets.count else { return nil }
        return targets[focus.selection].route
    }

    /// Completes the last path component when the match is unique (or to the
    /// longest common prefix otherwise).
    static func complete(_ input: String) -> String {
        let expanded = (input as NSString).expandingTildeInPath
        let parent = expanded.hasSuffix("/") ? expanded : (expanded as NSString).deletingLastPathComponent
        let prefix = expanded.hasSuffix("/") ? "" : (expanded as NSString).lastPathComponent
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: parent)) ?? [])
            .filter { $0.hasPrefix(prefix) && !$0.hasPrefix(".") }
            .filter { name in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: (parent as NSString).appendingPathComponent(name), isDirectory: &isDirectory) && isDirectory.boolValue
            }
        guard let first = names.first else { return input }
        var common = first
        for name in names.dropFirst() {
            while !name.hasPrefix(common) { common.removeLast() }
        }
        let completed = (parent as NSString).appendingPathComponent(common) + (names.count == 1 ? "/" : "")
        return abbreviated(completed)
    }

    static func abbreviated(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

