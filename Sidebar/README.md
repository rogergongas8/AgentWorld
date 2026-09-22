# AgentWorld Sidebar

A visual, navigable map of your Claude Code setup, living next to Claude in
the same terminal. Type `claude` as usual: the real Claude Code UI opens on
the left and AgentWorld on the right, split with tmux (no status bar, so it
feels like one terminal). It doesn't repeat the chat: it shows who and what
you can work with, and what fits the task in front of you.

**1 explore** (the default view) is a little world you can walk around:

- **Your crew**: every agent is a pixel character on a card: Claude, the
  built-in agents (Explore, Plan, general-purpose), and your own and your
  plugins' agents. Cards come alive when that agent is working right now
  ("● browsing"). Open one to see what it does, its tools, the skills it
  carries, its runs this session and how to call it.
- **Use now**: agents, skills and commands that fit your last prompt (English
  or Spanish), the files being touched, or, before the first prompt, this
  repo's stack. Each one says which words matched.
- **Browse**: skills grouped by where they come from (project, yours, each
  plugin), plugins and everything they add, MCP servers, slash commands.
- **This repo**: what CLAUDE.md tells Claude (or a nudge to run `/init`),
  folders, detected stack, project-level agents/skills/MCP, hooks.
- **Find** (`/`): search everything by name and description.

**2 live** is the animated stage: Claude acting out what it's doing, one
character per running subagent, plus tasks, crew, MCP and tool counts.
**3 log** is the raw activity timeline, if you want it.

### Moving around

Click the sidebar to focus it (click Claude's side to go back), or use tmux's
`Ctrl-b ←/→`. Then:

| keys | |
|---|---|
| `↑↓←→` / `hjkl` | move between cards and rows |
| `⏎` / `→` / click | open |
| `esc` / `←` / `⌫` / click `‹` | back |
| `/` | find |
| `g` | home |
| `PgUp` `PgDn`, wheel | scroll |
| `1` `2` `3`, `tab`, click a tab | switch view |
| `s` | toggle the stage (live view) |
| `q` | close the sidebar |

## Install

Requirements: macOS 13+, Swift 6 toolchain (Xcode 16+), tmux (`brew install tmux`), zsh.

```sh
./scripts/install.sh      # build, install to ~/.local/bin, hook up ~/.zshrc
```

Re-run it to update. `./scripts/uninstall.sh` removes it again.

Preview every animation without spending tokens:

```sh
agentworld --demo         # or: make demo
```

Settings (environment variables): `AGENTWORLD_DISABLE=1` runs plain claude,
`AGENTWORLD_WIDTH=34%` sets the sidebar width, `AGENTWORLD_FPS=12` sets the
frame rate, `AGENTWORLD_COLOR=256` forces 256-color mode, and
`AGENTWORLD_MOUSE=0` leaves tmux mouse mode off. With mouse mode on (the
default, for AgentWorld's own tmux session only), dragging selects text
through tmux; hold `⌥ Option` (or `Shift`, depending on the terminal) to use
your terminal's native selection instead.

## How it works

Claude Code already writes every session to
`~/.claude/projects/<cwd with non-alphanumerics → "-">/<sessionId>.jsonl`,
and each subagent to `<sessionId>/subagents/agent-*.jsonl`. The sidebar
tails those files. It never talks to Claude Code, and Claude Code doesn't
know it's there.

The `claude` wrapper (`shell/agentworld.zsh`) generates a UUID and passes it
to both `claude --session-id` and the sidebar, so the sidebar follows exactly
that conversation even when other sessions run in the same project. With
`--resume`/`--continue` it follows the project's most recently active
transcript instead. Non-interactive uses (`claude -p`, `claude mcp …`,
`--version`, pipes) skip the sidebar entirely.

## Layout

```
Sources/
  AgentWorldKit/        model layer, no terminal code
    Config/             agents, skills, commands, plugins, MCP servers,
                        repo profile; the "use now" recommender
    Transcript/         slug → directory, session locator, tailers
    Session/            JSONL → TranscriptEvent parser; SessionStore state machine
  TerminalUI/           generic terminal primitives
                        (cell canvas, half-block pixel canvas, diffing screen,
                         truecolor/256 colors, raw-mode keys, SGR mouse)
  agentworld-sidebar/
    App/                options, main loop, session feed, --demo script
    World/              characters, poses/animations, the stage scene
    Explore/            the navigable explorer: routes, pages, character
                        cards, pixel icons, focus/scroll handling
    Panels/             header, tasks, crew, MCP, skills, tools, log, layout
Tests/                  swift-testing suites for both libraries
shell/agentworld.zsh    the `claude` wrapper
scripts/                install / uninstall
```

Development: `make test`, `make demo`, and `make snapshot`, which prints one
frame of the current directory's latest session to stdout.
