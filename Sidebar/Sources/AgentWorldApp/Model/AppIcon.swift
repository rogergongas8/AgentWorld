import AgentWorldArt
import AgentWorldKit
import AppKit
import Foundation
import TerminalUI

/// Draws the app icon from the same pixel art: Claude on a dark, rounded
/// tile with a strip of ground and two crew members peeking in. Used by
/// `scripts/build-app.sh` through `AgentWorldApp --render-icon <dir.iconset>`.
enum AppIcon {
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

    static func canvas() -> PixelCanvas {
        let size = 32
        var p = PixelCanvas(width: size, height: size)
        let tile = RGB(hex: 0x13171C)
        // Rounded tile: fill, then clip the corners.
        p.rect(x: 1, y: 1, width: size - 2, height: size - 2, tile)
        for (x, y) in [(1, 1), (2, 1), (1, 2), (size - 2, 1), (size - 3, 1), (size - 2, 2),
                       (1, size - 2), (2, size - 2), (1, size - 3), (size - 2, size - 2), (size - 3, size - 2), (size - 2, size - 3)] {
            p[x, y] = nil
        }
        // Stars.
        for (x, y) in [(6, 5), (24, 4), (27, 9), (10, 8)] { p[x, y] = Theme.muted }
        // Ground.
        p.rect(x: 2, y: 25, width: size - 4, height: 1, RGB(hex: 0x3FA34D))
        p.rect(x: 2, y: 26, width: size - 4, height: 4, RGB(hex: 0x6B4F3A))
        p.rect(x: 3, y: 30, width: size - 6, height: 1, RGB(hex: 0x6B4F3A))
        // Claude in the middle, waving.
        CharacterPainter.drawClaude(on: &p, x: 8, ground: 25, pose: Animator.waving(t: 0))
        return p
    }
}
