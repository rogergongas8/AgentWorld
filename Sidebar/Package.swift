// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentWorld",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AgentWorldApp", targets: ["AgentWorldApp"]),
        .executable(name: "agentworld-ctl", targets: ["agentworld-ctl"]),
    ],
    dependencies: [
        // A real terminal emulator view, for the CLIs inside the app.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.20.0"),
    ],
    targets: [
        // Pure model layer: reads each CLI's config, live transcripts, git and
        // the project's files. No UI code in here.
        .target(name: "AgentWorldKit"),
        // Pixel canvas and colors the characters are drawn with (born in the
        // old terminal sidebar; the app draws the canvases as images).
        .target(name: "TerminalUI"),
        // The pixel characters, their looks and poses, colors and formatting,
        // for the app.
        .target(name: "AgentWorldArt", dependencies: ["AgentWorldKit", "TerminalUI"]),
        // The macOS app: workspaces, agents and real terminals in one window.
        .executableTarget(
            name: "AgentWorldApp",
            dependencies: ["AgentWorldKit", "AgentWorldArt", "TerminalUI", .product(name: "SwiftTerm", package: "SwiftTerm")]
        ),
        // Drives the running app from its terminals (agents opening agents).
        .executableTarget(name: "agentworld-ctl", dependencies: ["AgentWorldKit"]),
        .testTarget(name: "AgentWorldKitTests", dependencies: ["AgentWorldKit"]),
        .testTarget(name: "TerminalUITests", dependencies: ["TerminalUI"]),
    ]
)
