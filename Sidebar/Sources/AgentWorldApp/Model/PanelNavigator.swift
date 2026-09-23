import AgentWorldKit
import AppKit
import SwiftUI

/// One row of the right panel, whatever its section.
enum PanelItem: Identifiable {
    case agent(AgentDefinition)
    case skill(SkillDefinition)
    case server(MCPServerDefinition)
    case plugin(PluginDefinition)
    case command(CommandDefinition)
    case change(FileChange)
    case tip(Suggestion)

    var id: String {
        switch self {
        case .agent(let agent): "agent:" + agent.qualifiedName
        case .skill(let skill): "skill:" + skill.qualifiedName
        case .server(let server): "mcp:" + server.name + (server.plugin ?? "")
        case .plugin(let plugin): "plugin:" + plugin.name
        case .command(let command): "command:" + command.qualifiedName
        case .change(let change): "change:" + change.path
        case .tip(let tip): "tip:" + tip.name
        }
    }

    /// For the panel's search: the query in its name or what it says it does.
    func matches(_ query: String) -> Bool {
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else { return true }
        let haystack: String
        switch self {
        case .agent(let agent): haystack = [agent.qualifiedName, agent.description ?? "", agent.skills.joined(separator: " ")].joined(separator: " ")
        case .skill(let skill): haystack = [skill.qualifiedName, skill.summary ?? "", skill.category.title].joined(separator: " ")
        case .server(let server): haystack = [server.name, server.transport, server.plugin ?? ""].joined(separator: " ")
        case .plugin(let plugin): haystack = [plugin.name, plugin.description ?? ""].joined(separator: " ")
        case .command(let command): haystack = [command.qualifiedName, command.description ?? ""].joined(separator: " ")
        case .change(let change): haystack = change.path + " " + change.kind.rawValue
        case .tip(let tip): haystack = tip.name + " " + tip.reasons.joined(separator: " ")
        }
        let text = haystack.lowercased()
        return words.allSatisfy { text.contains($0) }
    }

    /// The skill or agent behind it, for the detail card.
    var kitItem: KitItem? {
        switch self {
        case .agent(let agent): .agent(agent)
        case .skill(let skill): .skill(skill)
        default: nil
        }
    }
}

/// Where the keyboard is in the right panel: which section, which row, and
/// whether the panel has the keys at all (⌘E) instead of the terminal.
@MainActor
final class PanelNavigator: ObservableObject {
    enum Section: Int, CaseIterable, Identifiable {
        case crew, skills, tools, changes, tips

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .crew: "Crew"
            case .skills: "Skills"
            case .tools: "Tools"
            case .changes: "Changes"
            case .tips: "Tips"
            }
        }

        var symbol: String {
            switch self {
            case .crew: "person.3"
            case .skills: "books.vertical"
            case .tools: "powerplug"
            case .changes: "plusminus"
            case .tips: "sparkles"
            }
        }
    }

    @Published var section = Section.crew {
        didSet { if section != oldValue { selection = 0; openDetail = nil } }
    }
    @Published var selection = 0
    @Published var isFocused = false
    /// The row whose detail card is open.
    @Published var openDetail: String?
    /// Open the card with the cursor in its "what should change?" box.
    @Published var editing = false
    /// The "+ New" card for the section, opened from the keyboard.
    @Published var creating = false
    /// `/`: typing filters the rows (names, descriptions) instead of running keys.
    @Published var searching = false
    @Published var query = "" {
        didSet { if query != oldValue { selection = 0; openDetail = nil } }
    }

    func stopSearching() {
        searching = false
        query = ""
    }

    func move(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        selection = min(max(0, selection + delta), count - 1)
    }

    func cycleSection(_ delta: Int) {
        let all = Section.allCases
        section = all[(section.rawValue + delta + all.count) % all.count]
    }
}

extension AppModel {
    /// The terminal the panel is about: the focused pane, else the tab's first.
    var panelSession: TerminalSession? {
        guard !showsLauncher, let tab = selectedTab, tab.folder == selectedFolder else { return nil }
        return focusedSession.flatMap { focused in tab.sessions.first { $0 === focused } } ?? lastPanelSession.flatMap { last in
            tab.sessions.first { $0 === last }
        } ?? tab.sessions.first
    }

