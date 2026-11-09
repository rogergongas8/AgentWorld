import Foundation
import Testing
@testable import AgentWorldKit

@Suite struct GraphAnalysisTests {
    // Two triangles joined by one link: 0-1-2 and 3-4-5, bridge 2-3.
    let edges = [(0, 1), (1, 2), (2, 0), (3, 4), (4, 5), (5, 3), (2, 3)]

    @Test func findsTheTwoClusters() {
        let community = GraphAnalysis.communities(nodes: 6, edges: edges)
        #expect(community[0] == community[1])
        #expect(community[1] == community[2])
        #expect(community[3] == community[4])
        #expect(community[4] == community[5])
        #expect(community[0] != community[3])
    }

    @Test func hubsBridgesAndPaths() {
        let hubs = GraphAnalysis.hubs(nodes: 6, edges: edges, count: 2)
        #expect(hubs.map(\.node) == [2, 3])
        #expect(hubs.first?.degree == 3)

        let community = GraphAnalysis.communities(nodes: 6, edges: edges)
        let bridges = GraphAnalysis.bridges(edges: edges, community: community)
        #expect(bridges.count == 1)
        #expect(bridges.first.map { [$0.0, $0.1] } == [2, 3])

        #expect(GraphAnalysis.path(from: 0, to: 5, nodes: 6, edges: edges) == [0, 2, 3, 5])
        #expect(GraphAnalysis.path(from: 0, to: 0, nodes: 6, edges: edges) == [0])
        #expect(GraphAnalysis.path(from: 0, to: 6, nodes: 7, edges: edges) == nil)
    }
}
