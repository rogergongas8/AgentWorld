import AgentWorldKit
import Foundation

/// Types a request into the agent CLI running next to the sidebar (the other
/// pane of this tmux window) without pressing enter, then focuses that pane
/// so you finish the sentence: "Use the ui-reviewer agent to ▌".
enum Summoner {
    enum Target {
        case agent(String)
        case agentWithSkill(agent: String, skill: String)
        case skill(qualifiedName: String, name: String)
        case command(String)
    }

    /// What gets typed, in the words each CLI understands.
    static func text(for target: Target, provider: Provider) -> String {
        switch target {
        case .agent(let name):
            return "Use the \(name) agent to "
        case .agentWithSkill(let agent, let skill):
            return "Use the \(agent) agent with the \(skill) skill to "
        case .skill(let qualifiedName, let name):
            // Claude Code runs skills as slash commands; elsewhere, ask for it.
            return provider.kind == .claude ? "/\(qualifiedName) " : "Use the \(name) skill to "
        case .command(let name):
            return "/\(name) "
        }
    }

    /// Returns an error message, or nil when the text was typed.
    static func type(_ text: String) -> String? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TMUX"] != nil, let me = environment["TMUX_PANE"] else {
            return "Summoning works when the sidebar runs next to a CLI (claude or agentworld)"
        }
        guard let window = tmux(["display-message", "-p", "-t", me, "#{window_id}"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              let panes = tmux(["list-panes", "-t", window, "-F", "#{pane_id}"]) else {
            return "Couldn't reach tmux"
        }
        guard let cli = panes.split(separator: "\n").map(String.init).first(where: { $0 != me }) else {
            return "No CLI pane next to this sidebar"
        }
        guard tmux(["send-keys", "-t", cli, "-l", text]) != nil else { return "Couldn't type into the CLI" }
        _ = tmux(["select-pane", "-t", cli])
        return nil
    }

    private static func tmux(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tmux"] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
