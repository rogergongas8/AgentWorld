import Foundation

/// A project's source files and how they depend on each other, for the
/// app's project map. Language-agnostic by design: relative imports where a
/// language has them (JS/TS, Python, C, CSS), and for the languages that
/// share a module (Swift, Kotlin, Java, C#, Go, Rust, Dart…) an edge from a
/// file to the file that declares a type it names.
public struct ProjectGraph: Sendable, Equatable {
    public struct Node: Sendable, Equatable, Identifiable {
        public let path: String
        /// The folder it belongs to, for color: the first folder under the
        /// project that tells files apart (`Sources/App` rather than `Sources`).
        public let group: String
        public let lines: Int
        public var id: String { path }
        public var name: String { (path as NSString).lastPathComponent }
    }

    public struct Edge: Sendable, Equatable, Hashable {
        /// Node indices: `from` uses `to`.
        public let from: Int
        public let to: Int
    }

    public let nodes: [Node]
    public let edges: [Edge]

    public static let maxNodes = 900
    static let sourceExtensions: Set<String> = [
        "swift", "ts", "tsx", "js", "jsx", "mjs", "cjs", "py", "go", "rs", "kt", "kts", "java", "cs", "rb", "php",
        "c", "h", "m", "mm", "cc", "cpp", "hpp", "vue", "svelte", "dart", "scala", "ex", "exs", "lua", "css", "scss",
    ]
    /// Languages where files see each other's types without an import line.
    static let symbolLanguages: Set<String> = ["swift", "kt", "kts", "java", "cs", "go", "rs", "dart", "scala", "m", "mm", "php", "rb"]

    /// Builds the graph from `files` (relative paths) under `root`.
    public static func build(root: String, files: [String]) -> ProjectGraph {
        let sources = files.filter { sourceExtensions.contains(($0 as NSString).pathExtension.lowercased()) && !isVendored($0) }
            .prefix(maxNodes)
        let rootURL = URL(fileURLWithPath: root)
        var texts: [String] = []
        var nodes: [Node] = []
        for path in sources {
            let text = (try? String(contentsOf: rootURL.appendingPathComponent(path), encoding: .utf8)) ?? ""
            texts.append(text)
            nodes.append(Node(path: path, group: "", lines: text.reduce(into: 1) { if $1 == "\n" { $0 += 1 } }))
        }
        let groups = groupNames(nodes.map(\.path))
        nodes = nodes.enumerated().map { index, node in Node(path: node.path, group: groups[index], lines: node.lines) }

        let index = Dictionary(nodes.enumerated().map { ($1.path, $0) }, uniquingKeysWith: { first, _ in first })
        var edges = Set<Edge>()

        // Relative imports.
        for (from, node) in nodes.enumerated() {
            for target in importedPaths(in: texts[from], of: node.path) {
                if let to = resolve(target, in: index), to != from { edges.insert(Edge(from: from, to: to)) }
            }
        }

        // Named types, for the languages that don't import files.
        var declaredIn: [String: Int] = [:]
        var ambiguous = Set<String>()
        for (i, node) in nodes.enumerated() where symbolLanguages.contains((node.path as NSString).pathExtension.lowercased()) {
            for name in declaredTypes(in: texts[i]) {
                if let other = declaredIn[name], other != i { ambiguous.insert(name) } else { declaredIn[name] = i }
            }
        }
        for name in ambiguous { declaredIn[name] = nil }
        if !declaredIn.isEmpty {
            for (from, node) in nodes.enumerated() where symbolLanguages.contains((node.path as NSString).pathExtension.lowercased()) {
                for word in capitalizedWords(in: texts[from]) {
                    if let to = declaredIn[word], to != from { edges.insert(Edge(from: from, to: to)) }
                }
            }
        }
        return ProjectGraph(nodes: nodes, edges: edges.sorted { ($0.from, $0.to) < ($1.from, $1.to) })
    }

    // MARK: - Groups

