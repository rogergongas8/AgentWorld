import AgentWorldArt
import AgentWorldKit
import Foundation

struct Options {
    var cwd = FileManager.default.currentDirectoryPath
    var sessionId: String?
    var projectsRoot: URL?
    var demo = false
    /// Render a single frame to stdout and exit (no alt screen / raw mode).
    var once = false
    var size: (columns: Int, rows: Int)?
    var fps = 12.0
    var provider = Provider.claude
    /// Run the hub's terminal picker instead of a sidebar.
    var launcher = false

    static let usage = """
    agentworld-sidebar — a live, animated companion panel for Claude Code.

    Usually launched by the `claude` shell wrapper (see shell/agentworld.zsh),
    which splits your terminal with tmux: Claude on the left, this on the right.

    Usage: agentworld-sidebar [options]

      --cwd PATH            Project directory to follow (default: current dir)
      --session-id UUID     Follow exactly this session (set by the wrapper)
      --projects-root PATH  Claude Code transcripts root (default: ~/.claude/projects)
      --provider ID         Which CLI this sidebar maps: claude (default), codex,
                            gemini, kimi, grok
      --launcher            Run the hub's terminal picker (used by `agentworld`)
      --demo                Play a scripted session to show off every animation
      --once                Print one frame and exit (for scripts and tests)
      --size COLSxROWS      Frame size for --once (default: terminal size)
      --fps N               Animation frame rate (default: 12)
      -h, --help            Show this help

    Keys: 1/2/3 or tab switch views · s toggle stage · ↑↓ scroll · q quit
    """

    enum ParseError: Error, CustomStringConvertible {
        case missingValue(String)
        case invalid(String, String)
        case unknown(String)

        var description: String {
            switch self {
            case .missingValue(let flag): "\(flag) needs a value"
            case .invalid(let flag, let value): "invalid value for \(flag): \(value)"
            case .unknown(let flag): "unknown option: \(flag)"
            }
        }
    }

    /// Returns nil when help was requested.
    static func parse(_ arguments: [String]) throws -> Options? {
        var options = Options()
        var iterator = arguments.makeIterator()

        func value(for flag: String) throws -> String {
            guard let value = iterator.next() else { throw ParseError.missingValue(flag) }
            return value
        }

        while let argument = iterator.next() {
            switch argument {
            case "-h", "--help":
                return nil
            case "--cwd":
                options.cwd = try value(for: argument)
            case "--session-id":
                options.sessionId = try value(for: argument)
            case "--projects-root":
                options.projectsRoot = URL(fileURLWithPath: (try value(for: argument) as NSString).expandingTildeInPath, isDirectory: true)
            case "--provider":
                let raw = try value(for: argument)
                guard let provider = Provider.named(raw) else { throw ParseError.invalid(argument, raw) }
                options.provider = provider
            case "--launcher":
                options.launcher = true
            case "--demo":
                options.demo = true
            case "--once":
                options.once = true
            case "--size":
                let raw = try value(for: argument)
                let parts = raw.lowercased().split(separator: "x").compactMap { Int($0) }
                guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { throw ParseError.invalid(argument, raw) }
                options.size = (parts[0], parts[1])
            case "--fps":
                let raw = try value(for: argument)
                guard let fps = Double(raw), fps > 0, fps <= 60 else { throw ParseError.invalid(argument, raw) }
                options.fps = fps
            default:
                throw ParseError.unknown(argument)
            }
        }
        // Not `standardizedFileURL`: it rewrites /private/tmp to /tmp, which
        // changes the transcript directory name.
        options.cwd = URL(fileURLWithPath: (options.cwd as NSString).expandingTildeInPath).path
        return options
    }
}
