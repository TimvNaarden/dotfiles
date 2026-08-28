#!/usr/bin/env bash
# Records the Claude Code agent state on the tmux pane it runs in, so that
# pane-border-format can colour that pane's header. Invoked from Claude Code
# hooks, which inherit TMUX_PANE from the shell the agent was started in.
set -uo pipefail

[ -n "${TMUX:-}" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

state="${1:-}"
pane="${TMUX_PANE:-}"
[ -n "$pane" ] || exit 0

case "$state" in
  running|done|needs-input|idle) ;;
  *) exit 0 ;;
esac

# Hooks fire outside any client context, so address the pane explicitly.
tmux set-option -p -t "$pane" @claude_state "$state" 2>/dev/null || exit 0
tmux refresh-client -S 2>/dev/null || true