    /// The shortest folder prefix that still separates files: skips folders
    /// everything shares (`Sources/`, `src/`), up to two levels deep.
    static func groupNames(_ paths: [String]) -> [String] {
        let parts = paths.map { ($0 as NSString).deletingLastPathComponent.split(separator: "/").map(String.init) }
        var depth = 1
        // Go one level deeper while the first level puts nearly everything in one bucket.
        let firstLevel = Dictionary(grouping: parts.compactMap(\.first), by: { $0 }).mapValues(\.count)
        if let biggest = firstLevel.values.max(), Double(biggest) > Double(paths.count) * 0.7 { depth = 2 }
        if depth == 2 {
            let secondLevel = Dictionary(grouping: parts.filter { $0.count >= 2 }.map { $0[0] + "/" + $0[1] }, by: { $0 }).mapValues(\.count)
            if let biggest = secondLevel.values.max(), Double(biggest) > Double(paths.count) * 0.7 { depth = 3 }
        }
        return parts.map { $0.isEmpty ? "(root)" : $0.prefix(depth).joined(separator: "/") }
    }

    private static func isVendored(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        return parts.contains { ProjectFiles.skipped.contains(String($0)) } || path.hasSuffix(".min.js") || path.contains(".generated.")
    }

    // MARK: - Imports

    /// Relative paths this file imports, already joined to its folder.
    static func importedPaths(in text: String, of path: String) -> [String] {
        let ext = (path as NSString).pathExtension.lowercased()
        let folder = (path as NSString).deletingLastPathComponent
        var targets: [String] = []
        func relative(_ spec: String) {
            guard spec.hasPrefix("./") || spec.hasPrefix("../") else { return }
            targets.append(normalize(folder.isEmpty ? spec : folder + "/" + spec))
        }
        switch ext {
        case "ts", "tsx", "js", "jsx", "mjs", "cjs", "vue", "svelte":
            for spec in matches(#"(?:from\s+|import\s*\(?\s*|require\s*\(\s*)['"]([^'"]+)['"]"#, in: text) { relative(spec) }
        case "css", "scss":
            for spec in matches(#"@import\s+['"]([^'"]+)['"]"#, in: text) { relative(spec.hasPrefix(".") ? spec : "./" + spec) }
        case "c", "h", "m", "mm", "cc", "cpp", "hpp":
            for spec in matches(#"#\s*(?:include|import)\s+"([^"]+)""#, in: text) { relative("./" + spec) }
        case "py":
            // from .a.b import c  /  from ..pkg import x
            for spec in matches(#"(?m)^\s*from\s+(\.+[\w.]*)\s+import"#, in: text) {
                let dots = spec.prefix { $0 == "." }.count
                let rest = spec.dropFirst(dots).replacingOccurrences(of: ".", with: "/")
                let up = String(repeating: "../", count: max(0, dots - 1))
                relative("./" + up + rest)
            }
            // import pkg.mod (absolute, within the project)
            for spec in matches(#"(?m)^\s*(?:from|import)\s+([A-Za-z_][\w.]*)"#, in: text) {
                targets.append(spec.replacingOccurrences(of: ".", with: "/"))
            }
        default:
            break
        }
        return targets
    }

    /// A target path to a file: exact, with the language's extensions, or an index file.
    static func resolve(_ target: String, in index: [String: Int]) -> Int? {
        if let hit = index[target] { return hit }
        let extensions = ["ts", "tsx", "js", "jsx", "mjs", "vue", "svelte", "py", "h", "css", "scss"]
        for ext in extensions { if let hit = index[target + "." + ext] { return hit } }
        for name in ["index.ts", "index.tsx", "index.js", "index.jsx", "__init__.py"] {
            if let hit = index[target + "/" + name] { return hit }
        }
        // Python's absolute imports: a suffix of a project path.
        if !target.contains("."), target.contains("/") || !target.isEmpty {
            if let hit = index.first(where: { $0.key.hasSuffix("/" + target + ".py") })?.value { return hit }
        }
        return nil
    }

    static func normalize(_ path: String) -> String {
        var parts: [String] = []
        for part in path.split(separator: "/") {
            switch part {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(String(part))
            }
        }
        return parts.joined(separator: "/")
    }

    // MARK: - Types

    /// Type names a file declares: class, struct, enum, protocol, interface…
    static func declaredTypes(in text: String) -> [String] {
        matches(#"\b(?:class|struct|enum|protocol|actor|interface|record|trait|object|typealias|type)\s+([A-Z][A-Za-z0-9_]{2,})"#, in: text)
    }

    /// Capitalized identifiers, the way types are written in these languages.
    static func capitalizedWords(in text: String) -> Set<String> {
        Set(matches(#"\b([A-Z][A-Za-z0-9_]{2,})\b"#, in: text))
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
}
