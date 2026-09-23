import AgentWorldKit
import Foundation

/// A workspace's uncommitted changes, and which of the app's agents touched
/// each file. Exact when the CLI records its edits (Claude's transcript);
/// for every other CLI, a file whose modification time moves while agents
/// in that workspace are working is credited to them.
struct WorkspaceChanges: Equatable {
    var root: String
    var files: [FileChange]
    /// File path → the sessions that were working when it changed.
    var touchedBy: [String: [UUID]] = [:]
    /// Last seen modification time per path, to notice the next change.
    var stamps: [String: Date] = [:]

    var added: Int { files.compactMap(\.added).reduce(0, +) }
    var removed: Int { files.compactMap(\.removed).reduce(0, +) }
}

/// A file's diff on screen.
struct OpenChange: Equatable {
    let folder: String
    let change: FileChange
}

extension AppModel {
    func openDiff(_ change: FileChange, in folder: String) {
        openChange = OpenChange(folder: folder, change: change)
    }

    /// The next or previous changed file in the open diff's workspace.
    func stepDiff(_ offset: Int) {
        guard let open = openChange, let files = changes[open.folder]?.files, !files.isEmpty else { return }
        let index = files.firstIndex { $0.path == open.change.path } ?? 0
        openChange = OpenChange(folder: open.folder, change: files[(index + offset + files.count) % files.count])
    }

    /// Rereads `folder`'s changes off the main thread; one read at a time.
    func refreshChanges(_ folder: String) {
        guard !changesInFlight.contains(folder) else { return }
        changesInFlight.insert(folder)
        Task.detached(priority: .utility) {
            let read = GitChanges.read(folder)
            let stamps: [String: Date] = read.map { result in
                Dictionary(uniqueKeysWithValues: result.changes.compactMap { change in
                    let url = URL(fileURLWithPath: result.root).appendingPathComponent(change.path)
                    return ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate).map { (change.path, $0) }
                })
            } ?? [:]
            await MainActor.run {
                self.changesInFlight.remove(folder)
                self.apply(read, stamps: stamps, to: folder)
            }
        }
    }

    private func apply(_ read: (root: String, changes: [FileChange])?, stamps: [String: Date], to folder: String) {
        guard let read else {
            if changes[folder] != nil { changes[folder] = nil }
            return
        }
        let previous = changes[folder]
        var next = WorkspaceChanges(root: read.root, files: read.changes)
        let sessions = tabs(in: folder).flatMap(\.sessions)
        let working = sessions.filter { $0.status.tone == .busy }.map(\.id)
        // git reports real paths, a CLI may write through a symlink (/tmp → /private/tmp).
        let edited = sessions.compactMap { session -> (UUID, Set<String>)? in
            guard let files = session.store?.editedFiles, !files.isEmpty else { return nil }
            return (session.id, Set(files.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }))
        }
        let resolvedRoot = URL(fileURLWithPath: read.root).resolvingSymlinksInPath().path
        for file in read.changes {
            var who = previous?.touchedBy[file.path] ?? []
            // Exact where the CLI says what it edited (Claude's Edit/Write calls,
            // rebuilt from the transcript after a relaunch too).
            let full = URL(fileURLWithPath: resolvedRoot).appendingPathComponent(file.path).path
            for (id, files) in edited where files.contains(full) && !who.contains(id) {
                who.append(id)
            }
            let stamp = stamps[file.path]
            // First sight on launch isn't news: only changes seen happening count.
            let changed = previous != nil && (previous?.stamps[file.path] != stamp || previous?.files.contains { $0.path == file.path } == false)
            if changed { who += working.filter { !who.contains($0) } }
            if !who.isEmpty { next.touchedBy[file.path] = who }
            if let stamp { next.stamps[file.path] = stamp }
        }
        if next != previous { changes[folder] = next }
    }

    /// The sessions still open among those that touched `path`.
    func sessions(touching path: String, in folder: String) -> [TerminalSession] {
        let ids = changes[folder]?.touchedBy[path] ?? []
        return allSessions.filter { ids.contains($0.id) }
    }
}
