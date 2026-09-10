import Darwin
import Foundation

/// Watches the project and its Claude configuration directories for external edits.
final class ConfigurationFileWatcher {
    private let projectURL: URL
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.agentworld.configuration-watcher")
    private var sources: [DispatchSourceFileSystemObject] = []

    init(projectURL: URL, onChange: @escaping @Sendable () -> Void) {
        self.projectURL = projectURL
        self.onChange = onChange
        start()
    }

    deinit {
        stop()
    }

    func stop() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
    }

    private func start() {
        watchedDirectories().forEach(watch)
    }

    private func watchedDirectories() -> [URL] {
        let claudeDirectory = projectURL.appendingPathComponent(".claude", isDirectory: true)
        var directories = [projectURL]

        guard FileManager.default.fileExists(atPath: claudeDirectory.path) else {
            return directories
        }

        directories.append(claudeDirectory)
        let configurationDirectories = [
            claudeDirectory.appendingPathComponent("agents", isDirectory: true),
            claudeDirectory.appendingPathComponent("skills", isDirectory: true)
        ]

        for directory in configurationDirectories where FileManager.default.fileExists(atPath: directory.path) {
            directories.append(directory)

            if let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                for case let url as URL in enumerator {
                    if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        directories.append(url)
                    }
                }
            }
        }

        return Array(Set(directories))
    }

    private func watch(directory: URL) {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: queue
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        sources.append(source)
    }
}
