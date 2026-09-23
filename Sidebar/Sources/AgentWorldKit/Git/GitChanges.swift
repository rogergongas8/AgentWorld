import Foundation

/// A file that differs from HEAD in a working tree.
public struct FileChange: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable {
        case modified, added, deleted, renamed, untracked, conflicted
    }

    /// Relative to the repository root.
    public let path: String
    public let kind: Kind
    /// Lines added and removed against HEAD; nil for binaries.
    public let added: Int?
    public let removed: Int?

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
    public var folder: String { (path as NSString).deletingLastPathComponent }

    public init(path: String, kind: Kind, added: Int?, removed: Int?) {
        self.path = path
        self.kind = kind
        self.added = added
        self.removed = removed
    }
}

/// Reads uncommitted changes with the `git` command line, the same view
/// any CLI gets with `git status` and `git diff`.
public enum GitChanges {
    /// Changes in `folder`'s repository, or nil when it isn't one.
    public static func read(_ folder: String) -> (root: String, changes: [FileChange])? {
        guard let root = run(["rev-parse", "--show-toplevel"], in: folder)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !root.isEmpty,
              let status = run(["status", "--porcelain=v1", "-z", "--untracked-files=all"], in: root) else { return nil }
        let counts = numstat(in: root)
        return (root, parseStatus(status).map { path, kind in
            let count = counts[path]
            let untrackedLines = kind == .untracked ? lineCount(URL(fileURLWithPath: root).appendingPathComponent(path)) : nil
            return FileChange(path: path, kind: kind, added: count?.added ?? untrackedLines, removed: count?.removed ?? (kind == .untracked ? 0 : nil))
        })
    }

    /// The unified diff of one file against HEAD (a new file: all of it).
    public static func diff(_ change: FileChange, root: String) -> String {
        if change.kind == .untracked {
            return run(["diff", "--no-color", "--no-index", "--", "/dev/null", change.path], in: root, allowFailure: true) ?? ""
        }
        let head = run(["diff", "--no-color", "HEAD", "--", change.path], in: root) ?? ""
        // No commit yet: against the index.
        return head.isEmpty ? (run(["diff", "--no-color", "--cached", "--", change.path], in: root) ?? "") : head
    }

    /// `git status --porcelain=v1 -z` entries: "XY path\0" (renames add "\0old").
    static func parseStatus(_ output: String) -> [(String, FileChange.Kind)] {
        var result: [(String, FileChange.Kind)] = []
        var entries = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)[...]
        while let entry = entries.popFirst() {
            guard entry.count > 3 else { continue }
            let code = String(entry.prefix(2))
            let path = String(entry.dropFirst(3))
            let kind: FileChange.Kind
            switch code {
            case "??": kind = .untracked
            case "DD", "AU", "UD", "UA", "DU", "AA", "UU": kind = .conflicted
            default:
                if code.contains("R") || code.contains("C") {
                    kind = .renamed
                    _ = entries.popFirst()   // the old name
                } else if code.contains("D") {
                    kind = .deleted
                } else if code.contains("A") {
                    kind = .added
                } else {
                    kind = .modified
                }
            }
            result.append((path, kind))
        }
        return result
    }

    /// Added and removed lines per path, staged and not, against HEAD.
    private static func numstat(in root: String) -> [String: (added: Int?, removed: Int?)] {
        guard let output = run(["diff", "--numstat", "-z", "HEAD"], in: root) ?? run(["diff", "--numstat", "-z", "--cached"], in: root) else { return [:] }
        var result: [String: (Int?, Int?)] = [:]
        var fields = output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)[...]
        while let field = fields.popFirst() {
            let parts = field.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else { continue }
            var path = parts.count == 3 ? parts[2] : ""
            // A rename: the paths follow as their own fields, old then new.
            if path.isEmpty {
                _ = fields.popFirst()
                path = fields.popFirst() ?? ""
            }
            result[path] = (Int(parts[0]), Int(parts[1]))
        }
        return result
    }

    private static func lineCount(_ url: URL) -> Int? {
        guard let data = try? Data(contentsOf: url), data.count < 5_000_000, !data.contains(0) else { return nil }
        let count = data.reduce(0) { $1 == 10 ? $0 + 1 : $0 }
        return data.last == 10 || data.isEmpty ? count : count + 1
    }

    @discardableResult
    static func run(_ arguments: [String], in folder: String, allowFailure: Bool = false) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder, "-c", "core.quotepath=off"] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"   // reading must never block the agents' own git
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 || allowFailure else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
