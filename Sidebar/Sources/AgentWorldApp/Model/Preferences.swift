import AgentWorldKit
import AppKit
import Foundation
import ServiceManagement

/// What the Settings window changes, kept in the user defaults. One shared
/// instance: terminals, the notifier and the launcher read it directly.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    // MARK: General

    /// Where "New Project…" creates and clones.
    @Published var projectsFolder: String { didSet { defaults.set(projectsFolder, forKey: "projectsFolder") } }
    /// Ask before closing a tab whose agent is still working.
    @Published var confirmClosingBusy: Bool { didSet { defaults.set(confirmClosingBusy, forKey: "confirmClosingBusy") } }
    /// The live crew at the foot of the workspaces column.
    @Published var showsLiveCrew: Bool { didSet { defaults.set(showsLiveCrew, forKey: "showsLiveCrew") } }
    /// The little theater beside a lone terminal.
    @Published var showsStories: Bool { didSet { defaults.set(showsStories, forKey: "showsStories") } }
    /// The pixel scene at the top of the right panel. Off leaves just the
    /// agent's face and its one-line status.
    @Published var showsPanelScene: Bool { didSet { defaults.set(showsPanelScene, forKey: "showsPanelScene") } }

    // MARK: Terminal

    @Published var fontName: String { didSet { defaults.set(fontName, forKey: "terminalFont"); terminalLookChanged() } }
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: "terminalFontSize"); terminalLookChanged() } }
    /// ⌥ sends Meta (for Emacs-style word moves) instead of typing symbols.
    @Published var optionAsMeta: Bool { didSet { defaults.set(optionAsMeta, forKey: "optionAsMeta"); terminalLookChanged() } }

    // MARK: CLIs

    /// Provider ids left out of the launcher (still usable from profiles).
    @Published var hiddenProviders: Set<String> { didSet { defaults.set(Array(hiddenProviders), forKey: "hiddenProviders") } }

    // MARK: Notifications

    @Published var notifies: Bool { didSet { defaults.set(notifies, forKey: "notifies") } }
    /// Only after this much work (seconds): short jobs don't deserve a ping.
    @Published var minimumWork: Double { didSet { defaults.set(minimumWork, forKey: "minimumWork") } }
    @Published var notificationSound: Bool { didSet { defaults.set(notificationSound, forKey: "notificationSound") } }
    @Published var dockBadge: Bool { didSet { defaults.set(dockBadge, forKey: "dockBadge") } }
    @Published var bouncesDock: Bool { didSet { defaults.set(bouncesDock, forKey: "bouncesDock") } }

    // MARK: Integrations

    /// Keep the `agentworld` skill installed for the CLIs that read skills.
    @Published var installsSkill: Bool {
        didSet {
            defaults.set(installsSkill, forKey: "installsSkill")
            if installsSkill { AgentWorldSkill.install() } else { AgentWorldSkill.uninstall() }
        }
    }

    // MARK: Memory

    /// The shared memory's folder of notes.
    @Published var memoryFolder: String {
        didSet {
            defaults.set(memoryFolder, forKey: "memoryFolder")
            MemoryVault.saveConfigured(URL(fileURLWithPath: memoryFolder, isDirectory: true))
        }
    }
    /// Keep the memory's MCP server registered with every CLI set up here.
    @Published var connectsMemory: Bool { didSet { defaults.set(connectsMemory, forKey: "connectsMemory") } }
    /// Keep a short "use the shared memory" block in each CLI's global instructions.
    @Published var teachesMemory: Bool {
        didSet {
            defaults.set(teachesMemory, forKey: "teachesMemory")
            if teachesMemory { MemoryInstructions.installAll() } else { MemoryInstructions.uninstallAll() }
        }
    }

    /// Called when the terminal font or keys change, to restyle open terminals.
    var onTerminalLookChange: (() -> Void)?

    private init() {
        defaults.register(defaults: [
            "projectsFolder": Self.suggestedProjectsFolder,
            "confirmClosingBusy": true,
            // Each session row already shows its character; the big live crew
            // and the idle stories are opt-in so the window stays calm.
            "showsLiveCrew": false,
            "showsStories": false,
            "showsPanelScene": true,
            "terminalFont": "",
            "terminalFontSize": 13.0,
            "optionAsMeta": false,
            "notifies": true,
            "minimumWork": 8.0,
            "notificationSound": true,
            "dockBadge": true,
            "bouncesDock": true,
            "installsSkill": true,
            "memoryFolder": MemoryVault.defaultRoot.path,
            "connectsMemory": true,
            "teachesMemory": true,
        ])
        projectsFolder = defaults.string(forKey: "projectsFolder") ?? Self.suggestedProjectsFolder
        confirmClosingBusy = defaults.bool(forKey: "confirmClosingBusy")
        showsLiveCrew = defaults.bool(forKey: "showsLiveCrew")
        showsStories = defaults.bool(forKey: "showsStories")
        showsPanelScene = defaults.bool(forKey: "showsPanelScene")
        fontName = defaults.string(forKey: "terminalFont") ?? ""
        fontSize = defaults.double(forKey: "terminalFontSize")
        optionAsMeta = defaults.bool(forKey: "optionAsMeta")
        hiddenProviders = Set(defaults.stringArray(forKey: "hiddenProviders") ?? [])
        notifies = defaults.bool(forKey: "notifies")
        minimumWork = defaults.double(forKey: "minimumWork")
        notificationSound = defaults.bool(forKey: "notificationSound")
        dockBadge = defaults.bool(forKey: "dockBadge")
        bouncesDock = defaults.bool(forKey: "bouncesDock")
        installsSkill = defaults.bool(forKey: "installsSkill")
        // $AGENTWORLD_MEMORY wins for this run (scripted test runs use a scratch vault).
        memoryFolder = ProcessInfo.processInfo.environment["AGENTWORLD_MEMORY"]
            ?? defaults.string(forKey: "memoryFolder") ?? MemoryVault.defaultRoot.path
        connectsMemory = defaults.bool(forKey: "connectsMemory")
        teachesMemory = defaults.bool(forKey: "teachesMemory")
    }

    static var suggestedProjectsFolder: String {
        let developer = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer").path
        return FileManager.default.fileExists(atPath: developer) ? developer : FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// The terminal font: "" (or one that's gone) is the system's monospaced one, SF Mono.
    var terminalFont: NSFont {
        NSFont(name: fontName, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    /// Monospaced fonts installed here, the usual ones first.
    static let monospacedFonts: [String] = {
        let preferred = ["Menlo", "Monaco", "JetBrains Mono", "Fira Code", "Cascadia Code", "Hack", "Source Code Pro", "IBM Plex Mono"]
        let families = NSFontManager.shared.availableFontFamilies
        let fixed = families.filter { family in
            NSFont(name: family, size: 12)?.isFixedPitch == true
        }
        let known = preferred.filter { families.contains($0) || NSFont(name: $0, size: 12) != nil }
        return [""] + known + fixed.filter { !known.contains($0) && !$0.hasPrefix(".") }.sorted()
    }()

    private func terminalLookChanged() { onTerminalLookChange?() }

    // MARK: Start at login

    /// Only for the installed app: a bare binary can't be a login item.
    var canStartAtLogin: Bool { Bundle.main.bundleIdentifier != nil }

    var startsAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }
}
