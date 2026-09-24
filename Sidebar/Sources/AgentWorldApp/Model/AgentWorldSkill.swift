import Foundation

/// The `agentworld` skill: teaches an agent CLI running inside one of the
/// app's terminals to use `agentworld-ctl`. Installed on launch into the
/// `skills/` folder of every agent CLI set up here (Claude Code, Codex,
/// Gemini, Kimi, Grok, OpenCode, Cursor: the Agent Skills format they share);
/// a copy you've edited (one without the marker line) is left alone. A CLI
/// that doesn't load skills still gets there: `agentworld-ctl help` explains itself.
enum AgentWorldSkill {
    static let marker = "<!-- installed by AgentWorld.app: edits are overwritten; delete this line to keep your own version -->"

    static let text = """
    ---
    name: agentworld
    description: Drive the AgentWorld app you are running inside — open other agent CLIs (Claude, Codex, Gemini…) in panes beside you, hand them tasks, wait for them, read their answers, and talk to the user through your on-screen character. Use when $AGENTWORLD_SOCKET is set and the user asks for a second opinion, a reviewer, parallel work, or to compare CLIs; or to leave the user a short status line or notification during long work; to coordinate with the other agents working in the same project (who's doing what, which files, messages between agents); also to see a project's structure cheaply (clusters, hubs, what depends on a file) with agentworld-ctl map; and to search, read and write the shared memory every CLI uses (agentworld-ctl memory) before starting a task and when you learn something worth keeping.
    ---

    # AgentWorld

    You are running in a terminal pane of AgentWorld, a macOS app that shows
    several agent CLIs side by side, each with a pixel character acting out
    what it's doing. `agentworld-ctl` (already on PATH) drives it. Check
    `echo $AGENTWORLD_SOCKET` first: if it's empty you're not inside
    AgentWorld and none of this applies.

    ## Commands

    ```sh
    agentworld-ctl panes                     # open panes: #n, CLI, status (* = you)
    agentworld-ctl clis                      # CLIs installed here
    agentworld-ctl open codex --prompt "…"   # new pane beside you; prints #n
    agentworld-ctl send '#3' "…"             # type into #3 and press return
    agentworld-ctl wait '#3' 900             # block until #3 stops working
    agentworld-ctl read '#3' 80              # last 80 lines of #3's screen
    agentworld-ctl focus '#3'                # show #3 to the user
    agentworld-ctl close '#3'
    agentworld-ctl say "…"                   # a line on your character's stage
    agentworld-ctl notify "…"                # macOS notification
    agentworld-ctl map                       # project structure: clusters, hubs, surprising links
    agentworld-ctl map file src/a.ts         # what a file uses / what uses it (blast radius)
    agentworld-ctl map path a.ts b.ts        # how two files are linked
    agentworld-ctl map show src/a.ts         # show the user the project map on that file
    ```

    ## Finding your way in the project

    `agentworld-ctl map` reads the workspace's files and how they link
    (imports, and the types one file names that another declares), locally
    and in a second. Use it before reading lots of files: the overview says
    which files cluster together and which are hubs; `map file <path>` lists
    what depends on a file before you change it; `map path a b` shows how
    two parts connect. `map show <path>` puts the map on the user's screen.

    ## Shared memory

    Notes every agent CLI here reads and writes: Markdown in a vault the user
    also browses (in the app with ⌘⇧O, or in Obsidian). They belong to this
    project or are global (about the user, for every project). This works
    even outside AgentWorld. If you have the `agentworld-memory` MCP tools
    (memory_search, memory_write…), use those; otherwise:

    ```sh
    agentworld-ctl memory                          # this project's notes + global ones
    agentworld-ctl memory search deploy staging    # notes with all these words
    agentworld-ctl memory read deploy              # one note
    agentworld-ctl memory write deploy --kind howto --description "How to deploy" --tags ops <<'EOF'
    Deploy with `make release`; staging first. See [[release-checklist]].
    EOF
    agentworld-ctl memory write deploy --append "Staging needs VPN since 2026-09."
    agentworld-ctl memory write prefers-short-answers --global "The user wants terse replies."
    agentworld-ctl memory delete old-note          # wrong or no longer true
    agentworld-ctl memory-show deploy              # show the user that note
    ```

    - **Before** non-trivial work, search for the topic: another agent (maybe
      another CLI) may already know how to run, test or deploy this project.
    - **Write** when you learn what a future agent would need: a decision and
      why, how to build/test/run, a gotcha, a user preference. One fact or
      topic per note, a short-kebab-case name, a one-line description, and a
      `--kind`: context, howto, decision, gotcha or preference.
    - Update (`--append`, or rewrite) instead of adding near-copies; delete
      notes that turn out wrong. Link related notes with `[[name]]`.
    - Never store secrets, or what the code or git history already records.

    ## Working alongside other agents

    Several agents (any CLI) may work in the same project at once. Stay out of
    each other's way without chatting:

    ```sh
    agentworld-ctl board                     # who's here, doing what, which files they edited
    agentworld-ctl doing "Refactoring the parser in src/parse/"   # tell them what you're on
    agentworld-ctl message '#3' "I changed parse() to return a Result; update callers"
    agentworld-ctl message all "Don't touch db/migrations, I'm reordering them"
    agentworld-ctl inbox                     # messages waiting for you
    ```

    - At the start of a task, check the board if others are open, and set `doing`.
    - Before editing a file another agent edited, message it first.
    - Messages arrive in your prompt as "[AgentWorld · message from…]" when
      your turn is over. Act on them; reply only if it's needed, briefly.
    - AgentWorld warns both of you when two agents edit the same file.
    - The MCP tools team_board, team_doing, team_message and team_inbox do the same.

    ## Handing work to another pane

    1. `agentworld-ctl clis` — pick one. Prefer a *different* CLI for a second
       opinion or review (a different model catches different things);
       another of your own CLI is fine for parallel work.
    2. Open it with a self-contained brief: the other agent sees none of your
       conversation. Say what to do, which files, what "done" looks like, and
       ask it to finish with a short summary.
       `P=$(agentworld-ctl open codex --prompt "…" | cut -d' ' -f1)`
    3. `agentworld-ctl wait "$P"` then `agentworld-ctl read "$P" 120`. The
       screen is the CLI's UI, not clean output: pick out the answer. If it
       asked a question or needs approval, answer with `send`, or tell the user
       to look at that pane (`focus`).
    4. Tell the user what the other agent concluded and what you did with it.
       Leave its pane open unless the user wants it closed.

    Keep it to at most 3 helper panes; a tab holds 6. Run `wait` in the
    foreground with a timeout rather than polling in a loop.

    ## Talking to the user

    - `say` for a one-line status during long work ("Tests pass, now updating
      the docs") — it shows under your character for two minutes.
    - `notify` only when the user needs to come back (done, blocked, a
      question), not for progress.

    \(marker)

    """

