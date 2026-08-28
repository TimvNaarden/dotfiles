#!/usr/bin/env bash
# Renders one browser-style tab for a tmux window.
#
# The label is the session name of the first Claude Code pane in the window
# (the agent publishes it as the pane title over OSC), falling back to the
# command running in the first pane. The accent colour reports the most urgent
# agent state across every pane in the window.
set -uo pipefail

win="${1:-}"
[ -n "$win" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

# Catppuccin Mocha.
CRUST="#11111b"; SURFACE0="#313244"; SURFACE1="#45475a"
TEXT="#cdd6f4"; SUBTEXT="#a6adc8"; OVERLAY="#6c7086"
GREEN="#a6e3a1"; YELLOW="#f9e2af"; BLUE="#89b4fa"

# One tmux call: window fields are resolvable in a pane format.
panes=$(tmux list-panes -t "$win" -F \
  '#{window_active}|#{window_index}|#{window_flags}|#{@claude_state}|#{pane_current_command}|#{pane_title}' \
  2>/dev/null) || exit 0
[ -n "$panes" ] || exit 0

active=""; index=""; flags=""
label=""; fallback=""
has_done=""; has_input=""; has_running=""

while IFS='|' read -r w_active w_index w_flags state command title; do
    [ -n "$w_index" ] || continue
    [ -n "$index" ] || { active="$w_active"; index="$w_index"; flags="$w_flags"; }

    case "$state" in
        needs-input) has_input=1 ;;
        done)        has_done=1 ;;
        running)     has_running=1 ;;
    esac

    # First agent pane wins the label; anything else only fills the fallback.
    if [ -z "$label" ] && { [ -n "$state" ] || [ "$command" = "claude" ]; }; then
        label="$title"
    fi
    [ -n "$fallback" ] || fallback="$command"
done <<< "$panes"

[ -n "$label" ] || label="$fallback"
[ -n "$label" ] || label="shell"

# Blocked on a human outranks finished, which outranks still working.
if   [ -n "$has_input" ];   then accent="$YELLOW"
elif [ -n "$has_done" ];    then accent="$GREEN"
elif [ -n "$has_running" ]; then accent="$BLUE"
else accent="$OVERLAY"
fi

if [ "$active" = "1" ]; then
    label_bg="$SURFACE1"; label_fg="$TEXT"
else
    label_bg="$SURFACE0"; label_fg="$SUBTEXT"
fi

# Zoom and bell markers are worth keeping; the window-activity ones are noise.
marker=""
case "$flags" in *Z*) marker=" ";; esac
case "$flags" in *!*) marker="$marker ";; esac

max=28
if [ "${#label}" -gt "$max" ]; then
    label="${label:0:$((max - 1))}…"
fi

printf '#[fg=%s,bg=default]#[fg=%s,bg=%s,bold] %s #[fg=%s,bg=%s,nobold] %s%s #[fg=%s,bg=default,none]' \
    "$accent" "$CRUST" "$accent" "$index" "$label_fg" "$label_bg" "$label" "$marker" "$label_bg"
