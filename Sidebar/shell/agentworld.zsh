# AgentWorld — makes `claude` open with a live, animated sidebar in the same
# terminal: Claude Code's normal UI on the left, AgentWorld on the right,
# split with tmux. Installed by `scripts/install.sh` to
# ~/.config/agentworld/sidebar.zsh and sourced from ~/.zshrc.
#
# It is strictly best-effort: whenever the sidebar can't or shouldn't run
# (no tmux, no binary, not a terminal, a non-interactive subcommand…) plain
# `claude` runs exactly as if this file didn't exist.
#
# Settings (environment variables):
#   AGENTWORLD_DISABLE=1   skip the sidebar entirely
#   AGENTWORLD_WIDTH=34%   sidebar width (tmux size: percentage or columns)
#   AGENTWORLD_FPS=12      animation frame rate
#   AGENTWORLD_MOUSE=0     don't turn on tmux mouse mode (clicking a pane to
#                          focus it, clicking/scrolling in the explorer)

# Subcommands and flags that print and exit, or aren't the interactive TUI.
typeset -ga _agentworld_passthrough_commands=(
    agents attach auth auto-mode config doctor gateway import install logs mcp
    migrate-installer plugin plugins project respawn rm setup-token stop kill
    ultrareview update upgrade
)
typeset -ga _agentworld_passthrough_flags=(-p --print -h --help -v --version)
# Flags meaning "not a brand-new session": don't pin a session id.
typeset -ga _agentworld_resume_flags=(-c --continue -r --resume --session-id --fork-session --from-pr)

claude() {
    local real_claude sidebar_bin
    # `whence -p` (not `command -v`): this function is itself named `claude`,
    # and `command -v` would resolve back to it and recurse forever.
    real_claude=$(whence -p claude) || { print -u2 "agentworld: 'claude' not found in PATH"; return 127 }
    sidebar_bin=$(whence -p agentworld-sidebar 2>/dev/null)

    if [[ -n "$AGENTWORLD_DISABLE" || -z "$sidebar_bin" || ! -t 0 || ! -t 1 ]] \
        || ! command -v tmux >/dev/null 2>&1 \
        || (( ${_agentworld_passthrough_commands[(Ie)${1:-}]} )); then
        "$real_claude" "$@"
        return $?
    fi
    local arg
    for arg in "$@"; do
        if (( ${_agentworld_passthrough_flags[(Ie)$arg]} )); then
            "$real_claude" "$@"
            return $?
        fi
    done

    # Pin both sides to the same session id so the sidebar follows exactly
    # this conversation, even with other `claude` sessions open in the same
    # project. Resumed/forked sessions pick their own id; the sidebar then
    # follows the project's most recently active transcript instead.
    local session_id="" resuming=0
    for arg in "$@"; do
        (( ${_agentworld_resume_flags[(Ie)${arg%%=*}]} )) && resuming=1
    done
    local -a claude_args=("$@")
    local -a sidebar_args=(--cwd "$PWD")
    [[ -n "$AGENTWORLD_FPS" ]] && sidebar_args+=(--fps "$AGENTWORLD_FPS")
    if (( ! resuming )) && command -v uuidgen >/dev/null 2>&1; then
        session_id=${(L)$(uuidgen)}
        claude_args=(--session-id "$session_id" "${claude_args[@]}")
        sidebar_args+=(--session-id "$session_id")
    fi

    local width=${AGENTWORLD_WIDTH:-34%}
    local claude_cmd="${(q)real_claude} ${(j: :)${(q)claude_args[@]}}"
    local sidebar_cmd="${(q)sidebar_bin} ${(j: :)${(q)sidebar_args[@]}}"

    if [[ -n "$TMUX" ]]; then
        # Already inside tmux: add a pane next to this one (-d keeps focus
        # here), run claude in place, and remove the pane when it exits.
        local pane_id
        pane_id=$(tmux split-window -h -d -l "$width" -c "$PWD" -P -F '#{pane_id}' "$sidebar_cmd" 2>/dev/null)
        "$real_claude" "${claude_args[@]}"
        local exit_code=$?
        [[ -n "$pane_id" ]] && tmux kill-pane -t "$pane_id" 2>/dev/null
        return $exit_code
    fi

    # A dedicated, status-bar-less tmux session that disappears with claude.
    local session_name="agentworld-$$-$RANDOM"
    # A tmux server that's already running doesn't see this shell's
    # environment. Forward what claude needs through a private file that the
    # pane sources and deletes (not tmux -e: that would put API keys on a
    # command line, visible in `ps`).
    local env_file
    env_file=$(mktemp -t agentworld-env) || { "$real_claude" "$@"; return $? }
    chmod 600 "$env_file"
    local name
    for name in PATH COLORTERM TERM_PROGRAM LANG LC_ALL ${(k)parameters[(I)ANTHROPIC_*]} ${(k)parameters[(I)CLAUDE_*]} ${(k)parameters[(I)AWS_*]} ${(k)parameters[(I)GOOGLE_*]}; do
        [[ -n "${(P)name}" ]] && print -r -- "export $name=${(qq)${(P)name}}" >> "$env_file"
    done
    local -a sidebar_env=()
    for name in COLORTERM ${(k)parameters[(I)AGENTWORLD_*]}; do
        [[ -n "${(P)name}" ]] && sidebar_env+=(-e "$name=${(P)name}")
    done

    if ! tmux new-session -d -s "$session_name" -c "$PWD" \
        ". ${(q)env_file}; rm -f ${(q)env_file}; $claude_cmd; tmux kill-session -t ${(q)session_name}" 2>/dev/null; then
        rm -f "$env_file"
        "$real_claude" "$@"
        return $?
    fi
    tmux set-option -t "$session_name" status off >/dev/null 2>&1
    # Session-scoped: lets you click the sidebar to focus it and click or
    # scroll inside the explorer. Other tmux sessions keep their setting.
    [[ "${AGENTWORLD_MOUSE:-1}" != 0 ]] && tmux set-option -t "$session_name" mouse on >/dev/null 2>&1
    tmux split-window -t "$session_name" -h -d -l "$width" -c "$PWD" "${sidebar_env[@]}" "$sidebar_cmd" 2>/dev/null
    tmux attach-session -t "$session_name"
}

