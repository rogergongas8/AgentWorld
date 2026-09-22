import Foundation
import AgentWorldKit
import TerminalUI

/// Every color and glyph the sidebar uses, in one place.
public enum Theme {
    public static let claude = RGB(hex: 0xD97757)
    public static let cream = RGB(hex: 0xF0E6D2)
    public static let text = RGB(hex: 0xD6D6D6)
    public static let muted = RGB(hex: 0x8B949E)
    public static let faint = RGB(hex: 0x5C6370)
    public static let rule = RGB(hex: 0x3B4048)
    public static let live = RGB(hex: 0x56D364)
    public static let warning = RGB(hex: 0xE3B341)
    public static let error = RGB(hex: 0xFF7B72)
    public static let barEmpty = RGB(hex: 0x30363D)

    public static func color(for kind: ToolKind) -> RGB {
        switch kind {
        case .read: RGB(hex: 0x6CB6FF)
        case .search: RGB(hex: 0x56D4DD)
        case .edit: RGB(hex: 0x7EE787)
        case .shell: RGB(hex: 0xE3B341)
        case .web: RGB(hex: 0x79C0FF)
        case .agent: RGB(hex: 0xFFA657)
        case .skill: RGB(hex: 0xF778BA)
        case .todo: RGB(hex: 0xD2A8FF)
        case .question: cream
        case .plan: RGB(hex: 0xA5D6FF)
        case .mcp: RGB(hex: 0xBC8CFF)
        case .other: muted
        }
    }

    public static func glyph(for kind: ToolKind) -> Character {
        switch kind {
        case .read: "▤"
        case .search: "◎"
        case .edit: "✎"
        case .shell: "$"
        case .web: "⊕"
        case .agent: "◆"
        case .skill: "✦"
        case .todo: "▣"
        case .question: "?"
        case .plan: "▦"
        case .mcp: "↯"
        case .other: "•"
        }
    }

    public static func color(for status: ActorStatus) -> RGB {
        switch status {
        case .idle: muted
        case .thinking: RGB(hex: 0xD2A8FF)
        case .reading: color(for: .read)
        case .editing: color(for: .edit)
        case .running: color(for: .shell)
        case .browsing: color(for: .web)
        case .usingTool: color(for: .mcp(server: "", tool: ""))
        case .delegating: color(for: .agent)
        case .waitingForUser: cream
        case .done: live
        case .failed: error
        }
    }

    public static func glyph(for status: ActorStatus) -> Character {
        switch status {
        case .idle: "·"
        case .thinking: "◌"
        case .reading: "▤"
        case .editing: "✎"
        case .running: "$"
        case .browsing: "⊕"
        case .usingTool: "↯"
        case .delegating: "◆"
        case .waitingForUser: "▸"
        case .done: "✓"
        case .failed: "✗"
        }
    }
}
