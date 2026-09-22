import AgentWorldKit
import Foundation

// `agentworld-ctl <command> [arguments…]`: drives the running AgentWorld app
// from any of its terminals, so an agent can open other CLIs beside it, hand
// them work, wait for them and read their answers. `agentworld-ctl help`
// lists the commands (the app answers it).

let arguments = Array(CommandLine.arguments.dropFirst())
let environment = ProcessInfo.processInfo.environment

guard let command = arguments.first, !["-h", "--help"].contains(command) else {
    print("usage: agentworld-ctl <command> [arguments…]   (try: agentworld-ctl help)")
    exit(0)
}

let sockets = environment["AGENTWORLD_SOCKET"].map { [$0] } ?? ControlSocket.running()
guard let socket = sockets.first else {
    FileHandle.standardError.write(Data("agentworld-ctl: AgentWorld isn't running\n".utf8))
    exit(3)
}

let request = ControlRequest(command: command, arguments: Array(arguments.dropFirst()),
                             caller: environment["AGENTWORLD_PANE"].flatMap(Int.init))
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
