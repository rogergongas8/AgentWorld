import Foundation

/// A skill declared by a `SKILL.md` file inside `.claude/skills`.
struct Skill: Identifiable, Hashable {
    let id: URL
    let name: String
    let description: String?
    let path: URL
    let source: String
}
