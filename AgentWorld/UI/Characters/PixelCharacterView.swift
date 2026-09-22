import SwiftUI

/// Renders one agent's pixel sprite. The outline isn't hand-authored in the
/// grid — it's generated automatically as any empty cell adjacent to a
/// filled one, drawn in black beneath the fill pass. This is what makes a
/// grid of colored squares read as "pixel art" instead of a blob of color:
/// real sprites are outlined, and computing it saves hand-placing every
/// border pixel whenever the shape changes.
struct PixelCharacterView: View {
    let agentName: String?
    let status: AgentStatus
    var pixelSize: CGFloat = 10

    @State private var startDate = Date()

    private var width: CGFloat { pixelSize * CGFloat(PixelCharacterSprite.width) }
    private var height: CGFloat { pixelSize * CGFloat(PixelCharacterSprite.height) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 8.0)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            let pose = PixelPose.forStatus(status, elapsed: elapsed)
            let costume = PixelCostume.forAgent(named: agentName)
            let grid = PixelCharacterSprite.grid(costume: costume, armsUp: pose.armsUp)

            Canvas { graphicsContext, _ in
                draw(grid: grid, costume: costume, pose: pose, into: graphicsContext)
            }
            .frame(width: width, height: height)
        }
        .onChange(of: agentName) { _, _ in startDate = Date() }
    }

    private func draw(grid: [[PixelCellKind]], costume: PixelCostume, pose: PixelPose, into context: GraphicsContext) {
        let cols = PixelCharacterSprite.width
        let rows = PixelCharacterSprite.height

        func isFilled(_ row: Int, _ col: Int) -> Bool {
            guard row >= 0, row < rows, col >= 0, col < cols else { return false }
            return grid[row][col] != .empty
        }

        for row in 0..<rows {
            for col in 0..<cols {
                guard !isFilled(row, col) else { continue }
                let hasFilledNeighbor = isFilled(row - 1, col) || isFilled(row + 1, col)
                    || isFilled(row, col - 1) || isFilled(row, col + 1)
                guard hasFilledNeighbor else { continue }
                context.fill(Path(cellRect(row: row, col: col, pose: pose)), with: .color(.black))
            }
        }

        for row in 0..<rows {
            for col in 0..<cols {
                let kind = grid[row][col]
                guard kind != .empty else { continue }
                let rect = cellRect(row: row, col: col, pose: pose)
                let color = costume.color(for: kind, accent: pose.accentColor)
                context.fill(Path(rect), with: .color(Color(nsColor: color)))
                if let tint = pose.tint {
                    var glow = context
                    glow.blendMode = .plusLighter
                    glow.fill(Path(rect), with: .color(Color(nsColor: tint)))
                }
            }
        }
    }

    private func cellRect(row: Int, col: Int, pose: PixelPose) -> CGRect {
        CGRect(
            x: CGFloat(col + pose.horizontalOffset) * pixelSize,
            y: CGFloat(row + pose.verticalOffset) * pixelSize,
            width: pixelSize,
            height: pixelSize
        )
    }
}
