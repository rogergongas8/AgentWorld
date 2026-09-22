import Foundation

/// Something worth using right now, and why.
public struct Suggestion: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case agent
        case skill
        case command
    }

    public let kind: Kind
    /// Qualified name (`plugin:name` for plugin items).
    public let name: String
    public let score: Double
    /// The context words that matched, strongest first.
    public let reasons: [String]
}

/// Ranks agents, skills and commands against what's happening: the latest
/// prompts, the files being touched and what kind of repository this is.
/// Plain keyword overlap with a few weights — cheap enough to run every frame
/// batch, transparent enough to explain ("matches swift, test").
public enum Recommender {
    public static func suggest(
        config: AgentConfiguration,
        prompts: [String],
        files: [String],
        limit: Int = 4
    ) -> [Suggestion] {
        var context: [String: Double] = [:]
        func add(_ words: [String], weight: Double) {
            for word in words { context[word] = max(context[word] ?? 0, weight) }
        }

        add(config.repository.stacks.flatMap { expansions[$0] ?? [$0] }, weight: 1)
        for file in files {
            let ext = (file as NSString).pathExtension.lowercased()
            add(expansions[ext] ?? [], weight: 2)
        }
        // Newest prompt counts most; older ones fade.
        for (age, prompt) in prompts.reversed().prefix(3).enumerated() {
            let words = tokens(prompt)
            add(words + words.flatMap { expansions[$0] ?? [] }, weight: [4, 2, 1.5][age])
        }
        guard !context.isEmpty else { return [] }

        var candidates: [(Suggestion.Kind, String, String, String?)] = []
        candidates += config.agents.map { (.agent, $0.qualifiedName, $0.name, $0.description) }
        candidates += config.skills.map { (.skill, $0.qualifiedName, $0.name, $0.description) }
        candidates += config.commands.map { (.command, $0.qualifiedName, $0.name, $0.description) }

        var seen = Set<String>()
        let ranked = candidates.compactMap { kind, qualified, name, description -> Suggestion? in
            guard seen.insert(qualified.lowercased()).inserted else { return nil }
            let nameWords = Set(tokens(qualified.replacingOccurrences(of: ":", with: " ")))
            let descriptionWords = Set(tokens(description ?? ""))
            var matches: [(String, Double)] = []
            for (word, weight) in context {
                if nameWords.contains(word) {
                    matches.append((word, weight * 3))
                } else if descriptionWords.contains(word) {
                    matches.append((word, weight))
                }
            }
            guard !matches.isEmpty else { return nil }
            // Long descriptions match everything a little; don't let them win on volume.
            let score = matches.reduce(0) { $0 + $1.1 } / max(1, sqrt(Double(descriptionWords.count) / 8))
            let reasons = matches.sorted { $0.1 > $1.1 || ($0.1 == $1.1 && $0.0 < $1.0) }.prefix(3).map(\.0)
            return Suggestion(kind: kind, name: qualified, score: score, reasons: reasons)
        }
        let sorted = ranked.sorted { $0.score > $1.score || ($0.score == $1.score && $0.name < $1.name) }
        // Keep only real contenders: a single incidental word shouldn't make the list.
        let floor = (sorted.first?.score ?? 0) * 0.35
        return Array(sorted.prefix { $0.score >= floor }.prefix(limit))
    }

    // MARK: - Text

    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map { stem(String($0)) }
            .filter { $0.count >= 3 && !stopWords.contains($0) }
    }

    private static func stem(_ word: String) -> String {
        guard word.count > 4 else { return word }
        for suffix in ["ing", "es", "s"] where word.hasSuffix(suffix) && !word.hasSuffix("ss") {
            return String(word.dropLast(suffix.count))
        }
        return word
    }

    /// File extensions, stacks and common Spanish words → the vocabulary
    /// skill and agent descriptions are written in.
    private static let expansions: [String: [String]] = [
        "swift": ["swift", "swiftui", "ios"],
        "ios": ["ios", "swiftui", "iphone"],
        "tsx": ["react", "frontend", "component", "typescript"],
        "jsx": ["react", "frontend", "component"],
        "ts": ["typescript"],
        "js": ["javascript"],
        "css": ["css", "frontend", "design", "style"],
        "scss": ["css", "frontend", "design"],
        "html": ["html", "frontend", "web", "page"],
        "react": ["react", "frontend", "component"],
        "nextjs": ["react", "frontend", "web"],
        "vue": ["vue", "frontend"],
        "tailwind": ["tailwind", "css", "design"],
        "py": ["python"],
        "md": ["doc", "documentation", "markdown"],
        "pdf": ["pdf"],
        "docx": ["docx", "word", "document"],
        "xlsx": ["xlsx", "spreadsheet", "excel"],
        "csv": ["csv", "spreadsheet", "data"],
        "pptx": ["pptx", "slide", "presentation"],
        "fig": ["figma", "design"],
        // Spanish → English
        "diseño": ["design", "ui"], "diseno": ["design", "ui"], "disenar": ["design"],
        "interfaz": ["ui", "interface", "design"], "pantalla": ["screen", "ui"],
        "prueba": ["test"], "pruebas": ["test"], "testear": ["test"],
        "documento": ["document", "doc"], "documentacion": ["documentation", "doc"],
        "revisar": ["review"], "revision": ["review"], "revisa": ["review"],
        "presentacion": ["presentation", "slide", "deck"], "diapositiva": ["slide"],
        "hoja": ["spreadsheet"], "calculo": ["spreadsheet"], "excel": ["excel", "spreadsheet", "xlsx"],
        "buscar": ["search", "find"], "busca": ["search", "find"], "encontrar": ["find", "search"],
        "error": ["bug", "debug", "error"], "fallo": ["bug", "debug"], "arreglar": ["fix", "bug"], "arregla": ["fix", "bug"],
        "planificar": ["plan"], "plan": ["plan", "architecture"], "arquitectura": ["architecture", "plan"],
        "entender": ["explore", "understand", "codebase"], "explicar": ["explain"], "explica": ["explain"],
        "codigo": ["code", "codebase"], "repo": ["codebase", "repository"], "repositorio": ["codebase", "repository"],
        "diagrama": ["diagram"], "tablero": ["board"], "pizarra": ["board", "whiteboard"],
        "seguridad": ["security"], "rendimiento": ["performance"], "animacion": ["animation", "motion"],
        "web": ["web", "frontend", "page"], "pagina": ["page", "web"],
    ]

    private static let stopWords: Set<String> = [
        // English
        "the", "and", "for", "with", "you", "your", "this", "that", "use", "when", "from", "are", "any",
        "can", "will", "not", "all", "into", "via", "its", "has", "have", "who", "what", "how", "why",
        "user", "users", "want", "need", "should", "must", "also", "only", "such", "like", "more", "one",
        "other", "about", "them", "they", "their", "then", "than", "etc", "whenever", "wants", "using",
        "skill", "tool", "claude", "agent", "agente", "habilidad", "trigger", "task", "work", "make", "includ", "request", "ask",
        // Spanish
        "que", "los", "las", "del", "por", "para", "con", "una", "uno", "unos", "este", "esta", "esto",
        "como", "pero", "mas", "muy", "sin", "sobre", "entre", "tambien", "hay", "ser", "son", "tengo",
        "tiene", "hacer", "quiero", "puede", "puedes", "ahora", "mismo", "todo", "cosa", "sabe", "sabes",
    ]
}
