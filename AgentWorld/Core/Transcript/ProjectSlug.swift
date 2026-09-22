import Foundation

/// Resolves which `~/.claude/projects/<slug>/` directory holds the transcripts
/// for a given working directory, and which `.jsonl` inside it is the newest.
enum ProjectSlug {
    /// The transform Claude Code uses: replace every "/" in the absolute cwd
    /// with "-". Verified two ways: against real session directories on this
    /// machine, and directly against a live `system/init` transcript line's
    /// own `memory_paths.auto` field for a deeply-nested test path (dashes, a
    /// UUID, everything) — it matched exactly.
    static func naiveSlug(forCwd cwd: String) -> String {
        cwd.replacingOccurrences(of: "/", with: "-")
    }

    /// Finds the project's session directory by the naive slug only. There is
    /// deliberately no cross-project fallback (e.g. "newest session directory
    /// anywhere under `projectsRoot`"): on a machine that's actively running
    /// other Claude Code sessions — which is normal, not an edge case — that
    /// kind of fallback reliably locks onto whichever *unrelated* session
    /// happens to be busiest, not this project's, because it can't tell "not
    /// created yet" apart from "our transform is wrong". Safer to keep
    /// retrying the exact path and surface "not linked yet" than to guess.
    static func resolveSessionDirectory(cwd: String, projectsRoot: URL) -> URL? {
        let candidate = projectsRoot.appendingPathComponent(naiveSlug(forCwd: cwd), isDirectory: true)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    /// The most recently modified `.jsonl` file directly inside `directory`.
    static func newestJSONL(in directory: URL) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return files
            .filter { $0.pathExtension.caseInsensitiveCompare("jsonl") == .orderedSame }
            .compactMap { url -> (url: URL, date: Date)? in
                guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                    return nil
                }
                return (url, date)
            }
            .max { $0.date < $1.date }?
            .url
    }
}
