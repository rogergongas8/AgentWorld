import Foundation

/// Maps a working directory to the `~/.claude/projects/<slug>/` directory that
/// holds its session transcripts.
public enum ProjectSlug {
    /// Claude Code's transform: every character that isn't ASCII alphanumeric
    /// becomes "-". Verified against real session directories and against a
    /// live session's own `memory_paths.auto` (dashes, dots, UUIDs included).
    public static func slug(forCwd cwd: String) -> String {
        String(cwd.unicodeScalars.map { scalar in
            scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        })
    }

    /// The project's session directory, if it exists yet. There is deliberately
    /// no "most recent session anywhere" fallback: on a machine running several
    /// Claude Code sessions at once, that reliably locks onto an unrelated one.
    /// Both the path as given and its `realpath` are tried (`/tmp/x` vs
    /// `/private/tmp/x`), since which one Claude Code saw depends on how the
    /// shell reported its cwd. (Foundation's `resolvingSymlinksInPath` can't
    /// be used for this: it deliberately strips `/private`.)
    public static func sessionDirectory(forCwd cwd: String, projectsRoot: URL) -> URL? {
        var candidates = [cwd]
        if let resolved = realpath(cwd, nil) {
            candidates.append(String(cString: resolved))
            free(resolved)
        }
        for path in candidates {
            let candidate = projectsRoot.appendingPathComponent(slug(forCwd: path), isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
        }
        return nil
    }

    public static var defaultProjectsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
    }
}
