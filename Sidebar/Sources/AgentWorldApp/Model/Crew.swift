import AgentWorldKit
import Foundation

/// A set of CLIs you open together, tiled in one tab: "Claude + Codex +
/// Gemini" to compare, "Claude ×3" for three tasks side by side. Your own
/// live in `~/.config/agentworld/crews.json`; a few come ready-made.
struct Crew: Codable, Hashable {
    var name: String
    /// Profile names, repeated for several copies.
    var members: [String]

    @MainActor
    func profiles(in model: AppModel) -> [LaunchProfile] {
        members.compactMap { name in model.profiles.first { $0.name == name || $0.provider.id == name } }
            .filter { model.executable(for: $0) != nil }
    }

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/agentworld/crews.json")
    }

    static func saved() -> [Crew] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Crew].self, from: data)) ?? []
    }

    static func save(_ crew: Crew) {
        let crews = [crew] + saved().filter { $0.name != crew.name }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(crews).write(to: url)
    }

    static func delete(named name: String) {
        let crews = saved().filter { $0.name != name }
        try? JSONEncoder().encode(crews).write(to: url)
    }

    /// Saved crews first, then presets built from what's installed.
    @MainActor
    static func presets(model: AppModel) -> [(name: String, summary: String, profiles: [LaunchProfile])] {
        var result: [(String, String, [LaunchProfile])] = []
        for crew in saved() {
            let profiles = crew.profiles(in: model)
            guard !profiles.isEmpty else { continue }
            result.append((crew.name, "your crew · " + summary(profiles), profiles))
        }
        let agents = model.profiles.filter { !$0.isCustom && $0.provider.isAgent && model.executable(for: $0) != nil }
        if agents.count > 1 {
            let all = Array(agents.prefix(AppModel.maxPanes))
            result.append(("Every CLI you have (\(all.count))", "compare them on the same task · " + summary(all), all))
        }
        if let first = agents.first {
            for count in [2, 3, 4] {
                result.append(("\(first.provider.shortName) ×\(count)", "\(count) sessions side by side, for \(count) tasks at once",
                               Array(repeating: first, count: count)))
            }
        }
        return result
    }

    static func summary(_ profiles: [LaunchProfile]) -> String {
        var counts: [(String, Int)] = []
        for profile in profiles {
            let name = profile.isCustom ? profile.name : profile.provider.shortName
            if let index = counts.firstIndex(where: { $0.0 == name }) { counts[index].1 += 1 } else { counts.append((name, 1)) }
        }
        return counts.map { $0.1 > 1 ? "\($0.0) ×\($0.1)" : $0.0 }.joined(separator: " + ")
    }
}
