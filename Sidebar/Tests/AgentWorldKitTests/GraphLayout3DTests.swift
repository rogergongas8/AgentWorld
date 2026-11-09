import Testing
@testable import AgentWorldKit

@Suite struct GraphLayout3DTests {
    /// Two triangles joined by one link (6 nodes), plus `loose` unlinked files.
    private func sample(loose: Int = 0) -> (nodes: Int, edges: [(Int, Int)], clusters: [Int], groups: [Int]) {
        let edges = [(0, 1), (1, 2), (2, 0), (3, 4), (4, 5), (5, 3), (2, 3)]
        let nodes = 6 + loose
        let clusters = [0, 0, 0, 1, 1, 1] + (0..<loose).map { 2 + $0 }
        let groups = [0, 0, 0, 1, 1, 1] + (0..<loose).map { $0 % 3 }
        return (nodes, edges, clusters, groups)
    }

    @Test func isDeterministicAndFinite() {
        let g = sample(loose: 10)
        let a = GraphLayout3D.layout(nodes: g.nodes, edges: g.edges, clusters: g.clusters, groups: g.groups)
        let b = GraphLayout3D.layout(nodes: g.nodes, edges: g.edges, clusters: g.clusters, groups: g.groups)
        #expect(a == b)
        #expect(a.count == g.nodes)
        #expect(a.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
    }

    @Test func linkedFilesClusterTogether() {
        let g = sample()
        let p = GraphLayout3D.layout(nodes: g.nodes, edges: g.edges, clusters: g.clusters, groups: g.groups)
        func distance(_ a: Int, _ b: Int) -> Double {
            let dx = p[a].x - p[b].x, dy = p[a].y - p[b].y, dz = p[a].z - p[b].z
            return (dx * dx + dy * dy + dz * dz).squareRoot()
        }
        let inside = (distance(0, 1) + distance(1, 2) + distance(0, 2) + distance(3, 4) + distance(4, 5) + distance(3, 5)) / 6
        let across = (distance(0, 4) + distance(0, 5) + distance(1, 4) + distance(1, 5)) / 4
        #expect(inside < across)
    }

    @Test func unlinkedFilesSitOnAShellOutsideTheCloud() {
        let g = sample(loose: 12)
        let p = GraphLayout3D.layout(nodes: g.nodes, edges: g.edges, clusters: g.clusters, groups: g.groups)
        let cloud = (0..<6).map { p[$0].length }.max() ?? 0
        let shell = (6..<g.nodes).map { p[$0].length }
        #expect(shell.allSatisfy { $0 >= cloud })
        // They share one radius: an orderly shell, not a scatter.
        #expect((shell.max() ?? 0) - (shell.min() ?? 0) < 1e-6)
    }

    @Test func fitsInsideTheRadius() {
        let g = sample(loose: 5)
        let p = GraphLayout3D.layout(nodes: g.nodes, edges: g.edges, clusters: g.clusters, groups: g.groups, radius: 300)
        #expect(p.allSatisfy { $0.length <= 300.0001 })
    }

    @Test func handlesNoLinksAndNoNodes() {
        #expect(GraphLayout3D.layout(nodes: 0, edges: [], clusters: [], groups: []).isEmpty)
        let lone = GraphLayout3D.layout(nodes: 4, edges: [], clusters: [0, 1, 2, 3], groups: [0, 0, 1, 1])
        #expect(lone.count == 4 && lone.allSatisfy { $0.length.isFinite })
    }
}
