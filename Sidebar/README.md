# AgentWorld

Your agent CLIs (Claude Code, Codex, Gemini CLI, Kimi CLI, Grok…) side by
side in one terminal, each with a visual, navigable map of its agents,
skills, plugins and MCP servers.

## The hub: `agentworld`

Run `agentworld` in any folder. It's a terminal app with two tabs, like a
desktop agent manager but 100% CLI:

- **Code**: on the left, your **workspaces** (folders) with the terminals
  open in each, nested underneath, with live status: what a Claude session
  is doing right now ("Edit Stage.swift", "your turn", "idle 3m"), or tmux
  activity for other CLIs. On the right, **Start coding in <folder>**: a
  button per CLI with its character's face (Claude Code, Codex, Gemini, Kimi,
  Grok, OpenCode, Cursor Agent, a plain Terminal, and your saved profiles).
  One opens as a new tab with the CLI on the left and its AgentWorld map on
  the right; **Launch more than one…** lets you tick several (space) and
  opens them **tiled side by side** in one tab, each pane with a title bar.
  Highlight a running terminal in the tree to see its card: status, tasks,
  agents at work, and buttons to jump to it, open another agent next to it
  or close it.
- **Agents**: every agent across your CLIs as a character, with what it's
  doing ("working in AgentWorld: Read Stage.swift", "done 4m ago") or what
  it's for. Its page shows who powers it, the skills it carries (on a
  shelf), its tools, and **Start a session with it** (a new tab with
  "Use the X agent to " already typed) or **Hand it to** a running session.

Tabs along the very top (click them, or `a` / `c`); `tab` moves between the
tree and the main area, arrows move inside, `⏎` opens, `d` opens a folder
(tab completes), `1`–`9` jump to a terminal, `x` twice closes one, `q` leaves
with everything still running. In any terminal, `Ctrl-b h` brings you back to
the hub, and clicking a tab at the top switches.

The hub runs on its own tmux server (`tmux -L agentworld`), so it never
touches your other tmux sessions, and your terminals keep running when you
close the window: `agentworld` brings them back. Running it from another
folder points it there. Terminals inherit the environment of the shell that
first started the hub (PATH, API keys).

**Profiles** are saved presets: model, flags, environment. Add them to
`~/.config/agentworld/profiles.json` and they appear in the picker:

```json
[
  { "name": "Claude · Opus plan", "provider": "claude", "args": ["--model", "opus", "--permission-mode", "plan"] },
  { "name": "Codex high effort", "provider": "codex", "args": ["-c", "model_reasoning_effort=high"] },
  { "name": "Kimi via wrapper", "provider": "kimi", "command": "~/bin/kimi-work", "env": { "KIMI_PROFILE": "work" } }
]
```

`provider` is one of `claude`, `codex`, `gemini`, `kimi`, `grok`, `opencode`,
`cursor`, `terminal`; `command`
overrides the executable. Keep secrets in your shell environment, not here.

**What each sidebar reads:**

| CLI | skills | MCP servers | commands | plugins | instructions |
|---|---|---|---|---|---|
| Claude Code | `.claude/skills`, `~/.claude/skills`, plugins | `.mcp.json`, `~/.claude.json` | `.claude/commands` | installed + synced plugins | `CLAUDE.md` |
| Codex | `.codex/skills`, `~/.codex/skills` (+ system), plugins | `config.toml` `[mcp_servers.*]` | `~/.codex/prompts` | enabled plugins in `config.toml` | `AGENTS.md` |
| Gemini CLI | `.gemini/skills`, `~/.gemini/skills`, extensions | `settings.json` | `commands/*.toml` | `~/.gemini/extensions` | `GEMINI.md` |
| Kimi / Grok | `~/.kimi/skills`, `~/.grok/skills` | `mcpServers` in their JSON settings | `commands/*.md` | — | `AGENTS.md` / `GROK.md` |
| OpenCode | `.opencode/`, `~/.config/opencode/` (`agent/`, `command/`) | `opencode.json` `mcp` | `command/*.md` | — | `AGENTS.md` |
| Cursor Agent | `.cursor/`, `~/.cursor/` | `mcp.json` | — | — | `AGENTS.md` / `.cursorrules` |

Every CLI also picks up `.agents/skills` in the project. Live activity
(tasks, subagents at work, tool calls, the **live** and **log** views) is
available for Claude Code, whose transcripts AgentWorld can follow; for the
others the sidebar maps their setup.

## The Claude sidebar: `claude`

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
- **Skills on shelves**: every skill is a book on the shelf of its category
  (design, documents, code & quality, integrations, data, workflow). The
  band on the spine says where it comes from (yours, this repo, a plugin),
  used ones sparkle, and the selected book shows a one-line summary. Pin a
  skill to a shelf with `category: design` (or documents, code, integrations,
  data, workflow) in its `SKILL.md` front matter.
- **Skills on agents**: an agent's `skills:` front matter equips it; they show
  as little books on its card and on both detail pages.
- **Summon** (`u` on any card or book, or the ▶ buttons on detail pages):
  types "Use the ui-reviewer agent to ", "Use the ui-reviewer agent with the
  pixel-character skill to " or "/terminal-snapshot " into the CLI next to
  the sidebar, without sending it, and moves the cursor there so you finish
  the sentence.
- **Browse**: plugins and everything they add, MCP servers, slash commands.
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
| `u` | summon the selected agent, skill or command into the CLI |
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

This installs both `agentworld` (the hub) and the `claude` wrapper.

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
    Config/             per-CLI config readers (Claude, Codex, Gemini, Kimi,
                        Grok), repo profile, the "use now" recommender
    Providers/          the CLIs AgentWorld hosts, launch profiles
    Transcript/         slug → directory, session locator, tailers
    Session/            JSONL → TranscriptEvent parser; SessionStore state machine
  TerminalUI/           generic terminal primitives
                        (cell canvas, half-block pixel canvas, diffing screen,
                         truecolor/256 colors, raw-mode keys, SGR mouse)
  agentworld-sidebar/
    App/                options, main loop, session feed, --demo script
    World/              characters, poses/animations, the stage scene
    Hub/                the `agentworld` picker and its tmux workspace
    Explore/            the navigable explorer: routes, pages, character
                        cards, pixel icons, focus/scroll handling
    Panels/             header, tasks, crew, MCP, skills, tools, log, layout
Tests/                  swift-testing suites for both libraries
shell/agentworld.zsh    the `claude` wrapper and the `agentworld` command
shell/hub.tmux.conf     the hub's tmux server config (tabs, mouse, keys)
scripts/                install / uninstall
```

Development: `make test`, `make demo`, and `make snapshot`, which prints one
frame of the current directory's latest session to stdout.
