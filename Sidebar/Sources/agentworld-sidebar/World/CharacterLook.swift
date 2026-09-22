import TerminalUI

/// How a crew member (subagent) looks. Derived deterministically from its
/// type name, so the same subagent always shows up as the same character.
struct CharacterLook {
    enum Headgear: CaseIterable {
        case antenna, cap, crown, headphones, bare, horns
    }

    enum Face: CaseIterable {
        case skin, visor
    }

    let body: RGB
    let hair: RGB
    let skin: RGB
    let accent: RGB
    let headgear: Headgear
    let face: Face

    /// Claude's own orange; subagents use the rest of the wheel.
    static let claude = CharacterLook(
        body: Theme.claude, hair: Theme.claude, skin: Theme.claude,
        accent: Theme.cream, headgear: .bare, face: .skin
    )

    init(body: RGB, hair: RGB, skin: RGB, accent: RGB, headgear: Headgear, face: Face) {
        self.body = body
        self.hair = hair
        self.skin = skin
        self.accent = accent
        self.headgear = headgear
        self.face = face
    }

    init(name: String) {
        // Mixed so similar names ("ui-reviewer", "sidebar-tester") still differ.
        let hash = Self.mixed(Self.stableHash(name.lowercased()))
        // Skip the orange band (~0.03-0.1) so nobody is mistaken for Claude.
        let hue = (0.12 + Double(hash % 1000) / 1000 * 0.86).truncatingRemainder(dividingBy: 1)
        body = RGB.hsv(hue, 0.55, 0.9)
        hair = RGB.hsv((hue + 0.5).truncatingRemainder(dividingBy: 1), 0.45, 0.55)
        let skins = [RGB(hex: 0xF1C27D), RGB(hex: 0xE0AC69), RGB(hex: 0xC68642), RGB(hex: 0x8D5524), RGB(hex: 0xFFDBAC)]
        skin = skins[Int((hash >> 10) % UInt64(skins.count))]
        accent = RGB.hsv((hue + 0.33).truncatingRemainder(dividingBy: 1), 0.7, 1)
        headgear = Headgear.allCases[Int((hash >> 16) % UInt64(Headgear.allCases.count))]
        face = Face.allCases[Int((hash >> 24) % UInt64(Face.allCases.count))]
    }

    /// SplitMix64 finalizer: spreads FNV's weak low bits across the word.
    static func mixed(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// FNV-1a: stable across runs, unlike `Hasher`.
    static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
