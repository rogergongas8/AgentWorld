import AppKit

/// Generic color *roles* a sprite cell can play. Kept costume-agnostic (not
/// "shirt"/"pants") so every costume can reuse the same cell vocabulary while
/// mapping each role to its own colors — a hard hat and a space helmet are
/// both `.hat`, just colored differently.
enum PixelCellKind: Equatable {
    case empty
    case skin
    case hat
    case hair
    case visor
    case suitPrimary
    case suitSecondary
    case sleeve
    case boot
    case accent
    case eye
    case mouth
}

/// One of a small roster of character professions. Each agent is assigned a
/// costume deterministically from its name (see `forAgent`), so the same
/// agent always looks the same, and different agents read as visibly
/// different little workers rather than clones of one generic robot.
enum PixelCostume: CaseIterable {
    case architect
    case lumberjack
    case astronaut

    static func forAgent(named name: String?) -> PixelCostume {
        let seed = abs((name ?? "claude").lowercased().hashValue)
        return allCases[seed % allCases.count]
    }

    /// Fixed, costume-defining colors — an architect's hard hat is always
    /// safety yellow, an astronaut's suit is always white, regardless of
    /// which agent wears it. Recognizability comes from the costume, not a
    /// per-agent hue.
    func color(for kind: PixelCellKind, accent: NSColor) -> NSColor {
        switch (self, kind) {
        case (_, .empty): .clear
        case (_, .skin): NSColor(hue: 0.08, saturation: 0.35, brightness: 0.9, alpha: 1)
        case (_, .accent): accent
        // Regular faces: dark eyes/mouth on skin. The astronaut overrides
        // `.eye` below to glow through the visor instead, and never places
        // `.mouth` at all (hidden under the helmet bubble).
        case (.architect, .eye), (.lumberjack, .eye): NSColor(white: 0.12, alpha: 1)
        case (.architect, .mouth), (.lumberjack, .mouth): NSColor(white: 0.2, alpha: 1)
        case (.astronaut, .mouth): .clear

        case (.architect, .hat): NSColor(hue: 0.13, saturation: 0.85, brightness: 0.95, alpha: 1)
        case (.architect, .hair): NSColor(hue: 0.08, saturation: 0.4, brightness: 0.35, alpha: 1)
        case (.architect, .suitPrimary): NSColor(hue: 0.58, saturation: 0.35, brightness: 0.85, alpha: 1)
        case (.architect, .sleeve): NSColor(hue: 0.58, saturation: 0.4, brightness: 0.65, alpha: 1)
        case (.architect, .suitSecondary): NSColor(hue: 0.6, saturation: 0.25, brightness: 0.35, alpha: 1)
        case (.architect, .boot): NSColor(hue: 0.08, saturation: 0.3, brightness: 0.25, alpha: 1)
        case (.architect, .visor): .clear

        case (.lumberjack, .hat): NSColor(hue: 0.02, saturation: 0.75, brightness: 0.55, alpha: 1)
        case (.lumberjack, .hair): NSColor(hue: 0.07, saturation: 0.5, brightness: 0.3, alpha: 1)
        case (.lumberjack, .suitPrimary): NSColor(hue: 0.02, saturation: 0.7, brightness: 0.75, alpha: 1)
        case (.lumberjack, .sleeve): NSColor(hue: 0.02, saturation: 0.75, brightness: 0.55, alpha: 1)
        case (.lumberjack, .suitSecondary): NSColor(hue: 0.6, saturation: 0.35, brightness: 0.3, alpha: 1)
        case (.lumberjack, .boot): NSColor(hue: 0.08, saturation: 0.45, brightness: 0.22, alpha: 1)
        case (.lumberjack, .visor): .clear

        case (.astronaut, .hat): NSColor(white: 0.92, alpha: 1)
        case (.astronaut, .hair): NSColor(white: 0.92, alpha: 1)
        case (.astronaut, .visor): NSColor(hue: 0.55, saturation: 0.4, brightness: 0.25, alpha: 1)
        case (.astronaut, .eye): accent
        case (.astronaut, .suitPrimary): NSColor(white: 0.95, alpha: 1)
        case (.astronaut, .sleeve): NSColor(white: 0.85, alpha: 1)
        case (.astronaut, .suitSecondary): NSColor(white: 0.8, alpha: 1)
        case (.astronaut, .boot): NSColor(white: 0.55, alpha: 1)
        }
    }
}

/// The sprite's shape, defined as named rectangular regions rather than
/// hand-aligned ASCII art — far less error-prone to get right, and just as
/// much a real pixel grid once rasterized. A 16-wide × 22-tall canvas gives
/// legs real vertical room; a 16×16 square left them as a stubby 3-row strip
/// that read as almost no legs at all.
enum PixelCharacterSprite {
    static let width = 16
    static let height = 22

