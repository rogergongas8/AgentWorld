import Foundation

/// `agentworld-ctl mcp`: the shared memory as an MCP server (stdio, one
/// JSON-RPC message per line), so any CLI that speaks MCP gets `memory_*`
/// tools. Registered for each CLI in its own config (see Settings › Memory).
public final class MemoryMCPServer {
    public static let name = "agentworld-memory"

    private let vault: MemoryVault
    private let folder: String
    /// From `$AGENTWORLD_AGENT` (set in the app's terminals), else the MCP client's name.
    private var agent: String?
    /// Called after a note is written or deleted (the app is told, when it's up).
    private let onChange: (MemoryNote, String) -> Void

    public init(vault: MemoryVault, folder: String, agent: String?, onChange: @escaping (MemoryNote, String) -> Void = { _, _ in }) {
        self.vault = vault
        self.folder = folder
        self.agent = agent
        self.onChange = onChange
    }

    static let instructions = """
    A memory shared by every agent CLI the user runs (Claude Code, Codex, Gemini…), \
    kept as Markdown notes the user also reads in Obsidian. Notes belong to the \
    current project or are global (about the user, for every project). \
    Before starting non-trivial work, memory_search for the topic: another agent may \
    already know the answer. When you learn something a future agent would need \
    (a decision and why, how to run or test the project, a gotcha, a user \
    preference), write it: one fact or topic per note, a clear name, a one-line \
    description. Update or delete notes that turn out wrong instead of adding near-copies. \
    Don't store secrets, or what the code or git history already records.
    """

    // MARK: - Loop

    /// Reads requests from stdin until it closes.
    public func run() {
        while let line = readLine(strippingNewline: true) {
            guard let reply = handle(line) else { continue }
            FileHandle.standardOutput.write(Data((reply + "\n").utf8))
        }
    }

    /// One message in, the reply out (nil for notifications).
    public func handle(_ line: String) -> String? {
        guard let data = line.data(using: .utf8), !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "parse error"]])
        }
        let id = message["id"]
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]
        guard let id else { return nil }   // a notification (initialized, cancelled…)

        switch method {
        case "initialize":
            if agent == nil, let client = (params["clientInfo"] as? [String: Any])?["name"] as? String {
                agent = Self.agentName(fromClient: client)
            }
            let version = params["protocolVersion"] as? String ?? "2025-06-18"
            return result(id, [
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": Self.name, "version": "1.0.0"],
                "instructions": Self.instructions,
            ])
        case "ping":
            return result(id, [:])
        case "tools/list":
            return result(id, ["tools": Self.tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let outcome = call(name, arguments)
            return result(id, ["content": [["type": "text", "text": outcome.output]], "isError": !outcome.ok])
        case "resources/list":
            return result(id, ["resources": []])
        case "prompts/list":
            return result(id, ["prompts": []])
        default:
            return encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "unknown method \(method)"]])
        }
    }

    // MARK: - Tools

    func call(_ tool: String, _ arguments: [String: Any]) -> MemoryCommands.Result {
        let commands = MemoryCommands(vault: vault, folder: folder, agent: agent)
        let string = { (key: String) in arguments[key] as? String }
        let outcome: MemoryCommands.Result
        switch tool {
        case "memory_search":
            outcome = commands.search(string("query") ?? "", scope: string("scope"))
        case "memory_list":
            outcome = commands.list(scope: string("scope"))
        case "memory_read":
            outcome = commands.read(string("name") ?? "")
        case "memory_write":
            let tags = (arguments["tags"] as? [String]) ?? string("tags")?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
            outcome = commands.write(name: string("name") ?? "", body: string("content") ?? "",
                                     global: arguments["global"] as? Bool ?? false, description: string("description"),
                                     tags: tags, append: arguments["append"] as? Bool ?? false)
        case "memory_delete":
            outcome = commands.delete(string("name") ?? "")
        default:
            return MemoryCommands.Result(ok: false, output: "unknown tool \(tool)")
        }
        if let note = outcome.changed { onChange(note, tool == "memory_delete" ? "deleted" : "saved") }
        return outcome
    }

    static var scopeProperty: [String: Any] {
        [
            "type": "string", "enum": ["project", "global", "all"],
            "description": "project: this project's notes; global: notes for every project; all: every project's. Default: this project and global.",
        ]
    }

    static var tools: [[String: Any]] { [
        [
            "name": "memory_search",
            "description": "Search the shared memory (notes from every agent CLI) for notes mentioning all these words. Use before starting work on a topic.",
            "inputSchema": ["type": "object", "properties": ["query": ["type": "string"], "scope": scopeProperty], "required": ["query"]],
        ],
        [
            "name": "memory_list",
            "description": "List the shared memory's notes (name, description, who wrote it, when).",
            "inputSchema": ["type": "object", "properties": ["scope": scopeProperty]],
        ],
        [
            "name": "memory_read",
            "description": "Read a note of the shared memory by name (or scope/name).",
            "inputSchema": ["type": "object", "properties": ["name": ["type": "string"]], "required": ["name"]],
        ],
        [
            "name": "memory_write",
            "description": "Create, replace or append to a note in the shared memory. One fact or topic per note; search first and update an existing note rather than adding a near-copy. Link other notes with [[name]].",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "short-kebab-case name"],
                    "content": ["type": "string", "description": "Markdown text of the note"],
                    "description": ["type": "string", "description": "one line: what the note is about"],
                    "tags": ["type": "array", "items": ["type": "string"]],
                    "global": ["type": "boolean", "description": "true for every project (facts about the user); default: this project"],
                    "append": ["type": "boolean", "description": "add to the end of the note instead of replacing it"],
                ],
                "required": ["name", "content"],
            ],
        ],
        [
            "name": "memory_delete",
            "description": "Delete a note of the shared memory that is wrong or no longer true.",
            "inputSchema": ["type": "object", "properties": ["name": ["type": "string"]], "required": ["name"]],
        ],
    ] }

    /// "claude-code" → claude, "codex-mcp-client" → codex, and so on.
    static func agentName(fromClient client: String) -> String {
        let lower = client.lowercased()
        for known in ["claude", "codex", "gemini", "kimi", "grok", "opencode", "cursor", "kiro"] where lower.contains(known) {
            return known
        }
        return lower
    }

    // MARK: - JSON

    private func result(_ id: Any, _ value: [String: Any]) -> String? {
        encode(["jsonrpc": "2.0", "id": id, "result": value])
    }

    private func encode(_ object: [String: Any]) -> String? {
        (try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])).map { String(decoding: $0, as: UTF8.self) }
    }
}
