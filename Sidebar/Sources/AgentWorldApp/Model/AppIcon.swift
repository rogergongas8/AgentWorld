import AgentWorldArt
import AgentWorldKit
import AppKit
import Foundation
import TerminalUI

/// Draws the app icon from the same pixel art: a terminal window with three
/// crew members inside, for any CLI (no brand's character). Used by
/// `scripts/build-app.sh` through `AgentWorldApp --render-icon <dir.iconset>`.
enum AppIcon {
    /// Candidate crew for the icon, side by side (`--render-crew <png>`), to pick contrasting colors.
    static func renderCandidates(_ names: [String], to path: String) {
        var p = PixelCanvas(width: names.count * 12 + 2, height: 16)
        for (index, name) in names.enumerated() {
            _ = CharacterPainter.drawCrew(on: &p, look: CharacterLook(name: name), x: 1 + index * 12, ground: 15, pose: Pose())
        }
        if let image = p.cgImage(factor: 12) {
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }

    static func renderIconset(to directory: String) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let art = canvas()
        for size in [16, 32, 128, 256, 512] {
            for retina in [1, 2] {
                let pixels = size * retina
                let factor = max(1, pixels / art.width)
                guard let image = art.cgImage(factor: factor) else { continue }
                let rep = NSBitmapImageRep(cgImage: image)
                // Nearest-neighbour resample to the exact size macOS wants.
                let target = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                              samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                              bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: target)
                NSGraphicsContext.current?.imageInterpolation = .none
                rep.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
                NSGraphicsContext.restoreGraphicsState()
                let name = "icon_\(size)x\(size)" + (retina == 2 ? "@2x" : "") + ".png"
                try? target.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
            }
        }
    }

    /// Any CLI, not one: a terminal window with its prompt, and three
    /// crew members of no particular brand standing inside it. A margin
    /// around the window, like every macOS icon.
    static func canvas() -> PixelCanvas {
        let size = 48, o = 4, w = 40
        var p = PixelCanvas(width: size, height: size)
        let tile = RGB(hex: 0x0D1014)
        let bar = RGB(hex: 0x222831)
        p.rect(x: o, y: o, width: w, height: w, tile)
        // Title bar with the three buttons.
        p.rect(x: o, y: o, width: w, height: 6, bar)
        for (index, color) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            p.rect(x: o + 3 + index * 4, y: o + 2, width: 2, height: 2, RGB(hex: UInt32(color)))
        }
        // The prompt: "›" and a cursor.
        let prompt = RGB(hex: 0x56D364)
        for (x, y) in [(0, 0), (1, 1), (2, 2), (1, 3), (0, 4)] { p[o + 3 + x, o + 9 + y] = prompt }
        p.rect(x: o + 8, y: o + 13, width: 5, height: 1, Theme.cream)
        // Three of the crew, each its own color, on a line of ground.
        let ground = o + w - 4
        p.rect(x: o, y: ground, width: w, height: 1, RGB(hex: 0x3FA34D))
        p.rect(x: o, y: ground + 1, width: w, height: 3, RGB(hex: 0x6B4F3A))
        let crew = ["tester", "scout", "runner"].map(CharacterLook.init(name:))
        let poses = [Pose(), Pose(leftArm: .up, rightArm: .up, eyes: .happy), Animator.waving(t: 0.2)]
        for (index, look) in crew.enumerated() {
            _ = CharacterPainter.drawCrew(on: &p, look: look, x: o + 3 + index * 12, ground: ground, pose: poses[index])
        }
        roundCorners(&p, x: o, y: o, size: w)
        return p
    }

    /// Clips a 3-pixel rounding off each corner of the square at (x, y).
    private static func roundCorners(_ p: inout PixelCanvas, x: Int, y: Int, size: Int) {
        let cut = [(0, 0), (1, 0), (2, 0), (0, 1), (0, 2)]
        for (dx, dy) in cut {
            p[x + dx, y + dy] = nil
            p[x + size - 1 - dx, y + dy] = nil
            p[x + dx, y + size - 1 - dy] = nil
            p[x + size - 1 - dx, y + size - 1 - dy] = nil
        }
        // A softer edge: the pixel just inside each corner.
        p[x + 1, y + 1] = nil
        p[x + size - 2, y + 1] = nil
        p[x + 1, y + size - 2] = nil
        p[x + size - 2, y + size - 2] = nil
    }
}
