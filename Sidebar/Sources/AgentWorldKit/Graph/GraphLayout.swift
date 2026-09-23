import Foundation

/// Places a graph's nodes so linked files sit together and the rest spread
/// out (Fruchterman–Reingold forces, with a grid for the repulsion so a few
/// hundred files lay out in a blink). Deterministic: the same graph always
/// comes out the same, so the map doesn't reshuffle on every refresh.
public enum GraphLayout {
    public struct Point: Sendable, Equatable {
        public var x: Double
        public var y: Double
    }

    /// Positions in a square about `size` wide, centered on 0.
    public static func layout(nodes: Int, edges: [(Int, Int)], groups: [Int], size: Double = 1000, iterations: Int = 220) -> [Point] {
        guard nodes > 0 else { return [] }
        let groupCount = (groups.max() ?? 0) + 1
        // Start each folder in its own slice of a circle, so folders cluster.
        var random = SplitMix(seed: UInt64(nodes * 7919 + edges.count))
        var positions = (0..<nodes).map { index -> Point in
            let slice = Double(groups[index]) / Double(max(1, groupCount)) * 2 * .pi
            let radius = size * 0.3 * (0.4 + 0.6 * random.unit())
            return Point(x: cos(slice) * radius + (random.unit() - 0.5) * size * 0.1,
                         y: sin(slice) * radius + (random.unit() - 0.5) * size * 0.1)
        }
        let area = size * size
        let k = sqrt(area / Double(nodes)) * 0.9
        var temperature = size * 0.1
        let cell = k * 2
        for _ in 0..<iterations {
            var shift = [Point](repeating: Point(x: 0, y: 0), count: nodes)
            // Repulsion between neighbors in the grid only.
            var grid: [Int64: [Int]] = [:]
            for (i, p) in positions.enumerated() { grid[key(p, cell), default: []].append(i) }
            for (i, p) in positions.enumerated() {
                let cx = Int64((p.x / cell).rounded(.down)), cy = Int64((p.y / cell).rounded(.down))
                for dx in -1...1 {
                    for dy in -1...1 {
                        for j in grid[(cx + Int64(dx)) << 32 ^ (cy + Int64(dy)) & 0xFFFF_FFFF] ?? [] where j != i {
                            let ddx = p.x - positions[j].x, ddy = p.y - positions[j].y
                            let distance = max(0.01, sqrt(ddx * ddx + ddy * ddy))
                            let force = k * k / distance
                            shift[i].x += ddx / distance * force
                            shift[i].y += ddy / distance * force
                        }
                    }
                }
            }
            // Attraction along edges.
            for (a, b) in edges where a != b && a < nodes && b < nodes {
                let ddx = positions[a].x - positions[b].x, ddy = positions[a].y - positions[b].y
                let distance = max(0.01, sqrt(ddx * ddx + ddy * ddy))
                let force = distance * distance / k
                let fx = ddx / distance * force, fy = ddy / distance * force
                shift[a].x -= fx; shift[a].y -= fy
                shift[b].x += fx; shift[b].y += fy
            }
            // A gentle pull to the middle keeps loose files from drifting off.
            for i in 0..<nodes {
                shift[i].x -= positions[i].x * 0.02 * k / 10
                shift[i].y -= positions[i].y * 0.02 * k / 10
                let length = max(0.01, sqrt(shift[i].x * shift[i].x + shift[i].y * shift[i].y))
                let step = min(length, temperature)
                positions[i].x += shift[i].x / length * step
                positions[i].y += shift[i].y / length * step
            }
            temperature = max(size * 0.002, temperature * 0.97)
        }
        return positions
    }

    private static func key(_ p: Point, _ cell: Double) -> Int64 {
        let cx = Int64((p.x / cell).rounded(.down)), cy = Int64((p.y / cell).rounded(.down))
        return cx << 32 ^ cy & 0xFFFF_FFFF
    }

    /// A tiny seeded generator, so layouts repeat.
    struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    }
}
