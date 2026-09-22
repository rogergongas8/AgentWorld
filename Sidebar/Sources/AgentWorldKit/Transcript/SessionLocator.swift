import Foundation

/// Decides which transcript in the project's session directory is "the"
/// session to follow.
///
/// * Pinned (`sessionId` given — the shell wrapper passes the same UUID it
///   hands to `claude --session-id`): follow exactly that file. The only
///   reason to leave it is `/clear`, which starts a fresh transcript and
///   stops writing the old one; that's detected as "a file born after ours,
///   while ours went quiet".
/// * Unpinned: follow the most recently written transcript.
public final class SessionLocator {
    public let cwd: String
    public let projectsRoot: URL
    private let pinnedSessionId: String?
    private var directory: URL?
    public private(set) var current: URL?

    public init(cwd: String, projectsRoot: URL, pinnedSessionId: String?) {
        self.cwd = cwd
        self.projectsRoot = projectsRoot
        self.pinnedSessionId = pinnedSessionId
    }

    public var isProjectDirectoryFound: Bool { directory != nil }

    /// The file to switch to, or nil when nothing changed.
    public func poll() -> URL? {
        if directory == nil {
            directory = ProjectSlug.sessionDirectory(forCwd: cwd, projectsRoot: projectsRoot)
        }
        guard let directory else { return nil }

        let next: URL?
        if let current {
            next = pinnedSessionId == nil ? newestWritten(in: directory) : successor(of: current, in: directory)
        } else if let pinnedSessionId {
            let pinned = directory.appendingPathComponent("\(pinnedSessionId).jsonl")
            next = FileManager.default.fileExists(atPath: pinned.path) ? pinned : nil
        } else {
            next = newestWritten(in: directory)
        }

        guard let next, next != current else { return nil }
        current = next
        return next
    }

    private func successor(of current: URL, in directory: URL) -> URL? {
        guard let currentStamp = stamps(of: current) else { return current }
        let newer = transcripts(in: directory)
            .filter { $0.url != current && $0.created > currentStamp.created && $0.created > currentStamp.modified }
            .max { $0.created < $1.created }
        return newer?.url ?? current
    }

    private func newestWritten(in directory: URL) -> URL? {
        transcripts(in: directory).max { $0.modified < $1.modified }?.url
    }

    private struct Stamped {
        let url: URL
        let created: Date
        let modified: Date
    }

    private func transcripts(in directory: URL) -> [Stamped] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files
            .filter { $0.pathExtension == "jsonl" }
            .compactMap { url in stamps(of: url) }
    }

    private func stamps(of url: URL) -> Stamped? {
        guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]),
              let modified = values.contentModificationDate else { return nil }
        return Stamped(url: url, created: values.creationDate ?? modified, modified: modified)
    }
}
