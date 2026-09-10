import AppKit
import Combine
import Foundation

@MainActor
final class ProjectManager: ObservableObject {
    @Published private(set) var project: Project?
    private var fileWatcher: ConfigurationFileWatcher?
    private var refreshTask: Task<Void, Never>?

    deinit {
        refreshTask?.cancel()
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.title = "Abrir proyecto"
        panel.message = "Selecciona la carpeta raíz de tu proyecto"
        panel.prompt = "Abrir"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        loadProject(at: url)
    }

    func loadProject(at url: URL) {
        let claudeDirectory = url.appendingPathComponent(".claude", isDirectory: true)
        let hasClaudeDirectory = FileManager.default.fileExists(atPath: claudeDirectory.path)
        let configuration = ClaudeConfigScanner().scan(projectURL: url)
        project = Project(
            url: url,
            hasClaudeDirectory: hasClaudeDirectory,
            agents: configuration.agents,
            skills: configuration.skills
        )
        startWatching(projectURL: url)
    }

    private func startWatching(projectURL: URL) {
        fileWatcher?.stop()
        fileWatcher = ConfigurationFileWatcher(projectURL: projectURL) { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh()
            }
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self, let project else { return }
            loadProject(at: project.path)
        }
    }
}
