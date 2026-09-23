import Foundation

/// What a graph says about a project, the way graphify reports it: the
/// clusters it falls into, its hubs, the links that cross clusters, and the
/// shortest way from one file to another.
public enum GraphAnalysis {
    /// Clusters by modularity (the local-moving phase of Louvain, repeated
    /// on the clusters it finds): each node joins the neighboring cluster
    /// that most raises the share of links inside clusters. Deterministic.
    /// Returned ids are dense, biggest cluster first; lone nodes get their own.
    public static func communities(nodes: Int, edges: [(Int, Int)]) -> [Int] {
        guard nodes > 0 else { return [] }
        // Undirected, one link per pair.
        var pairs = Set<[Int]>()
        for (a, b) in edges where a != b && a < nodes && b < nodes { pairs.insert([min(a, b), max(a, b)]) }
        var membership = Array(0..<nodes)
        var graph: [[Int: Double]] = Array(repeating: [:], count: nodes)
        for pair in pairs {
            graph[pair[0]][pair[1], default: 0] += 1
            graph[pair[1]][pair[0], default: 0] += 1
        }
        // Up to a few levels: move nodes, then treat each cluster as a node.
        for _ in 0..<4 {
            let local = localMoving(graph)
            let clusters = Set(local).count
            // Map original nodes through this level.
            membership = membership.map { local[$0] }
            if clusters == graph.count { break }
            var next: [[Int: Double]] = Array(repeating: [:], count: clusters)
            for (node, links) in graph.enumerated() {
                for (other, weight) in links { next[local[node]][local[other], default: 0] += weight }
            }
            graph = next
        }
        let sizes = Dictionary(grouping: membership, by: { $0 }).mapValues(\.count)
        let order = sizes.keys.sorted { sizes[$0]! != sizes[$1]! ? sizes[$0]! > sizes[$1]! : $0 < $1 }
        let dense = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return membership.map { dense[$0]! }
    }

    /// One Louvain level: returns each node's cluster, dense from 0.
    private static func localMoving(_ graph: [[Int: Double]]) -> [Int] {
        let count = graph.count
        // Self-loops (a cluster's inner links) count twice in the degree, like any link end.
        let degree = graph.enumerated().map { node, links in links.reduce(0) { $0 + ($1.key == node ? 2 * $1.value : $1.value) } }
        let twiceM = degree.reduce(0, +)
        guard twiceM > 0 else { return Array(0..<count) }
        var cluster = Array(0..<count)
        var total = degree
        var improved = true
        var passes = 0
        while improved, passes < 20 {
            improved = false
            passes += 1
            for node in 0..<count {
                let current = cluster[node]
                var weightTo: [Int: Double] = [:]
                for (other, weight) in graph[node] where other != node { weightTo[cluster[other], default: 0] += weight }
                total[current] -= degree[node]
                var best = current
                var bestGain = (weightTo[current] ?? 0) - total[current] * degree[node] / twiceM
                for (candidate, weight) in weightTo.sorted(by: { $0.key < $1.key }) {
                    let gain = weight - total[candidate] * degree[node] / twiceM
                    if gain > bestGain + 1e-12 {
                        bestGain = gain
                        best = candidate
                    }
                }
                total[best] += degree[node]
                if best != current {
                    cluster[node] = best
                    improved = true
                }
            }
        }
        let ids = Dictionary(uniqueKeysWithValues: Set(cluster).sorted().enumerated().map { ($1, $0) })
        return cluster.map { ids[$0]! }
    }

    /// The most connected nodes (links in and out), most first.
    public static func hubs(nodes: Int, edges: [(Int, Int)], count: Int = 10) -> [(node: Int, degree: Int)] {
        var degree = [Int](repeating: 0, count: nodes)
        for (a, b) in edges where a < nodes && b < nodes {
            degree[a] += 1
            degree[b] += 1
        }
        return degree.enumerated().filter { $0.element > 0 }
            .sorted { $0.element != $1.element ? $0.element > $1.element : $0.offset < $1.offset }
            .prefix(count).map { ($0.offset, $0.element) }
    }

    /// Links between different clusters, the rarest pairs first: the
    /// surprising connections, where one part of the project reaches into
    /// another.
    public static func bridges(edges: [(Int, Int)], community: [Int], count: Int = 8) -> [(Int, Int)] {
        var pairCounts: [String: Int] = [:]
        let crossing = edges.filter { community[$0.0] != community[$0.1] }
        for (a, b) in crossing {
            let key = "\(min(community[a], community[b]))-\(max(community[a], community[b]))"
            pairCounts[key, default: 0] += 1
        }
        return crossing.sorted { lhs, rhs in
            let l = pairCounts["\(min(community[lhs.0], community[lhs.1]))-\(max(community[lhs.0], community[lhs.1]))"]!
            let r = pairCounts["\(min(community[rhs.0], community[rhs.1]))-\(max(community[rhs.0], community[rhs.1]))"]!
            return l != r ? l < r : (lhs.0, lhs.1) < (rhs.0, rhs.1)
        }.prefix(count).map { $0 }
    }

