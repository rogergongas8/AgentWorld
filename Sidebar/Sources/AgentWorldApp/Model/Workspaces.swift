import AgentWorldKit
import AppKit
import Foundation

/// A project folder you work on, saved across launches with what you had
/// open in it, so the app is somewhere you come back to (from the Dock, not
/// only from a shell's `agentworld app`).
struct SavedWorkspace: Codable, Equatable {
    var path: String
    /// Your name for it; the folder's name otherwise.
    var name: String?
    var pinned = false
    var lastOpened = Date()
    /// What was open last time, to pick up where you left off.
    var panes: [SavedPane] = []

    var displayName: String { name ?? URL(fileURLWithPath: path).lastPathComponent }
}

struct SavedPane: Codable, Equatable {
    /// Launch profile name (a provider name for the defaults).
    var profile: String
    /// The CLI's own conversation id, handed back to its own resume
    /// (`claude --resume <id>`, `codex resume <id>`).
    var resumeID: String?
    var agentName: String?
}

/// `~/.config/agentworld/workspaces.json` (or `$AGENTWORLD_WORKSPACES`, so
/// test runs keep their hands off yours), with the old recent-folders list
/// folded in the first time.
enum WorkspaceFile {
    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["AGENTWORLD_WORKSPACES"] { return URL(fileURLWithPath: path) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/agentworld/workspaces.json")
    }

    static func load() -> [SavedWorkspace] {
        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let saved = try? decoder.decode([SavedWorkspace].self, from: data) {
                return saved.filter { FileManager.default.fileExists(atPath: $0.path) }
            }
        }
        return RecentFolders.load().map { SavedWorkspace(path: $0) }
    }

    static func save(_ workspaces: [SavedWorkspace]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(workspaces).write(to: url, options: .atomic)
    }
}

/// Folders you've already worked in with any of your CLIs, read from each
/// one's own history (Claude's transcripts, Codex's session files, Gemini's
/// project list), newest first: suggestions for your workspaces.
enum CLIHistory {
    struct Folder: Identifiable {
        let path: String
        /// Which CLIs have been used there ("Claude Code", "Codex"…).
        var clis: [String]
        var lastUsed: Date
        var id: String { path }
    }

    static func recentFolders(limit: Int = 8) -> [Folder] {
        var byPath: [String: Folder] = [:]
        func add(_ path: String, _ cli: String, _ date: Date) {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            guard path != home, !path.hasPrefix("/private/"), !path.hasPrefix("/tmp/"),
                  FileManager.default.fileExists(atPath: path) else { return }
            var folder = byPath[path] ?? Folder(path: path, clis: [], lastUsed: .distantPast)
            if !folder.clis.contains(cli) { folder.clis.append(cli) }
            folder.lastUsed = max(folder.lastUsed, date)
            byPath[path] = folder
        }
        for (path, date) in claude() { add(path, Provider.claude.name, date) }
        for (path, date) in codex() { add(path, Provider.codex.name, date) }
        for (path, date) in gemini() { add(path, Provider.gemini.name, date) }
        return byPath.values.sorted { $0.lastUsed > $1.lastUsed }.prefix(limit).map { $0 }
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Claude Code: one folder per project, the cwd inside its transcripts.
    private static func claude() -> [(String, Date)] {
        let directories = contents(of: ProjectSlug.defaultProjectsRoot)
        return directories.compactMap { directory in
            guard let (newest, date) = contents(of: directory).filter({ $0.pathExtension == "jsonl" })
                .map({ ($0, modified($0)) }).max(by: { $0.1 < $1.1 }),
                  let cwd = firstValue("cwd", in: newest) else { return nil }
            return (cwd, date)
        }
    }

    /// Codex: dated folders of rollout files that open with their cwd.
    private static func codex() -> [(String, Date)] {
        let root = home.appendingPathComponent(".codex/sessions")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        let files = walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
            .map { ($0, modified($0)) }.sorted { $0.1 > $1.1 }.prefix(80)
        return files.compactMap { file, date in firstValue("cwd", in: file).map { ($0, date) } }
    }

    /// Gemini CLI: its projects list (no dates: the file's own).
    private static func gemini() -> [(String, Date)] {
        let file = home.appendingPathComponent(".gemini/projects.json")
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = object["projects"] as? [String: Any] else { return [] }
        let date = modified(file)
        return projects.keys.map { ($0, date) }
    }

    private static func contents(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// The first `"key":"…"` in the file's opening lines.
    private static func firstValue(_ key: String, in file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let head = String(decoding: handle.readData(ofLength: 64 * 1024), as: UTF8.self)
        guard let range = head.range(of: "\"\(key)\":\"") else { return nil }
        let rest = head[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end]).replacingOccurrences(of: "\\/", with: "/")
    }
}

/// A folder's git branch and whether it has uncommitted changes, refreshed
/// in the background every so often.
struct GitInfo: Equatable {
    var branch: String?
    var dirty = false

