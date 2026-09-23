import AppKit
import CoreGraphics
import Foundation

/// The app icon, drawn as vectors at every size macOS asks for: a terminal
/// prompt (`›_`, any CLI or a plain shell) inside an orbit (the world) with
/// three agents traveling on it. It fills Apple's icon squircle exactly, so
/// macOS doesn't set it on a grey plate. Used by `scripts/build-app.sh`
/// through `AgentWorldApp --render-icon <dir.iconset>`.
enum AppIcon {
    static func renderIconset(to directory: String) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for retina in [1, 2] {
                let pixels = size * retina
                guard let image = render(pixels: pixels) else { continue }
                let name = "icon_\(size)x\(size)" + (retina == 2 ? "@2x" : "") + ".png"
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
            }
        }
    }

    /// The icon at `pixels` × `pixels`, drawn on Apple's 1024-point grid.
    static func render(pixels: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let scale = CGFloat(pixels) / 1024
        context.scaleBy(x: scale, y: scale)
        // Top-left origin, like the design grid.
        context.translateBy(x: 0, y: 1024)
        context.scaleBy(x: 1, y: -1)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high
        draw(in: context, detailed: pixels >= 64)
        return context.makeImage()
    }

    // MARK: - Drawing (1024 × 1024, top-left origin)

    private static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    private static func gradient(_ colors: [CGColor]) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: nil)!
    }

    /// Apple's macOS icon shape: an 824-point rounded square with smooth
    /// (continuous) corners, centered on the 1024 canvas.
    static func squircle() -> CGPath {
        let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
        return NSBezierPath(roundedRect: rect, xRadius: 186, yRadius: 186).cgPathCompat
    }

    private static func draw(in context: CGContext, detailed: Bool) {
        let shape = squircle()

        // Background: deep night, lighter at the top.
        context.saveGState()
        context.addPath(shape)
        context.clip()
        context.drawLinearGradient(gradient([color(0x262B55), color(0x10132A), color(0x07080F)]),
                                   start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
        // A soft glow behind the prompt.
        context.drawRadialGradient(gradient([color(0x6D5DF6, 0.35), color(0x6D5DF6, 0)]),
                                   startCenter: CGPoint(x: 512, y: 550), startRadius: 0,
                                   endCenter: CGPoint(x: 512, y: 550), endRadius: 400, options: [])
        context.restoreGState()

        // The orbit: a tilted ellipse around the prompt.
        let orbitCenter = CGPoint(x: 512, y: 570)
        let tilt: CGFloat = -0.32
        let radii = CGSize(width: 340, height: 132)
        var orbit = CGAffineTransform(translationX: orbitCenter.x, y: orbitCenter.y).rotated(by: tilt)
        let ellipse = CGPath(ellipseIn: CGRect(x: -radii.width, y: -radii.height, width: radii.width * 2, height: radii.height * 2),
                             transform: &orbit)
        context.saveGState()
        context.addPath(ellipse)
        context.setLineWidth(detailed ? 18 : 26)
        context.setStrokeColor(color(0xFFFFFF, detailed ? 0.22 : 0.3))
        context.strokePath()
        context.restoreGState()

        // The prompt: a bold chevron and a cursor, in a teal → violet gradient.
        let chevron = CGMutablePath()
        chevron.move(to: CGPoint(x: 336, y: 416))
        chevron.addLine(to: CGPoint(x: 484, y: 552))
        chevron.addLine(to: CGPoint(x: 336, y: 688))
        let stroke = chevron.copy(strokingWithWidth: 82, lineCap: .round, lineJoin: .round, miterLimit: 10)
        let cursor = CGPath(roundedRect: CGRect(x: 540, y: 646, width: 190, height: 66), cornerWidth: 33, cornerHeight: 33, transform: nil)
        let glyphs = CGMutablePath()
        glyphs.addPath(stroke)
        glyphs.addPath(cursor)
        // A shadow so the glyph lifts off the orbit.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 10), blur: 30, color: color(0x000000, 0.5))
        context.addPath(glyphs)
        context.setFillColor(color(0x5EEAD4))
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(glyphs)
        context.clip()
        context.drawLinearGradient(gradient([color(0x5EEAD4), color(0x8B9CFF), color(0xB794F6)]),
                                   start: CGPoint(x: 330, y: 410), end: CGPoint(x: 730, y: 710), options: [])
        context.restoreGState()

        // Three agents on the orbit, each its own color, ringed in the night.
        // Left, top right and right: around the prompt, never on it.
        let agents: [(angle: CGFloat, hex: UInt32)] = [(-2.3, 0xF472B6), (-0.6, 0xFBBF24), (0.45, 0x34D399)]
        for agent in agents {
            let local = CGPoint(x: cos(agent.angle) * radii.width, y: sin(agent.angle) * radii.height)
            let point = local.applying(CGAffineTransform(translationX: orbitCenter.x, y: orbitCenter.y).rotated(by: tilt))
            let radius: CGFloat = detailed ? 40 : 56
            let ring: CGFloat = detailed ? 8 : 12
            context.addEllipse(in: CGRect(x: point.x - radius - ring, y: point.y - radius - ring, width: (radius + ring) * 2, height: (radius + ring) * 2))
            context.setFillColor(color(0x0B0D1A))
            context.fillPath()
            context.saveGState()
            context.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            context.clip()
            context.drawRadialGradient(gradient([color(0xFFFFFF, 0.9), color(agent.hex), color(agent.hex)]),
                                       startCenter: CGPoint(x: point.x - radius * 0.35, y: point.y - radius * 0.35), startRadius: 0,
                                       endCenter: point, endRadius: radius, options: [.drawsAfterEndLocation])
            context.restoreGState()
        }

        // A fine light edge along the top, like glass.
        context.saveGState()
        context.addPath(shape)
        context.setLineWidth(4)
        context.setStrokeColor(color(0xFFFFFF, 0.08))
        context.strokePath()
        context.restoreGState()
    }
}

private extension NSBezierPath {
    /// `cgPath` arrived in macOS 14; this builds the same path on macOS 13.
    var cgPathCompat: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for index in 0..<elementCount {
            switch element(at: index, associatedPoints: &points) {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo, .cubicCurveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo: path.addQuadCurve(to: points[1], control: points[0])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}
