# AgentWorld app — roadmap

Ideas agreed for the next rounds of the macOS app (`Sources/AgentWorldApp`).
Everything must work for every agent CLI (Claude Code, Codex, Gemini, Kimi…),
using each CLI's own features rather than Claude-only logic.

## Done (2026-09-23)

- **UI redesign**: tabs in the title bar with the traffic lights lined up,
  real tabs (✕, hover, drag to reorder, right-click to close others or
  rename), full-height workspaces column (⌃⌘S hides it), one bar instead of
  three, the launcher centered; the right panel no longer flickers or drops
  hovers and clicks (the model stopped republishing twice a second).
- **Settings** (⌘, or the gear): projects folder, open at login, ask before
  closing a working agent, terminal font/size/⌥ as Meta, which CLIs the
  launcher shows, launch profiles editor, notifications, the agentworld
  skill per CLI, every shortcut.
- **A proper Mac app**: `make app` installs to /Applications; the welcome
  screen's "Make it yours" (Dock, login, Settings).
- **Changes** (panel key 4): uncommitted files with +/−, who touched them
  (any CLI: credited to the agents working when the file changed), the diff
  (↩), "review these" for the pane's agent; in ⌘K too.
- **Helpers walk in**: a pane opened with `agentworld-ctl open` walks over,
  stands beside its lead on the stage, and they celebrate when it's done.
- **Search in the panel**: `/` or ⌘F, counts per section.
- **Usage**: tokens today in the title bar; by CLI, day and session in its
  popover (Claude, Codex with its plan window, Gemini).
- **agentworld skill for every CLI** that's set up (skills folder of each).
- **Commit from the app** (⌘⇧C): your message or the agent writes it; push.
- **Exact attribution** from Claude's Edit/Write calls, surviving relaunches.
- **Resume tab by tab**, with names and layouts.
- **⌘K in sections** (All, Terminals, Launch, Workspaces, Agents, Skills,
  Files, Git, Actions; tab, and > @ # / prefixes), with the project's files
  to mention in the terminal.
- **Project map** (⌘⇧M): files as a graph of who uses whom, live rings for
  changes and agents' edits, details and actions per file.
- **Map**: a 3D graph you turn with the mouse (clusters, hubs, surprising
  links, ⇧-click paths, unlinked files on an outer shell); a minimap in Changes; `agentworld-ctl map` so every CLI can ask for the
  structure, a file's blast radius or the path between two files.
- **Grid button** on the home screen: hover 3×3 boxes, open that many tiled
  (up to 9 panes per tab).

## Done (2026-09-24)

- **Shared memory** for every CLI: Markdown notes per project plus global,
  in `~/AgentWorld/Memory` (plain Markdown). `agentworld-ctl memory`
  (search, read, write, append, delete) and the same as MCP tools
  (`agentworld-ctl mcp`, registered per CLI from Settings › Memory); who
  wrote what, an index per project, works without the app.
- **Memory view** (⌘⇧O, the brain): rendered notes with clickable
  `[[links]]`, backlinks, editing, a graph of the links; Memory section in
  the panel (6), notes in ⌘K.

- **Agents in touch** (any CLI, same workspace): `agentworld-ctl board`
  (who's doing what, the files each surely edited), `doing`, `message
  <#n|all>` handed over when the receiver's turn is over, `inbox`; the same
  as team_* MCP tools; a warning to both agents and you when two edit the
  same file. Also: switching tabs shows that tab's terminal (was stuck).

## Next

1. **Memory, next**: tags and a timeline in the view; offer to import each
   CLI's own memory (CLAUDE.md, AGENTS.md, GEMINI.md) as notes; notes on
   the project map beside the files they mention; a nudge to write a note
   when a long session ends.

2. **Cost next to tokens**, opt-in, from a price table you can edit (API
   users); subscriptions keep tokens only.
3. **Drag a tab onto another** to merge them into one tiled tab, and a pane
   out to its own tab.
4. **Smarter map links**: per-language resolvers (Go packages, Rust `mod`,
   Swift targets) instead of the shared type-name heuristic, and folders
   collapsed into single dots for very large repos.
5. **Map over time**: replay how the changes spread across the map during
   a session.
6. **Timing-based attribution that survives a relaunch** for CLIs without a
   transcript of their edits (keep it in `workspaces.json`).

## To verify by hand

These run in their own windows or need real input, which the debug
snapshots can't capture:

- Dragging tabs to reorder, and right-click › Rename.
- The project map with the mouse: hover, click, scroll/pinch zoom, drag.
- ⌘K: tab / ⇧tab between sections while typing.
- The Grid button's hover picker, and typing a commit message in its sheet.
- The right panel with the mouse: hover and clicks on rows (the flicker
  fix), popover cards.
- Skill/agent detail cards opened with ↩ / `e`, and the "+ New" card (`n`).
- The workspace context menu (rename, pin, open in editor, remove).
- "Ask before closing" with a busy agent (⌘W).
- Open at login (installed app), notification permission.
- Resuming a Codex conversation (`codex resume <id>`) and Codex's usage and
  plan window with real sessions.
- A full workflow (e.g. *Build & review*) with real CLIs, not just shells.
- Memory with real CLIs: each one's MCP tools after Settings › Memory
  connects it.
- Agents messaging each other with real CLIs: delivery into Claude and
  Codex prompts when their turn ends, and Gemini & co. picking theirs up
  from the 📬 hint.
- The notes view with the mouse: clicking [[links]], editing and ⌘S,
  delete (click twice), the graph's hover and click.
