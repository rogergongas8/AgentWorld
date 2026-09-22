import Foundation

/// The `agentworld` skill: teaches Claude Code, running inside one of the
/// app's terminals, to use `agentworld-ctl`. Installed into
/// `~/.claude/skills/agentworld/` on launch; a copy you've edited (one without
/// the marker line) is left alone.
enum AgentWorldSkill {
    static let marker = "<!-- installed by AgentWorld.app: edits are overwritten; delete this line to keep your own version -->"

    static let text = """
    ---
    name: agentworld
    description: Drive the AgentWorld app you are running inside — open other agent CLIs (Claude, Codex, Gemini…) in panes beside you, hand them tasks, wait for them, read their answers, and talk to the user through your on-screen character. Use when $AGENTWORLD_SOCKET is set and the user asks for a second opinion, a reviewer, parallel work, or to compare CLIs; or to leave the user a short status line or notification during long work.
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
    ```

    ## Handing work to another pane

    1. `agentworld-ctl clis` — pick one. Prefer a *different* CLI for a second
       opinion or review (Codex reviewing Claude's work catches other things);
       another `claude` is fine for parallel work.
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

    static func install() {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills/agentworld", isDirectory: true)
        let file = folder.appendingPathComponent("SKILL.md")
        if let existing = try? String(contentsOf: file, encoding: .utf8) {
            guard existing.contains(marker), existing != text else { return }
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? text.write(to: file, atomically: true, encoding: .utf8)
    }
}
