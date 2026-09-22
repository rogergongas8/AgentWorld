import AppKit
import SwiftUI

@main
struct AgentWorldApp: App {
    @StateObject private var model: AppModel

    init() {
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
                Button("New Terminal…") {
                    model.showsLauncher = true
                }
                .keyboardShortcut("t")
                Button("Close Tab") {
                    if let tab = model.selectedTab { model.close(tab) }
                }
                .keyboardShortcut("w")
            }
            CommandMenu("View") {
                Button(model.showsInspector ? "Hide Tips & Kit" : "Show Tips & Kit") { model.showsInspector.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
    }
}
