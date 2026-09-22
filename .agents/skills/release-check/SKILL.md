---
name: release-check
description: Pre-release checklist for AgentWorld — build in release mode, run the test suites, smoke-test the hub and the sidebar, and reinstall. Use before committing a user-facing change, tagging a version, or when asked whether the project is ready to ship. Works from any agent CLI (this skill lives in .agents/skills).
---

# Release check

Run from the repo root; stop at the first failure and report it with its output.

1. **Tests**: `cd Sidebar && swift test` — all suites must pass.
2. **Release build**: `swift build -c release --product agentworld-sidebar`, no warnings in our sources.
3. **Sidebar smoke test**: `.build/release/agentworld-sidebar --once --size 56x40 --cwd ..` prints a frame
   without crashing; repeat with `--provider codex` and `--demo`.
4. **Hub smoke test**: `.build/release/agentworld-sidebar --launcher --once --size 130x50 --cwd ..`
   shows the NEW TERMINAL cards for every provider.
5. **Shell integration**: `zsh -n shell/agentworld.zsh`.
6. **Docs**: new flags, keys, providers or settings are in `Sidebar/README.md`.
7. **Install**: `./scripts/install.sh`, then tell the user to open a new terminal.
