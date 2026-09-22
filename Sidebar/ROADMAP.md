# AgentWorld app — roadmap

Ideas agreed for the next rounds of the macOS app (`Sources/AgentWorldApp`).
Everything must work for every agent CLI (Claude Code, Codex, Gemini, Kimi…),
using each CLI's own features rather than Claude-only logic.

## First: UI redesign

User feedback 2026-09-23: it doesn't feel like a finished app yet.

- **Layout**: everything is crammed at the top of the window; use the space,
  with clear hierarchy and breathing room.
- **Real tabs**: tabs that look like tabs (not just text), each with a
  visible ✕ to close, hover states, reorder by dragging.
- **Right panel glitches**: flicker and bad mouse tracking (hover and clicks
  miss). Suspects: the 10 fps `TimelineView` rebuilding rows and resetting
  `onHover` state, the model's 0.5 s tick republishing the whole tree, and
  popovers anchored to rows that get rebuilt. Animate only the pixel art,
  keep rows static.
- **Settings window** (⌘,): default workspace folder, which CLIs to show,
  launch profiles (flags/env per CLI, today only `profiles.json`), theme and
  font size, notifications, keyboard shortcuts, turning the `agentworld`
  skill install on or off, start at login.
- **A proper Mac app**: open from the Dock or Spotlight without a terminal
  (it works today, see the README), plus install it in `/Applications`, a
  first-run screen, and "keep in Dock" guidance.

## Next

1. **Git changes panel** for the workspace: what each agent touched, with a
   diff, from the right panel or its own tab.
2. **Helpers walk in**: when a CLI opens another with `agentworld-ctl open`,
   the new character walks over to its pane; they celebrate together when
   the work is done.
3. **Search in the panel**: `/` filters skills (and agents, tools) while the
   panel has the keys (⌘E).
4. **Budget and usage**: tokens and cost per session and per day, for every
   CLI.
5. **`agentworld` skill for every CLI**: in each one's own format (Gemini
   extensions, Kimi…), so any of them can lead a workflow. Today: Claude and
   Codex (`skills/`), others through `agentworld-ctl help`.

## To verify by hand

These run in their own windows, which the debug snapshots can't capture:

- Skill/agent detail cards opened with ↩ / `e`, and the "+ New" card (`n`).
- The workspace context menu (rename, pin, open in editor, remove).
- Resuming a Codex conversation (`codex resume <id>`): Codex isn't installed
  on the dev machine yet.
- A full workflow (e.g. *Build & review*) with real CLIs, not just shells.
