/// A screen in the explorer. The explorer keeps a stack of these, like a
/// file browser: open pushes, back pops.
enum Route: Hashable {
    case home
    /// The CLI itself: the crew's leader.
    case leader
    case agents
    case skills
    case plugins
    case mcpServers
    case commands
    case repository
    case search
    case agent(String)
    case skill(String)
    case plugin(String)
    case mcpServer(String)
    case command(String)
    // The hub's picker.
    case launch(String)
    case window(String)
    case folder(String)
    case typeFolder

    /// Short name for the breadcrumb.
    var title: String {
        switch self {
        case .home: "home"
        case .leader: "me"
        case .agents: "agents"
        case .skills: "skills"
        case .plugins: "plugins"
        case .mcpServers: "mcp"
        case .commands: "commands"
        case .repository: "repo"
        case .search: "find"
        case .agent(let name), .skill(let name), .plugin(let name), .mcpServer(let name), .command(let name): name
        case .launch(let id): id
        case .window(let id): id
        case .folder(let path): path
        case .typeFolder: "folder"
        }
    }
}
