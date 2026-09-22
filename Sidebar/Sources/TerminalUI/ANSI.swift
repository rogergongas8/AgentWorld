import Foundation

public enum ANSI {
    public static let enterAltScreen = "\u{1B}[?1049h"
    public static let exitAltScreen = "\u{1B}[?1049l"
    public static let hideCursor = "\u{1B}[?25l"
    public static let showCursor = "\u{1B}[?25h"
    public static let disableLineWrap = "\u{1B}[?7l"
    public static let enableLineWrap = "\u{1B}[?7h"
    public static let clearScreen = "\u{1B}[2J"
    /// Click, wheel and hover (any-motion) reporting with SGR coordinates.
    public static let enableMouse = "\u{1B}[?1000h\u{1B}[?1003h\u{1B}[?1006h"
    public static let disableMouse = "\u{1B}[?1006l\u{1B}[?1003l\u{1B}[?1000l"
    public static let reset = "\u{1B}[0m"
    /// DEC mode 2026; ignored by terminals that don't support it.
    public static let beginSynchronizedUpdate = "\u{1B}[?2026h"
    public static let endSynchronizedUpdate = "\u{1B}[?2026l"

    public static func moveTo(row: Int, column: Int) -> String {
        "\u{1B}[\(row);\(column)H"
    }
}
