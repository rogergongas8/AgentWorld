import AgentWorldArt
import AgentWorldKit
import AppKit
import SwiftUI

/// ⌘, — the app's settings, one tab per topic, in the standard Mac window.
struct SettingsView: View {
    /// Reopens on the tab you left.
    @AppStorage("settingsTab") private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }.tag("general")
            TerminalSettings().tabItem { Label("Terminal", systemImage: "terminal") }.tag("terminal")
            CLISettings().tabItem { Label("CLIs", systemImage: "person.2") }.tag("clis")
            NotificationSettings().tabItem { Label("Notifications", systemImage: "bell.badge") }.tag("notifications")
            MemorySettings().tabItem { Label("Memory", systemImage: "brain") }.tag("memory")
            IntegrationSettings().tabItem { Label("Integrations", systemImage: "puzzlepiece.extension") }.tag("integrations")
            ShortcutSettings().tabItem { Label("Shortcuts", systemImage: "keyboard") }.tag("shortcuts")
        }
        .frame(width: 620)
        .preferredColorScheme(.dark)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @ObservedObject private var preferences = Preferences.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Projects folder") {
                    HStack {
                        Text((preferences.projectsFolder as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button("Choose…", action: chooseFolder)
                    }
                }
            } footer: {
                Text("Where New Project creates and clones repositories.").settingsFootnote()
            }
            Section {
                Toggle("Open AgentWorld at login", isOn: Binding(get: { preferences.startsAtLogin },
                                                                   set: { preferences.startsAtLogin = $0 }))
                    .disabled(!preferences.canStartAtLogin)
                Toggle("Ask before closing an agent that's still working", isOn: $preferences.confirmClosingBusy)
                Toggle("Show the live crew under the workspaces", isOn: $preferences.showsLiveCrew)
                Toggle("Show stories beside a lone terminal", isOn: $preferences.showsStories)
                Toggle("Show the pixel scene at the top of the right panel", isOn: $preferences.showsPanelScene)
            } footer: {
                if !preferences.canStartAtLogin {
                    Text("Opening at login needs the installed app (make app), not a bare build.").settingsFootnote()
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: preferences.projectsFolder)
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { preferences.projectsFolder = url.path }
    }
}

// MARK: - Terminal

struct TerminalSettings: View {
    @ObservedObject private var preferences = Preferences.shared

