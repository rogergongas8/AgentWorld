import Foundation

/// Reads the configuration surface AgentWorld visualizes: agents, skills and
/// MCP servers, from both the project (`<cwd>/.claude`, `<cwd>/.mcp.json`)
/// and the user (`~/.claude`, `~/.claude.json`). Unknown fields are ignored
/// so this stays safe as Claude Code's formats evolve.
public struct ClaudeConfigScanner: Sendable {
    public let projectURL: URL
    public let homeURL: URL

    public init(projectURL: URL, homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.projectURL = projectURL
        self.homeURL = homeURL
    }

    public func scan() -> ClaudeConfiguration {
        let projectClaude = projectURL.appendingPathComponent(".claude", isDirectory: true)
        let userClaude = homeURL.appendingPathComponent(".claude", isDirectory: true)

        let agents = scanAgents(in: projectClaude.appendingPathComponent("agents"), scope: .project)
            + scanAgents(in: userClaude.appendingPathComponent("agents"), scope: .user)
        let skills = scanSkills(in: projectClaude.appendingPathComponent("skills"), scope: .project)
            + scanSkills(in: userClaude.appendingPathComponent("skills"), scope: .user)

        return ClaudeConfiguration(
            agents: deduplicated(agents, by: \.name).sorted(by: nameThenScope),
            skills: deduplicated(skills, by: \.name).sorted(by: nameThenScope),
            mcpServers: deduplicated(scanMCPServers(), by: \.name).sorted(by: nameThenScope)
        )
    }

    // MARK: - Agents & skills

    private func scanAgents(in directory: URL, scope: ConfigScope) -> [AgentDefinition] {
        markdownFiles(in: directory).compactMap { url in
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let meta = FrontMatter.parse(content)
            return AgentDefinition(
                name: meta["name"] ?? url.deletingPathExtension().lastPathComponent,
                description: meta["description"],
                model: meta["model"],
                scope: scope
            )
        }
    }

    private func scanSkills(in directory: URL, scope: ConfigScope) -> [SkillDefinition] {
        markdownFiles(in: directory)
            .filter { $0.lastPathComponent.caseInsensitiveCompare("SKILL.md") == .orderedSame }
            .compactMap { url in
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let meta = FrontMatter.parse(content)
                return SkillDefinition(
                    name: meta["name"] ?? url.deletingLastPathComponent().lastPathComponent,
                    description: meta["description"],
                    scope: scope
                )
            }
    }

    private func markdownFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension.caseInsensitiveCompare("md") == .orderedSame }
    }

    // MARK: - MCP servers

    private func scanMCPServers() -> [MCPServerDefinition] {
        var servers: [MCPServerDefinition] = []

        if let project = jsonObject(at: projectURL.appendingPathComponent(".mcp.json")) {
            servers += mcpServers(in: project["mcpServers"], scope: .project)
        }

        if let user = jsonObject(at: homeURL.appendingPathComponent(".claude.json")) {
            if let projects = user["projects"] as? [String: Any],
               let entry = projects[projectURL.standardizedFileURL.path] as? [String: Any] {
                servers += mcpServers(in: entry["mcpServers"], scope: .local)
            }
            servers += mcpServers(in: user["mcpServers"], scope: .user)
        }
        return servers
    }

    private func mcpServers(in value: Any?, scope: ConfigScope) -> [MCPServerDefinition] {
        guard let dictionary = value as? [String: Any] else { return [] }
        return dictionary.map { name, config in
            let transport = (config as? [String: Any])?["type"] as? String ?? "stdio"
            return MCPServerDefinition(name: name, transport: transport, scope: scope)
        }
    }

    private func jsonObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - Helpers

    /// Project-level definitions shadow user-level ones with the same name,
    /// matching Claude Code's precedence. Input must already be in precedence order.
    private func deduplicated<T>(_ items: [T], by key: KeyPath<T, String>) -> [T] {
        var seen = Set<String>()
        return items.filter { seen.insert($0[keyPath: key].lowercased()).inserted }
    }
}

private func nameThenScope<T>(_ lhs: T, _ rhs: T) -> Bool where T: NamedScoped {
    if lhs.scope != rhs.scope { return lhs.scope < rhs.scope }
    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
}

private protocol NamedScoped {
    var name: String { get }
    var scope: ConfigScope { get }
}

extension AgentDefinition: NamedScoped {}
extension SkillDefinition: NamedScoped {}
extension MCPServerDefinition: NamedScoped {}
