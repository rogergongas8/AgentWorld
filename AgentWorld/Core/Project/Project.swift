import Foundation

/// The project currently open in AgentWorld.
struct Project: Identifiable, Equatable {
    let id: URL
    let name: String
    let path: URL
    let hasClaudeDirectory: Bool
    let agents: [Agent]
    let skills: [Skill]

    init(url: URL, hasClaudeDirectory: Bool, agents: [Agent] = [], skills: [Skill] = []) {
        self.id = url
        self.name = url.lastPathComponent
        self.path = url
        self.hasClaudeDirectory = hasClaudeDirectory
        self.agents = agents
        self.skills = skills
    }
}
