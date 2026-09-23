import AgentWorldKit
import Foundation

/// A workspace's project map: its dependency graph laid out, ready to draw.
struct ProjectMap {
    let folder: String
    let graph: ProjectGraph
    /// Layout positions, same order as `graph.nodes`.
    let positions: [CGPoint]
    /// Folders by size, biggest first: the first eight get colors.
    let groups: [String]
    let groupOf: [Int]
    let uses: [[Int]]
    let usedBy: [[Int]]

    init(folder: String, graph: ProjectGraph) {
        self.folder = folder
        self.graph = graph
        let counts = Dictionary(grouping: graph.nodes.map(\.group), by: { $0 }).mapValues(\.count)
        groups = counts.keys.sorted { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : $0 < $1 }
        let order = Dictionary(uniqueKeysWithValues: groups.enumerated().map { ($1, $0) })
        groupOf = graph.nodes.map { order[$0.group] ?? 0 }
        var uses = [[Int]](repeating: [], count: graph.nodes.count)
        var usedBy = [[Int]](repeating: [], count: graph.nodes.count)
        for edge in graph.edges {
            uses[edge.from].append(edge.to)
            usedBy[edge.to].append(edge.from)
        }
        self.uses = uses
        self.usedBy = usedBy
        positions = GraphLayout.layout(nodes: graph.nodes.count, edges: graph.edges.map { ($0.from, $0.to) }, groups: groupOf)
            .map { CGPoint(x: $0.x, y: $0.y) }
    }

    /// The bounding box of the layout, for fitting it to the view.
    var bounds: CGRect {
        guard let first = positions.first else { return .zero }
        var box = CGRect(origin: first, size: .zero)
        for point in positions { box = box.union(CGRect(origin: point, size: .zero)) }
        return box.insetBy(dx: -30, dy: -30)
    }
}

extension AppModel {
    /// Builds (or rebuilds) the map of `folder` off the main thread.
    func buildProjectMap(_ folder: String) {
        guard !mapBuilding else { return }
        mapBuilding = true
        Task.detached(priority: .userInitiated) {
            let files = ProjectFiles.list(folder)
            let map = ProjectMap(folder: folder, graph: ProjectGraph.build(root: folder, files: files))
            await MainActor.run {
                self.mapBuilding = false
                self.projectMap = map
            }
        }
    }

    func openProjectMap() {
        showsMap = true
        if projectMap?.folder != selectedFolder { projectMap = nil }
        buildProjectMap(selectedFolder)
        refreshChanges(selectedFolder)
    }

    /// Changes keyed by path relative to the workspace (git reports them
    /// relative to the repository, which may be a folder above).
    func changesByWorkspacePath(_ folder: String) -> [String: FileChange] {
        guard let changes = changes[folder] else { return [:] }
        let prefix = folder.hasPrefix(changes.root + "/") ? String(folder.dropFirst(changes.root.count + 1)) + "/" : ""
        var result: [String: FileChange] = [:]
        for file in changes.files where prefix.isEmpty || file.path.hasPrefix(prefix) {
            result[String(file.path.dropFirst(prefix.count))] = file
        }
        return result
    }
}
