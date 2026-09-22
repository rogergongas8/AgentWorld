import AgentWorldKit
import TerminalUI
import Foundation

public enum Format {
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m" }
        if total >= 48 * 3600 { return "\(total / 86400)d" }
        return "\(total / 3600)h\(String(format: "%02d", (total % 3600) / 60))"
    }

    public static func tokens(_ count: Int) -> String {
        switch count {
        case ..<1000: "\(count)"
        case ..<10_000: String(format: "%.1fk", Double(count) / 1000)
        case ..<1_000_000: "\(count / 1000)k"
        default: String(format: "%.1fM", Double(count) / 1_000_000)
        }
    }

    public static func clock(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// `claude-opus-5-5` → `opus-5-5`, `claude-sonnet-5-20260101` → `sonnet-5`.
    public static func model(_ model: String) -> String {
        var name = model.hasPrefix("claude-") ? String(model.dropFirst("claude-".count)) : model
        if let range = name.range(of: #"-\d{8}$"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        return name
    }

    /// Smooth horizontal bar using eighth blocks.
    public static func bar(fraction: Double, width: Int) -> (filled: String, empty: String) {
        guard width > 0 else { return ("", "") }
        let eighths = Int((min(max(fraction, 0), 1) * Double(width * 8)).rounded())
        let partials: [Character] = ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉"].map { $0.first ?? " " }
        var filled = String(repeating: "█", count: eighths / 8)
        if eighths % 8 > 0 { filled.append(partials[eighths % 8]) }
        return (filled, String(repeating: " ", count: max(0, width - filled.count)))
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
