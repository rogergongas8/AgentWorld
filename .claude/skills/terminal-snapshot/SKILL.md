---
name: terminal-snapshot
description: Capture the AgentWorld sidebar or hub as a PNG to check how it really renders — pixel characters, colors, layout at a given pane size. Use after any UI change in Sidebar/Sources (panels, explorer pages, hub picker, character art) before calling it done, or when asked to screenshot, preview or visually verify the sidebar.
---

# Terminal snapshot

The sidebar is a full-screen terminal app, so the only honest check is to run
it at a real size and look at the frame. `scripts/snapshot.sh` does that in a
throwaway tmux server (`-L aw-snapshot`, never the user's own) and
`scripts/ansi2png.py` turns the capture into an image you can Read.

## Steps

1. Build: `cd Sidebar && swift build` (the script builds if the binary is missing, not if it's stale).
2. Capture, from anywhere in the repo:

   ```sh
   .claude/skills/terminal-snapshot/scripts/snapshot.sh /tmp/aw/home.png
   .claude/skills/terminal-snapshot/scripts/snapshot.sh /tmp/aw/agent.png --keys "Right Enter"
   .claude/skills/terminal-snapshot/scripts/snapshot.sh /tmp/aw/codex.png -- --provider codex
   .claude/skills/terminal-snapshot/scripts/snapshot.sh /tmp/aw/demo.png --wait 14 -- --demo
   .claude/skills/terminal-snapshot/scripts/snapshot.sh /tmp/aw/hub.png --size 130x50 -- --launcher
   ```

   `--keys` are tmux key names (`Down`, `Enter`, `Escape`, `/`, `j`…), sent
   0.35 s apart. Use the scratchpad for output when one is available.
3. Read the PNG and look for: clipped or overlapping text, unreadable
   contrast (dark names on the dark background), cards wrapping badly,
   selection highlight on the wrong item, broken glyphs.
4. Check the narrow case too (`--size 40x40`): the sidebar is usually ~34% of
   the terminal.

## Gotchas

- Mouse clicks: `tmux -L aw-snapshot send-keys -t <session> -l $'\e[<0;X;YM'`
  (1-based cell coordinates) — but the script kills its session, so run the
  steps by hand for click tests.
- The live views follow the newest Claude session for the repo; `--demo`
  gives deterministic content. Demo timeline: subagents appear around 9 s,
  three at once around 32 s.
- Glyphs missing from Menlo render as boxes in the PNG only; real terminals
  may be fine. Prefer glyphs from the existing Theme anyway.
