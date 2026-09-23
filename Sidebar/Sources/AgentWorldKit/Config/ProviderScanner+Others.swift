import Foundation

/// Config layouts of the non-Claude CLIs. Each reads what that CLI documents
/// (skills as `SKILL.md` folders, MCP servers, custom commands, plugins or
/// extensions, and its instructions file) and maps it onto the same model,
/// so the explorer works the same whatever the CLI.
extension ProviderScanner {
    // MARK: - Codex (~/.codex)

    func scanCodex() -> AgentConfiguration {
        let home = homeURL.appendingPathComponent(".codex", isDirectory: true)
        let project = projectURL.appendingPathComponent(".codex", isDirectory: true)
        let userConfig = TOMLLite.parse(file: home.appendingPathComponent("config.toml"))
        let projectConfig = TOMLLite.parse(file: project.appendingPathComponent("config.toml"))

        // Enabled plugins live in the cache as <market>/<name>/<version>/.
        var plugins: [ScannedPlugin] = []
        for (path, values) in userConfig.sections where path.count == 2 && path[0] == "plugins" && values["enabled"] == "true" {
            let parts = path[1].split(separator: "@", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let versions = subdirectories(of: home.appendingPathComponent("plugins/cache/\(parts[1])/\(parts[0])"))
                .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending }
            if let root = versions.last, let plugin = scanPlugin(at: root, manifestPath: ".codex-plugin/plugin.json") {
                plugins.append(plugin)
            }
        }

        let skills = scanSkills(in: project.appendingPathComponent("skills"), scope: .project)
            + scanSkills(in: projectURL.appendingPathComponent(".agents/skills"), scope: .project)
            + scanSkills(in: home.appendingPathComponent("skills"), scope: .user)
            + scanSkills(in: home.appendingPathComponent("skills/.system"), scope: .builtin)
            + plugins.flatMap(\.skills)
        // Custom prompts are invoked as /prompts:<name>.
        let prompts = markdownFiles(in: home.appendingPathComponent("prompts"), recursive: false).map { url in
            let meta = FrontMatter.parse((try? String(contentsOf: url, encoding: .utf8)) ?? "")
            return CommandDefinition(name: "prompts:" + url.deletingPathExtension().lastPathComponent, description: meta.description, scope: .user)
        }
        let servers = Self.codexMCPServers(projectConfig, scope: .project) + Self.codexMCPServers(userConfig, scope: .user)
            + plugins.flatMap(\.mcpServers)

        return AgentConfiguration(
            model: projectConfig.value("model") ?? userConfig.value("model"),
            agents: plugins.flatMap(\.agents),
            skills: deduplicated(skills, by: \.qualifiedName).sorted(by: nameThenScope),
            mcpServers: deduplicated(servers, by: \.name).sorted(by: nameThenScope),
            commands: prompts.sorted(by: nameThenScope),
            plugins: plugins.map(\.definition).sorted { $0.name < $1.name },
            repository: scanRepository()
        )
    }

    /// `[mcp_servers.<name>]` tables (not their `.env` sub-tables).
    static func codexMCPServers(_ config: TOMLLite, scope: ConfigScope) -> [MCPServerDefinition] {
        config.sections.compactMap { path, values in
            guard path.count == 2, path[0] == "mcp_servers" else { return nil }
            return MCPServerDefinition(name: path[1], transport: values["url"] == nil ? "stdio" : "http", scope: scope)
        }
    }

    // MARK: - Gemini CLI (~/.gemini)

