import AgentWorldKit
import Foundation

// `agentworld-ctl <command> [arguments…]`: drives the running AgentWorld app
// from any of its terminals, so an agent can open other CLIs beside it, hand
// them work, wait for them and read their answers. `agentworld-ctl help`
// lists the commands (the app answers it). `memory` and `mcp` (the shared
// memory, as commands or as an MCP server) work without the app.

let arguments = Array(CommandLine.arguments.dropFirst())
let environment = ProcessInfo.processInfo.environment

guard let command = arguments.first, !["-h", "--help"].contains(command) else {
    print("usage: agentworld-ctl <command> [arguments…]   (try: agentworld-ctl help)")
    exit(0)
}

let sockets = environment["AGENTWORLD_SOCKET"].map { [$0] } ?? ControlSocket.running()
let caller = environment["AGENTWORLD_PANE"].flatMap(Int.init)

/// Tells the app a note changed (so its panel updates and the character
/// says so). Best effort: memory works without the app.
func tellApp(_ note: MemoryNote, _ action: String) {
    guard let socket = sockets.first else { return }
    _ = try? ControlSocket.send(ControlRequest(command: "memory-changed", arguments: [action, note.id], caller: caller), to: socket)
}

// The shared memory is files: these run here, with or without the app.
let agent = environment["AGENTWORLD_AGENT"].flatMap { $0.isEmpty ? nil : $0 }
let folder = FileManager.default.currentDirectoryPath
if command == "mcp" {
    MemoryMCPServer(vault: .configured(), folder: folder, agent: agent, onChange: tellApp).run()
    exit(0)
}
if command == "memory" {
    let commands = MemoryCommands(vault: .configured(), folder: folder, agent: agent ?? "you")
    let result = commands.run(Array(arguments.dropFirst())) {
        isatty(STDIN_FILENO) == 0 ? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) : nil
    }
    if let note = result.changed { tellApp(note, ["delete", "rm", "forget"].contains(arguments.dropFirst().first ?? "") ? "deleted" : "saved") }
    let text = result.output.hasSuffix("\n") ? result.output : result.output + "\n"
    (result.ok ? FileHandle.standardOutput : FileHandle.standardError).write(Data(text.utf8))
    exit(result.ok ? 0 : 1)
}

guard let socket = sockets.first else {
    FileHandle.standardError.write(Data("agentworld-ctl: AgentWorld isn't running\n".utf8))
    exit(3)
}

let request = ControlRequest(command: command, arguments: Array(arguments.dropFirst()), caller: caller)
do {
    let reply = try ControlSocket.send(request, to: socket)
    if !reply.output.isEmpty {
        let text = reply.output.hasSuffix("\n") ? reply.output : reply.output + "\n"
        (reply.ok ? FileHandle.standardOutput : FileHandle.standardError).write(Data(text.utf8))
    }
    exit(reply.ok ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data("agentworld-ctl: \(error)\n".utf8))
    exit(3)
}
