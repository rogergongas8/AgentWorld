import AgentWorldKit
import TerminalUI

/// How each agent CLI appears in the world. Claude keeps its orange block
/// creature; the others are crew-style characters with a fixed look (plain
/// colors and headgear, no logos).
extension Provider {
    /// "Claude", "Codex"…: the name used in sentences ("Ask Codex: …").
    var shortName: String {
        switch kind {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .kimi: "Kimi"
        case .grok: "Grok"
        }
    }

    var color: RGB {
        switch kind {
        case .claude: Theme.claude
        case .codex: RGB(hex: 0x3FB68B)
        case .gemini: RGB(hex: 0x6E9BF5)
        case .kimi: RGB(hex: 0x8AB4F8)
        case .grok: RGB(hex: 0xE6EDF3)
        }
    }

    var figure: CharacterCard.Figure {
        switch kind {
        case .claude:
            .claude
        case .codex:
            .crew(CharacterLook(body: RGB(hex: 0xE6EDF3), hair: RGB(hex: 0x30363D), skin: RGB(hex: 0xFFDBAC),
                                accent: color, headgear: .antenna, face: .visor))
        case .gemini:
            .crew(CharacterLook(body: color, hair: RGB(hex: 0x3B2F80), skin: RGB(hex: 0xF1C27D),
                                accent: RGB(hex: 0xC4A7FF), headgear: .crown, face: .skin))
        case .kimi:
            .crew(CharacterLook(body: RGB(hex: 0x1F2A44), hair: RGB(hex: 0x0B1220), skin: RGB(hex: 0xE0AC69),
                                accent: color, headgear: .headphones, face: .skin))
        case .grok:
            .crew(CharacterLook(body: RGB(hex: 0x24292F), hair: RGB(hex: 0xF0F0F0), skin: RGB(hex: 0xC68642),
                                accent: RGB(hex: 0xF0F0F0), headgear: .horns, face: .visor))
        }
    }
}
