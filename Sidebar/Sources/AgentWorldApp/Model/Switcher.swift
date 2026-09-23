import AppKit
import Foundation

/// ⌃Tab, like ⌘Tab for apps: every open terminal as a card, most recently
/// used first. Hold ⌃ and press Tab to move (⇧ goes back, the arrows work
/// too), let go of ⌃ to jump there. Opened from the menu instead, ↩ picks.
struct Switcher: Equatable {
    var sessions: [UUID]
    var index: Int
    /// Opened with ⌃Tab: letting go of ⌃ picks the highlighted one.
    var holdingControl: Bool
}

extension AppModel {
    /// Remembers the terminal you're in, so ⌃Tab's first stop is the one before.
    func noteFocus() {
        guard let focused = focusedSession, recentSessionIDs.first != focused.id else { return }
        recentSessionIDs.removeAll { $0 == focused.id }
        recentSessionIDs.insert(focused.id, at: 0)
    }

    /// Open terminals, the most recently used first, then the rest in order.
    var switcherOrder: [TerminalSession] {
        let all = allSessions
        let recent = recentSessionIDs.compactMap { id in all.first { $0.id == id } }
        return recent + all.filter { session in !recent.contains { $0 === session } }
    }

    func openSwitcher(holdingControl: Bool, backwards: Bool = false) {
        let order = switcherOrder
        guard !order.isEmpty else { return }
        // Start on the one before the current terminal, like ⌘Tab.
        let current = focusedSession.flatMap { focused in order.firstIndex { $0 === focused } } ?? -1
        let start = order.count == 1 ? 0 : (backwards ? (current - 1 + order.count) % order.count : (current + 1) % order.count)
        switcher = Switcher(sessions: order.map(\.id), index: max(0, start), holdingControl: holdingControl)
    }

    func moveSwitcher(_ delta: Int) {
        guard var state = switcher, !state.sessions.isEmpty else { return }
        state.index = (state.index + delta + state.sessions.count) % state.sessions.count
        switcher = state
    }

    func commitSwitcher() {
        guard let state = switcher else { return }
        switcher = nil
        guard state.sessions.indices.contains(state.index),
              let session = allSessions.first(where: { $0.id == state.sessions[state.index] }) else { return }
        panel.isFocused = false
        reveal(session)
    }

    /// Keys for the switcher, before anything else sees them. True when used.
    func routeSwitcher(_ event: NSEvent) -> Bool {
        let control = event.modifierFlags.contains(.control)
        let shift = event.modifierFlags.contains(.shift)
        if event.keyCode == 48, control {                      // ⌃Tab / ⌃⇧Tab
            if switcher == nil { openSwitcher(holdingControl: true, backwards: shift) } else { moveSwitcher(shift ? -1 : 1) }
            return true
        }
        guard switcher != nil else { return false }
        switch event.keyCode {
        case 124, 125: moveSwitcher(1)                          // → ↓
        case 123, 126: moveSwitcher(-1)                         // ← ↑
        case 48: moveSwitcher(shift ? -1 : 1)                   // tab
        case 36, 76, 49: commitSwitcher()                       // return, space
        case 53: switcher = nil                                 // esc
        default:
            // A digit picks that card straight away.
            if let digit = event.charactersIgnoringModifiers.flatMap(Int.init), (1...9).contains(digit),
               let state = switcher, state.sessions.indices.contains(digit - 1) {
                switcher?.index = digit - 1
                commitSwitcher()
            }
        }
        return true
    }

    /// Letting go of ⌃ picks; holding ⌘ alone shows the tab numbers.
    func routeModifiers(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if let state = switcher, state.holdingControl, !flags.contains(.control) { commitSwitcher() }
        if flags == .command {
            keyBadgeTimer?.invalidate()
            keyBadgeTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.showsKeyBadges = true }
            }
        } else {
            keyBadgeTimer?.invalidate()
            keyBadgeTimer = nil
            if showsKeyBadges { showsKeyBadges = false }
        }
    }

    /// ⌘1…9: the workspace's tabs, like a browser's.
    func selectTab(number: Int) {
        let open = tabs(in: selectedFolder)
        guard open.indices.contains(number - 1) else { return }
        let tab = open[number - 1]
        selectedTabID = tab.id
        showsLauncher = false
        panel.isFocused = false
        if let session = tab.sessions.first { DispatchQueue.main.async { session.focus() } }
    }
}
