import Foundation
import TerminalUI

do {
    guard let options = try Options.parse(Array(CommandLine.arguments.dropFirst())) else {
        print(Options.usage)
        exit(0)
    }
    let app = try SidebarApp(options: options)
    if options.once || !Terminal.isInteractive {
        app.renderOnce()
    } else {
        app.run()
    }
} catch {
    FileHandle.standardError.write(Data("agentworld-sidebar: \(error)\n".utf8))
    exit(2)
}
