import AgentWorldArt
import AgentWorldKit
import AppKit
import SwiftUI
import TerminalUI

/// The app's look: a terminal at night. Dark surfaces, monospaced type,
/// the same accent colors as the terminal sidebar.
enum Palette {
    static let background = Color(rgb: RGB(hex: 0x0D1014))
    static let panel = Color(rgb: RGB(hex: 0x13171C))
    static let raised = Color(rgb: RGB(hex: 0x1A1F26))
    static let hover = Color(rgb: RGB(hex: 0x222831))
    static let selected = Color(rgb: RGB(hex: 0x2A3039))
    static let border = Color(rgb: RGB(hex: 0x262C34))
    static let terminalBackgroundRGB = RGB(hex: 0x0B0E12)
    static let terminalBackground = Color(rgb: terminalBackgroundRGB)

    static let text = Color(rgb: Theme.text)
    static let cream = Color(rgb: Theme.cream)
    static let muted = Color(rgb: Theme.muted)
    static let faint = Color(rgb: Theme.faint)
    static let claude = Color(rgb: Theme.claude)
    static let live = Color(rgb: Theme.live)
    static let warning = Color(rgb: Theme.warning)
    static let error = Color(rgb: Theme.error)
    static let skill = Color(rgb: Theme.color(for: .skill))
    static let agent = Color(rgb: Theme.color(for: .agent))
    static let mcp = Color(rgb: Theme.color(for: .mcp(server: "", tool: "")))
}

extension Color {
    init(rgb: RGB) {
        self.init(.sRGB, red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255, opacity: 1)
    }
}

extension NSColor {
    convenience init(rgb: RGB) {
        self.init(srgbRed: CGFloat(rgb.r) / 255, green: CGFloat(rgb.g) / 255, blue: CGFloat(rgb.b) / 255, alpha: 1)
    }
}

extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension TerminalSession.Status.Tone {
    var color: Color {
        switch self {
        case .busy: Palette.live
        case .needsYou: Palette.warning
        case .idle: Palette.faint
        case .ended: Palette.error.opacity(0.7)
        }
    }
}

// MARK: - Pixel art

extension PixelCanvas {
    /// The pixels as a crisp image, each pixel repeated `factor`×`factor`
    /// times so no scaling step can blur it (transparent where nothing is drawn).
    func cgImage(factor: Int = 1) -> CGImage? {
        guard width > 0, height > 0, factor > 0 else { return nil }
        let outWidth = width * factor, outHeight = height * factor
        var bytes = [UInt8](repeating: 0, count: outWidth * outHeight * 4)
        for y in 0..<outHeight {
            for x in 0..<outWidth {
                guard let color = self[x / factor, y / factor] else { continue }
                let i = (y * outWidth + x) * 4
                bytes[i] = color.r
                bytes[i + 1] = color.g
                bytes[i + 2] = color.b
                bytes[i + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: outWidth, height: outHeight, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: outWidth * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// A pixel canvas scaled up with hard edges.
struct PixelImage: View {
    let canvas: PixelCanvas
    /// Screen points per pixel.
    var scale: CGFloat = 3

    var body: some View {
        // Rendered at the screen's pixel size (2× on Retina), shown 1:1.
        if let image = canvas.cgImage(factor: max(1, Int((scale * 2).rounded()))) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: CGFloat(canvas.width) * scale, height: CGFloat(canvas.height) * scale)
        }
    }
}

/// A character's face, gently animated (idle breathing, waving when active,
/// working when busy).
struct FaceView: View {
    let figure: CharacterFigure
    var scale: CGFloat = 3
    var waving = false
    var busy = false
    var sleeping = false
    var seed = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.15)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pose = busy ? Animator.pose(status: .running, elapsed: 1, t: t, seed: seed, recentError: false)
                : waving ? Animator.waving(t: t)
                : Animator.pose(status: .idle, elapsed: sleeping ? Animator.sleepAfter + 1 : 0, t: t, seed: seed, recentError: false)
            PixelImage(canvas: Face.render(figure, pose: pose), scale: scale)
        }
    }
}

/// A full-body portrait for profile headers.
struct PortraitView: View {
    let figure: CharacterFigure
    var scale: CGFloat = 5
    var busy = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.12)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pose = busy ? Animator.pose(status: .running, elapsed: 1, t: t, seed: 1, recentError: false) : Animator.waving(t: t)
            PixelImage(canvas: Self.canvas(figure, pose: pose), scale: scale)
        }
    }

    static func canvas(_ figure: CharacterFigure, pose: Pose) -> PixelCanvas {
        let size = figure.isClaude ? CharacterPainter.claudeSize : CharacterPainter.crewSize
        var pixels = PixelCanvas(width: size.width + 2, height: size.height + 3)
        let ground = pixels.height - 1
        switch figure {
        case .claude: CharacterPainter.drawClaude(on: &pixels, x: 1, ground: ground, pose: pose)
        case .crew(let look): CharacterPainter.drawCrew(on: &pixels, look: look, x: 1, ground: ground, pose: pose)
        }
        return pixels
    }
}

extension CharacterFigure {
    var isClaude: Bool {
        if case .claude = self { return true }
        return false
    }
}

extension Provider {
    var swiftColor: Color { Color(rgb: color) }
}

// MARK: - Small building blocks

/// A section title in the terminal style: "── WORKSPACES ────".
struct SectionTitle: View {
    let title: String
    var color: Color = Palette.muted
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.mono(10.5, .semibold))
                .foregroundStyle(color)
                .tracking(1.2)
            Rectangle().fill(Palette.border).frame(height: 1)
            if let trailing { trailing }
        }
    }
}

/// A rounded, hover-aware surface.
struct HoverCard<Content: View>: View {
    var selected = false
    var accent: Color = Palette.claude
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        content
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Palette.selected : hovering ? Palette.hover : Palette.raised))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? accent : hovering ? accent.opacity(0.5) : Palette.border, lineWidth: 1))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct StatusDot: View {
    let tone: TerminalSession.Status.Tone
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(tone.color)
            .frame(width: 7, height: 7)
            .opacity(tone == .busy && pulse ? 0.35 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever()) { pulse = true }
            }
    }
}
