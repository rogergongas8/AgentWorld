import Foundation

/// Reads the configuration surface AgentWorld visualizes for one agent CLI:
/// agents, skills, commands, plugins and MCP servers, from the project and
/// the user's home, plus a profile of the repository itself. Claude Code is
/// read here; the other CLIs in `ProviderScanner+Others.swift`. Unknown
/// fields are ignored so this stays safe as the CLIs' formats evolve.
public struct ProviderScanner: Sendable {
    public let provider: Provider
    public let projectURL: URL
    public let homeURL: URL

    public init(provider: Provider = .claude, projectURL: URL, homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.provider = provider
        self.projectURL = projectURL
        self.homeURL = homeURL
    }

    public func scan() -> AgentConfiguration {
        switch provider.kind {
        case .claude: scanClaude()
        case .codex: scanCodex()
        case .gemini: scanGemini()
        case .kimi: scanGeneric(home: ".kimi", project: ".kimi", mcpFiles: ["mcp.json", "config.json"])
        case .grok: scanGeneric(home: ".grok", project: ".grok", mcpFiles: ["user-settings.json", "settings.json"])
        }
    }

    // MARK: - Claude Code

    private func scanClaude() -> AgentConfiguration {
        let projectClaude = projectURL.appendingPathComponent(".claude", isDirectory: true)
        let userClaude = homeURL.appendingPathComponent(".claude", isDirectory: true)
        let plugins = scanPlugins(userClaude: userClaude)

        let agents = scanAgents(in: projectClaude.appendingPathComponent("agents"), scope: .project)
            + scanAgents(in: userClaude.appendingPathComponent("agents"), scope: .user)
            + plugins.flatMap(\.agents)
            + AgentDefinition.builtIns
        let skills = scanSkills(in: projectClaude.appendingPathComponent("skills"), scope: .project)
            + scanSkills(in: userClaude.appendingPathComponent("skills"), scope: .user)
            + plugins.flatMap(\.skills)
        let commands = scanCommands(in: projectClaude.appendingPathComponent("commands"), scope: .project)
            + scanCommands(in: userClaude.appendingPathComponent("commands"), scope: .user)
            + plugins.flatMap(\.commands)

        return AgentConfiguration(
            model: jsonObject(at: userClaude.appendingPathComponent("settings.json"))?["model"] as? String,
            agents: deduplicated(agents, by: \.qualifiedName).sorted(by: nameThenScope),
            skills: deduplicated(skills, by: \.qualifiedName).sorted(by: nameThenScope),
            mcpServers: deduplicated(scanMCPServers() + plugins.flatMap(\.mcpServers), by: \.name).sorted(by: nameThenScope),
            commands: deduplicated(commands, by: \.qualifiedName).sorted(by: nameThenScope),
            plugins: plugins.map(\.definition).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            repository: scanRepository(settingsFiles: [
                projectURL.appendingPathComponent(".claude/settings.json"),
                projectURL.appendingPathComponent(".claude/settings.local.json"),
                userClaude.appendingPathComponent("settings.json"),
            ])
        )
    }

    // MARK: - Agents, skills & commands

    func scanAgents(in directory: URL, scope: ConfigScope, plugin: String? = nil) -> [AgentDefinition] {
        markdownFiles(in: directory, recursive: false).compactMap { url in
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let meta = FrontMatter.parse(content)
            return AgentDefinition(
                name: meta["name"] ?? url.deletingPathExtension().lastPathComponent,
                description: meta.description,
                model: meta["model"],
                scope: scope,
                tools: meta.list("tools"),
                skills: meta.list("skills"),
                plugin: plugin,
                path: url.path
            )
        }
    }

    func scanSkills(in directory: URL, scope: ConfigScope, plugin: String? = nil) -> [SkillDefinition] {
        markdownFiles(in: directory, recursive: true)
            .filter { $0.lastPathComponent.caseInsensitiveCompare("SKILL.md") == .orderedSame }
            .compactMap { url in
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let meta = FrontMatter.parse(content)
                return SkillDefinition(
                    name: meta["name"] ?? url.deletingLastPathComponent().lastPathComponent,
                    description: meta.description,
                    scope: scope,
                    plugin: plugin,
                    path: url.deletingLastPathComponent().path
                )
            }
    }

    func scanCommands(in directory: URL, scope: ConfigScope, plugin: String? = nil) -> [CommandDefinition] {
        markdownFiles(in: directory, recursive: true).compactMap { url in
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let meta = FrontMatter.parse(content)
            // Subfolders namespace commands: commands/git/sync.md → git:sync.
            let relative = url.deletingPathExtension().path.dropFirst(directory.path.count + 1)
            return CommandDefinition(
                name: meta["name"] ?? relative.replacingOccurrences(of: "/", with: ":"),
                description: meta.description,
                scope: scope,
                plugin: plugin
            )
        }
    }

