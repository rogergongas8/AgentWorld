import AgentWorldKit
import Foundation
import TerminalUI

/// Head-and-shoulders crops of the characters, 10×6 pixels (10 columns × 3
/// rows): the faces on the hub's launcher buttons and agent list.
public enum Face {
    public static let width = 10
    public static let rows = 3

    public static func render(_ figure: CharacterFigure, pose: Pose, background: RGB? = nil) -> PixelCanvas {
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
        case .ghost:
            CharacterPainter.drawGhost(on: &pixels, x: -1, ground: CharacterPainter.ghostSize.height - 1, pose: pose)
        }
        return pixels
    }

    /// A small book, for skills in lists.
    public static func book(color: RGB, band: RGB, background: RGB?, t: TimeInterval) -> PixelCanvas {
        var pixels = PixelCanvas(width: width, height: rows * 2)
        if let background { pixels.rect(x: 0, y: 0, width: width, height: rows * 2, background) }
        pixels.rect(x: 3, y: 0, width: 5, height: 6, color)
        pixels.rect(x: 2, y: 0, width: 1, height: 6, color.darker(0.4))
        pixels.rect(x: 8, y: 1, width: 1, height: 5, Theme.cream)
        pixels.rect(x: 3, y: 1, width: 5, height: 1, band)
        pixels[5, 3] = sin(t * 3) > 0 ? RGB(hex: 0xFFF3B0) : RGB(hex: 0xF2C94C)
        return pixels
    }

    /// A small terminal window, for commands.
    public static func terminal(background: RGB?, t: TimeInterval) -> PixelCanvas {
        var pixels = PixelCanvas(width: width, height: rows * 2)
        if let background { pixels.rect(x: 0, y: 0, width: width, height: rows * 2, background) }
        pixels.rect(x: 1, y: 0, width: 8, height: 6, RGB(hex: 0x9DA5B4))
        pixels.rect(x: 2, y: 1, width: 6, height: 4, RGB(hex: 0x1B1F24))
        pixels[3, 3] = Theme.live
        pixels[4, 2] = Theme.live
        if sin(t * 3) > 0 { pixels.rect(x: 5, y: 3, width: 2, height: 1, Theme.cream) }
        return pixels
    }
}
