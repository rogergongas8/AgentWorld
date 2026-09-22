import AgentWorldKit
import Foundation
import TerminalUI

/// Skills as books on a shelf: one colored spine each, grouped by category.
/// The selected book slides up and its name and summary show under the
/// shelf, so a whole category reads at a glance instead of as a text list.
struct BookSpec {
    let name: String
    let summary: String?
    let color: RGB
    /// Band across the spine: where the skill comes from.
    let band: RGB
    let origin: String
    let used: Bool
    let route: Route

    init(skill: SkillDefinition, used: Bool) {
        name = skill.name
        summary = skill.summary
        color = Icon.color(for: skill.name)
        band = skill.plugin != nil ? Bookshelf.pluginBand : skill.scope == .project ? Bookshelf.projectBand : Theme.cream
        origin = skill.plugin.map { "plugin \($0)" } ?? skill.scope.rawValue
        self.used = used
        route = .skill(skill.qualifiedName)
    }
}

enum Bookshelf {
    static let rows = 7
    static let bookWidth = 3
    static let pitch = 4
    static let pluginBand = RGB(hex: 0xF2C94C)
    static let projectBand = RGB(hex: 0x56D364)
    static let wood = RGB(hex: 0x6B4F3A)

    /// Taller or shorter spines, stable per name, like a real shelf.
    static func height(for name: String) -> Int {
        7 + Int(CharacterLook.stableHash(name + "#h") % 4)
    }
}

extension SkillCategory {
    var color: RGB {
        switch self {
        case .design: RGB(hex: 0xF778BA)
        case .documents: RGB(hex: 0x79C0FF)
        case .code: RGB(hex: 0x7EE787)
        case .integrations: RGB(hex: 0xBC8CFF)
        case .data: RGB(hex: 0xFFA657)
        case .workflow: RGB(hex: 0xE3B341)
        case .other: Theme.muted
        }
    }
}

extension PageBuilder {
    /// One shelf (wrapping onto more planks when needed) plus a two-line
    /// caption: the selected book's name and summary, or the shelf's titles.
    mutating func shelf(_ books: [BookSpec], t: TimeInterval) {
        guard !books.isEmpty else { return }
        let perRow = max(1, (width - 2) / Bookshelf.pitch)
        var selectedBook: BookSpec?

        for start in stride(from: 0, to: books.count, by: perRow) {
            let rowBooks = Array(books[start..<min(books.count, start + perRow)])
            reserve(Bookshelf.rows)
            var pixels = PixelCanvas(width: width, height: Bookshelf.rows * 2)
            let plank = pixels.height - 2
            pixels.rect(x: 0, y: plank, width: min(width, 2 + rowBooks.count * Bookshelf.pitch), height: 1, Bookshelf.wood.lighter(0.15))
            pixels.rect(x: 0, y: plank + 1, width: min(width, 2 + rowBooks.count * Bookshelf.pitch), height: 1, Bookshelf.wood.darker(0.3))

            for (index, book) in rowBooks.enumerated() {
                let selected = nextIsSelected
                if selected { selectedBook = book }
                let x = 1 + index * Bookshelf.pitch
                let height = Bookshelf.height(for: book.name) + (selected ? 2 : 0)
                let top = plank - height
                let color = selected ? book.color.lighter(0.2) : book.color
                pixels.rect(x: x, y: top, width: Bookshelf.bookWidth, height: height, color)
                pixels.rect(x: x, y: top, width: Bookshelf.bookWidth, height: 1, color.lighter(0.3))
                pixels.rect(x: x + Bookshelf.bookWidth - 1, y: top + 1, width: 1, height: height - 1, color.darker(0.25))
                pixels.rect(x: x, y: top + 2, width: Bookshelf.bookWidth, height: 1, book.band)
                pixels.rect(x: x, y: top + height - 3, width: Bookshelf.bookWidth, height: 1, color.darker(0.4))
                if book.used, Int(t * 3 + Double(index)) % 3 != 0 {
                    pixels[x + 1, top - 2] = RGB(hex: 0xFFF3B0)
                }
                if selected {
                    pixels[x + 1, plank + 1] = Theme.cream
                }
                register(x: x, y: y, width: Bookshelf.bookWidth, height: Bookshelf.rows, route: book.route)
            }
            draw { canvas, y in pixels.render(into: &canvas, column: 0, row: y) }
            advance(Bookshelf.rows)
        }

        if let book = selectedBook {
            line(StyledLine(" ✦ ", .fg(book.color, bold: true)).appending(book.name, .fg(Theme.cream, bold: true))
                .appending(book.used ? "  used" : "", .fg(Theme.warning))
                .trailing(book.origin, .fg(Theme.faint)))
            line(StyledLine("   " + (book.summary ?? "no description"), .fg(Theme.muted)))
        } else {
            let names = books.map(\.name).joined(separator: " · ")
            line(StyledLine(" " + names, .fg(Theme.faint)))
            line(StyledLine())
        }
    }
}
