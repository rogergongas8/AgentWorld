---
name: app-snapshot
description: Drive the AgentWorld macOS app from a script and capture it as PNGs to check a change really works on screen — launch CLIs, open the palette, the map, Settings, simulate an agent's status, send keys through the app's key router, resize the window. Use after any change in Sidebar/Sources/AgentWorldApp before calling it done, or when asked to screenshot or visually verify the app.
---

# App snapshot

The debug build reads one command per line from the file in
`AGENTWORLD_DEBUG_CONTROL` (then empties it), so a script can drive it and
take window snapshots without Screen Recording access. The full list is at
the top of `Sidebar/Sources/AgentWorldApp/Model/DebugControl.swift`.

## Steps

1. `cd Sidebar && swift build --product AgentWorldApp` (and `agentworld-ctl` if you test it).
2. Start it on its own workspaces file, so the user's stay untouched:

   ```sh
   S=<scratch dir>; : > $S/ctl; echo '[]' > $S/ws.json
   (AGENTWORLD_WORKSPACES=$S/ws.json AGENTWORLD_DEBUG_CONTROL=$S/ctl \
     .build/debug/AgentWorldApp --folder "$PWD/.." > $S/app.log 2>&1 &)
   sleep 5; pgrep -n AgentWorldApp > $S/pid
   ```

3. Send commands one at a time, a second or two apart, and wait for files:

   ```sh
   echo "launch Terminal" > $S/ctl            # a plain shell: no tokens spent
   echo "act 0 running Bash swift test" > $S/ctl   # pretend pane 0 is working
   echo "panel" > $S/ctl; echo "keys 4{down}{ret}" > $S/ctl   # panel keys
   echo "palette @map" > $S/ctl               # ⌘K with a query
   echo "map" > $S/ctl; echo "map-select AppModel.swift>Tiles.swift" > $S/ctl
   echo "settings terminal" > $S/ctl; echo "snapshot-key $S/settings.png" > $S/ctl
   echo "size 980 620" > $S/ctl               # the minimum window
   echo "snapshot $S/shot.png" > $S/ctl       # the main window
   ```

4. Crop with PIL (`sips` crops from the wrong corner) and Read the PNG.
5. Kill it when done: `kill $(cat $S/pid)`.

## Gotchas

- Terminal contents draw white in snapshots; that's the capture, not the app.
- A capture taken while the window is busy can show a stale list: take another.
- `hittest <x> <y> <file>` says which view a click lands on (points from the
  top left): the way to check clickability without clicking.
- Real CLIs (`launch Claude Code`) spend the user's tokens: prefer Terminal
  panes with `act` for statuses, and `agentworld-ctl` against the pane's
  socket (`~/.config/agentworld/run/<pid>.sock`, `AGENTWORLD_PANE=<n>`).
