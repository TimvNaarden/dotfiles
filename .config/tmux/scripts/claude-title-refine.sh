#!/usr/bin/env bash
# Second pass over a tmux pane title, run detached from the UserPromptSubmit
# hook so it never delays a turn.
#
# claude-session-title.py sets an immediate title by stripping filler off the
# prompt, which is fast and free but reads like a truncated sentence. This asks
# Haiku for a real name and replaces it roughly seven seconds later.
#
# Usage: claude-title-refine.sh <pane_id> <prompt_file> <seq>
set -uo pipefail

pane="${1:-}"; prompt_file="${2:-}"; seq="${3:-}"
[ -n "$pane" ] && [ -f "$prompt_file" ] || exit 0

prompt=$(cat "$prompt_file" 2>/dev/null)
rm -f "$prompt_file"
[ -n "$prompt" ] || exit 0

command -v tmux >/dev/null 2>&1 || exit 0
command -v claude >/dev/null 2>&1 || exit 0

# Opt-out switch, so the Haiku spend can be turned off without unwiring the hook.
[ "$(tmux show-option -gqv @claude_ai_titles 2>/dev/null)" = "off" ] && exit 0

# CLAUDE_TITLE_REFINER stops the nested claude from running these hooks again,
# which would recurse and would also mark this pane running and fire a
# notification. --bare would skip hooks too, but it drops the OAuth credentials.
title=$(CLAUDE_TITLE_REFINER=1 timeout 60 claude -p \
    --model claude-haiku-4-5 \
    --no-session-persistence \
    "Title this task in 2-4 words, Title Case, no punctuation, no quotes. Reply with the title only.

$prompt" 2>/dev/null | head -1)

# A refusal or an error message is not a title.
title=$(printf '%s' "$title" | tr -d '\r\n"' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[.]*$//')
[ -n "$title" ] || exit 0
[ "${#title}" -le 40 ] || exit 0
case "$title" in *"Please run"*|*"Not logged in"*|*"Error"*|*"error:"*) exit 0 ;; esac

# The turn may have moved on during those seconds. Only apply the title if no
# newer prompt has claimed the pane since this run was spawned.
[ "$(tmux show-option -p -t "$pane" -qv @claude_title_seq 2>/dev/null)" = "$seq" ] || exit 0

tmux select-pane -t "$pane" -T "✳ $title" 2>/dev/null || true
