import Foundation

/// What a graph says about a project, the way a code-graph report would: the
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
