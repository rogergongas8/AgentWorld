import AgentWorldKit
import Foundation

/// A workspace's project map: its dependency graph laid out, ready to draw.
struct ProjectMap {
    let folder: String
    /// Files (the app's own reading), or symbols from graphify's graph.
    let symbols: Bool
    let graph: ProjectGraph
    /// Layout positions, same order as `graph.nodes`.
    let positions: [CGPoint]
    /// Folders by size, biggest first: the first eight get colors.
    let groups: [String]
    let groupOf: [Int]
    let uses: [[Int]]
    let usedBy: [[Int]]
    /// Clusters found in the links (biggest first), and a name for each:
    /// the folder most of it lives in and its best-connected file.
    let cluster: [Int]
    let clusterNames: [String]
    /// The most connected files, and the links between clusters that are rarest.
    let hubs: [(node: Int, degree: Int)]
    let bridges: [(Int, Int)]

    init(folder: String, graph: ProjectGraph, symbols: Bool = false, communities: [Int]? = nil) {
        self.folder = folder
        self.symbols = symbols
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
        let links = graph.edges.map { ($0.from, $0.to) }
        // graphify's own communities when it found them; ours otherwise.
        let cluster = communities.map { raw -> [Int] in
            let sizes = Dictionary(grouping: raw, by: { $0 }).mapValues(\.count)
            let order = sizes.keys.sorted { sizes[$0]! != sizes[$1]! ? sizes[$0]! > sizes[$1]! : $0 < $1 }
            let dense = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            return raw.map { dense[$0]! }
        } ?? GraphAnalysis.communities(nodes: graph.nodes.count, edges: links)
        self.cluster = cluster
        hubs = GraphAnalysis.hubs(nodes: graph.nodes.count, edges: links, count: 8)
        bridges = GraphAnalysis.bridges(edges: links, community: cluster, count: 6)
        let clusterCount = (cluster.max() ?? -1) + 1
        clusterNames = (0..<clusterCount).map { id in
            let members = cluster.indices.filter { cluster[$0] == id }
            let folders = Dictionary(grouping: members.map { graph.nodes[$0].group }, by: { $0 }).mapValues(\.count)
            let folder = folders.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? ""
            let hub = members.max { uses[$0].count + usedBy[$0].count < uses[$1].count + usedBy[$1].count }
            let short = (folder as NSString).lastPathComponent
            if symbols, let hub { return short + " · " + graph.nodes[hub].name }
            return members.count == 1 ? graph.nodes[members[0]].name
                : short + (hub.map { " · " + ((graph.nodes[$0].name as NSString).deletingPathExtension) } ?? "")
        }
        // Clusters get their own area, so they read as islands.
        positions = GraphLayout.layout(nodes: graph.nodes.count, edges: links, groups: cluster)
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
    /// Builds (or rebuilds) the map of `folder` off the main thread: files,
    /// or graphify's symbols when asked and it has a graph there.
    func buildProjectMap(_ folder: String, symbols: Bool? = nil) {
        guard !mapBuilding else { return }
        mapBuilding = true
        let wantsSymbols = symbols ?? (projectMap?.folder == folder ? projectMap?.symbols ?? false : false)
        Task.detached(priority: .userInitiated) {
            let map: ProjectMap
            if wantsSymbols, let graphify = GraphifyGraph.load(folder: folder) {
                let converted = graphify.projectGraph(root: folder)
                map = ProjectMap(folder: folder, graph: converted.graph, symbols: true, communities: converted.communities)
            } else {
                map = ProjectMap(folder: folder, graph: ProjectGraph.build(root: folder, files: ProjectFiles.list(folder)))
            }
            await MainActor.run {
                self.mapBuilding = false
                self.projectMap = map
            }
        }
    }

    /// Whether graphify has left a graph in `folder` (graphify-out/graph.json).
    func hasGraphify(_ folder: String) -> Bool {
        FileManager.default.fileExists(atPath: GraphifyGraph.url(in: folder).path)
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
