import AgentWorldKit
import AppKit
import Foundation
import SwiftUI

/// A test hook, off unless `AGENTWORLD_DEBUG_CONTROL=<file>` is set: the app
/// reads one command per line from that file (then empties it), so scripts
/// can drive it and take window snapshots without Screen Recording access.
///
///     snapshot /tmp/shot.png     launch <profile name>     launcher
///     inspector on|off           folder <path>       type <text>
///     launch-many <name>,<name>…  layout grid|columns|rows|main
///     broadcast <text>           zoom <pane index>|off
///     hittest <x> <y> <file>     which view a click there lands on
///     settings                   open Settings; snapshot-key <png> shoots it
@MainActor
enum DebugControl {
    static func start(model: AppModel) {
        guard let path = ProcessInfo.processInfo.environment["AGENTWORLD_DEBUG_CONTROL"] else { return }
        FileManager.default.createFile(atPath: path, contents: Data())
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            Task { @MainActor in poll(path: path, model: model) }
        }
    }

    private static func poll(path: String, model: AppModel) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8), !text.isEmpty else { return }
        try? "".write(toFile: path, atomically: true, encoding: .utf8)
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            let argument = parts.count > 1 ? parts[1] : ""
            switch parts.first {
            case "snapshot": snapshot(to: argument)
            case "panel": model.enterPanel()
            case "commit": model.showsCommit = true
            case "map": model.openProjectMap()
            case "map-symbols": model.buildProjectMap(model.selectedFolder, symbols: argument != "off")
            case "map-select": model.mapFocus = argument
            case "palette":
                model.paletteSeed = argument
                model.showsPalette = false
                DispatchQueue.main.async { model.showsPalette = true }
            case "grid":
                // grid <rows> <columns> <profile name>: what the grid picker does on a click.
                let words = argument.split(separator: " ", maxSplits: 2).map(String.init)
                if words.count == 3, let rows = Int(words[0]), let columns = Int(words[1]),
                   let profile = model.profiles.first(where: { $0.name == words[2] }) {
                    model.launchGrid(profile, rows: rows, columns: columns, in: model.selectedFolder)
                }
            case "resume": model.resume(in: model.selectedFolder)
            case "size":
                // size <width> <height>: resize the main window (points).
                let numbers = argument.split(separator: " ").compactMap { Double($0) }
                if numbers.count == 2, let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) {
                    var frame = window.frame
                    frame.origin.y += frame.height - numbers[1]
                    frame.size = NSSize(width: numbers[0], height: numbers[1])
                    window.setFrame(frame, display: true)
                }
            case "rename-tab": model.selectedTab?.customTitle = argument.isEmpty ? nil : argument
            case "render-usage":
                // render-usage <png>: the usage popover, drawn offscreen.
                if let usage = model.usage {
                    let renderer = ImageRenderer(content: UsagePopover(usage: usage).environmentObject(model))
                    renderer.scale = 2
                    if let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: argument))
                    }
                }
            case "keys":
                // keys <text>: typed through the key router; {esc} {bs} {down} {up} {ret} {tab} for the rest.
                keys(argument, model: model)
            case "settings":
                // settings [tab]: general, terminal, clis, notifications, integrations, shortcuts
                if !argument.isEmpty { UserDefaults.standard.set(argument, forKey: "settingsTab") }
                model.openSettings()
            case "snapshot-key":
                // The key window (Settings, a sheet's window) instead of the main one.
                let main = NSApp.windows.first { $0.isVisible && $0.contentView != nil }
                if let window = NSApp.windows.last(where: { $0.isVisible && $0 !== main && $0.frame.width > 200 }) ?? NSApp.keyWindow, let view = window.contentView?.superview ?? window.contentView,
                   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: argument))
                }
            case "snapshot-layers": snapshotLayers(to: argument)
            case "snapshot-window": snapshotWindow(to: argument)
            case "dump": dump(model: model, to: argument)
            case "windows":
                let list = NSApp.windows.map { "\($0.title) visible=\($0.isVisible) key=\($0.isKeyWindow) \(Int($0.frame.width))x\(Int($0.frame.height))" }
                let menu = (NSApp.mainMenu?.items.first?.submenu?.items ?? []).map { "menu: \($0.title) \($0.action.map(NSStringFromSelector) ?? "-")" }
                try? (list + menu).joined(separator: "\n").write(toFile: argument, atomically: true, encoding: .utf8)
            case "hittest":
                // hittest <x> <y> <file>: which view a click at x, y (points from the top left) lands on.
                let words = argument.split(separator: " ").map(String.init)
                if words.count == 3, let x = Double(words[0]), let y = Double(words[1]),
                   let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                   let frame = window.contentView?.superview {
                    let point = NSPoint(x: x, y: frame.bounds.height - y)
                    let hit = frame.hitTest(point)
                    var chain: [String] = []
                    var view = hit
                    while let current = view, chain.count < 6 { chain.append(String(describing: type(of: current))); view = current.superview }
                    try? chain.joined(separator: " < ").write(toFile: words[2], atomically: true, encoding: .utf8)
                }
            case "act":
                // act <pane index> <status> [action text], e.g. `act 0 running Bash swift test`
                let words = argument.split(separator: " ", maxSplits: 2).map(String.init)
                if words.count >= 2, let index = Int(words[0]), model.allSessions.indices.contains(index),
                   let status = ActorStatus(rawValue: words[1]) {
                    model.allSessions[index].forcedActivity = (status, words.count > 2 ? words[2] : nil)
                    model.allSessions[index].refresh(now: Date())
                }
            case "activate": NSApp.activate(ignoringOtherApps: true); NSApp.windows.first?.makeKeyAndOrderFront(nil)
            case "launcher": model.showsLauncher = true
            case "inspector": model.showsInspector = argument != "off"
            case "folder": model.select(folder: argument)
            case "launch":
                if let profile = model.profiles.first(where: { $0.name == argument }) { model.launch(profile, in: model.selectedFolder) }
            case "launch-many":
                let names = argument.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                model.launchTogether(names.compactMap { name in model.profiles.first { $0.name == name } }, in: model.selectedFolder)
            case "layout":
                if let layout = TileLayout(rawValue: argument) { model.selectedTab?.layout = layout }
            case "broadcast":
                if let tab = model.selectedTab { model.broadcast(argument, to: tab, submit: true) }
            case "zoom":
                let tab = model.selectedTab
                tab?.zoomedID = Int(argument).flatMap { tab?.sessions.indices.contains($0) == true ? tab?.sessions[$0].id : nil }
            case "render-card":
                // render-card <skill or agent name> <png>: the detail popover, drawn offscreen.
                let words = argument.split(separator: " ", maxSplits: 1).map(String.init)
                if words.count == 2 { renderCard(named: words[0], to: words[1], model: model) }
            case "keys":
                // keys down down return | esc | u… : fed to the key router like real presses.
                for name in argument.split(separator: " ").map(String.init) { press(name, model: model) }
            case "panel": if argument == "on" { model.enterPanel() } else { model.leavePanel() }
            case "shortcuts": model.showsShortcuts = argument != "off"
            case "type":
                model.selectedTab?.sessions.first?.type(argument)
            default: break
            }
        }
    }

    private static func press(_ name: String, model: AppModel) {
        let codes: [String: (UInt16, String)] = [
            "down": (125, ""), "up": (126, ""), "right": (124, ""), "left": (123, ""),
            "return": (36, "\r"), "esc": (53, "\u{1b}"), "tab": (48, "\t"),
        ]
        let (code, characters) = codes[name] ?? (0, name)
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                           windowNumber: NSApp.windows.first?.windowNumber ?? 0, context: nil,
                                           characters: characters, charactersIgnoringModifiers: characters,
                                           isARepeat: false, keyCode: code) else { return }
        _ = model.route(event)
    }

    private static func renderCard(named name: String, to path: String, model: AppModel) {
        let config = model.config(.claude, in: model.selectedFolder)
        let item: KitItem? = config.skills.first { $0.name == name }.map(KitItem.skill)
            ?? config.agents.first { $0.name == name }.map(KitItem.agent)
        guard let item else { return }
        let card = KitDetailCard(item: item, session: model.selectedTab?.sessions.first, provider: .claude, use: {}, isPresented: .constant(true))
            .environmentObject(model)
            .preferredColorScheme(.dark)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private static func keys(_ text: String, model: AppModel) {
        let named: [String: (UInt16, String)] = ["esc": (53, "\u{1b}"), "bs": (51, "\u{7f}"), "down": (125, "\u{F701}"),
                                                 "up": (126, "\u{F700}"), "ret": (36, "\r"), "tab": (48, "\t")]
        var tokens: [(UInt16, String)] = []
        var rest = Substring(text)
        while let first = rest.first {
            if first == "{", let close = rest.firstIndex(of: "}"), let key = named[String(rest[rest.index(after: rest.startIndex)..<close])] {
                tokens.append(key)
                rest = rest[rest.index(after: close)...]
            } else {
                tokens.append((first == " " ? 49 : 0, String(first)))
                rest = rest.dropFirst()
            }
        }
        for (code, characters) in tokens {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                               context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                               isARepeat: false, keyCode: code) else { continue }
            _ = model.route(event)
        }
    }

    private static func snapshot(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// The window as the window server composites it (our own window needs
    /// no Screen Recording permission). Looked up at runtime: the call is
    /// deprecated and hidden from newer SDKs.
    private static func snapshotWindow(to path: String) {
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return }
        let capture = unsafeBitCast(symbol, to: Capture.self)
        // .optionIncludingWindow = 1 << 3; .boundsIgnoreFraming = 1 << 0, .bestResolution = 1 << 3.
        guard let image = capture(.null, 1 << 3, UInt32(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue() else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// Each pane's text and look, for checking terminals without pixels.
    private static func dump(model: AppModel, to path: String) {
        var out = "occlusion visible: \(NSApp.windows.first?.occlusionState.contains(.visible) ?? false) badge: \(NSApp.dockTile.badgeLabel ?? "none") active: \(NSApp.isActive)\n"
        for (index, session) in model.allSessions.enumerated() {
            let view = session.terminal
            let text = String(decoding: view.getTerminal().getBufferAsData(), as: UTF8.self)
                .split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.suffix(4).joined(separator: " ⏎ ")
            out += "[\(index)] \(session.label) frame=\(view.frame.size) bg=\(view.nativeBackgroundColor) layerBg=\(view.layer?.backgroundColor.map { "\($0)" } ?? "nil") window=\(view.window != nil)\n    \(text)\n"
        }
        try? out.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Renders the layer tree instead: catches layer backgrounds (which
    /// `cacheDisplay` skips) as the window really composites them.
    private static func snapshotLayers(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView, let layer = view.layer else { return }
        let scale = window.backingScaleFactor
        let size = view.bounds.size
        guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.scaleBy(x: scale, y: scale)
        if !view.isFlipped {
            // Layers render top-down.
        }
        layer.render(in: context)
        guard let image = context.makeImage() else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