    func scanGemini() -> AgentConfiguration {
        let home = homeURL.appendingPathComponent(".gemini", isDirectory: true)
        let project = projectURL.appendingPathComponent(".gemini", isDirectory: true)
        let userSettings = jsonObject(at: home.appendingPathComponent("settings.json"))
        let projectSettings = jsonObject(at: project.appendingPathComponent("settings.json"))

        // Extensions are Gemini's plugins: a folder with gemini-extension.json.
        var extensions: [ScannedPlugin] = []
        for root in subdirectories(of: home.appendingPathComponent("extensions")) {
            guard let manifest = jsonObject(at: root.appendingPathComponent("gemini-extension.json")) else { continue }
            let name = manifest["name"] as? String ?? root.lastPathComponent
            let skills = subdirectories(of: root.appendingPathComponent("skills")).flatMap { scanSkills(in: $0, scope: .plugin, plugin: name) }
            let commands = geminiCommands(in: root.appendingPathComponent("commands"), scope: .plugin, plugin: name)
            let servers = geminiMCPServers(manifest["mcpServers"], scope: .plugin, plugin: name)
            extensions.append(ScannedPlugin(
                definition: PluginDefinition(
                    name: name,
                    description: manifest["description"] as? String,
                    version: manifest["version"] as? String,
                    skills: skills.map(\.name).sorted(),
                    commands: commands.map(\.name).sorted(),
                    mcpServers: servers.map(\.name).sorted()
                ),
                skills: skills, agents: [], commands: commands, mcpServers: servers
            ))
        }

        let agents = scanAgents(in: project.appendingPathComponent("agents"), scope: .project)
            + scanAgents(in: home.appendingPathComponent("agents"), scope: .user)
        let skills = scanSkills(in: project.appendingPathComponent("skills"), scope: .project)
            + scanSkills(in: projectURL.appendingPathComponent(".agents/skills"), scope: .project)
            + scanSkills(in: home.appendingPathComponent("skills"), scope: .user)
            + extensions.flatMap(\.skills)
        let commands = geminiCommands(in: project.appendingPathComponent("commands"), scope: .project)
            + geminiCommands(in: home.appendingPathComponent("commands"), scope: .user)
            + extensions.flatMap(\.commands)
        let servers = geminiMCPServers(projectSettings?["mcpServers"], scope: .project)
            + geminiMCPServers(userSettings?["mcpServers"], scope: .user)
            + extensions.flatMap(\.mcpServers)

        let model = [projectSettings, userSettings].lazy.compactMap { settings -> String? in
            (settings?["model"] as? [String: Any])?["name"] as? String ?? settings?["model"] as? String
        }.first

        return AgentConfiguration(
            model: model,
            agents: deduplicated(agents, by: \.qualifiedName).sorted(by: nameThenScope),
            skills: deduplicated(skills, by: \.qualifiedName).sorted(by: nameThenScope),
            mcpServers: deduplicated(servers, by: \.name).sorted(by: nameThenScope),
            commands: deduplicated(commands, by: \.qualifiedName).sorted(by: nameThenScope),
            plugins: extensions.map(\.definition).sorted { $0.name < $1.name },
            repository: scanRepository()
        )
    }

    /// Commands are TOML files; subfolders namespace them (git/ship.toml → git:ship).
    private func geminiCommands(in directory: URL, scope: ConfigScope, plugin: String? = nil) -> [CommandDefinition] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "toml" }.map { url in
            return CommandDefinition(
                name: commandName(for: url, in: directory),
                description: TOMLLite.parse(file: url).value("description"),
                scope: scope,
                plugin: plugin
            )
        }
    }

    private func geminiMCPServers(_ value: Any?, scope: ConfigScope, plugin: String? = nil) -> [MCPServerDefinition] {
        guard let servers = value as? [String: Any] else { return [] }
        return servers.map { name, config in
            let config = config as? [String: Any] ?? [:]
            let transport = config["httpUrl"] != nil ? "http" : (config["url"] != nil ? "sse" : "stdio")
            return MCPServerDefinition(name: name, transport: transport, scope: scope, plugin: plugin)
        }
    }

    // MARK: - Kimi, Grok and similar

    /// CLIs with a `~/.<name>` folder holding `skills/` and JSON files with an
    /// `mcpServers` object — the common denominator most agent CLIs share.
    func scanGeneric(home homeFolder: String, project projectFolder: String, mcpFiles: [String], mcpKey: String = "mcpServers") -> AgentConfiguration {
        let home = homeURL.appendingPathComponent(homeFolder, isDirectory: true)
        let project = projectURL.appendingPathComponent(projectFolder, isDirectory: true)

        // Singular folder names too (opencode uses agent/ and command/).
        let agents = ["agents", "agent"].flatMap { name in
            scanAgents(in: project.appendingPathComponent(name), scope: .project) + scanAgents(in: home.appendingPathComponent(name), scope: .user)
        }
        let skills = scanSkills(in: project.appendingPathComponent("skills"), scope: .project)
            + scanSkills(in: projectURL.appendingPathComponent(".agents/skills"), scope: .project)
            + scanSkills(in: home.appendingPathComponent("skills"), scope: .user)
        let commands = ["commands", "command"].flatMap { name in
            scanCommands(in: project.appendingPathComponent(name), scope: .project) + scanCommands(in: home.appendingPathComponent(name), scope: .user)
        }
        var servers: [MCPServerDefinition] = []
        for (folder, scope) in [(project, ConfigScope.project), (home, .user)] {
            for file in mcpFiles {
                servers += mcpServers(in: jsonObject(at: folder.appendingPathComponent(file))?[mcpKey], scope: scope)
            }
        }
        let settings = mcpFiles.lazy.compactMap { jsonObject(at: home.appendingPathComponent($0)) }.first

        return AgentConfiguration(
            model: settings?["model"] as? String ?? settings?["default_model"] as? String,
            agents: deduplicated(agents, by: \.qualifiedName).sorted(by: nameThenScope),
            skills: deduplicated(skills, by: \.qualifiedName).sorted(by: nameThenScope),
            mcpServers: deduplicated(servers, by: \.name).sorted(by: nameThenScope),
            commands: deduplicated(commands, by: \.qualifiedName).sorted(by: nameThenScope),
            repository: scanRepository()
        )
    }
}

