import Testing
@testable import AgentWorldKit

@Suite struct SkillCategoryTests {
    @Test func summariesDropTriggerBoilerplate() {
        #expect(SkillCategory.summarize("**MANDATORY prerequisite** — you MUST invoke this skill BEFORE every `use_figma` call. Creates Figma nodes from code.")
            == "Creates Figma nodes from code")
        #expect(SkillCategory.summarize("Use this skill whenever the user wants to create, read or edit Word documents (.docx). Triggers include…")
            == "Create, read or edit Word documents (.docx)")
        #expect(SkillCategory.summarize("Use this skill any time a .pptx or .potx file is involved in any way")
            == "A .pptx or .potx file is involved in any way")
        #expect(SkillCategory.summarize("Checklist for adding a CLI (e.g. opencode) to the hub. Use when…")
            == "Checklist for adding a CLI (e.g. opencode) to the hub")
        let long = SkillCategory.summarize(String(repeating: "word ", count: 40))
        #expect(long.count <= 90 && long.hasSuffix("…"))
    }

    @Test func categoriesComeFromFrontMatterOrKeywords() {
        #expect(SkillDefinition(name: "x", scope: .user, category: "Testing").category == .code)
        #expect(SkillDefinition(name: "figma-use", description: "Run JavaScript in files", scope: .plugin, plugin: "figma").category == .design)
        #expect(SkillDefinition(name: "pdf", description: "Read and merge PDF files", scope: .user).category == .documents)
        #expect(SkillDefinition(name: "terminal-snapshot", description: "Capture the sidebar to verify a UI change", scope: .project).category == .code)
        #expect(SkillDefinition(name: "zzz", description: "Nothing to see", scope: .user).category == .other)
    }
}
