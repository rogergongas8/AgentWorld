import Foundation
import Testing
@testable import AgentWorldKit

@Suite struct RecommenderTests {
    private let config = AgentConfiguration(
        agents: AgentDefinition.builtIns,
        skills: [
            SkillDefinition(name: "pdf", description: "Read, merge and split PDF files.", scope: .user),
            SkillDefinition(name: "figma-swiftui", description: "Translate Figma designs into SwiftUI views for iOS.", scope: .plugin, plugin: "figma"),
            SkillDefinition(name: "xlsx", description: "Create and edit spreadsheets.", scope: .user),
        ],
        repository: RepositoryProfile(stacks: ["swift"])
    )

    @Test func promptWordsRankMatchingSkills() {
        let suggestions = Recommender.suggest(config: config, prompts: ["merge these two PDF reports"], files: [])
        #expect(suggestions.first?.name == "pdf")
        #expect(suggestions.first?.reasons.contains("pdf") == true)
    }

    @Test func spanishPromptsAreUnderstood() {
        let suggestions = Recommender.suggest(config: config, prompts: ["ayúdame a entender el código del repo"], files: [])
        #expect(suggestions.first?.name == "Explore")
    }

    @Test func repositoryStackSuggestsWithoutPrompts() {
        let suggestions = Recommender.suggest(config: config, prompts: [], files: [])
        #expect(suggestions.map(\.name) == ["figma:figma-swiftui"])
    }

    @Test func nothingMatchesNothing() {
        let empty = AgentConfiguration(skills: config.skills)
        #expect(Recommender.suggest(config: empty, prompts: [], files: []).isEmpty)
        #expect(Recommender.suggest(config: empty, prompts: ["hello there"], files: []).isEmpty)
    }
}
