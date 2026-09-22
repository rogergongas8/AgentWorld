# AgentWorld app — roadmap

Ideas agreed for the next rounds of the macOS app (`Sources/AgentWorldApp`).
Everything must work for every agent CLI (Claude Code, Codex, Gemini, Kimi…),
using each CLI's own features rather than Claude-only logic.

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
