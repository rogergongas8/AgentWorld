import Foundation

/// Claude Code writes each subagent's own transcript next to the session:
/// `<sessionId>/subagents/agent-<id>.jsonl`, plus an `agent-<id>.meta.json`
/// whose `toolUseId` links it back to the `Agent`/`Task` call that spawned it.
/// This tails all of them so the sidebar can show what each subagent is doing.
public final class SubagentWatcher {
    public struct Lines {
        public let toolUseId: String
        public let lines: [String]
    }

    private var directory: URL?
    private var tailers: [URL: (toolUseId: String, tailer: TranscriptTailer)] = [:]

    public init() {}

    /// Points at the subagents folder belonging to `sessionTranscript`.
    /// `replayExisting` mirrors the main tailer: rebuild history or only follow new lines.
    public func attach(toSessionTranscript sessionTranscript: URL, replayExisting: Bool) {
        directory = sessionTranscript.deletingPathExtension().appendingPathComponent("subagents", isDirectory: true)
        tailers.removeAll()
        discover(replayExisting: replayExisting)
    }

    /// Picks up newly spawned subagents. Cheap; call every second or so.
    public func discover(replayExisting: Bool = true) {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }

        for file in files where file.pathExtension == "jsonl" && tailers[file] == nil {
            let meta = file.deletingPathExtension().appendingPathExtension("meta.json")
            guard let data = try? Data(contentsOf: meta),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let toolUseId = object["toolUseId"] as? String else { continue }
            let tailer = TranscriptTailer()
            tailer.attach(to: file, fromStart: replayExisting)
            tailers[file] = (toolUseId, tailer)
        }
    }

    public func poll() -> [Lines] {
        tailers.values.compactMap { entry in
            let lines = entry.tailer.poll()
            return lines.isEmpty ? nil : Lines(toolUseId: entry.toolUseId, lines: lines)
        }
    }
}