    var body: some View {
        Form {
            Section {
                Picker("Font", selection: $preferences.fontName) {
                    ForEach(Preferences.monospacedFonts, id: \.self) { name in
                        Text(name.isEmpty ? "System (SF Mono)" : name).tag(name)
                    }
                }
                LabeledContent("Size") {
                    HStack {
                        Slider(value: $preferences.fontSize, in: 9...24, step: 1)
                        Text("\(Int(preferences.fontSize)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                preview
            }
            Section {
                Toggle("Use ⌥ as Meta", isOn: $preferences.optionAsMeta)
            } footer: {
                Text("On: ⌥← and ⌥→ jump by word in the shell. Off: ⌥ types symbols like # and €.").settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .frame(height: 380)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("~/Developer/AgentWorld % claude").foregroundStyle(Color(rgb: Theme.text))
            Text("✻ Thinking… reading 12 files").foregroundStyle(Palette.claude)
            Text("● swift test — 48 passed").foregroundStyle(Palette.live)
        }
        .font(Font(preferences.terminalFont))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.terminalBackground))
    }
}

// MARK: - CLIs

struct CLISettings: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var preferences = Preferences.shared
    @State private var editing: ProfileDraft?

    var body: some View {
        Form {
            Section {
                ForEach(Provider.all, id: \.id) { provider in
                    HStack(spacing: 10) {
                        FaceView(figure: provider.figure, scale: 2).frame(width: 22, height: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(provider.name)
                            Text(location(provider)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Toggle("Show in launcher", isOn: Binding(
                            get: { !preferences.hiddenProviders.contains(provider.id) },
                            set: { shown in
                                if shown { preferences.hiddenProviders.remove(provider.id) } else { preferences.hiddenProviders.insert(provider.id) }
                            }))
                            .labelsHidden()
                            .help("Show \(provider.name) in the launcher")
                    }
                }
            } header: {
                Text("In the launcher")
            }
            Section {
                let custom = model.profiles.filter(\.isCustom)
                if custom.isEmpty {
                    Text("No profiles yet. A profile is a CLI with your flags and environment, e.g. Claude with --model opus.")
                        .foregroundStyle(.secondary)
                }
                ForEach(custom) { profile in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(profile.name)
                            Text(([profile.executable] + profile.args).joined(separator: " "))
                                .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("Edit") { editing = ProfileDraft(profile) }
                        Button(role: .destructive) {
                            model.saveCustomProfiles(custom.filter { $0.id != profile.id })
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .help("Delete this profile")
                    }
                }
                HStack {
                    Button("Add Profile…") { editing = ProfileDraft() }
                    Spacer()
                    Button("Show profiles.json") {
                        NSWorkspace.shared.activateFileViewerSelecting([LaunchProfile.configURL])
                    }
                    .disabled(!FileManager.default.fileExists(atPath: LaunchProfile.configURL.path))
                }
            } header: {
                Text("Launch profiles")
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
        .sheet(item: $editing) { draft in
            ProfileEditor(draft: draft) { saved in
                var custom = model.profiles.filter(\.isCustom)
                if let original = draft.original, let index = custom.firstIndex(where: { $0.id == original.id }) {
                    custom[index] = saved
                } else {
                    custom.append(saved)
                }
                model.saveCustomProfiles(custom)
            }
        }
    }

    private func location(_ provider: Provider) -> String {
        if let path = model.executable(for: LaunchProfile(name: provider.name, provider: provider)) {
            return (path as NSString).abbreviatingWithTildeInPath
        }
        return provider.installHint.map { "not installed · \($0)" } ?? "not installed"
    }
}

struct ProfileDraft: Identifiable {
    let id = UUID()
    var original: LaunchProfile?
    var name = ""
    var providerID = Provider.claude.id
    var command = ""
    var arguments = ""
    var environment = ""

    init() {}

    init(_ profile: LaunchProfile) {
        original = profile
        name = profile.name
        providerID = profile.provider.id
        command = profile.command ?? ""
        arguments = LaunchProfile.joinArguments(profile.args)
        environment = profile.env.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }

    var profile: LaunchProfile? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let provider = Provider.named(providerID) else { return nil }
        var env: [String: String] = [:]
        for line in environment.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, !parts[0].isEmpty { env[parts[0]] = parts[1] }
        }
        let command = command.trimmingCharacters(in: .whitespaces)
        return LaunchProfile(name: trimmed, provider: provider, command: command.isEmpty ? nil : command,
                             args: LaunchProfile.splitArguments(arguments), env: env, isCustom: true)
    }
}

struct ProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: ProfileDraft
    let save: (LaunchProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField("Name", text: $draft.name, prompt: Text("Claude · Opus, plan mode"))
                Picker("CLI", selection: $draft.providerID) {
                    ForEach(Provider.all.filter(\.isAgent), id: \.id) { provider in Text(provider.name).tag(provider.id) }
                }
                TextField("Arguments", text: $draft.arguments, prompt: Text("--model opus --permission-mode plan"))
                    .font(.body.monospaced())
                TextField("Command", text: $draft.command, prompt: Text("default: \(Provider.named(draft.providerID)?.command ?? "")"))
                    .font(.body.monospaced())
                LabeledContent("Environment") {
                    TextEditor(text: $draft.environment)
                        .font(.body.monospaced())
                        .frame(height: 64)
                        .overlay(alignment: .topLeading) {
                            if draft.environment.isEmpty {
                                Text("KEY=value, one per line").foregroundStyle(.tertiary).padding(.leading, 5).allowsHitTesting(false)
                            }
                        }
                }
            }
            .formStyle(.grouped)
            HStack {
                Text("Saved to ~/.config/agentworld/profiles.json").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(draft.original == nil ? "Add" : "Save") {
                    if let profile = draft.profile { save(profile) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.profile == nil)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 520)
    }
}

// MARK: - Notifications

struct NotificationSettings: View {
    @ObservedObject private var preferences = Preferences.shared

    var body: some View {
        Form {
            Section {
                Toggle("Notify when an agent is waiting for you or ends", isOn: $preferences.notifies)
                Toggle("Play a sound", isOn: $preferences.notificationSound).disabled(!preferences.notifies)
                LabeledContent("Only after it worked for") {
                    HStack {
                        Slider(value: $preferences.minimumWork, in: 0...120, step: 5)
                        Text(preferences.minimumWork == 0 ? "always" : "\(Int(preferences.minimumWork)) s")
                            .monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
            } footer: {
                Text("Nothing is sent while you're looking at that terminal.").settingsFootnote()
            }
            Section {
                Toggle("Count who's waiting on the Dock icon", isOn: $preferences.dockBadge)
                Toggle("Bounce the Dock icon", isOn: $preferences.bouncesDock)
            }
            Section {
                Button("Open Notification Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } footer: {
                Text("Banners need permission in System Settings the first time.").settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .frame(height: 420)
    }
}

// MARK: - Integrations

struct IntegrationSettings: View {
    @ObservedObject private var preferences = Preferences.shared
    @State private var status = AgentWorldSkill.status()

    var body: some View {
        Form {
            Section {
                Toggle("Install the agentworld skill", isOn: $preferences.installsSkill)
                    .onChange(of: preferences.installsSkill) { _ in status = AgentWorldSkill.status() }
                ForEach(status, id: \.cli) { entry in
                    LabeledContent {
                        Text(entry.yours ? "your own copy" : entry.installed ? "installed" : "not installed")
                            .foregroundStyle(entry.installed ? Color.green : .secondary)
                    } label: {
                        Text(entry.cli)
                        Text(entry.path).font(.caption.monospaced())
                    }
                }
            } header: {
                Text("Agents driving the app")
            } footer: {
                Text("The skill teaches each agent CLI set up here to open panes beside it, hand off work and talk through its character with agentworld-ctl, so any of them can lead a workflow. A CLI that doesn't load skills can still run agentworld-ctl help. A copy you edited (without the marker line) is never touched.")
                    .settingsFootnote()
            }
            Section {
                LabeledContent("Control socket", value: (ControlServer.socketPath as NSString).abbreviatingWithTildeInPath)
                LabeledContent("Launch profiles", value: (LaunchProfile.configURL.path as NSString).abbreviatingWithTildeInPath)
            }
        }
        .formStyle(.grouped)
        .frame(height: 360)
        .onAppear { status = AgentWorldSkill.status() }
    }
}

// MARK: - Memory

struct MemorySettings: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var preferences = Preferences.shared
    @State private var status = MemoryMCP.status()
    @State private var instructions = MemoryInstructions.status()
    @State private var working = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Vault") {
                    HStack {
                        Text((preferences.memoryFolder as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                LabeledContent("Notes") {
                    HStack {
                        Text("\(model.memoryNotes.count) in \(Set(model.memoryNotes.map(\.scope)).count) scopes").foregroundStyle(.secondary)
                        Button("Open") { model.openNotes() }
                    }
                }
            } header: {
                Text("Shared memory")
            } footer: {
                Text("Markdown notes every agent CLI reads and writes: one folder per project, plus global. Terminals opened after a change use the new folder.")
                    .settingsFootnote()
            }
            Section {
                Toggle("Give every CLI the memory as MCP tools", isOn: $preferences.connectsMemory)
                    .onChange(of: preferences.connectsMemory) { on in
                        if on { update { MemoryMCP.connectAll(claudeExecutable: $0) } }
                    }
                ForEach(status, id: \.target.provider.id) { entry in
                    LabeledContent {
                        HStack {
                            Text(entry.connected ? "connected" : "not connected")
                                .foregroundStyle(entry.connected ? Color.green : .secondary)
                            Button(entry.connected ? "Remove" : "Connect") {
                                let target = entry.target
                                let connected = entry.connected
                                update { claude in
                                    if connected { MemoryMCP.disconnect(target, claudeExecutable: claude) }
                                    else if let command = MemoryMCP.command { MemoryMCP.connect(target, command: command, claudeExecutable: claude) }
                                }
                            }
                            .disabled(working)
                        }
                    } label: {
                        Text(entry.target.provider.name)
                        Text("~/" + entry.target.file).font(.caption.monospaced())
                    }
                }
                Toggle("Tell every CLI to use it, in its global instructions", isOn: $preferences.teachesMemory)
                    .onChange(of: preferences.teachesMemory) { _ in instructions = MemoryInstructions.status() }
                ForEach(instructions, id: \.target.provider.id) { entry in
                    LabeledContent {
                        Text(entry.installed ? "added" : "not added").foregroundStyle(entry.installed ? Color.green : .secondary)
                    } label: {
                        Text(entry.target.provider.name)
                        Text("~/" + entry.target.file).font(.caption.monospaced())
                    }
                }
            } header: {
                Text("Agents using it")
            } footer: {
                Text("Adds an MCP server named agentworld-memory (agentworld-ctl mcp) to each CLI's own config, so it gets memory_search, memory_read, memory_write… tools. The instructions are a short marked block in the file each CLI reads every session (search before a task, write what it learns); the rest of those files is never touched. Kimi, Grok and Cursor have no global file: they get the MCP tools and the skill.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .frame(height: 560)
        .onAppear { status = MemoryMCP.status(); instructions = MemoryInstructions.status(); model.refreshMemory() }
    }

    /// Runs a change to the CLIs' configs off the main thread, then rereads their status.
    private func update(_ change: @escaping @Sendable (String?) -> Void) {
        working = true
        let claude = model.executable(for: LaunchProfile(name: Provider.claude.name, provider: .claude))
        Task.detached(priority: .userInitiated) {
            change(claude)
            await MainActor.run {
                status = MemoryMCP.status()
                working = false
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: preferences.memoryFolder)
        panel.prompt = "Use as Vault"
        panel.message = "Pick a folder for the shared memory (a folder of notes you already keep works too)."
        if panel.runModal() == .OK, let url = panel.url {
            preferences.memoryFolder = url.path
            try? MemoryVault(root: url).prepare()
            model.refreshMemory()
        }
    }
}

// MARK: - Shortcuts

struct ShortcutSettings: View {
    var body: some View {
        Form {
            ForEach(ShortcutsSheet.groups, id: \.0) { title, rows in
                Section(title) {
                    ForEach(rows, id: \.0) { key, label in
                        LabeledContent(label) { Text(key).font(.body.monospaced()).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
    }
}

private extension Text {
    func settingsFootnote() -> some View {
        font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
