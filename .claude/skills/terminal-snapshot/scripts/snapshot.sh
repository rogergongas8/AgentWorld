#!/bin/zsh
# Runs agentworld-sidebar in a detached tmux of a fixed size, sends keys,
# captures the pane with colors and converts it to a PNG you can look at.
#
#   snapshot.sh OUT.png [--keys "Down Enter"] [--size 56x46] [--wait 1.5] [-- sidebar args…]
#
# Examples:
#   snapshot.sh /tmp/home.png
#   snapshot.sh /tmp/agent.png --keys "Right Enter"
#   snapshot.sh /tmp/codex.png -- --provider codex
#   snapshot.sh /tmp/hub.png --size 130x50 -- --launcher
set -e
out=$1; shift
keys=""; size="56x46"; wait=1.5
while (( $# )); do
    case $1 in
        --keys) keys=$2; shift 2 ;;
        --size) size=$2; shift 2 ;;
        --wait) wait=$2; shift 2 ;;
        --) shift; break ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
done
repo=$(git -C "${0:A:h}" rev-parse --show-toplevel)
bin="$repo/Sidebar/.build/debug/agentworld-sidebar"
[[ -x $bin ]] || (cd "$repo/Sidebar" && swift build >/dev/null)
cols=${size%x*}; rows=${size#*x}
session="aw-snapshot-$$"
tmux -L aw-snapshot new-session -d -s $session -x $cols -y $rows -c "$repo" \
    "COLORTERM=truecolor ${(q)bin} --cwd ${(q)repo} ${(j: :)${(q)@}}"
sleep $wait
for key in ${(s: :)keys}; do tmux -L aw-snapshot send-keys -t $session "$key"; sleep 0.35; done
sleep 0.6
tmux -L aw-snapshot capture-pane -t $session -e -p > "${out:r}.ans"
tmux -L aw-snapshot kill-session -t $session
python3 "${0:A:h}/ansi2png.py" "${out:r}.ans" "$out" $cols
echo "$out"