extension ProviderScanner {
    /// Kiro CLI: `~/.kiro` like the others (skills, MCP in settings/mcp.json),
    /// plus its agents, which are JSON files (`agents/<name>.json`) with a
    /// name, description, model, tools and resources.
    func scanKiro() -> AgentConfiguration {
        let base = scanGeneric(home: ".kiro", project: ".kiro", mcpFiles: ["settings/mcp.json"])
        var agents = base.agents
        let folders = [(projectURL.appendingPathComponent(".kiro/agents"), ConfigScope.project),
                       (homeURL.appendingPathComponent(".kiro/agents"), .user)]
        for (folder, scope) in folders {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "json" {
                guard let json = jsonObject(at: file) else { continue }
                agents.append(AgentDefinition(
                    name: json["name"] as? String ?? file.deletingPathExtension().lastPathComponent,
                    description: json["description"] as? String,
                    model: json["model"] as? String,
                    scope: scope,
                    tools: json["tools"] as? [String] ?? [],
                    path: file.path))
            }
        }
        return AgentConfiguration(model: base.model, agents: deduplicated(agents, by: \.qualifiedName).sorted(by: nameThenScope),
                                  skills: base.skills, mcpServers: base.mcpServers, commands: base.commands, repository: base.repository)
    }
}

/// Just enough TOML for CLI config files: `[table]` / `[a."b.c"]` headers and
/// single-line `key = value` pairs. Arrays and inline tables are kept as raw
/// text; multi-line strings are skipped.
struct TOMLLite {
    /// Table path → key → value (strings unquoted). The root table is `[]`.
    private(set) var sections: [[String]: [String: String]] = [:]

    func value(_ key: String, in path: [String] = []) -> String? {
        sections[path]?[key]
    }

    static func parse(file url: URL) -> TOMLLite {
        parse((try? String(contentsOf: url, encoding: .utf8)) ?? "")
    }

    static func parse(_ content: String) -> TOMLLite {
        var result = TOMLLite()
        var current: [String] = []
        var inMultiline = false
        for raw in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if inMultiline {
                if line.contains("\"\"\"") || line.contains("'''") { inMultiline = false }
                continue
            }
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("["), !line.hasPrefix("[["), line.hasSuffix("]") {
                current = keyPath(String(line.dropFirst().dropLast()))
                result.sections[current, default: [:]] = result.sections[current] ?? [:]
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = keyPath(String(line[..<equals])).joined(separator: ".")
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"\"\"") || value.hasPrefix("'''") {
                // A multi-line string: skip its body unless it closes on this line.
                if value.count < 6 || !(value.hasSuffix("\"\"\"") || value.hasSuffix("'''")) { inMultiline = true }
                continue
            }
            if let quote = value.first, quote == "\"" || quote == "'", let end = value.dropFirst().firstIndex(of: quote) {
                value = String(value[value.index(after: value.startIndex)..<end])
            } else if let comment = value.firstIndex(of: "#") {
                value = value[..<comment].trimmingCharacters(in: .whitespaces)
            }
            result.sections[current, default: [:]][key] = value
        }
        return result
    }

    /// `a."b.c".d` → ["a", "b.c", "d"].
    private static func keyPath(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        for character in text {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "." {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        return parts.filter { !$0.isEmpty }
    }
}
