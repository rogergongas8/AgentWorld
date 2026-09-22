#!/usr/bin/env bash
# Builds agentworld-sidebar in release mode and installs it plus the `claude`
# shell integration. Safe to re-run: it's how you update too.
#
#   PREFIX=~/.local ./scripts/install.sh
set -euo pipefail

cd "$(dirname "$0")/.."
prefix="${PREFIX:-$HOME/.local}"
bin_dir="$prefix/bin"
config_dir="$HOME/.config/agentworld"
integration="$config_dir/sidebar.zsh"
zshrc="${ZDOTDIR:-$HOME}/.zshrc"

echo "==> Building (release)"
swift build -c release --product agentworld-sidebar

echo "==> Installing binary to $bin_dir"
mkdir -p "$bin_dir"
install -m 755 "$(swift build -c release --show-bin-path)/agentworld-sidebar" "$bin_dir/agentworld-sidebar"

echo "==> Installing shell integration to $integration"
mkdir -p "$config_dir"
if [[ -f "$integration" ]] && ! cmp -s shell/agentworld.zsh "$integration"; then
    cp "$integration" "$integration.bak"
    echo "    (previous version saved as $integration.bak)"
fi
cp shell/agentworld.zsh "$integration"
cp shell/hub.tmux.conf "$config_dir/hub.tmux.conf"

if ! grep -q "agentworld sidebar" "$zshrc" 2>/dev/null; then
    echo "==> Hooking into $zshrc"
    cat >> "$zshrc" <<'ZSH'

# >>> agentworld sidebar >>>
[[ -f ~/.config/agentworld/sidebar.zsh ]] && source ~/.config/agentworld/sidebar.zsh
# <<< agentworld sidebar <<<
ZSH
fi

case ":$PATH:" in
    *":$bin_dir:"*) ;;
    *) echo "!!  $bin_dir is not in your PATH — add it so the wrapper can find agentworld-sidebar" ;;
esac
command -v tmux >/dev/null || echo "!!  tmux not found: install it (brew install tmux) — without it, claude runs without the sidebar"

echo
echo "Done. Open a new terminal (or: source $integration) and run:"
echo "  agentworld   the hub: open Claude, Codex, Gemini, Kimi, Grok… terminals side by side"
echo "  claude       Claude Code with its sidebar, as before"
echo "Preview the animations any time with: agentworld --demo"
