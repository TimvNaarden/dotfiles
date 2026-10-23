#!/usr/bin/env bash
# Renders one browser-style tab for a tmux window.
#
# The name comes from @claude_label, which claude-pane-label.py resolves for the
# window's first Claude Code pane: the branch of the worktree the agent works
# in, or the pull request it is on, or a name Haiku took from the conversation.
# Everything that used to be decided here (whether the branch or the task name
# leads, whether a shared branch still identifies a window, whether the two
# repeat each other) is decided there now, and one pane carries one name.
#
# Panes with no label yet fall back to the Claude Code session title, and panes
# that are not agents at all to the command they are running.
#
# Width is divided between the windows on screen, so tabs shrink as windows are
# added rather than overflowing.
#
# Usage: claude-window-label.sh <window_id> [client_width] [window_count]
set -uo pipefail

win="${1:-}"
[ -n "$win" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

client_width="${2:-180}"
window_count="${3:-1}"
[[ "$client_width" =~ ^[0-9]+$ ]] || client_width=180
[[ "$window_count" =~ ^[0-9]+$ ]] && [ "$window_count" -gt 0 ] || window_count=1

# Catppuccin Mocha.
CRUST="#11111b"; SURFACE1="#45475a"; SURFACE2="#585b70"
TEXT="#cdd6f4"; OVERLAY="#6c7086"; OVERLAY2="#9399b2"
GREEN="#a6e3a1"; YELLOW="#f9e2af"; BLUE="#89b4fa"; LAVENDER="#b4befe"

panes=$(tmux list-panes -t "$win" -F \
  '#{window_active}|#{window_index}|#{window_flags}|#{@claude_state}|#{@claude_label}|#{pane_current_command}|#{pane_title}' \
  2>/dev/null) || exit 0
[ -n "$panes" ] || exit 0

active=""; index=""; flags=""; title=""; fallback=""
has_done=""; has_input=""; has_running=""

while IFS='|' read -r w_active w_index w_flags state pane_label command pane_title; do
    [ -n "$w_index" ] || continue
    [ -n "$index" ] || { active="$w_active"; index="$w_index"; flags="$w_flags"; }

    case "$state" in
        needs-input) has_input=1 ;;
        done)        has_done=1 ;;
        running)     has_running=1 ;;
    esac

    # First agent pane wins the label; anything else only fills the fallback.
    if [ -z "$title" ] && { [ -n "$state" ] || [ "$command" = "claude" ]; }; then
        title="${pane_label:-$pane_title}"
    fi
    [ -n "$fallback" ] || fallback="$command"
done <<< "$panes"

# Blocked on a human outranks finished, which outranks still working. State
# colours are identical on active and inactive tabs on purpose: an alert on a
# background window is exactly the one you must not miss. Only the neutral
# no-state badge dims, because there it is free to carry the active cue instead.
if   [ -n "$has_input" ];   then accent="$YELLOW"
elif [ -n "$has_done" ];    then accent="$GREEN"
elif [ -n "$has_running" ]; then accent="$BLUE"
elif [ "$active" = "1" ];   then accent="$OVERLAY2"
else accent="$SURFACE1"
fi

# Roughly what status-right occupies, plus the per-tab index badge and padding.
RESERVED=48
CHROME=8
budget=$(( (client_width - RESERVED) / window_count - CHROME ))
[ "$budget" -lt 16 ] && budget=16
[ "$budget" -gt 46 ] && budget=46

# The agent marker is noise once the tab's own chrome says which panes are agents.
title="${title#✳ }"
label="${title:-${fallback:-shell}}"
if [ "${#label}" -gt "$budget" ]; then
    label="${label:0:$((budget - 1))}…"
fi

if [ "$active" = "1" ]; then
    label_bg="$SURFACE2"; label_fg="$TEXT"; weight="bold"
    # us= sets the underline colour independently of the text colour.
    rule=",underscore,us=$LAVENDER"
else
    # No fill at all, so inactive tabs melt into the status bar and leave the
    # single filled tab obvious. Dropping their brightness matters as much as
    # raising the active one: five near-equal neighbours are what buried it.
    label_bg="default"; label_fg="$OVERLAY"; weight="nobold"
    rule=""
fi

marker=""
case "$flags" in *Z*) marker=" ";; esac
case "$flags" in *!*) marker="$marker ";; esac

printf '#[fg=%s,bg=%s,bold%s] %s #[fg=%s,bg=%s,%s%s] %s%s #[fg=default,bg=default,nobold,nounderscore]' \
    "$CRUST" "$accent" "$rule" "$index" "$label_fg" "$label_bg" "$weight" "$rule" "$label" "$marker"