    static func read(_ folder: String) -> GitInfo? {
        let head = URL(fileURLWithPath: folder).appendingPathComponent(".git/HEAD")
        guard let text = try? String(contentsOf: head, encoding: .utf8) else { return nil }
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = line.hasPrefix("ref: refs/heads/") ? String(line.dropFirst("ref: refs/heads/".count)) : String(line.prefix(7))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder, "status", "--porcelain", "--untracked-files=no"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        var dirty = false
        if (try? process.run()) != nil {
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            dirty = !output.isEmpty
        }
        return GitInfo(branch: branch, dirty: dirty)
    }
}

extension AppModel {
    // MARK: - Saving

    /// Rewrites the workspaces file: order, names, pins and what's open.
    func saveWorkspaces() {
        let saved = folders.map { path -> SavedWorkspace in
            var workspace = workspaceInfo[path] ?? SavedWorkspace(path: path)
            let open = tabs(in: path).flatMap(\.sessions).filter { $0.health == .running }
            if !open.isEmpty {
                workspace.panes = open.map {
                    SavedPane(profile: $0.profile.name, resumeID: $0.resumeID, agentName: $0.agentName)
                }
            }
            return workspace
        }
        WorkspaceFile.save(saved)
    }

    func workspaceName(_ path: String) -> String {
        workspaceInfo[path]?.displayName ?? URL(fileURLWithPath: path).lastPathComponent
    }

    func rename(workspace path: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        var info = workspaceInfo[path] ?? SavedWorkspace(path: path)
        info.name = trimmed.isEmpty || trimmed == URL(fileURLWithPath: path).lastPathComponent ? nil : trimmed
        workspaceInfo[path] = info
        saveWorkspaces()
    }

    func togglePin(_ path: String) {
        var info = workspaceInfo[path] ?? SavedWorkspace(path: path)
        info.pinned.toggle()
        workspaceInfo[path] = info
        // Pinned ones stay on top.
        folders = folders.filter { workspaceInfo[$0]?.pinned == true } + folders.filter { workspaceInfo[$0]?.pinned != true }
        saveWorkspaces()
    }

    // MARK: - Picking up where you left off

    /// What was open here last time and isn't now.
    func resumablePanes(in folder: String) -> [SavedPane] {
        guard tabs(in: folder).isEmpty else { return [] }
        return workspaceInfo[folder]?.panes ?? []
    }

    /// Reopens last time's panes, tiled in one tab; each CLI that can resume
    /// a conversation (Claude Code, Codex) picks it up where it was.
    func resume(in folder: String) {
        let panes = resumablePanes(in: folder).prefix(Self.maxPanes)
        let sessions = panes.compactMap { pane -> TerminalSession? in
            guard let profile = profiles.first(where: { $0.name == pane.profile }), let executable = executable(for: profile) else { return nil }
            return TerminalSession(profile: profile, executable: executable, folder: folder, agentName: pane.agentName,
                                   resumeID: pane.resumeID)
        }
        guard !sessions.isEmpty else { return }
        let tab = TerminalTab(folder: folder, sessions: sessions)
        tabs.append(tab)
        selectedTabID = tab.id
        showsLauncher = false
    }

    // MARK: - Git

    /// Refreshes the branch and dirty flag of every workspace, off the main thread.
    func refreshGit() {
        let paths = folders
        Task.detached(priority: .utility) {
            var results: [String: GitInfo] = [:]
            for path in paths { if let info = GitInfo.read(path) { results[path] = info } }
            await MainActor.run { if self.git != results { self.git = results } }
        }
    }

    // MARK: - New projects

    /// Creates `name` under `parent` (with `git init`), or clones `url` there.
    func createProject(name: String, in parent: String, cloneURL: String?, gitInit: Bool) async -> String? {
        let cleanURL = cloneURL?.trimmingCharacters(in: .whitespaces)
        let folderName = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? (cleanURL.flatMap { URL(string: $0)?.deletingPathExtension().lastPathComponent } ?? "")
            : name.trimmingCharacters(in: .whitespaces)
        guard !folderName.isEmpty else { return "Give it a name" }
        let path = URL(fileURLWithPath: parent).appendingPathComponent(folderName).path
        if FileManager.default.fileExists(atPath: path) { return "\(folderName) already exists there" }
        let result: String? = await Task.detached {
            if let cleanURL, !cleanURL.isEmpty {
                return Self.run(["git", "clone", cleanURL, path])
            }
            do {
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            } catch {
                return error.localizedDescription
            }
            return gitInit ? Self.run(["git", "init", "-q", path]) : nil
        }.value
        if result == nil { addFolder(path) }
        return result
    }

    /// Runs a command; nil on success, else what it printed.
    nonisolated private static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = FileHandle.nullDevice
        do { try process.run() } catch { return error.localizedDescription }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? nil : String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
