---
name: release-check
description: Pre-release checklist for AgentWorld — run the test suites, build the app in release mode, smoke-test it and reinstall. Use before committing a user-facing change, tagging a version, or when asked whether the project is ready to ship. Works from any agent CLI (this skill lives in .agents/skills).
---

# Release check

Run from the repo root; stop at the first failure and report it with its output.

1. **Tests**: `cd Sidebar && swift test` — all suites must pass.
2. **Release build**: `swift build -c release --product AgentWorldApp` and
   `--product agentworld-ctl`, no warnings in our sources.
3. **Smoke test**: the debug app driven as the `app-snapshot` skill shows
   (`.claude/skills/app-snapshot/SKILL.md`): launcher, a Terminal pane, ⌘K,
   the map, Settings — captured and looked at.
4. **Docs**: new keys, settings, commands or providers are in `Sidebar/README.md`
   and `Sidebar/ROADMAP.md`.
5. **Install**: `make app` (from `Sidebar/`), then tell the user to reopen AgentWorld.
