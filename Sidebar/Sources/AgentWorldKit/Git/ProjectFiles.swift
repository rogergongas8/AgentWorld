import Foundation

/// The files of a project, relative to its folder: what git tracks (plus
/// new files it doesn't ignore), or a plain walk that skips the usual
/// build and dependency folders when it isn't a repository.
public enum ProjectFiles {
    public static let limit = 20_000
    static let skipped: Set<String> = ["node_modules", ".build", "build", "dist", "DerivedData", "Pods", ".git", ".venv",
                                       "venv", "__pycache__", "target", ".next", ".swiftpm", "vendor", ".gradle", "out"]

    public static func list(_ folder: String) -> [String] {
        if let output = GitChanges.run(["ls-files", "-co", "--exclude-standard", "-z"], in: folder) {
            let files = output.split(separator: "\0").map(String.init)
            if !files.isEmpty { return Array(files.prefix(limit)) }
        }
        return walk(folder)
    }

    static func walk(_ folder: String) -> [String] {
        let root = URL(fileURLWithPath: folder, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                              options: [.skipsHiddenFiles]) else { return [] }
        var files: [String] = []
        let prefix = root.standardizedFileURL.path + "/"
        for case let url as URL in enumerator {
            if skipped.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false else { continue }
            let path = url.standardizedFileURL.path
            files.append(path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path)
            if files.count >= limit { break }
        }
        return files.sorted()
    }
}
