import Darwin
import Foundation

public enum Key: Equatable, Sendable {
    case character(Character)
    case tab
    case backTab
    case enter
    case escape
    case backspace
    case up, down, left, right
    case pageUp, pageDown, home, end
    /// A mouse event at a 0-based cell (only when mouse reporting is on).
    case mouse(MouseEvent)
}

public struct MouseEvent: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case press
        case scrollUp
        case scrollDown
        /// The pointer moved with no button held (hover).
        case move
    }

    public let action: Action
    public let x: Int
    public let y: Int

    public init(action: Action, x: Int, y: Int) {
        self.action = action
        self.x = x
        self.y = y
    }
}

/// Thin wrapper over the controlling terminal: size, raw mode, alternate
/// screen and non-blocking key reads.
public enum Terminal {
    nonisolated(unsafe) private static var savedAttributes: termios?

    public static func write(_ string: String) {
        var data = Array(string.utf8)
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeMutableBytes { buffer in
                Darwin.write(STDOUT_FILENO, buffer.baseAddress! + offset, buffer.count - offset)
            }
            if written <= 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                return
            }
            offset += written
        }
        data.removeAll()
    }

    public static func size() -> (columns: Int, rows: Int) {
        var size = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0, size.ws_row > 0 {
            return (Int(size.ws_col), Int(size.ws_row))
        }
        return (40, 40)
    }

    public static var isInteractive: Bool {
        isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
    }

    /// Alternate screen, hidden cursor, no echo / line buffering, and
    /// optionally mouse click/wheel reporting (SGR encoding).
    public static func enterFullscreen(mouse: Bool = false) {
        if isatty(STDIN_FILENO) == 1 {
            var attributes = termios()
            tcgetattr(STDIN_FILENO, &attributes)
            savedAttributes = attributes
            attributes.c_lflag &= ~tcflag_t(ECHO | ICANON)
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &attributes)
        }
        write(ANSI.enterAltScreen + ANSI.hideCursor + ANSI.disableLineWrap + ANSI.clearScreen + (mouse ? ANSI.enableMouse : ""))
    }

    public static func exitFullscreen() {
        if var attributes = savedAttributes {
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &attributes)
            savedAttributes = nil
        }
        write(ANSI.disableMouse + ANSI.reset + ANSI.enableLineWrap + ANSI.showCursor + ANSI.exitAltScreen)
    }

    /// Waits up to `timeout` for input and returns the keys read (possibly none).
    /// Doubles as the main loop's frame pacing.
    public static func readKeys(timeout: TimeInterval) -> [Key] {
        var readSet = fd_set()
        fdZero(&readSet)
        fdSet(STDIN_FILENO, &readSet)
        var interval = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000))
        guard select(STDIN_FILENO + 1, &readSet, nil, nil, &interval) > 0 else { return [] }

        var buffer = [UInt8](repeating: 0, count: 64)
        let count = read(STDIN_FILENO, &buffer, buffer.count)
        guard count > 0 else {
            // EOF on stdin (e.g. detached): don't spin, just wait out the frame.
            usleep(UInt32(timeout * 1_000_000))
            return []
        }
        return parseKeys(Array(buffer[0..<count]))
    }

    static func parseKeys(_ bytes: [UInt8]) -> [Key] {
        var keys: [Key] = []
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x1B, index + 2 < bytes.count, bytes[index + 1] == 0x5B || bytes[index + 1] == 0x4F {
                // CSI / SS3: read parameters up to the final byte.
                var end = index + 2
                while end < bytes.count, !(0x40...0x7E).contains(bytes[end]) { end += 1 }
                guard end < bytes.count else { break }
                let parameters = String(decoding: bytes[(index + 2)..<end], as: UTF8.self)
                if let key = csiKey(final: bytes[end], parameters: parameters) { keys.append(key) }
                index = end + 1
                continue
            }
            switch byte {
            case 0x1B: keys.append(.escape)
            case 0x7F, 0x08: keys.append(.backspace)
            case 0x09: keys.append(.tab)
            case 0x0A, 0x0D: keys.append(.enter)
            default:
                if byte >= 0x20 && byte < 0x7F { keys.append(.character(Character(UnicodeScalar(byte)))) }
            }
            index += 1
        }
        return keys
    }

    private static func csiKey(final: UInt8, parameters: String) -> Key? {
        switch (final, parameters) {
        case (0x41, _): return .up
        case (0x42, _): return .down
        case (0x43, _): return .right
        case (0x44, _): return .left
        case (0x5A, _): return .backTab
        case (0x48, _): return .home
        case (0x46, _): return .end
        case (0x7E, "5"): return .pageUp
        case (0x7E, "6"): return .pageDown
        case (0x7E, "1"), (0x7E, "7"): return .home
        case (0x7E, "4"), (0x7E, "8"): return .end
        case (0x4D, _) where parameters.hasPrefix("<"):
            // SGR mouse: ESC [ < button ; x ; y M  (release, `m`, is ignored).
            let fields = parameters.dropFirst().split(separator: ";").compactMap { Int($0) }
            guard fields.count == 3 else { return nil }
            let action: MouseEvent.Action
            switch fields[0] {
            case 0: action = .press
            case 35: action = .move
            case 64: action = .scrollUp
            case 65: action = .scrollDown
            default: return nil
            }
            return .mouse(MouseEvent(action: action, x: fields[1] - 1, y: fields[2] - 1))
        default: return nil
        }
    }

    private static func fdZero(_ set: inout fd_set) {
        set.fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static func fdSet(_ fd: Int32, _ set: inout fd_set) {
        let intOffset = Int(fd / 32)
        let bitOffset = fd % 32
        withUnsafeMutableBytes(of: &set.fds_bits) { buffer in
            let words = buffer.bindMemory(to: Int32.self)
            words[intOffset] |= Int32(bitPattern: UInt32(1) << UInt32(bitOffset))
        }
    }
}
