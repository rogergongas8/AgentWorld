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
    /// Asks the AgentWorld app a `agentworld-ctl` command (the team tools);
    /// nil when the CLI isn't running inside the app.
    private let ask: ((String, [String]) -> MemoryCommands.Result?)?

    public init(vault: MemoryVault, folder: String, agent: String?, onChange: @escaping (MemoryNote, String) -> Void = { _, _ in },
                ask: ((String, [String]) -> MemoryCommands.Result?)? = nil) {
        self.vault = vault
        self.folder = folder
        self.agent = agent
        self.onChange = onChange
        self.ask = ask
    }

    static let instructions = """
    Notes shared by all the user's agent CLIs (per project, or global about the user), \
    plus what Claude and Gemini remember on their own: use the memory tool to look things up \
    and to keep what other agents will need; the team tool to coordinate with agents working here.
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
        // Two tools with an action each (fewer tokens in every session); the
        // older one-tool-per-action names still work.
        if tool == "memory" || tool == "team" {
            let action = (arguments["action"] as? String ?? (tool == "memory" ? "search" : "board")).lowercased()
            return call(tool + "_" + action, arguments)
        }
        let commands = MemoryCommands(vault: vault, folder: folder, agent: agent)
        let string = { (key: String) in arguments[key] as? String }
        let outcome: MemoryCommands.Result
        switch tool {
        case "memory_search":
            outcome = commands.search(string("query") ?? string("text") ?? "", scope: string("scope"))
        case "memory_list":
            outcome = commands.list(scope: string("scope"))
        case "memory_read":
            outcome = commands.read(string("name") ?? "")
        case "memory_write":
            let tags = (arguments["tags"] as? [String]) ?? string("tags")?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
            outcome = commands.write(name: string("name") ?? "", body: string("content") ?? string("text") ?? "",
                                     global: arguments["global"] as? Bool ?? false, description: string("description"), kind: string("kind"),
                                     tags: tags, append: arguments["append"] as? Bool ?? false)
        case "memory_delete":
            outcome = commands.delete(string("name") ?? "")
        case "team_board", "team_doing", "team_message", "team_inbox":
            let request: (String, [String]) = switch tool {
            case "team_board": ("board", arguments["all"] as? Bool == true ? ["--all"] : [])
            case "team_doing": ("doing", [string("text") ?? "-"])
            case "team_message": ("message", [string("to") ?? "", string("text") ?? ""])
            default: ("inbox", [])
            }
            return ask?(request.0, request.1)
                ?? MemoryCommands.Result(ok: false, output: "Not running inside AgentWorld: there are no other agents to coordinate with.")
        default:
            return MemoryCommands.Result(ok: false, output: "unknown tool \(tool)")
        }
        if let note = outcome.changed { onChange(note, tool == "memory_delete" ? "deleted" : "saved") }
        return outcome
    }

    static var tools: [[String: Any]] { [
        [
            "name": "memory",
            "description": "Shared memory of all the user's agent CLIs. search: before work, or when asked something you don't know. write: when told to remember something, or you learned what another agent will need (one topic per note). read, list, delete: the rest.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "enum": ["search", "read", "write", "list", "delete"]],
                    "query": ["type": "string", "description": "search: words to look for"],
                    "name": ["type": "string", "description": "read/write/delete: short-kebab-case note name"],
                    "content": ["type": "string", "description": "write: Markdown; link notes with [[name]]"],
                    "description": ["type": "string", "description": "write: one line"],
                    "kind": ["type": "string", "enum": MemoryVault.kinds.map(\.id)],
                    "global": ["type": "boolean", "description": "write: about the user, for every project"],
                    "append": ["type": "boolean"],
                    "scope": ["type": "string", "enum": ["project", "global", "all"]],
                ],
                "required": ["action"],
            ],
        ],
        [
            "name": "team",
            "description": "Other agents working in this project now (any CLI). board: who's doing what, which files. doing: say what you're on. message: to \"#3\" or \"all\", delivered when their turn ends. inbox: messages for you.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "enum": ["board", "doing", "message", "inbox"]],
                    "to": ["type": "string"],
                    "text": ["type": "string"],
                ],
                "required": ["action"],
            ],
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
