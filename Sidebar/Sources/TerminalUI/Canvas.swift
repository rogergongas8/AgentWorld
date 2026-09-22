import Foundation

public struct Style: Hashable, Sendable {
    public var fg: RGB?
    public var bg: RGB?
    public var bold: Bool
    public var dim: Bool
    public var italic: Bool

    public init(fg: RGB? = nil, bg: RGB? = nil, bold: Bool = false, dim: Bool = false, italic: Bool = false) {
        self.fg = fg
        self.bg = bg
        self.bold = bold
        self.dim = dim
        self.italic = italic
    }

    public static let plain = Style()
}

public struct Cell: Hashable, Sendable {
    public var character: Character
    public var style: Style

    public init(_ character: Character = " ", _ style: Style = .plain) {
        self.character = character
        self.style = style
    }

    public static let blank = Cell()
}

/// A fixed-size grid of styled cells. Everything is drawn into a canvas first
/// and then handed to `Screen`, which diffs it against the previous frame.
///
/// Every character is assumed to occupy one column, so callers must stick to
/// narrow glyphs (Latin, box drawing, blocks, simple symbols — no emoji).
public struct Canvas: Sendable {
    public let width: Int
    public let height: Int
    public private(set) var cells: [Cell]

    public init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
        cells = Array(repeating: .blank, count: self.width * self.height)
    }

    public subscript(x: Int, y: Int) -> Cell {
        get { contains(x, y) ? cells[y * width + x] : .blank }
        set { if contains(x, y) { cells[y * width + x] = newValue } }
    }

    public func contains(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height
    }

    public func row(_ y: Int) -> ArraySlice<Cell> {
        cells[(y * width)..<((y + 1) * width)]
    }

    /// Writes `text` starting at (x, y), clipped to `maxWidth` (and the canvas).
    /// Returns the x just after the last written column.
    @discardableResult
    public mutating func text(_ text: String, x: Int, y: Int, style: Style = .plain, maxWidth: Int? = nil) -> Int {
        let limit = min(width, maxWidth.map { x + $0 } ?? width)
        var column = x
        for character in text where column < limit {
            if character.isNewline { break }
            self[column, y] = Cell(character, style)
            column += 1
        }
        return column
    }

    public mutating func fill(x: Int, y: Int, width w: Int, height h: Int, cell: Cell) {
        for row in y..<(y + h) {
            for column in x..<(x + w) { self[column, row] = cell }
        }
    }

    public mutating func horizontalLine(y: Int, from x0: Int = 0, to x1: Int? = nil, character: Character = "─", style: Style = .plain) {
        for column in x0..<(x1 ?? width) { self[column, y] = Cell(character, style) }
    }

    /// Paints `style.bg` behind a region without touching its characters.
    public mutating func tint(x: Int, y: Int, width w: Int, background: RGB) {
        for column in x..<(x + w) where contains(column, y) {
            cells[y * width + column].style.bg = background
        }
    }
}

extension String {
    /// Clips to `width` columns, ending with an ellipsis when something was cut.
    public func fitted(to width: Int) -> String {
        guard width > 0 else { return "" }
        guard count > width else { return self }
        return String(prefix(max(0, width - 1))) + "…"
    }

    public func padded(to width: Int) -> String {
        count >= width ? fitted(to: width) : self + String(repeating: " ", count: width - count)
    }
}