    func markdownFiles(in directory: URL, recursive: Bool) -> [URL] {
        let files: [URL]
        if recursive {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return [] }
            files = enumerator.compactMap { $0 as? URL }
        } else {
            files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        }
        return files.filter { $0.pathExtension.caseInsensitiveCompare("md") == .orderedSame }
    }

    // MARK: - Plugins

    struct ScannedPlugin {
        let definition: PluginDefinition
        let skills: [SkillDefinition]
        let agents: [AgentDefinition]
        let commands: [CommandDefinition]
        let mcpServers: [MCPServerDefinition]
    }

    /// Enabled marketplace plugins (`installed_plugins.json`) plus the ones
    /// synced from claude.ai (`plugins/synced/<account>/<plugin>`).
    private func scanPlugins(userClaude: URL) -> [ScannedPlugin] {
        let pluginsRoot = userClaude.appendingPathComponent("plugins", isDirectory: true)
        let settings = jsonObject(at: userClaude.appendingPathComponent("settings.json"))
        let enabled = settings?["enabledPlugins"] as? [String: Any] ?? [:]

        var roots: [URL] = []
        if let installed = jsonObject(at: pluginsRoot.appendingPathComponent("installed_plugins.json")),
           let entries = installed["plugins"] as? [String: Any] {
            for (key, value) in entries.sorted(by: { $0.key < $1.key }) {
                // Installed but switched off in /plugin: Claude doesn't load it.
                if let flag = enabled[key] as? Bool, !flag { continue }
                let installs = value as? [[String: Any]] ?? []
                if let path = installs.last?["installPath"] as? String {
                    roots.append(URL(fileURLWithPath: path, isDirectory: true))
                }
            }
        }
        let synced = pluginsRoot.appendingPathComponent("synced", isDirectory: true)
        for account in subdirectories(of: synced) {
            roots += subdirectories(of: account)
        }

        var seen = Set<String>()
        return roots.compactMap { root in
            guard let plugin = scanPlugin(at: root), seen.insert(plugin.definition.name).inserted else { return nil }
            return plugin
        }
    }

    func scanPlugin(at root: URL, manifestPath: String = ".claude-plugin/plugin.json") -> ScannedPlugin? {
        let manifest = jsonObject(at: root.appendingPathComponent(manifestPath))
        guard manifest != nil || FileManager.default.fileExists(atPath: root.appendingPathComponent("skills").path) else { return nil }
        let name = manifest?["name"] as? String ?? root.lastPathComponent

        var skillDirectories = [root.appendingPathComponent("skills")]
        for extra in stringList(manifest?["skills"]) {
            skillDirectories.append(root.appendingPathComponent(extra))
        }
        let skills = skillDirectories.flatMap { directory in
            subdirectories(of: directory).flatMap { scanSkills(in: $0, scope: .plugin, plugin: name) }
        }
        let agents = scanAgents(in: root.appendingPathComponent("agents"), scope: .plugin, plugin: name)
        let commands = scanCommands(in: root.appendingPathComponent("commands"), scope: .plugin, plugin: name)

        var mcp = mcpServers(in: jsonObject(at: root.appendingPathComponent(".mcp.json"))?["mcpServers"], scope: .plugin, plugin: name)
        mcp += mcpServers(in: manifest?["mcpServers"], scope: .plugin, plugin: name)

        let hasHooks = FileManager.default.fileExists(atPath: root.appendingPathComponent("hooks").path)
            || manifest?["hooks"] != nil
        let author = (manifest?["author"] as? [String: Any])?["name"] as? String ?? manifest?["author"] as? String

        return ScannedPlugin(
            definition: PluginDefinition(
                name: name,
                description: manifest?["description"] as? String,
                version: manifest?["version"] as? String,
                author: author,
                skills: skills.map(\.name).sorted(),
                agents: agents.map(\.name).sorted(),
                commands: commands.map(\.name).sorted(),
                mcpServers: mcp.map(\.name).sorted(),
                hasHooks: hasHooks
            ),
            skills: skills,
            agents: agents,
            commands: commands,
            mcpServers: mcp
        )
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

    func mcpServers(in value: Any?, scope: ConfigScope, plugin: String? = nil) -> [MCPServerDefinition] {
        guard let dictionary = value as? [String: Any] else { return [] }
        return dictionary.map { name, config in
            let transport = (config as? [String: Any])?["type"] as? String ?? "stdio"
            return MCPServerDefinition(name: name, transport: transport, scope: scope, plugin: plugin)
        }
    }

    // MARK: - Repository

    /// `settingsFiles`: Claude-style settings whose `hooks` keys are listed.
    func scanRepository(settingsFiles: [URL] = []) -> RepositoryProfile {
        var profile = RepositoryProfile(instructionsFile: provider.instructionsFiles.first)

        let found = provider.instructionsFiles.lazy.compactMap { name -> (String, String)? in
            (try? String(contentsOf: projectURL.appendingPathComponent(name), encoding: .utf8)).map { (name, $0) }
        }.first
        if let (name, content) = found {
            profile.instructionsFile = name
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            profile.instructionsLines = lines.count
            profile.instructionsTitle = lines.first { $0.hasPrefix("# ") }.map { String($0.dropFirst(2)) }
            let meaningful: [String] = lines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("# ") && !$0.hasPrefix("```") }
            profile.instructionsExcerpt = Array(meaningful.prefix(6))
        }

        let fileManager = FileManager.default
        let entries = (try? fileManager.contentsOfDirectory(atPath: projectURL.path)) ?? []
        let ignored: Set<String> = ["node_modules", "build", "dist", "DerivedData", "Pods", "vendor", "target", "out"]
        profile.folders = entries.filter { name in
            var isDirectory: ObjCBool = false
            return !name.hasPrefix(".") && !ignored.contains(name)
                && fileManager.fileExists(atPath: projectURL.appendingPathComponent(name).path, isDirectory: &isDirectory)
                && isDirectory.boolValue && !name.hasSuffix(".xcodeproj") && !name.hasSuffix(".xcassets")
        }.sorted()

        // Marker files at the root and one level down (monorepos, sub-packages).
        var names = Set(entries)
        for folder in profile.folders.prefix(20) {
            for name in (try? fileManager.contentsOfDirectory(atPath: projectURL.appendingPathComponent(folder).path)) ?? [] {
                names.insert(name)
            }
        }
        profile.stacks = Self.stacks(from: names, packageJSON: jsonObject(at: projectURL.appendingPathComponent("package.json")))

        var hooks = Set<String>()
        for file in settingsFiles {
            if let events = jsonObject(at: file)?["hooks"] as? [String: Any] { hooks.formUnion(events.keys) }
        }
        profile.hookEvents = hooks.sorted()
        return profile
    }

    static func stacks(from names: Set<String>, packageJSON: [String: Any]?) -> [String] {
        var stacks: [String] = []
        func has(_ predicate: (String) -> Bool) -> Bool { names.contains(where: predicate) }

        if has({ $0 == "Package.swift" || $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".swift") }) { stacks.append("swift") }
        if has({ $0.hasSuffix(".xcodeproj") }) { stacks.append("ios") }
        if names.contains("package.json") {
            stacks.append("node")
            let dependencies = ((packageJSON?["dependencies"] as? [String: Any]) ?? [:])
                .merging((packageJSON?["devDependencies"] as? [String: Any]) ?? [:]) { first, _ in first }
            for (package, stack) in [("next", "nextjs"), ("react", "react"), ("vue", "vue"), ("svelte", "svelte"), ("typescript", "typescript"), ("tailwindcss", "tailwind")]
            where dependencies[package] != nil {
                stacks.append(stack)
            }
        }
        if has({ ["pyproject.toml", "requirements.txt", "setup.py"].contains($0) }) { stacks.append("python") }
        if names.contains("Cargo.toml") { stacks.append("rust") }
        if names.contains("go.mod") { stacks.append("go") }
        if names.contains("Gemfile") { stacks.append("ruby") }
        if has({ ["pom.xml", "build.gradle", "build.gradle.kts"].contains($0) }) { stacks.append("jvm") }
        if has({ $0 == "Dockerfile" || $0.hasPrefix("docker-compose") }) { stacks.append("docker") }
        if has({ $0.hasSuffix(".tf") }) { stacks.append("terraform") }
        return stacks
    }

    // MARK: - Helpers

    func jsonObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    func subdirectories(of directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        )) ?? []
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func stringList(_ value: Any?) -> [String] {
        if let string = value as? String { return [string] }
        return value as? [String] ?? []
    }

    /// Project-level definitions shadow user-level ones with the same name,
    /// matching Claude Code's precedence. Input must already be in precedence order.
    func deduplicated<T>(_ items: [T], by key: KeyPath<T, String>) -> [T] {
        var seen = Set<String>()
        return items.filter { seen.insert($0[keyPath: key].lowercased()).inserted }
    }
}

func nameThenScope<T>(_ lhs: T, _ rhs: T) -> Bool where T: NamedScoped {
    if lhs.scope != rhs.scope { return lhs.scope < rhs.scope }
    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
}

protocol NamedScoped {
    var name: String { get }
    var scope: ConfigScope { get }
}

extension AgentDefinition: NamedScoped {}
extension SkillDefinition: NamedScoped {}
extension MCPServerDefinition: NamedScoped {}
extension CommandDefinition: NamedScoped {}
