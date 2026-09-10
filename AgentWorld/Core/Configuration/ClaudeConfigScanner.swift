import Foundation

/// Reads the small, user-owned configuration surface used by AgentWorld's first explorer.
/// Unknown metadata is deliberately ignored so it remains safe to evolve with Claude Code.
struct ClaudeConfigScanner {
    private let fileManager = FileManager.default

    func scan(projectURL: URL) -> ClaudeConfiguration {
        let claudeDirectory = projectURL.appendingPathComponent(".claude", isDirectory: true)
        guard fileManager.fileExists(atPath: claudeDirectory.path) else {
            return .empty
        }

        return ClaudeConfiguration(
            agents: scanAgents(in: claudeDirectory.appendingPathComponent("agents", isDirectory: true)),
            skills: scanSkills(in: claudeDirectory.appendingPathComponent("skills", isDirectory: true))
        )
    }

    private func scanAgents(in directory: URL) -> [Agent] {
        markdownFiles(in: directory).compactMap { url in
            guard let document = markdownDocument(at: url) else { return nil }
            return Agent(
                id: url,
                name: document.metadata["name"] ?? url.deletingPathExtension().lastPathComponent,
                description: document.metadata["description"],
                model: document.metadata["model"],
                path: url,
                source: document.source
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func scanSkills(in directory: URL) -> [Skill] {
        markdownFiles(in: directory)
            .filter { $0.lastPathComponent.caseInsensitiveCompare("SKILL.md") == .orderedSame }
            .compactMap { url in
                guard let document = markdownDocument(at: url) else { return nil }
                return Skill(
                    id: url,
                    name: document.metadata["name"] ?? url.deletingLastPathComponent().lastPathComponent,
                    description: document.metadata["description"],
                    path: url,
                    source: document.source
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func markdownFiles(in directory: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        return enumerator.compactMap { $0 as? URL }.filter { url in
            url.pathExtension.caseInsensitiveCompare("md") == .orderedSame
        }
    }

    private func markdownDocument(at url: URL) -> MarkdownDocument? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        return MarkdownDocument(source: content, metadata: markdownMetadata(in: content))
    }

    private func markdownMetadata(in content: String) -> [String: String] {
        let lines = content.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---",
              let closingIndex = lines.dropFirst().firstIndex(where: {
                  $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---"
              }) else {
            return [:]
        }

        return lines[1..<closingIndex].reduce(into: [:]) { metadata, line in
            guard let separator = line.firstIndex(of: ":") else { return }

            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

            guard !key.isEmpty, !value.isEmpty else { return }
            metadata[key] = value
        }
    }
}

private struct MarkdownDocument {
    let source: String
    let metadata: [String: String]
}

struct ClaudeConfiguration {
    let agents: [Agent]
    let skills: [Skill]

    static let empty = ClaudeConfiguration(agents: [], skills: [])
}
