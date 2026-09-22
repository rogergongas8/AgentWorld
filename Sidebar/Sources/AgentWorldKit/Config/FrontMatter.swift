import Foundation

/// Minimal YAML front-matter reader for agent/skill markdown files. Only
/// flat `key: value` pairs are read; anything fancier (lists, nesting,
/// multi-line strings) is ignored rather than guessed at.
enum FrontMatter {
    static func parse(_ content: String) -> [String: String] {
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false).makeIterator()
        guard lines.next()?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }

        var metadata: [String: String] = [:]
        while let line = lines.next() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { return metadata }
            // Indented lines belong to a nested/multi-line value we don't read.
            guard let first = line.first, !first.isWhitespace,
                  let separator = line.firstIndex(of: ":") else { continue }

            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !key.isEmpty, !value.isEmpty, value != "|", value != ">" {
                metadata[key] = value
            }
        }
        // No closing fence: not front matter after all.
        return [:]
    }
}
