# AgentWorld

A macOS app for your agent CLIs — Claude Code, Codex, Gemini CLI, Kimi CLI,
Grok, OpenCode, Cursor Agent, Kiro CLI, or a plain shell — side by side in real
terminals, each with a map of its agents, skills, plugins and MCP servers,
and pixel characters acting out what they're doing.

## The app

- **Workspaces** (folders) down the left, with their sessions and live
  status and how many files are changed; ⌃⌘S hides the column.
- **Tabs in the title bar**: ✕ to close, drag to reorder, right-click to
  rename or close others. "Start coding in <folder>" has a card per CLI
  (Claude Code, Codex, Gemini, Kimi, Grok, OpenCode, Cursor Agent, a plain
  Terminal, your profiles): each opens a **real terminal** (SwiftTerm), and
  "Launch more than one…" tiles several in one tab.
- **The right panel**: the CLI and its crew acting out what they do, then
  Crew, Skills, Tools, **Changes** and Tips. Click (or ⌘E and the arrows)
  to hand one to the terminal; `/` or ⌘F searches. Changes lists the
  uncommitted files, which agent touched each one, and its diff.
- **Agents drive the app**: with the `agentworld` skill (installed for every
  CLI set up here) or `agentworld-ctl`, an agent opens helpers beside it;
  they walk in, work, and celebrate with their lead when done.
- **Usage**: tokens today in the title bar; by CLI, day and session in its
  popover (Claude Code, Codex with its plan window, Gemini CLI).
- **Stories**: a lone terminal gets a little theater beside it. The CLI's
  character (Claude's block, Kiro's ghost, Codex's visor…) acts out what it's
  doing, a crew member brings over the skill it reaches for, helpers work
  alongside; idle, stories take turns: a ball game, a coffee break, a nap,
  stargazing, a campfire, a bright idea, Kiro's "boo!".
- **Getting around**: ⌃Tab switches terminals like ⌘Tab switches apps;
  ⌘1…9 go to tabs (hold ⌘ to see the numbers).
- **Settings** (⌘,): terminal font, notifications, which CLIs show, launch
  profiles, open at login.

Build and install it with `make app` (or `./scripts/build-app.sh`): it goes
to /Applications (~/Applications if that isn't writable). Open **AgentWorld**
from Spotlight/Launchpad, or `agentworld` from a terminal to open it on
that folder. It reads your login shell's environment, so the CLIs are found
even when opened from the Dock. Needs macOS 13+.

## How it works

The app hosts each CLI in a real terminal (SwiftTerm) through your login
shell, so it sees your PATH and settings. It never talks to the CLIs: it
reads what they already write. Claude Code's transcripts
(`~/.claude/projects/<slug>/<session>.jsonl`, helpers under
`<session>/subagents/`) drive the characters and tasks — the app pins a
`--session-id` so it follows exactly that conversation — and Codex's
rollouts and Gemini's chats give their status and token use. Each CLI's own
config folders give the panel its agents, skills, commands, plugins and MCP
servers.

Agents drive the app with `agentworld-ctl` (on PATH in its terminals; the
`agentworld` skill, installed for every CLI set up here, explains it): open
panes beside them, hand off work, read answers, talk through their
character, and ask for the project's map.

## Layout

```
Sources/
  AgentWorldApp/        the macOS app (SwiftUI + SwiftTerm)
    Model/              workspaces, tabs, sessions, changes, usage, the
                        project map, settings, the control server
    Views/              window, tabs, launcher, panel, map, palette, sheets
  AgentWorldKit/        model layer, no UI
    Config/             per-CLI config readers, repo profile, recommender
    Providers/          the CLIs AgentWorld hosts, launch profiles
    Session/            transcript parsing, SessionStore, usage ledger
    Transcript/         session locating and tailing
    Git/                changes, diffs, commits, project files
    Graph/              the project graph, clusters, layout
    Control/            the socket protocol agentworld-ctl speaks
  AgentWorldArt/        pixel characters, looks, poses, props
  TerminalUI/           pixel canvas and colors the characters are drawn with
  agentworld-ctl/       the command agents run inside the app
Tests/                  swift-testing suites
scripts/build-app.sh    build, bundle, sign (ad hoc) and install the app
```

## Development

`make test`, and `make app` to build and install it. Requires macOS 13+ and
a Swift 6 toolchain (Xcode 16+). With `AGENTWORLD_DEBUG_CONTROL=<file>` the
app reads commands from that file (launch, snapshot, keys, map…; see
`Sources/AgentWorldApp/Model/DebugControl.swift`), so changes can be checked
on screen from scripts; `AGENTWORLD_WORKSPACES=<file>` keeps test runs away
from your own workspaces.
