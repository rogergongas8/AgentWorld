import Combine
import Foundation
import SwiftUI

/// Lets the `claude` shell wrapper tell an already-running (or freshly
/// launching) AgentWorld which project to show in the companion window,
/// without any IPC/URL-scheme machinery: the wrapper writes the project path
/// to a well-known file before activating the app, and this reads/consumes
/// it. Simpler and lower-risk than registering a custom URL scheme, which
/// would require editing the Xcode project's Info.plist generation.
@MainActor
final class LaunchCoordinator: ObservableObject {
    @Published private(set) var pendingProjectPath: URL?

    /// Captured once from whichever view happens to be alive when the app
    /// first launches (see `LaunchWindowOpener`), then reused afterward even
    /// if that view — and every window — later closes. `OpenWindowAction` is
    /// a stable handle into the app's scene system, not tied to the
    /// lifetime of the view that read it from the environment.
    var openWindow: OpenWindowAction?

    private var signalFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/agentworld/pending-project", isDirectory: false)
    }

    /// Reads and consumes (deletes) the signal file if present, and opens
    /// the companion window for it. Safe to call repeatedly — a no-op once
    /// there's nothing pending. Deliberately triggered from an app-level
    /// hook (`applicationDidBecomeActive`, see `AppDelegate`), not a view's
    /// `.onAppear`/`.onReceive`: those stop firing once their window closes,
    /// but the whole point is to react even when every window is closed.
    func checkForPendingProject() {
        let url = signalFileURL
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: url)

        let path = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        pendingProjectPath = URL(fileURLWithPath: path)
        openWindow?(id: "companion")
    }
}

/// Bridges `applicationDidBecomeActive` — an app-level lifecycle event that
/// fires regardless of whether any window is open — to the coordinator.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var coordinator: LaunchCoordinator?

    func applicationDidBecomeActive(_ notification: Notification) {
        coordinator?.checkForPendingProject()
    }
}
