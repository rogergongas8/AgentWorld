import Foundation

public struct RGB: Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Perceived brightness, 0…1.
    public var luminance: Double {
        (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255
    }

    /// `0xRRGGBB`.
    public init(hex: UInt32) {
        self.init(UInt8((hex >> 16) & 0xFF), UInt8((hex >> 8) & 0xFF), UInt8(hex & 0xFF))
    }

    /// Linear blend towards `other` (0 = self, 1 = other).
    public func mixed(with other: RGB, _ amount: Double) -> RGB {
        let t = min(max(amount, 0), 1)
        func mix(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8((Double(a) + (Double(b) - Double(a)) * t).rounded()) }
        return RGB(mix(r, other.r), mix(g, other.g), mix(b, other.b))
    }

    public func darker(_ amount: Double) -> RGB { mixed(with: RGB(0, 0, 0), amount) }
    public func lighter(_ amount: Double) -> RGB { mixed(with: RGB(255, 255, 255), amount) }

    /// Hue in [0, 1), saturation and value in [0, 1].
    public static func hsv(_ h: Double, _ s: Double, _ v: Double) -> RGB {
        let i = Int(h * 6) % 6
        let f = h * 6 - Double(Int(h * 6))
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        let (r, g, b): (Double, Double, Double) = switch i {
        case 0: (v, t, p)
        case 1: (q, v, p)
        case 2: (p, v, t)
        case 3: (p, q, v)
        case 4: (t, p, v)
        default: (v, p, q)
        }
        return RGB(UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
    }

    /// Nearest xterm-256 palette index, for terminals without truecolor.
    public var xterm256: Int {
        func cubeIndex(_ v: UInt8) -> Int { v < 48 ? 0 : v < 115 ? 1 : (Int(v) - 35) / 40 }
        let levels = [0, 95, 135, 175, 215, 255]
        let (ri, gi, bi) = (cubeIndex(r), cubeIndex(g), cubeIndex(b))
        let cube = RGB(UInt8(levels[ri]), UInt8(levels[gi]), UInt8(levels[bi]))

        let average = (Int(r) + Int(g) + Int(b)) / 3
        let grayIndex = average > 238 ? 23 : max(0, (average - 3) / 10)
        let grayLevel = UInt8(8 + grayIndex * 10)
        let gray = RGB(grayLevel, grayLevel, grayLevel)

        return distance(to: gray) < distance(to: cube) ? 232 + grayIndex : 16 + 36 * ri + 6 * gi + bi
    }

    private func distance(to other: RGB) -> Int {
        let dr = Int(r) - Int(other.r), dg = Int(g) - Int(other.g), db = Int(b) - Int(other.b)
        return dr * dr + dg * dg + db * db
    }
}

public enum ColorMode: Sendable {
    case trueColor
    case ansi256

    /// Truecolor when the terminal advertises it (tmux forwards COLORTERM).
    public static func detect(environment: [String: String] = ProcessInfo.processInfo.environment) -> ColorMode {
        if let forced = environment["AGENTWORLD_COLOR"] {
            return forced == "256" ? .ansi256 : .trueColor
        }
        let colorTerm = environment["COLORTERM"]?.lowercased() ?? ""
        if colorTerm.contains("truecolor") || colorTerm.contains("24bit") { return .trueColor }
        if environment["TERM_PROGRAM"] == "Apple_Terminal" { return .ansi256 }
        return environment["TERM"]?.contains("direct") == true ? .trueColor : .ansi256
    }
}
