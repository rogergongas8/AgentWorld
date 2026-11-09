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
    /// Clusters found in the links (biggest first), and a name for each:
    /// the folder most of it lives in and its best-connected file.
    let cluster: [Int]
    let clusterNames: [String]
    /// The most connected files, and the links between clusters that are rarest.
    let hubs: [(node: Int, degree: Int)]
    let bridges: [(Int, Int)]

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
        let links = graph.edges.map { ($0.from, $0.to) }
        let cluster = GraphAnalysis.communities(nodes: graph.nodes.count, edges: links)
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
    /// Builds (or rebuilds) the map of `folder` off the main thread.
    func buildProjectMap(_ folder: String) {
        guard !mapBuilding else { return }
        mapBuilding = true
        Task.detached(priority: .userInitiated) {
            let map = ProjectMap(folder: folder, graph: ProjectGraph.build(root: folder, files: ProjectFiles.list(folder)))
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

// MARK: - For agents (agentworld-ctl map)

extension AppModel {
    /// The files map of `folder`: the one on screen if it's that folder's,
    /// else built now (off the main thread).
    func fileMap(for folder: String) async -> ProjectMap {
        if let map = projectMap, map.folder == folder { return map }
        return await Task.detached(priority: .userInitiated) {
            ProjectMap(folder: folder, graph: ProjectGraph.build(root: folder, files: ProjectFiles.list(folder)))
        }.value
    }
}

extension ProjectMap {
    /// A file by path, or by a unique end of its path ("AppModel.swift").
    func find(_ reference: String) -> Int? {
        let clean = reference.trimmingCharacters(in: CharacterSet(charactersIn: "./ "))
        if let exact = graph.nodes.firstIndex(where: { $0.path == clean }) { return exact }
        let matches = graph.nodes.indices.filter { graph.nodes[$0].path.hasSuffix("/" + clean) || graph.nodes[$0].name == clean }
        return matches.count == 1 ? matches[0] : nil
    }

    var overviewText: String {
        var lines = ["\(graph.nodes.count) source files, \(graph.edges.count) links (a file uses another: an import, or a type it names)", ""]
        let clusterCount = (cluster.max() ?? -1) + 1
        lines.append("Clusters (files that mostly link among themselves):")
        for id in 0..<min(clusterCount, 10) {
            let members = cluster.indices.filter { cluster[$0] == id }
            guard members.count > 1 else { continue }
            let top = members.sorted { uses[$0].count + usedBy[$0].count > uses[$1].count + usedBy[$1].count }.prefix(4)
            lines.append("  \(clusterNames[id]) — \(members.count) files: " + top.map { graph.nodes[$0].path }.joined(separator: ", "))
        }
        lines.append("")
        lines.append("Hubs (most connected, touch with care):")
        for hub in hubs.prefix(8) {
            lines.append("  \(graph.nodes[hub.node].path) — uses \(uses[hub.node].count), used by \(usedBy[hub.node].count)")
        }
        if !bridges.isEmpty {
            lines.append("")
            lines.append("Surprising links (between clusters that rarely touch):")
            for (a, b) in bridges.prefix(6) { lines.append("  \(graph.nodes[a].path) → \(graph.nodes[b].path)") }
        }
        return lines.joined(separator: "\n")
    }

    func fileText(_ index: Int) -> String {
        let node = graph.nodes[index]
        var lines = ["\(node.path) — \(node.lines) lines, cluster \(clusterNames[cluster[index]])", ""]
        lines.append("Uses (\(uses[index].count)):")
        lines += uses[index].map { "  " + graph.nodes[$0].path }.sorted()
        lines.append("Used by (\(usedBy[index].count)) — what may break if it changes:")
        lines += usedBy[index].map { "  " + graph.nodes[$0].path }.sorted()
        return lines.joined(separator: "\n")
    }
}
