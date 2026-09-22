import Foundation

/// Periodically re-evaluates which transcript file should be tailed: the
/// project's session directory (resolved once, lazily, since it doesn't move)
/// and, within it, the newest `.jsonl` (re-checked every call, since a new
/// session can start at any time — e.g. the user reopens `claude` in another
/// window on the same project).
final class TranscriptLocator {
    private let cwd: String
    private let projectsRoot: URL
    private var resolvedDirectory: URL?
    private(set) var currentFile: URL?

    init(cwd: String, projectsRoot: URL) {
        self.cwd = cwd
        self.projectsRoot = projectsRoot
    }

    /// Returns the file to switch to if the target changed since the last
    /// call (a new session appeared, or the directory was just found for the
    /// first time), or `nil` if nothing changed.
    func pollForChange() -> URL? {
        if resolvedDirectory == nil {
            resolvedDirectory = ProjectSlug.resolveSessionDirectory(cwd: cwd, projectsRoot: projectsRoot)
        }
        guard let directory = resolvedDirectory,
              let newest = ProjectSlug.newestJSONL(in: directory),
              newest != currentFile else {
            return nil
        }
        currentFile = newest
        return newest
    }

    var isLinkedToProject: Bool {
        resolvedDirectory != nil
    }
}
