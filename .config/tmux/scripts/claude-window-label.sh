#!/usr/bin/env bash
# Renders one browser-style tab for a tmux window.
#
# The label leads with the git branch of the window's first Claude Code pane,
# because a branch is stable while the session title is rewritten on every
# prompt by claude-session-title.py. Several agents often share one branch
# though, so the session title is appended as a disambiguator whenever the tab
# bar has room for it. Width is divided between the windows on screen, so tabs
# shrink as windows are added rather than overflowing.
#
# Falls back to the session title outside a repo, and to the running command
# for panes that are not agents at all.
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
TEXT="#cdd6f4"; SUBTEXT="#a6adc8"; OVERLAY="#6c7086"; OVERLAY2="#9399b2"
GREEN="#a6e3a1"; YELLOW="#f9e2af"; BLUE="#89b4fa"; LAVENDER="#b4befe"

panes=$(tmux list-panes -t "$win" -F \
  '#{window_active}|#{window_index}|#{window_flags}|#{@claude_state}|#{pane_current_command}|#{pane_current_path}|#{pane_title}' \
  2>/dev/null) || exit 0
[ -n "$panes" ] || exit 0

active=""; index=""; flags=""
title=""; agent_path=""; fallback=""
has_done=""; has_input=""; has_running=""

while IFS='|' read -r w_active w_index w_flags state command path pane_title; do
    [ -n "$w_index" ] || continue
    [ -n "$index" ] || { active="$w_active"; index="$w_index"; flags="$w_flags"; }

    case "$state" in
        needs-input) has_input=1 ;;
        done)        has_done=1 ;;
        running)     has_running=1 ;;
    esac

    # First agent pane wins the label; anything else only fills the fallback.
    if [ -z "$title" ] && { [ -n "$state" ] || [ "$command" = "claude" ]; }; then
        title="$pane_title"
        agent_path="$path"
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

# The "· branch" suffix is secondary to the title, so it sits one step below
# whatever the tab's own text tone is rather than at a fixed grey.
if [ "$active" = "1" ]; then suffix_fg="$SUBTEXT"; else suffix_fg="$SURFACE2"; fi

# Roughly what status-right occupies, plus the per-tab index badge and padding.
RESERVED=48
CHROME=8
budget=$(( (client_width - RESERVED) / window_count - CHROME ))
[ "$budget" -lt 16 ] && budget=16
[ "$budget" -gt 46 ] && budget=46

trim() { # trim <text> <max>
    local text="$1" max="$2"
    if [ "${#text}" -gt "$max" ]; then
        printf '%s…' "${text:0:$((max - 1))}"
    else
        printf '%s' "$text"
    fi
}

branch_of() { # branch_of <path> -> branch name, short sha when detached, empty otherwise
    local path="$1" name
    [ -n "$path" ] || return 0
    name=$(git -C "$path" branch --show-current 2>/dev/null)
    if [ -z "$name" ] && git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
        # Detached HEAD, which is what a PR-review worktree looks like.
        name="@$(git -C "$path" rev-parse --short HEAD 2>/dev/null)"
    fi
    printf '%s' "$name"
}

branch=$(branch_of "$agent_path")

# A branch only identifies a window while it is the only window on it. Agents
# frequently share one, and three identical tabs are worse than three churning
# titles, so count how many windows resolve to this branch before committing to
# it. One tmux call for every window, then at most one git call per distinct
# directory.
shared=0
if [ -n "$branch" ]; then
    seen_paths=""
    while IFS='|' read -r other_win other_state other_cmd other_path; do
        case "$other_state$other_cmd" in
            *claude*) ;;
            *) continue ;;
        esac
        [ -n "$other_path" ] || continue
        # First agent pane per window only, matching the labelling rule above.
        case "|$seen_paths|" in *"|$other_win|"*) continue ;; esac
        seen_paths="$seen_paths|$other_win"
        [ "$(branch_of "$other_path")" = "$branch" ] && shared=$((shared + 1))
    done <<< "$(tmux list-panes -a -F '#{window_id}|#{@claude_state}|#{pane_current_command}|#{pane_current_path}' 2>/dev/null)"
fi

# The agent marker is noise once something else carries the identity.
title="${title#✳ }"

if [ -n "$branch" ] && [ "$shared" -le 1 ]; then
    # Unique branch: it is the most stable name this window has.
    label=$(trim "$branch" "$budget")
    spare=$(( budget - ${#label} - 3 ))
    if [ -n "$title" ] && [ "$spare" -ge 8 ]; then
        label="$label #[fg=$suffix_fg]· $(trim "$title" "$spare")"
    fi
elif [ -n "$title" ]; then
    # Shared or absent branch: the task title is the only thing that separates
    # these windows, so it leads. The branch follows only if it still fits.
    label=$(trim "$title" "$budget")
    spare=$(( budget - ${#label} - 3 ))
    if [ -n "$branch" ] && [ "$spare" -ge 8 ]; then
        label="$label #[fg=$suffix_fg]· $(trim "$branch" "$spare")"
    fi
elif [ -n "$branch" ]; then
    label=$(trim "$branch" "$budget")
else
    label=$(trim "${fallback:-shell}" "$budget")
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
