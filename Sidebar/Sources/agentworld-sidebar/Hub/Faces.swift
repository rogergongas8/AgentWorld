import Foundation
import TerminalUI

/// Head-and-shoulders crops of the characters, 10×6 pixels (10 columns × 3
/// rows): the faces on the hub's launcher buttons and agent list.
enum Face {
    static let width = 10
    static let rows = 3

    static func render(_ figure: CharacterCard.Figure, pose: Pose, background: RGB? = nil) -> PixelCanvas {
        var pixels = PixelCanvas(width: width, height: rows * 2)
        if let background { pixels.rect(x: 0, y: 0, width: width, height: rows * 2, background) }
        var pose = pose
        // Faces don't hop off their frame or carry props.
        pose.dy = min(0, max(-1, pose.dy))
        pose.props = []
        switch figure {
        case .claude:
            // Centered on the eyes; the body fills the frame.
            CharacterPainter.drawClaude(on: &pixels, x: -3, ground: CharacterPainter.claudeSize.height, pose: pose)
        case .crew(let look):
            CharacterPainter.drawCrew(on: &pixels, look: look, x: 0, ground: CharacterPainter.crewSize.height, pose: pose)
        }
        return pixels
    }
}
