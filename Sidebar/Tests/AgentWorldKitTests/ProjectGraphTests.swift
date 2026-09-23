import Foundation
import Testing
@testable import AgentWorldKit

@Suite struct ProjectGraphTests {
    private func project(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aw-graph-\(UUID().uuidString)")
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    private func edges(_ graph: ProjectGraph) -> Set<String> {
        Set(graph.edges.map { graph.nodes[$0.from].name + "→" + graph.nodes[$0.to].name })
    }

    @Test func typeScriptAndPythonImports() throws {
        let files = [
            "src/app.tsx": "import { Button } from './ui/Button'\nimport x from 'react'\nconst y = require('../lib/util')",
            "src/ui/Button.tsx": "export const Button = 1",
            "src/ui/index.ts": "export * from './Button'",
            "lib/util.js": "module.exports = {}",
            "pkg/a.py": "from .b import thing\nimport pkg.c",
            "pkg/b.py": "thing = 1",
            "pkg/c.py": "",
        ]
        let root = try project(files)
        defer { try? FileManager.default.removeItem(at: root) }
        let graph = ProjectGraph.build(root: root.path, files: files.keys.sorted())
        let found = edges(graph)
        #expect(found.contains("app.tsx→Button.tsx"))
        #expect(found.contains("app.tsx→util.js"))
        #expect(found.contains("index.ts→Button.tsx"))
        #expect(found.contains("a.py→b.py"))
        #expect(found.contains("a.py→c.py"))
        #expect(!found.contains { $0.contains("react") })
    }

    @Test func swiftTypesLinkFiles() throws {
        let files = [
            "Sources/App/Model.swift": "struct AppModel { var store: SessionStore }",
            "Sources/Kit/Store.swift": "public final class SessionStore {}",
            "Sources/App/View.swift": "struct RootView { let model: AppModel }",
            "README.md": "# not code",
        ]
        let root = try project(files)
        defer { try? FileManager.default.removeItem(at: root) }
        let graph = ProjectGraph.build(root: root.path, files: files.keys.sorted())
        #expect(graph.nodes.count == 3)
        #expect(edges(graph) == ["Model.swift→Store.swift", "View.swift→Model.swift"])
        // Everything is under Sources/: the groups go one level deeper.
        #expect(Set(graph.nodes.map(\.group)) == ["Sources/App", "Sources/Kit"])
    }

    @Test func layoutIsStableAndSpreadsNodes() {
        let edges = [(0, 1), (1, 2), (3, 4)]
        let a = GraphLayout.layout(nodes: 6, edges: edges, groups: [0, 0, 0, 1, 1, 2], iterations: 80)
        let b = GraphLayout.layout(nodes: 6, edges: edges, groups: [0, 0, 0, 1, 1, 2], iterations: 80)
        #expect(a == b)
        func distance(_ i: Int, _ j: Int) -> Double { hypot(a[i].x - a[j].x, a[i].y - a[j].y) }
        #expect(distance(0, 1) < distance(0, 5))
        #expect(a.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }
}