    /// The CLI whose kit the panel shows (a plain shell shows Claude's).
    var panelProvider: Provider {
        panelSession?.provider.isAgent == true ? panelSession!.provider : .claude
    }

    /// A section's rows, narrowed by the panel's search.
    func panelItems(_ section: PanelNavigator.Section) -> [PanelItem] {
        let all = allPanelItems(section)
        return panel.query.isEmpty ? all : all.filter { $0.matches(panel.query) }
    }

    private func allPanelItems(_ section: PanelNavigator.Section) -> [PanelItem] {
        let config = config(panelProvider, in: selectedFolder)
        switch section {
        case .crew:
            return config.agents.map(PanelItem.agent)
        case .skills:
            // Grouped the way the list shows them.
            return SkillCategory.allCases.flatMap { category in
                config.skills.filter { $0.category == category }.map(PanelItem.skill)
            }
        case .tools:
            return config.mcpServers.map(PanelItem.server) + config.plugins.map(PanelItem.plugin) + config.commands.map(PanelItem.command)
        case .changes:
            return (changes[selectedFolder]?.files ?? []).map(PanelItem.change)
        case .tips:
            return tips(for: panelSession?.provider.isAgent == true ? panelSession : nil, in: selectedFolder).map(PanelItem.tip)
        }
    }

    // MARK: - Keys

