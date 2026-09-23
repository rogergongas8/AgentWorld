import AgentWorldKit
import Foundation

extension AppModel {
    /// Rereads `folder`'s file list off the main thread when it's older than 20 s.
    func loadProjectFiles(_ folder: String) {
        if let cached = projectFiles[folder], Date().timeIntervalSince(cached.at) < 20 { return }
        Task.detached(priority: .userInitiated) {
            let files = ProjectFiles.list(folder)
            await MainActor.run { self.projectFiles[folder] = (files, Date()) }
        }
    }

    func files(in folder: String) -> [String] { projectFiles[folder]?.files ?? [] }

    /// Puts a file into `session`'s prompt the way its CLI takes file
    /// references: `@path` where the CLI attaches files that way, the plain
    /// path otherwise.
    func mention(_ path: String, in session: TerminalSession) {
        let relative = path.hasPrefix(session.folder + "/") ? String(path.dropFirst(session.folder.count + 1)) : path
        let quoted = relative.contains(" ") ? "\"\(relative)\"" : relative
        switch session.provider.kind {
        case .claude, .gemini, .codex, .opencode, .cursor: session.type("@" + quoted + " ")
        default: session.type(quoted + " ")
        }
    }
}
