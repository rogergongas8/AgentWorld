---
name: add-provider
category: code
description: Checklist for adding a new agent CLI (e.g. opencode, aider, a new Grok or Kimi release) to AgentWorld as a first-class provider — launchable from the hub with its own character and a sidebar that reads its skills, MCP servers, commands and plugins. Use when asked to support another CLI or to fix how an existing CLI's config is read.
---

# Add a provider

A provider is everything AgentWorld knows about one agent CLI. Work through
these in order; each step builds on the previous one.

## 1. Find out the facts first

Don't guess config layouts. From the CLI's official docs or source, collect:
executable name, install command, user config folder, project config folder,
where skills live (`SKILL.md` folders?), where MCP servers are declared (file
and key), custom commands format, plugins/extensions, and the instructions
file (`AGENTS.md`, `GEMINI.md`…). If a real install exists, look at its
folders too. Delegate the digging to the `cli-researcher` agent when it's a
big unknown.

## 2. Model — `Sidebar/Sources/AgentWorldKit/Providers/Provider.swift`

- Add a `Kind` case and a `static let` with name, command, tagline,
  `instructionsFiles`, `installHint` (nil unless you're sure of the official
  one) and `followsLiveSessions: false`.
- Append it to `Provider.all` (the hub shows them in that order).

## 3. Config reader — `Sidebar/Sources/AgentWorldKit/Config/`

- If the CLI matches the common shape (`~/.<name>/skills`, JSON with
  `mcpServers`), a `scanGeneric(home:project:mcpFiles:)` call in
  `ProviderScanner.scan()` is enough.
- Otherwise add `scanX()` in `ProviderScanner+Others.swift`, reusing
  `scanSkills`, `scanAgents`, `scanCommands`, `scanPlugin(at:manifestPath:)`,
  `mcpServers(in:scope:)` and `TOMLLite` for TOML files.
- Always include `.agents/skills` in the project, and pass
  `repository: scanRepository()`.

## 4. Look — `Sidebar/Sources/agentworld-sidebar/World/ProviderLook.swift`

Add `shortName`, `color` and a `figure`. See the `pixel-character` skill:
plain colors and headgear, no logos; check the name stays readable.

## 5. Tests — `Sidebar/Tests/AgentWorldKitTests/ProviderTests.swift`

Build a fake home + project in a temp dir with every kind of file the reader
handles and assert on the resulting `AgentConfiguration`. Run `swift test`.

## 6. Verify and document

- `terminal-snapshot` with `-- --provider <id>` and `--size 130x50 -- --launcher`.
- Add a row to the "What each sidebar reads" table in `Sidebar/README.md`.
