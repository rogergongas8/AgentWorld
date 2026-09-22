import Foundation

/// One command for the running AgentWorld app, from `agentworld-ctl`.
public struct ControlRequest: Codable, Sendable {
    public var command: String
    public var arguments: [String]
    /// The pane number of the terminal that sent it (`$AGENTWORLD_PANE`).
    public var caller: Int?

    public init(command: String, arguments: [String], caller: Int?) {
        self.command = command
        self.arguments = arguments
        self.caller = caller
    }
}

public struct ControlReply: Codable, Sendable {
    public var ok: Bool
    public var output: String

    public init(ok: Bool, output: String) {
        self.ok = ok
        self.output = output
    }
}

/// The app listens on a Unix socket, one per running instance, and hands
/// its path to every terminal it opens as `$AGENTWORLD_SOCKET`. One JSON
/// request per connection, one JSON reply, then it closes.
public enum ControlSocket {
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/agentworld/run", isDirectory: true)
    }

    public static func path(pid: Int32 = getpid()) -> String {
        directory.appendingPathComponent("\(pid).sock").path
    }

    public enum Failure: Error, CustomStringConvertible {
        case system(String)
        case badReply

        public var description: String {
            switch self {
            case .system(let what): what
            case .badReply: "the app sent back something unreadable"
            }
        }
    }

    // MARK: - Client

    public static func send(_ request: ControlRequest, to path: String) throws -> ControlReply {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.system("socket: \(String(cString: strerror(errno)))") }
        defer { close(fd) }
        var address = try self.address(path)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw Failure.system("AgentWorld isn't answering at \(path)") }
        try write(JSONEncoder().encode(request) + Data("\n".utf8), to: fd)
        shutdown(fd, SHUT_WR)
        guard let reply = try? JSONDecoder().decode(ControlReply.self, from: readAll(fd)) else { throw Failure.badReply }
        return reply
    }

    /// Live app sockets, newest first (stale ones from crashed apps skipped).
    public static func running() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.pathExtension == "sock" && Int32($0.deletingPathExtension().lastPathComponent).map { kill($0, 0) == 0 } == true }
            .sorted { modified($0) > modified($1) }
            .map(\.path)
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    // MARK: - Server

    /// Binds and listens; returns the listening descriptor.
    public static func listen(at path: String) throws -> Int32 {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Leftovers from apps that crashed.
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        where file.pathExtension == "sock" {
            if let pid = Int32(file.deletingPathExtension().lastPathComponent), kill(pid, 0) != 0 { unlink(file.path) }
        }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.system("socket: \(String(cString: strerror(errno)))") }
        var address = try self.address(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, Darwin.listen(fd, 16) == 0 else {
            close(fd)
            throw Failure.system("can't listen at \(path): \(String(cString: strerror(errno)))")
        }
        chmod(path, 0o600)
        closeOnExec(fd)
        return fd
    }

    /// Waits for the next client. Its descriptor is closed on exec: terminals
    /// the app opens meanwhile mustn't inherit it (the client would never see
    /// the reply end).
    public static func accept(_ fd: Int32) -> Int32 {
        let client = Darwin.accept(fd, nil, nil)
        if client >= 0 { closeOnExec(client) }
        return client
    }

    private static func closeOnExec(_ fd: Int32) {
        _ = fcntl(fd, F_SETFD, fcntl(fd, F_GETFD) | FD_CLOEXEC)
    }

    /// Reads a request until the client stops writing.
    public static func readRequest(_ fd: Int32) -> ControlRequest? {
        try? JSONDecoder().decode(ControlRequest.self, from: readAll(fd))
    }

    public static func reply(_ reply: ControlReply, to fd: Int32) {
        try? write(JSONEncoder().encode(reply), to: fd)
        close(fd)
    }

    // MARK: - Plumbing

    private static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw Failure.system("socket path too long: \(path)") }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        return address
    }

    private static func write(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                guard written > 0 else { throw Failure.system("write: \(String(cString: strerror(errno)))") }
                offset += written
            }
        }
    }

    private static func readAll(_ fd: Int32) -> Data {
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = read(fd, &chunk, chunk.count)
            guard count > 0 else { break }
            data.append(chunk, count: count)
        }
        return data
    }
}
