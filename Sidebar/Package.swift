// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentWorldSidebar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "agentworld-sidebar", targets: ["agentworld-sidebar"])
    ],
    targets: [
        // Pure model layer: reads Claude Code's config + live transcripts and
        // folds them into a `SessionStore`. No terminal code in here.
        .target(name: "AgentWorldKit"),
        // Terminal primitives: cell canvas, pixel (half-block) canvas, colors,
        // diffing screen presenter, raw-mode input. Knows nothing about Claude.
        .target(name: "TerminalUI"),
        // The sidebar itself: the animated stage + panels, wired to the above.
        .executableTarget(
            name: "agentworld-sidebar",
            dependencies: ["AgentWorldKit", "TerminalUI"]
        ),
        .testTarget(name: "AgentWorldKitTests", dependencies: ["AgentWorldKit"]),
        .testTarget(name: "TerminalUITests", dependencies: ["TerminalUI"]),
    ]
)
