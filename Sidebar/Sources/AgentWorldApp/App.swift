import AppKit
import SwiftUI

@main
struct AgentWorldApp: App {
    @StateObject private var model: AppModel

    init() {
        if let index = CommandLine.arguments.firstIndex(of: "--render-crew"), CommandLine.arguments.indices.contains(index + 2) {
            AppIcon.renderCandidates(Array(CommandLine.arguments[(index + 2)...]), to: CommandLine.arguments[index + 1])
            exit(0)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-icon"), CommandLine.arguments.indices.contains(index + 1) {
            AppIcon.renderIconset(to: CommandLine.arguments[index + 1])
            exit(0)
        }
        // Launched as a bare executable (or from the bundle): be a regular app
        // with a Dock icon and a key window.
        NSApplication.shared.setActivationPolicy(.regular)
        let arguments = CommandLine.arguments
        let folder = arguments.firstIndex(of: "--cwd").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        _model = StateObject(wrappedValue: AppModel(folder: folder))
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        WindowGroup("AgentWorld") {
            RootView()
                .environmentObject(model)
                .onAppear {
                    DebugControl.start(model: model)
                    ControlServer.start(model: model)
                }
                .frame(minWidth: 980, minHeight: 620)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open a CLI…") {
                    model.showsLauncher = true
                    model.panel.isFocused = false
                }
                .keyboardShortcut("t")
                Button("Add Workspace…") { model.chooseFolder() }
                    .keyboardShortcut("o")
                Button("New Project…") { model.showsNewProject = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("Close Tab") {
                    if let tab = model.selectedTab { model.requestClose(tab) }
                }
                .keyboardShortcut("w")
            }
            CommandMenu("Go") {
                Button("Next Tab") { model.selectTab(offset: 1) }.keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { model.selectTab(offset: -1) }.keyboardShortcut("[", modifiers: [.command, .shift])
                Divider()
                Button("Next Pane") { model.focusPane(offset: 1) }.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Button("Previous Pane") { model.focusPane(offset: -1) }.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Divider()
                Button("Next Workspace") { model.selectWorkspace(offset: 1) }.keyboardShortcut(.downArrow, modifiers: [.command, .option])
                Button("Previous Workspace") { model.selectWorkspace(offset: -1) }.keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Divider()
                Button("Project Map") { if model.showsMap { model.showsMap = false } else { model.openProjectMap() } }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Commit Changes…") { model.showsCommit = true }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(model.changes[model.selectedFolder]?.files.isEmpty != false)
                Button("Search the Panel") { model.searchPanel() }
                    .keyboardShortcut("f")
                Button("Browse the Panel") {
                    if model.panel.isFocused { model.leavePanel() } else { model.enterPanel() }
                }
                .keyboardShortcut("e")
            }
            CommandMenu("View") {
                Button(model.showsSidebar ? "Hide Workspaces" : "Show Workspaces") {
                    withAnimation(.easeOut(duration: 0.18)) { model.showsSidebar.toggle() }
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                Button(model.showsInspector ? "Hide Panel" : "Show Panel") { model.showsInspector.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") { model.showsShortcuts.toggle() }
                    .keyboardShortcut("/")
            }
        }
        Settings {
            SettingsView().environmentObject(model)
        }
    }
}
