// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentWorldSidebar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "agentworld-sidebar", targets: ["agentworld-sidebar"]),
        .executable(name: "AgentWorldApp", targets: ["AgentWorldApp"]),
    ],
    dependencies: [
        // A real terminal emulator view, for the CLIs inside the app.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.20.0"),
    ],
    targets: [
        // Pure model layer: reads Claude Code's config + live transcripts and
        // folds them into a `SessionStore`. No terminal code in here.
        .target(name: "AgentWorldKit"),
        // Terminal primitives: cell canvas, pixel (half-block) canvas, colors,
        // diffing screen presenter, raw-mode input. Knows nothing about Claude.
        .target(name: "TerminalUI"),
        // The pixel characters, their looks and poses, colors and formatting,
        // shared by the terminal sidebar and the macOS app.
        .target(name: "AgentWorldArt", dependencies: ["AgentWorldKit", "TerminalUI"]),
        // The sidebar itself: the animated stage + panels, wired to the above.
        .executableTarget(
            name: "agentworld-sidebar",
            dependencies: ["AgentWorldKit", "TerminalUI", "AgentWorldArt"]
        ),
        // The macOS app: workspaces, agents and real terminals in one window.
        .executableTarget(
            name: "AgentWorldApp",
            dependencies: ["AgentWorldKit", "AgentWorldArt", "TerminalUI", .product(name: "SwiftTerm", package: "SwiftTerm")]
        ),
        .testTarget(name: "AgentWorldKitTests", dependencies: ["AgentWorldKit"]),
        .testTarget(name: "TerminalUITests", dependencies: ["TerminalUI"]),
    ]
)
