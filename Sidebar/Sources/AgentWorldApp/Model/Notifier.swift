import AppKit
import Foundation
import UserNotifications

/// Tells you when an agent is waiting on you, so you can leave six of them
/// working and do something else: a notification (click it to jump to that
/// terminal), the Dock badge counting who's waiting, a bounce of the icon.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var lastTone: [UUID: TerminalSession.Status.Tone] = [:]
    private var busySince: [UUID: Date] = [:]
    private weak var model: AppModel?
    /// Notifications need a bundle; a bare `swift run` binary only gets the badge and bounce.
    private let center: UNUserNotificationCenter? = Bundle.main.bundleIdentifier == nil ? nil : .current()

    /// Short jobs don't deserve a ping: only after this much work.
    static let minimumWork: TimeInterval = 8

    init(model: AppModel) {
        self.model = model
        super.init()
        center?.delegate = self
        center?.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Called on every tick with every session.
    func update(_ sessions: [TerminalSession], now: Date) {
        var waiting = 0
        for session in sessions {
            let tone = session.status.tone
            let previous = lastTone[session.id]
            lastTone[session.id] = tone
            if tone == .busy, previous != .busy { busySince[session.id] = now }
            if tone == .needsYou { waiting += 1 }

            guard previous == .busy, tone == .needsYou || tone == .ended else { continue }
            let worked = busySince[session.id].map { now.timeIntervalSince($0) } ?? 0
            guard worked >= Self.minimumWork, !isWatching(session) else { continue }
            announce(session, worked: worked)
        }
        let live = Set(sessions.map(\.id))
        lastTone = lastTone.filter { live.contains($0.key) }
        busySince = busySince.filter { live.contains($0.key) }
        NSApp.dockTile.badgeLabel = waiting > 0 ? "\(waiting)" : nil
    }

    /// You're looking right at it: the app is frontmost and its pane is on screen.
    private func isWatching(_ session: TerminalSession) -> Bool {
        guard NSApp.isActive, let model, let tab = model.selectedTab, !model.showsLauncher else { return false }
        guard tab.sessions.contains(where: { $0.id == session.id }) else { return false }
        return tab.zoomedID == nil || tab.zoomedID == session.id
    }

    private func announce(_ session: TerminalSession, worked: TimeInterval) {
        NSApp.requestUserAttention(.informationalRequest)
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = session.status.tone == .ended ? "\(session.label) ended" : "\(session.label) is waiting for you"
        content.body = "In \(session.folderName) · worked \(Self.duration(worked))"
        content.sound = .default
        content.userInfo = ["session": session.id.uuidString]
        center.add(UNNotificationRequest(identifier: session.id.uuidString + "-\(Date().timeIntervalSince1970)", content: content, trigger: nil))
    }

    /// A message an agent sent with `agentworld-ctl notify`.
    func post(title: String, body: String, session: TerminalSession?) {
        NSApp.requestUserAttention(.informationalRequest)
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let session { content.userInfo = ["session": session.id.uuidString] }
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "\(Int(seconds))s" : seconds < 3600 ? "\(Int(seconds / 60))m" : "\(Int(seconds / 3600))h \(Int(seconds / 60) % 60)m"
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["session"] as? String else { return }
        await MainActor.run {
            guard let model, let session = model.allSessions.first(where: { $0.id.uuidString == id }) else { return }
            NSApp.activate(ignoringOtherApps: true)
            model.reveal(session)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
