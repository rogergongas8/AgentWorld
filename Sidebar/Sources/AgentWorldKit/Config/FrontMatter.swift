import Foundation

/// Small YAML front-matter reader for agent/skill/command markdown files.
/// Understands flat `key: value` pairs, block scalars (`key: >` / `key: |`
/// followed by indented lines) and simple lists (`key:` followed by `- item`
/// lines, or `[a, b]`). Anything fancier is ignored rather than guessed at.
struct FrontMatter {
    private(set) var values: [String: String] = [:]
    private(set) var lists: [String: [String]] = [:]

    subscript(key: String) -> String? { values[key] }

    var isEmpty: Bool { values.isEmpty && lists.isEmpty }

    /// A description for display: markdown emphasis and code ticks removed.
    var description: String? {
        values["description"].map {
            $0.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        }
    }

    /// A list value, also accepting the comma-separated string form
    /// (`tools: Read, Grep`) Claude Code allows.
    func list(_ key: String) -> [String] {
        if let list = lists[key] { return list }
        guard var value = values[key] else { return [] }
        if value.hasPrefix("["), value.hasSuffix("]") { value = String(value.dropFirst().dropLast()) }
        return value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .filter { !$0.isEmpty }
    }

    static func parse(_ content: String) -> FrontMatter {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return FrontMatter() }

        var result = FrontMatter()
        var pendingKey: String?
        var pendingBlock: [String] = []
        var pendingList: [String] = []

        func flush() {
            guard let key = pendingKey else { return }
            if !pendingList.isEmpty {
                result.lists[key] = pendingList
            } else if !pendingBlock.isEmpty {
                result.values[key] = pendingBlock.joined(separator: " ")
            }
            pendingKey = nil
            pendingBlock = []
            pendingList = []
        }

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                flush()
                return result
            }
            if let first = line.first, first.isWhitespace || first == "-" {
                // Continuation of the key above: a list item or block text.
                guard pendingKey != nil, !trimmed.isEmpty else { continue }
                if trimmed.hasPrefix("- ") {
                    pendingList.append(unquoted(String(trimmed.dropFirst(2))))
                } else {
                    pendingBlock.append(trimmed)
                }
                continue
            }
            flush()
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = unquoted(line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces))
            guard !key.isEmpty else { continue }
            if value.isEmpty || [">", "|", ">-", "|-", ">+", "|+"].contains(value) {
                pendingKey = key
            } else {
                result.values[key] = value
            }
        }
        // No closing fence: not front matter after all.
        return FrontMatter()
    }

    private static func unquoted(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
}
