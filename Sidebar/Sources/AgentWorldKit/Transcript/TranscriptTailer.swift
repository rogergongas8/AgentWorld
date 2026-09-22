import Foundation

/// Tails a JSONL file by byte offset, like `tail -f`. Handles truncation
/// (offset resets to 0) and buffers a trailing partial line until its
/// newline arrives, so callers only ever see complete lines.
public final class TranscriptTailer {
    public private(set) var fileURL: URL?
    private var offset: UInt64 = 0
    private var pending = Data()

    public init() {}

    /// Starts tailing `url`. With `fromStart: true` the next poll returns the
    /// whole existing file (used to rebuild state for an ongoing session).
    public func attach(to url: URL, fromStart: Bool) {
        fileURL = url
        pending.removeAll()
        offset = fromStart ? 0 : Self.size(of: url)
    }

    /// Whether there's more written than has been read (after a capped poll).
    public var isBehind: Bool {
        fileURL.map { Self.size(of: $0) > offset } ?? false
    }

    /// Complete lines written since the last call, reading at most
    /// `maxBytes` (a long transcript then catches up over several polls
    /// instead of blocking the first frame).
    public func poll(maxBytes: Int = .max) -> [String] {
        guard let fileURL else { return [] }
        let size = Self.size(of: fileURL)
        if size < offset {
            offset = 0
            pending.removeAll()
        }
        guard size > offset, let handle = try? FileHandle(forReadingFrom: fileURL) else { return [] }
        defer { try? handle.close() }

        try? handle.seek(toOffset: offset)
        let data = maxBytes == .max ? ((try? handle.readToEnd()) ?? Data()) : ((try? handle.read(upToCount: maxBytes)) ?? Data())
        offset += UInt64(data.count)
        pending.append(data)

        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let lineData = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            if !lineData.isEmpty, let line = String(data: lineData, encoding: .utf8) {
                lines.append(line)
            }
        }
        return lines
    }

    static func size(of url: URL) -> UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
    }
}
