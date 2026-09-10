import Combine
import Foundation

@MainActor
final class ClaudeRuntime: ObservableObject {
    @Published private(set) var status: AgentStatus = .idle
    @Published private(set) var activities: [ClaudeRuntimeActivity] = []
    @Published private(set) var isRunning = false
    @Published private(set) var launchError: String?
    @Published private(set) var activeAgentName: String?

    let eventBus: EventBus

    private var process: Process?
    private var pendingOutput = ""
    private let parser = ClaudeEventParser()

    init(eventBus: EventBus? = nil) {
        self.eventBus = eventBus ?? EventBus()
    }

    var isAvailable: Bool {
        claudeExecutableURL != nil
    }

    func start(prompt: String, projectURL: URL) {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isRunning else { return }
        guard let executableURL = claudeExecutableURL else {
            launchError = "No se encontró el ejecutable de Claude Code en el sistema."
            status = .error
            return
        }

        activities = []
        launchError = nil
        pendingOutput = ""
        status = .thinking
        isRunning = true

        let newProcess = Process()
        let output = Pipe()
        let errors = Pipe()
        newProcess.executableURL = executableURL
        newProcess.currentDirectoryURL = projectURL
        newProcess.arguments = [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--permission-mode", "plan"
        ]
        newProcess.standardOutput = output
        newProcess.standardError = errors

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.consumeStandardOutput(data)
            }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let message = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.record(title: "Claude Code", detail: message)
            }
        }
        newProcess.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                self?.finish(exitCode: process.terminationStatus)
            }
        }

        do {
            try newProcess.run()
            process = newProcess
        } catch {
            isRunning = false
            status = .error
            launchError = error.localizedDescription
        }
    }

    func stop() {
        process?.interrupt()
        record(title: "Cancelando sesión", detail: nil)
    }

    private func consumeStandardOutput(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        var lines = (pendingOutput + chunk).components(separatedBy: .newlines)
        pendingOutput = lines.removeLast()
        lines.filter { !$0.isEmpty }.forEach { line in
            parser.parse(line: line).forEach(apply)
        }
    }

    private func apply(_ signal: ClaudeRuntimeSignal) {
        switch signal {
        case .status(let newStatus):
            status = newStatus
            eventBus.publish(.status(newStatus))
        case .activity(let activity):
            activities.insert(activity, at: 0)
            activities = Array(activities.prefix(30))
            eventBus.publish(.activity(activity))
        case .agentActivated(let name):
            activeAgentName = name
            eventBus.publish(.agentActivated(name: name))
        }
    }

    private func record(title: String, detail: String?) {
        let activity = ClaudeRuntimeActivity(title: title, detail: detail)
        activities.insert(activity, at: 0)
        activities = Array(activities.prefix(30))
        eventBus.publish(.activity(activity))
    }

    private func finish(exitCode: Int32) {
        guard isRunning else { return }
        process = nil
        isRunning = false
        activeAgentName = nil
        if status != .completed && status != .error {
            status = exitCode == 0 ? .completed : .error
            eventBus.publish(.status(status))
        }
        if exitCode != 0 && status == .error {
            launchError = "Claude Code terminó con el código \(exitCode)."
        }
    }

    private var claudeExecutableURL: URL? {
        let pathDirectories = ProcessInfo.processInfo.environment["PATH", default: ""]
            .split(separator: ":")
            .map(String.init)
        let commonDirectories = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]

        var checkedDirectories = Set<String>()
        for directory in pathDirectories + commonDirectories where checkedDirectories.insert(directory).inserted {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("claude")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
