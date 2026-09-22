import Foundation

/// The shelves skills are organized on. A skill can name its shelf with
/// `category:` in its front matter (any of the raw values or titles below);
/// otherwise it's guessed from its name, plugin and description.
public enum SkillCategory: String, CaseIterable, Sendable, Hashable {
    case design
    case documents
    case code
    case integrations
    case data
    case workflow
    case other

    public var title: String {
        switch self {
        case .design: "Design & UI"
        case .documents: "Documents"
        case .code: "Code & quality"
        case .integrations: "Integrations"
        case .data: "Data & visuals"
        case .workflow: "Workflow & meta"
        case .other: "Other"
        }
    }

    public static func named(_ name: String) -> SkillCategory? {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        return allCases.first { $0.rawValue == key || $0.title.lowercased() == key }
            ?? aliases[key]
    }

    private static let aliases: [String: SkillCategory] = [
        "ui": .design, "ux": .design, "frontend": .design, "docs": .documents, "office": .documents,
        "testing": .code, "quality": .code, "dev": .code, "development": .code, "integration": .integrations,
        "tools": .integrations, "visualization": .data, "analytics": .data, "meta": .workflow, "productivity": .workflow,
    ]

    /// Keyword votes; the name and plugin count triple so "figma-use" lands in
    /// design even when its description talks about JavaScript.
    public static func guess(name: String, description: String?, plugin: String?) -> SkillCategory {
        let strong = words(name + " " + (plugin ?? ""))
        let weak = words(description ?? "")
        var best = (category: SkillCategory.other, score: 0)
        for category in allCases where category != .other {
            let keywords = self.keywords[category] ?? []
            let score = strong.filter(keywords.contains).count * 3 + weak.filter(keywords.contains).count
            if score > best.score { best = (category, score) }
        }
        return best.category
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static let keywords: [SkillCategory: Set<String>] = [
        .design: ["design", "ui", "ux", "figma", "css", "frontend", "visual", "animation", "motion", "pixel", "swiftui",
                  "component", "components", "style", "styles", "theme", "layout", "screen", "screens", "redesign", "canva", "shader", "shaders"],
        .documents: ["pdf", "docx", "doc", "docs", "document", "documents", "word", "pptx", "slides", "slide", "deck", "presentation",
                     "presentations", "xlsx", "spreadsheet", "spreadsheets", "excel", "brief", "memo", "report"],
        .code: ["test", "tests", "testing", "review", "reviews", "debug", "lint", "build", "release", "ci", "security", "refactor",
                "bug", "bugs", "code", "snapshot", "verify", "commit", "diff", "tester"],
        .integrations: ["mcp", "api", "board", "boards", "miro", "notion", "slack", "jira", "github", "browser", "connector", "sync",
                        "computer", "server", "servers", "webhook", "provider"],
        .data: ["data", "chart", "charts", "visualize", "visualization", "dashboard", "analytics", "sql", "csv", "graph", "diagram", "diagrams", "map", "maps"],
        .workflow: ["skill", "skills", "plugin", "plugins", "agent", "agents", "memory", "template", "templates", "workflow", "plan",
                    "planning", "creator", "installer", "customize", "import", "morning", "prompt", "prompts", "character"],
    ]

    // MARK: - Summary

    /// First sentence that says what the skill does, with trigger boilerplate
    /// ("MANDATORY…", "Use this skill whenever the user wants to…") removed,
    /// capped at ~90 characters on a word boundary.
    public static func summarize(_ description: String) -> String {
        let text = description.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        let sentences = self.sentences(text).filter { $0.count > 3 }
        let chosen = sentences.first { !isBoilerplate($0) } ?? sentences.first.map(stripTrigger) ?? text
        var summary = stripTrigger(chosen)
        if let first = summary.first { summary = first.uppercased() + summary.dropFirst() }
        guard summary.count > 90 else { return summary }
        let cut = summary.prefix(89)
        return (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)) + "…"
    }

    /// Splits on . ! ? followed by whitespace (so ".pptx" and "e.g." survive) and on newlines.
    private static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            if character == "\n" {
                result.append(current)
                current = ""
                continue
            }
            let endsAbbreviation = character == "." && ["e.g", "i.e", "etc", "vs", "cf"].contains { current.lowercased().hasSuffix($0) }
            if ".!?".contains(character), !endsAbbreviation, index + 1 == characters.count || characters[index + 1].isWhitespace {
                result.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        result.append(current)
        return result.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func isBoilerplate(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        return ["mandatory", "use this skill", "use when", "use whenever", "trigger", "always use", "always invoke",
                "you must", "load this skill", "invoke this skill", "do not use", "don't use", "never"].contains { lower.hasPrefix($0) }
    }

    /// "Use this skill whenever the user wants to create a PDF" → "create a PDF".
    private static func stripTrigger(_ sentence: String) -> String {
        let pattern = #"^(use (this skill )?(when|whenever|any ?time|for)|trigger(s)? (on|when)|always use this skill when)\s+(the user\s+)?((wants|asks|needs) to\s+|mentions\s+)?"#
        guard let range = sentence.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return sentence }
        let rest = sentence[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? sentence : rest
    }
}
