import Foundation

/// Tails a transcript file by byte offset, like `tail -f`. Handles truncation
/// (file replaced/rotated: offset resets to 0) and buffers a trailing partial
/// line across polls until its newline arrives.
final class TranscriptTailer {
    private var fileURL: URL?
    private var offset: UInt64 = 0
    private var pendingBytes = Data()

    /// Points the tailer at a new file. `seekToEnd: true` means "only report
    /// lines written from now on" (used when attaching to an already-running
    /// session, so the app doesn't dump its entire history on startup).
    func attach(to url: URL, seekToEnd: Bool) {
        fileURL = url
        pendingBytes.removeAll()
        let size = fileSize(at: url)
        offset = seekToEnd ? size : 0
    }

    /// Reads and returns any complete new lines written since the last call.
    func pollNewLines() -> [String] {
        guard let fileURL else { return [] }
        let size = fileSize(at: fileURL)

        if size < offset {
            offset = 0
            pendingBytes.removeAll()
        }
        guard size > offset, let handle = try? FileHandle(forReadingFrom: fileURL) else { return [] }
        defer { try? handle.close() }

        handle.seek(toFileOffset: offset)
        let newData = handle.readDataToEndOfFile()
        offset = size
        pendingBytes.append(newData)

        var lines: [String] = []
        while let newlineRange = pendingBytes.firstRange(of: Data([0x0A])) {
            let lineData = pendingBytes.subdata(in: pendingBytes.startIndex..<newlineRange.lowerBound)
            pendingBytes.removeSubrange(pendingBytes.startIndex..<newlineRange.upperBound)
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }

    private func fileSize(at url: URL) -> UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
    }
}
