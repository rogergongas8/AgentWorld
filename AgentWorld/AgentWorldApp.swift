//
//  AgentWorldApp.swift
//  AgentWorld
//
//  Created by Roger Gonzalbo Gaspar on 09/09/2026.
//

import SwiftUI

@main
struct AgentWorldApp: App {
    @StateObject private var launchCoordinator = LaunchCoordinator()
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(LaunchWindowOpener(coordinator: launchCoordinator, appDelegate: appDelegate))
        }

        WindowGroup("Personajes", id: "companion") {
            CompanionWindowView()
                .environmentObject(launchCoordinator)
        }
        .defaultSize(width: 280, height: 420)
        .windowResizability(.contentSize)
    }
}

/// Invisible helper that runs once at cold launch to wire the (view-free,
/// window-free) app delegate and coordinator together and capture the
/// `openWindow` action — kept out of `ContentView` itself so that file never
/// needs to change for this. After that one-time hookup, reacting to the
/// launch signal no longer depends on this view (or any window) still being
/// alive: `AppDelegate.applicationDidBecomeActive` handles it from then on.
private struct LaunchWindowOpener: View {
    @ObservedObject var coordinator: LaunchCoordinator
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .onAppear {
                coordinator.openWindow = openWindow
                appDelegate.coordinator = coordinator
                coordinator.checkForPendingProject()
            }
    }
}