# `agentworld` opens the hub: one terminal per agent CLI (Claude Code, Codex,
# Gemini, Kimi, Grok…), each with its AgentWorld sidebar, plus a picker to
# start and switch between them. It runs on its own tmux server, so the
# terminals keep running when you close the window: `agentworld` again brings
# them back. `agentworld app` opens the macOS app on this folder instead.
# With other arguments it runs the sidebar directly (`agentworld --demo`,
# `agentworld --provider codex`, `agentworld --help`).
agentworld() {
    # `agentworld app`: the macOS app, opened on this folder.
    if [[ "$1" == app ]]; then
        local bundle=~/Applications/AgentWorld.app
        [[ -d "$bundle" ]] || { print -u2 "agentworld: the app isn't installed (Sidebar: make app)"; return 1 }
        open -a "$bundle" --args --cwd "$PWD"
        return
    fi
    local sidebar_bin
    sidebar_bin=$(whence -p agentworld-sidebar) || { print -u2 "agentworld: agentworld-sidebar not installed"; return 127 }
    if (( $# )); then
        "$sidebar_bin" "$@"
        return $?
    fi
    command -v tmux >/dev/null 2>&1 || { print -u2 "agentworld: the hub needs tmux (brew install tmux)"; return 1 }

    local conf=~/.config/agentworld/hub.tmux.conf
    local -a server=(tmux -L agentworld)
    [[ -f "$conf" ]] && server+=(-f "$conf")
    if ! "${server[@]}" has-session -t hub 2>/dev/null; then
        # The server starts from this shell, so every terminal it opens
        # inherits this environment (PATH, API keys…) without writing it anywhere.
        "${server[@]}" new-session -d -s hub -n home -c "$PWD" \
            "${(q)sidebar_bin} --launcher --cwd ${(q)PWD}" || return $?
    else
        # Already running: pick up config changes and restart the picker in
        # this folder with the installed binary (the terminals keep running).
        [[ -f "$conf" ]] && "${server[@]}" source-file "$conf" >/dev/null 2>&1
        "${server[@]}" respawn-pane -k -t hub:0.0 -c "$PWD" \
            "${(q)sidebar_bin} --launcher --cwd ${(q)PWD}" >/dev/null 2>&1
        "${server[@]}" select-window -t hub:0 >/dev/null 2>&1
    fi
    # TMUX= : attaching from inside another tmux would otherwise refuse.
    TMUX= "${server[@]}" attach-session -t hub
}