    /// The shortest chain of links from `start` to `goal`, either way round
    /// (A uses B or B uses A), or nil when they aren't connected.
    public static func path(from start: Int, to goal: Int, nodes: Int, edges: [(Int, Int)]) -> [Int]? {
        guard start < nodes, goal < nodes else { return nil }
        if start == goal { return [start] }
        var neighbors = [[Int]](repeating: [], count: nodes)
        for (a, b) in edges where a < nodes && b < nodes {
            neighbors[a].append(b)
            neighbors[b].append(a)
        }
        var previous = [Int?](repeating: nil, count: nodes)
        var seen = Set([start])
        var queue = [start]
        var head = 0
        while head < queue.count {
            let node = queue[head]
            head += 1
            for next in neighbors[node].sorted() where !seen.contains(next) {
                seen.insert(next)
                previous[next] = node
                if next == goal {
                    var chain = [goal]
                    var step = node
                    while step != start { chain.append(step); step = previous[step]! }
                    chain.append(start)
                    return chain.reversed()
                }
                queue.append(next)
            }
        }
        return nil
    }
}

/// A graph graphify built (`graphify-out/graph.json`): its symbols —
/// classes, functions, modules — with the communities it found. Read
/// loosely, since the format is NetworkX's node-link JSON and its field
/// names have moved between versions.
public struct GraphifyGraph: Sendable, Equatable {
    public struct Node: Sendable, Equatable {
        public let id: String
        public let label: String
        public let kind: String
        /// The file it comes from, relative to the project when graphify says so.
        public let file: String?
        public let community: Int?
    }

    public struct Link: Sendable, Equatable {
        public let from: Int
        public let to: Int
        public let relation: String
        public let confidence: String?
    }

    public let nodes: [Node]
    public let links: [Link]

    public static func url(in folder: String) -> URL {
        URL(fileURLWithPath: folder).appendingPathComponent("graphify-out/graph.json")
    }

    public static func load(folder: String) -> GraphifyGraph? {
        guard let data = try? Data(contentsOf: url(in: folder)) else { return nil }
        return parse(data)
    }

    public static func parse(_ data: Data) -> GraphifyGraph? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawNodes = (object["nodes"] ?? (object["graph"] as? [String: Any])?["nodes"]) as? [[String: Any]] else { return nil }
        func string(_ value: Any?) -> String? {
            if let text = value as? String { return text }
            if let number = value as? NSNumber { return number.stringValue }
            return nil
        }
        var index: [String: Int] = [:]
        var nodes: [Node] = []
        for raw in rawNodes {
            guard let id = string(raw["id"] ?? raw["key"] ?? raw["name"]) else { continue }
            let file = string(raw["source_file"] ?? raw["file"] ?? raw["path"])
                ?? string(raw["source"]).map { $0.components(separatedBy: ":").first ?? $0 }
            index[id] = nodes.count
            nodes.append(Node(id: id, label: string(raw["label"] ?? raw["name"]) ?? id,
                              kind: string(raw["type"] ?? raw["file_type"] ?? raw["kind"]) ?? "node",
                              file: file, community: (raw["community"] as? NSNumber)?.intValue ?? Int(string(raw["community"]) ?? "")))
        }
        let rawLinks = (object["links"] ?? object["edges"]) as? [[String: Any]] ?? []
        let links = rawLinks.compactMap { raw -> Link? in
            guard let source = string(raw["source"]), let target = string(raw["target"]),
                  let from = index[source], let to = index[target] else { return nil }
            return Link(from: from, to: to, relation: string(raw["relation"] ?? raw["type"] ?? raw["label"]) ?? "uses",
                        confidence: string(raw["confidence"]))
        }
        return nodes.isEmpty ? nil : GraphifyGraph(nodes: nodes, links: links)
    }

    /// As a project graph for the map: each symbol a node in its file's
    /// folder, sized by how connected it is, and its communities kept.
    public func projectGraph(root: String) -> (graph: ProjectGraph, communities: [Int]?) {
        let prefix = URL(fileURLWithPath: root).standardizedFileURL.path + "/"
        func relative(_ file: String?) -> String {
            guard let file else { return "" }
            return file.hasPrefix(prefix) ? String(file.dropFirst(prefix.count)) : file
        }
        let files = nodes.map { relative($0.file) }
        let groups = ProjectGraph.groupNames(files.map { $0.isEmpty ? "(unknown)/x" : $0 })
        var degree = [Int](repeating: 0, count: nodes.count)
        for link in links { degree[link.from] += 1; degree[link.to] += 1 }
        let graphNodes = nodes.enumerated().map { index, node in
            ProjectGraph.Node(path: node.id, group: groups[index], lines: max(1, degree[index] * 25),
                              file: files[index].isEmpty ? node.id : files[index], label: node.label, kind: node.kind)
        }
        let edges = Set(links.filter { $0.from != $0.to }.map { ProjectGraph.Edge(from: $0.from, to: $0.to) })
            .sorted { ($0.from, $0.to) < ($1.from, $1.to) }
        let communities = nodes.allSatisfy { $0.community != nil } ? nodes.map { $0.community! } : nil
        return (ProjectGraph(nodes: graphNodes, edges: edges), communities)
    }
}