    static func grid(costume: PixelCostume, armsUp: Bool) -> [[PixelCellKind]] {
        var grid = Array(repeating: Array(repeating: PixelCellKind.empty, count: width), count: height)
        func fill(_ rows: ClosedRange<Int>, _ cols: ClosedRange<Int>, _ kind: PixelCellKind) {
            for row in rows {
                for col in cols {
                    grid[row][col] = kind
                }
            }
        }

        // Shared base: head, face, torso, arms, legs. Costumes then layer
        // their own headwear/visor/accents on top of this common frame.
        fill(3...7, 5...10, .skin)                      // head
        fill(5...5, 6...6, .eye)
        fill(5...5, 9...9, .eye)
        fill(7...7, 7...8, .mouth)
        fill(8...15, 4...11, .suitPrimary)              // torso
        // Arms sit one empty column away from the torso on each side (cols
        // 3 and 12 stay empty) so the automatic outline pass draws a real
        // border between them — flush against the torso, same-colored boxes
        // just visually merge into it instead of reading as arms.
        let armRows = armsUp ? (6...10) : (9...13)
        fill(armRows, 1...2, .sleeve)                   // left arm
        fill(armRows, 13...14, .sleeve)                 // right arm
        fill(16...20, 4...6, .suitSecondary)            // left leg
        fill(16...20, 9...11, .suitSecondary)           // right leg
        fill(21...21, 4...6, .boot)
        fill(21...21, 9...11, .boot)
        fill(12...12, 7...8, .accent)                   // chest accent light

        switch costume {
        case .architect:
            fill(1...2, 4...11, .hat)                   // hard hat brim, wide and flat
            fill(3...3, 5...10, .hat)                   // hard hat dome overlapping hairline
            fill(9...9, 7...8, .suitSecondary)          // tie knot
            fill(10...14, 7...8, .suitSecondary)        // tie
        case .lumberjack:
            fill(1...2, 5...10, .hat)                   // beanie
            fill(7...7, 5...10, .hair)                  // beard along the jaw (covers the mouth — a beard would)
            fill(9...9, 4...11, .suitSecondary)         // flannel chest stripe
            fill(13...13, 4...11, .suitSecondary)       // flannel chest stripe
        case .astronaut:
            // Rounded helmet silhouette: narrower at top/bottom rows than
            // the shared head block, so it reads as a bubble, not a box.
            fill(2...2, 6...9, .hat)
            fill(3...7, 4...11, .hat)
            fill(8...8, 5...10, .hat)
            fill(4...5, 5...10, .visor)                 // visor band across the bubble
            fill(5...5, 6...6, .eye)                    // eyes glow through the visor
            fill(5...5, 9...9, .eye)
            fill(16...20, 4...11, .suitPrimary)         // suit legs match the body, not separate pants
        }

        return grid
    }
}

/// One frame's worth of pose data, computed as a pure function of status and
/// elapsed time. Offsets are whole pixels, not sub-pixel floats — smooth
/// interpolation would blur the "chunky" retro-sprite look; real pixel art
/// animates by snapping between discrete positions/frames.
struct PixelPose {
    var armsUp = false
    var verticalOffset = 0
    var horizontalOffset = 0
    var accentColor: NSColor = .white
    var tint: NSColor?

    static func forStatus(_ status: AgentStatus, elapsed: TimeInterval) -> PixelPose {
        var pose = PixelPose()
        switch status {
        case .idle:
            pose.verticalOffset = Int(elapsed * 1.2) % 2
            pose.accentColor = .white
        case .thinking:
            pose.verticalOffset = Int(elapsed * 1.2) % 2
            pose.accentColor = Int(elapsed * 2) % 2 == 0 ? .systemYellow : .white
            pose.tint = NSColor.systemYellow.withAlphaComponent(0.25)
        case .reading:
            pose.accentColor = .systemCyan
            pose.tint = NSColor.systemCyan.withAlphaComponent(0.2)
        case .working:
            pose.armsUp = true
            pose.verticalOffset = Int(elapsed * 6) % 2
            pose.accentColor = Int(elapsed * 4) % 2 == 0 ? .systemGreen : .white
            pose.tint = NSColor.systemGreen.withAlphaComponent(0.25)
        case .waiting:
            pose.accentColor = .systemBlue
            pose.tint = NSColor.systemBlue.withAlphaComponent(0.2)
        case .completed:
            pose.armsUp = true
            pose.accentColor = .systemGreen
            pose.tint = NSColor.systemGreen.withAlphaComponent(0.4)
        case .error:
            pose.horizontalOffset = Int(elapsed * 10) % 2 == 0 ? -1 : 1
            pose.accentColor = .systemRed
            pose.tint = NSColor.systemRed.withAlphaComponent(0.35)
        }
        return pose
    }
}
