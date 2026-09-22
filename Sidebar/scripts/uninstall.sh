#!/usr/bin/env bash
# Removes the binary and the shell integration. Leaves the ~/.zshrc hook in
# place; it's guarded by a file-exists check and does nothing on its own.
set -euo pipefail
prefix="${PREFIX:-$HOME/.local}"
rm -f "$prefix/bin/agentworld-sidebar"
rm -f "$HOME/.config/agentworld/sidebar.zsh"
echo "Removed. You can also delete the '# >>> agentworld sidebar >>>' block from ~/.zshrc."