    /// Each CLI's config folder, where it loads `skills/<name>/SKILL.md`
    /// (the same folders the panel reads skills from).
    static let homes: [(name: String, folder: String)] = [
        ("Claude Code", ".claude"), ("Codex", ".codex"), ("Gemini CLI", ".gemini"), ("Kimi CLI", ".kimi"),
        ("Grok CLI", ".grok"), ("OpenCode", ".config/opencode"), ("Cursor Agent", ".cursor"), ("Kiro CLI", ".kiro"),
    ]
    static var skillHomes: [String] { homes.map(\.folder) }

    static func install() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for cli in skillHomes where FileManager.default.fileExists(atPath: home.appendingPathComponent(cli).path) {
            let folder = home.appendingPathComponent(cli + "/skills/agentworld", isDirectory: true)
            let file = folder.appendingPathComponent("SKILL.md")
            if let existing = try? String(contentsOf: file, encoding: .utf8) {
                guard existing.contains(marker), existing != text else { continue }
            }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    /// Removes the copies AgentWorld installed; your own edited ones stay.
    static func uninstall() {
        for file in installedFiles() {
            guard let text = try? String(contentsOf: file, encoding: .utf8), text.contains(marker) else { continue }
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        }
    }

    /// The CLIs here that have the skill, and whether it's AgentWorld's copy.
    static func status() -> [(cli: String, path: String, installed: Bool, yours: Bool)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return homes.filter { FileManager.default.fileExists(atPath: home.appendingPathComponent($0.folder).path) }.map { cli in
            let file = home.appendingPathComponent(cli.folder + "/skills/agentworld/SKILL.md")
            let text = try? String(contentsOf: file, encoding: .utf8)
            return (cli.name, "~/" + cli.folder + "/skills/agentworld", text != nil, text.map { !$0.contains(marker) } ?? false)
        }
    }

    private static func installedFiles() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return skillHomes.map { home.appendingPathComponent($0 + "/skills/agentworld/SKILL.md") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
