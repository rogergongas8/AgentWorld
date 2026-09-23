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

## Next

1. **Commit from the app**: a message box under Changes (or ask the agent
   to write it), commit and push, with the branch in the title.
2. **Cost next to tokens**, opt-in, from a price table you can edit (API
   users); subscriptions keep tokens only.
3. **Attribution that survives a relaunch**: keep who-touched-what per
   workspace in `workspaces.json`, and read Claude's Edit/Write tool calls
   for exact files when they're there.
4. **Tabs remembered with their names**, and dragging a tab onto another
   to merge them into one tiled tab.
5. **Full screen**: without the traffic lights, drop their reserved space.

## To verify by hand

These run in their own windows or need real input, which the debug
snapshots can't capture:

- Dragging tabs to reorder, and right-click › Rename.
- The right panel with the mouse: hover and clicks on rows (the flicker
  fix), popover cards.
- Skill/agent detail cards opened with ↩ / `e`, and the "+ New" card (`n`).
- The workspace context menu (rename, pin, open in editor, remove).
- "Ask before closing" with a busy agent (⌘W).
- Open at login (installed app), notification permission.
- Resuming a Codex conversation (`codex resume <id>`) and Codex's usage and
  plan window with real sessions.
- A full workflow (e.g. *Build & review*) with real CLIs, not just shells.