    /// Arrows, return and letters for the panel (⌘E) and the launcher,
    /// before the terminal sees them. Everything else passes through.
    func installKeyRouter() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.routeSwitcher(event) { return nil }
            return self.route(event) ? nil : event
        }
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.routeModifiers(event)
            return event
        }
    }

    /// True when the key was used.
    func route(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty else { return false }
        // Typing in a text field (a card's edit box, the palette) is typing.
        if NSApp.keyWindow?.firstResponder is NSText { return false }
        if showsShortcuts {
            if event.keyCode == 53 { showsShortcuts = false; return true }
            return false
        }
        if panel.isFocused { return routePanel(event) }
        if showsLauncher, !showsPalette, !showsKit { return routeLauncher(event) }
        return false
    }

    private func routePanel(_ event: NSEvent) -> Bool {
        let count = panelItems(panel.section).count
        let items = { self.panelItems(self.panel.section) }
        switch event.keyCode {
        case 125: panel.move(1, count: count)                        // ↓
        case 126: panel.move(-1, count: count)                       // ↑
        case 124, 48 where !event.modifierFlags.contains(.shift):    // → / tab
            panel.cycleSection(1)
        case 123, 48: panel.cycleSection(-1)                         // ← / ⇧tab
        case 36, 76:                                                 // return
            let list = items()
            if list.indices.contains(panel.selection) { activate(list[panel.selection], detail: true) }
        case 51 where panel.searching:                               // delete
            if panel.query.isEmpty { panel.searching = false } else { panel.query.removeLast() }
        case 53:                                                     // esc
            if panel.searching || !panel.query.isEmpty {
                panel.stopSearching()
            } else if panel.openDetail != nil || panel.creating {
                panel.openDetail = nil
                panel.creating = false
            } else {
                leavePanel()
            }
        default:
            if panel.searching {
                // Letters, digits, spaces and the like go into the query.
                guard let typed = event.characters, typed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
                      !typed.isEmpty else { return false }
                panel.query += typed
                jumpToSectionWithResults()
                return true
            }
            switch event.charactersIgnoringModifiers {
            case "/":
                panel.searching = true
            case "1", "2", "3", "4", "5":
                if let digit = Int(event.charactersIgnoringModifiers ?? ""), let section = PanelNavigator.Section(rawValue: digit - 1) {
                    panel.section = section
                }
            case "j": panel.move(1, count: count)
            case "k": panel.move(-1, count: count)
            case "u":
                let list = items()
                if list.indices.contains(panel.selection) { activate(list[panel.selection], detail: false) }
            case "e":
                let list = items()
                if list.indices.contains(panel.selection), list[panel.selection].kitItem != nil {
                    panel.editing = true
                    panel.openDetail = list[panel.selection].id
                }
            case "n":
                if panel.section == .crew || panel.section == .skills { panel.creating = true }
            case "m":
                let list = items()
                if list.indices.contains(panel.selection), case .change(let change) = list[panel.selection] {
                    leavePanel()
                    showOnMap(change, in: selectedFolder)
                }
            default:
                return false
            }
        }
        return true
    }

    /// Searching from a section with nothing that matches: go where there is.
    private func jumpToSectionWithResults() {
        guard panelItems(panel.section).isEmpty,
              let better = PanelNavigator.Section.allCases.first(where: { !panelItems($0).isEmpty }) else { return }
        panel.section = better
    }

    /// Opens the panel with the search going, from ⌘F or its magnifier.
    func searchPanel() {
        enterPanel()
        panel.searching = true
    }

    /// Return on a row: its card (skills, agents) or, for tips, use it.
    /// `u` uses it straight away.
    func activate(_ item: PanelItem, detail: Bool) {
        if detail, case .change(let change) = item {
            openDiff(change, in: selectedFolder)
            return
        }
        if detail, item.kitItem != nil {
            panel.editing = false
            panel.openDetail = item.id
            return
        }
        let session = panelSession?.provider.isAgent == true ? panelSession : nil
        switch item {
        case .agent(let agent):
            if let session { leavePanel(); session.type("Use the \(agent.qualifiedName) agent to ") }
            else { leavePanel(); startChat(with: agent, provider: panelProvider, in: selectedFolder) }
        case .skill(let skill):
            guard let session else { return }
            leavePanel()
            session.type(panelProvider.kind == .claude ? "/\(skill.qualifiedName) " : "Use the \(skill.name) skill to ")
        case .command(let command):
            guard let session else { return }
            leavePanel()
            session.type("/\(command.qualifiedName) ")
        case .tip(let tip):
            guard let session else { return }
            leavePanel()
            switch tip.kind {
            case .agent: session.type("Use the \(tip.name) agent to ")
            case .skill: session.type(panelProvider.kind == .claude ? "/\(tip.name) " : "Use the \(tip.name) skill to ")
            case .command: session.type("/\(tip.name) ")
            }
        case .change(let change):
            // The path, relative to the pane's folder, for the prompt you're typing.
            guard let session, let root = changes[selectedFolder]?.root else { return }
            leavePanel()
            let full = URL(fileURLWithPath: root).appendingPathComponent(change.path).path
            let relative = full.hasPrefix(session.folder + "/") ? String(full.dropFirst(session.folder.count + 1)) : full
            session.type(relative + " ")
        case .server, .plugin:
            break
        }
    }

    func enterPanel() {
        showsInspector = true
        if let session = focusedSession { lastPanelSession = session }
        panel.isFocused = true
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    func leavePanel() {
        panel.isFocused = false
        panel.searching = false
        panel.openDetail = nil
        panel.creating = false
        if let session = panelSession { DispatchQueue.main.async { session.focus() } }
    }

    private func routeLauncher(_ event: NSEvent) -> Bool {
        let count = launcherProfiles.count
        guard count > 0 else { return false }
        switch event.keyCode {
        case 124, 125: launcherIndex = min(launcherIndex + (event.keyCode == 125 ? 3 : 1), count - 1)   // → ↓
        case 123, 126: launcherIndex = max(launcherIndex - (event.keyCode == 126 ? 3 : 1), 0)          // ← ↑
        case 36, 76:
            let profile = launcherProfiles[min(launcherIndex, count - 1)]
            guard executable(for: profile) != nil else { return false }
            launch(profile, in: selectedFolder)
        default:
            return false
        }
        return true
    }

    /// The launcher's cards in order: installed first, without the CLIs
    /// Settings hides (your profiles always show).
    var launcherProfiles: [LaunchProfile] {
        let hidden = Preferences.shared.hiddenProviders
        let shown = profiles.filter { $0.isCustom || !hidden.contains($0.provider.id) }
        return shown.filter { executable(for: $0) != nil } + shown.filter { executable(for: $0) == nil }
    }
}
