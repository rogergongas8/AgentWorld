import Foundation

/// A pixel buffer rendered with Unicode half blocks: each terminal cell shows
/// two vertically stacked pixels (`▀` with fg = top, bg = bottom), which gives
/// square-ish pixels in most fonts. `nil` pixels are transparent and show the
/// terminal's own background.
public struct PixelCanvas: Sendable {
    public let width: Int
    public let height: Int
    private var pixels: [RGB?]

    /// `height` is rounded up to an even number of pixels.
    public init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height + height % 2)
        pixels = Array(repeating: nil, count: self.width * self.height)
    }

    public subscript(x: Int, y: Int) -> RGB? {
        get { x >= 0 && y >= 0 && x < width && y < height ? pixels[y * width + x] : nil }
        set { if x >= 0 && y >= 0 && x < width && y < height { pixels[y * width + x] = newValue } }
    }

    public mutating func rect(x: Int, y: Int, width w: Int, height h: Int, _ color: RGB?) {
        guard w > 0, h > 0 else { return }
        for py in y..<(y + h) {
            for px in x..<(x + w) { self[px, py] = color }
        }
    }

    /// Draws a sprite whose rows use single-character keys into `palette`;
    /// keys missing from the palette (e.g. ".") are transparent.
    public mutating func draw(_ sprite: [String], x: Int, y: Int, palette: [Character: RGB], flipped: Bool = false) {
        for (row, line) in sprite.enumerated() {
            let characters = Array(line)
            for (column, key) in characters.enumerated() {
                guard let color = palette[key] else { continue }
                let px = flipped ? x + characters.count - 1 - column : x + column
                self[px, y + row] = color
            }
        }
    }

    /// Composites into `canvas` with the top-left pixel at cell (column, row).
    public func render(into canvas: inout Canvas, column: Int, row: Int) {
        for cellRow in 0..<(height / 2) {
            for x in 0..<width {
                let top = self[x, cellRow * 2]
                let bottom = self[x, cellRow * 2 + 1]
                let cell: Cell
                switch (top, bottom) {
                case (nil, nil):
                    continue
                case let (top?, nil):
                    cell = Cell("▀", Style(fg: top))
                case let (nil, bottom?):
                    cell = Cell("▄", Style(fg: bottom))
                case let (top?, bottom?):
                    cell = top == bottom ? Cell("█", Style(fg: top)) : Cell("▀", Style(fg: top, bg: bottom))
                }
                canvas[column + x, row + cellRow] = cell
            }
        }
    }
}
