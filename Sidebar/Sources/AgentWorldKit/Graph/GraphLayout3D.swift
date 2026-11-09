import Foundation

/// A 3D layout for the project map. Linked files are placed by forces in a
/// ball (clusters get their own region, so they read as islands); files
/// with no links at all stay out of the forces and sit on an orderly shell
/// around the cloud, folder by folder, instead of smearing over the middle.
/// Deterministic: the same graph always comes out the same.
public enum GraphLayout3D {
    public struct Point: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var z: Double

        public init(x: Double, y: Double, z: Double) {
            self.x = x
            self.y = y
            self.z = z
        }

        public var length: Double { (x * x + y * y + z * z).squareRoot() }
    }

    /// Positions within a ball of about `radius`, centered on 0.
    /// - Parameters:
    ///   - clusters: a cluster id per node (0 = the biggest); linked nodes of a
    ///     cluster start together.
    ///   - groups: a folder id per node, to keep unlinked files of a folder together.
    public static func layout(nodes: Int, edges: [(Int, Int)], clusters: [Int], groups: [Int],
                              radius: Double = 500, iterations: Int = 150) -> [Point] {
        guard nodes > 0 else { return [] }
        var degree = [Int](repeating: 0, count: nodes)
        for (a, b) in edges where a != b && a < nodes && b < nodes { degree[a] += 1; degree[b] += 1 }
        let linked = (0..<nodes).filter { degree[$0] > 0 }
        var positions = [Point](repeating: Point(x: 0, y: 0, z: 0), count: nodes)

        if !linked.isEmpty {
            place(linked: linked, edges: edges, clusters: clusters, radius: radius, iterations: iterations, into: &positions)
        }

        // Unlinked files: a shell just outside the cloud, folder by folder.
        let loose = (0..<nodes).filter { degree[$0] == 0 }.sorted {
            (groups[$0], $0) < (groups[$1], $1)
        }
        if !loose.isEmpty {
            let cloud = linked.map { positions[$0].length }.max() ?? radius * 0.5
            let shell = max(cloud * 1.22, radius * 0.45)
            for (rank, node) in loose.enumerated() {
                positions[node] = fibonacci(rank, of: loose.count, radius: shell)
            }
        }

        // Fit everything inside `radius`.
        let farthest = positions.map(\.length).max() ?? 1
        if farthest > 0 {
            let scale = radius / farthest
            for index in positions.indices {
                positions[index].x *= scale
                positions[index].y *= scale
                positions[index].z *= scale
            }
        }
        return positions
    }

    // MARK: - Linked files (forces)

    private static func place(linked: [Int], edges: [(Int, Int)], clusters: [Int], radius: Double,
                              iterations: Int, into positions: inout [Point]) {
        var random = GraphLayout.SplitMix(seed: UInt64(linked.count * 7919 + edges.count * 31 + 5))
        let count = linked.count
        let clusterIDs = Array(Set(linked.map { clusters[$0] })).sorted()
        // Each cluster starts around its own seed on a spiral: the biggest nearest the middle.
        var seed: [Int: Point] = [:]
        for (rank, id) in clusterIDs.enumerated() {
            let reach = radius * 0.74 * min(1, 0.12 + 0.88 * Double(rank) / Double(max(1, clusterIDs.count - 1)))
            seed[id] = fibonacci(rank + 1, of: clusterIDs.count + 1, radius: reach)
        }
        var x = [Double](repeating: 0, count: count)
        var y = [Double](repeating: 0, count: count)
        var z = [Double](repeating: 0, count: count)
        var slot: [Int: Int] = [:]
        for (i, node) in linked.enumerated() {
            slot[node] = i
            let origin = seed[clusters[node]] ?? Point(x: 0, y: 0, z: 0)
            let spread = radius * 0.16
            x[i] = origin.x + (random.unit() - 0.5) * spread
            y[i] = origin.y + (random.unit() - 0.5) * spread
            z[i] = origin.z + (random.unit() - 0.5) * spread
        }
        let links: [(Int, Int)] = edges.compactMap { a, b in
            guard a != b, let i = slot[a], let j = slot[b] else { return nil }
            return (i, j)
        }
        let volume = 4.0 / 3.0 * Double.pi * radius * radius * radius
        let k = cbrt(volume / Double(count)) * 0.85
        let cell = k * 2.2
        var temperature = radius * 0.12
        var fx = [Double](repeating: 0, count: count)
        var fy = [Double](repeating: 0, count: count)
        var fz = [Double](repeating: 0, count: count)

        for _ in 0..<iterations {
            for i in 0..<count { fx[i] = 0; fy[i] = 0; fz[i] = 0 }
            // Repulsion between nearby nodes only (3D grid).
            var grid: [Int: [Int]] = [:]
            for i in 0..<count { grid[cellKey(x[i], y[i], z[i], cell), default: []].append(i) }
            for i in 0..<count {
                let cx = Int((x[i] / cell).rounded(.down)), cy = Int((y[i] / cell).rounded(.down)), cz = Int((z[i] / cell).rounded(.down))
                for dx in -1...1 {
                    for dy in -1...1 {
                        for dz in -1...1 {
                            guard let bucket = grid[key(cx + dx, cy + dy, cz + dz)] else { continue }
                            for j in bucket where j != i {
                                let ex = x[i] - x[j], ey = y[i] - y[j], ez = z[i] - z[j]
                                let distance = max(0.01, (ex * ex + ey * ey + ez * ez).squareRoot())
                                let force = k * k / distance
                                fx[i] += ex / distance * force
                                fy[i] += ey / distance * force
                                fz[i] += ez / distance * force
                            }
                        }
                    }
                }
            }
            // Attraction along links.
            for (a, b) in links {
                let ex = x[a] - x[b], ey = y[a] - y[b], ez = z[a] - z[b]
                let distance = max(0.01, (ex * ex + ey * ey + ez * ez).squareRoot())
                let force = distance * distance / k
                let ux = ex / distance * force, uy = ey / distance * force, uz = ez / distance * force
                fx[a] -= ux; fy[a] -= uy; fz[a] -= uz
                fx[b] += ux; fy[b] += uy; fz[b] += uz
            }
            // A gentle pull to the middle keeps loose clusters from drifting off.
            for i in 0..<count {
                fx[i] -= x[i] * 0.03 * k / 10
                fy[i] -= y[i] * 0.03 * k / 10
                fz[i] -= z[i] * 0.03 * k / 10
                let length = max(0.01, (fx[i] * fx[i] + fy[i] * fy[i] + fz[i] * fz[i]).squareRoot())
                let step = min(length, temperature)
                x[i] += fx[i] / length * step
                y[i] += fy[i] / length * step
                z[i] += fz[i] / length * step
            }
            temperature = max(radius * 0.002, temperature * 0.972)
        }

        // Center the cloud.
        let mx = x.reduce(0, +) / Double(count), my = y.reduce(0, +) / Double(count), mz = z.reduce(0, +) / Double(count)
        for (i, node) in linked.enumerated() {
            positions[node] = Point(x: x[i] - mx, y: y[i] - my, z: z[i] - mz)
        }
    }

    // MARK: - Helpers

    /// The `index`-th of `total` points spread evenly over a sphere.
    static func fibonacci(_ index: Int, of total: Int, radius: Double) -> Point {
        let golden = Double.pi * (3 - 5.0.squareRoot())
        let t = total <= 1 ? 0.5 : Double(index) / Double(total - 1)
        let height = 1 - 2 * t
        let ring = max(0, 1 - height * height).squareRoot()
        let angle = golden * Double(index)
        return Point(x: cos(angle) * ring * radius, y: height * radius, z: sin(angle) * ring * radius)
    }

    private static func key(_ cx: Int, _ cy: Int, _ cz: Int) -> Int {
        (cx & 0x1FFFFF) << 42 ^ (cy & 0x1FFFFF) << 21 ^ (cz & 0x1FFFFF)
    }

    private static func cellKey(_ px: Double, _ py: Double, _ pz: Double, _ cell: Double) -> Int {
        key(Int((px / cell).rounded(.down)), Int((py / cell).rounded(.down)), Int((pz / cell).rounded(.down)))
    }
}
