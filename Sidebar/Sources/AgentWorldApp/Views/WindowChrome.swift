import AppKit
import SwiftUI

/// Lines the traffic lights up with the tabs, the way Safari does: AppKit
/// puts them back at the top of a plain title bar after every resize or
/// full-screen change, so they're moved again each time.
struct TrafficLightAligner: NSViewRepresentable {
    /// Where the middle of the lights goes, from the top of the window.
    var centerY: CGFloat = 25
    var leading: CGFloat = 16

    final class Coordinator {
        var observers: [NSObjectProtocol] = []
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let align = { [centerY, leading] in Self.align(window, centerY: centerY, leading: leading) }
            align()
            for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                         NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification] {
                context.coordinator.observers.append(
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { _ in align() })
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private static func align(_ window: NSWindow, centerY: CGFloat, leading: CGFloat) {
        guard !window.styleMask.contains(.fullScreen) else { return }
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        // The lights' title bar is only as tall as a plain one; stretch it
        // down to the tab row so they aren't clipped.
        if let titlebar = window.standardWindowButton(.closeButton)?.superview?.superview {
            let height = centerY * 2
            titlebar.frame = NSRect(x: titlebar.frame.minX, y: window.frame.height - height, width: titlebar.frame.width, height: height)
        }
        for (index, type) in buttons.enumerated() {
            guard let button = window.standardWindowButton(type), let container = button.superview else { continue }
            let spacing: CGFloat = 20
            // The container is flipped or not depending on the macOS version.
            let y = container.isFlipped ? centerY - button.frame.height / 2
                : container.frame.height - centerY - button.frame.height / 2
            button.setFrameOrigin(NSPoint(x: leading + CGFloat(index) * spacing, y: y))
        }
    }
}
