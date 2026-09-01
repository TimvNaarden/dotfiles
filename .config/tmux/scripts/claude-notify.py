#!/usr/bin/env python3
"""Raise a desktop notification when a Claude Code agent needs you.

Noctalia owns org.freedesktop.Notifications on the session bus, so notify-send
delivers straight to it. `noctalia msg notification-show` is the native path but
takes only a summary and body, with no urgency, app name or icon.

Invoked from Claude Code hooks as: claude-notify.py <done|needs-input>
"""

import json
import os
import re
import subprocess
import sys

BODY_LIMIT = 140


def tmux(fmt):
    """Ask tmux about the pane this agent is running in."""
    pane = os.environ.get("TMUX_PANE")
    if not pane or not os.environ.get("TMUX"):
        return ""
    try:
        result = subprocess.run(
            ["tmux", "display-message", "-p", "-t", pane, fmt],
            capture_output=True, text=True, timeout=2,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return result.stdout.strip() if result.returncode == 0 else ""


def shorten(text):
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) > BODY_LIMIT:
        cut = text[:BODY_LIMIT]
        space = cut.rfind(" ")
        text = (cut[:space] if space > BODY_LIMIT * 0.6 else cut).rstrip() + "…"
    return text


def main():
    # The refiner spawns a nested `claude -p`, which inherits TMUX_PANE and would
    # otherwise run these hooks again. Recursion, plus a pane wrongly marked
    # running and a spurious notification.
    if os.environ.get("CLAUDE_TITLE_REFINER"):
        return 0

    state = sys.argv[1] if len(sys.argv) > 1 else ""
    if state not in ("done", "needs-input"):
        return 0

    # Global tmux option is the mute switch; unset counts as enabled.
    if tmux("#{@claude_notify}") == "off":
        return 0

    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        payload = {}
    if not isinstance(payload, dict):
        payload = {}

    # The pane title is the session name the agent publishes over OSC.
    title = tmux("#{pane_title}").lstrip("✳ ").strip() or "Claude Code"
    window = tmux("#{session_name}:#{window_index}")
    where = f"[{window}] " if window else ""

    if state == "done":
        summary = f"✳ {title}"
        body = shorten(payload.get("last_assistant_message") or "Finished.")
        urgency, icon = "normal", "utilities-terminal"
    else:
        summary = f"✳ {title}"
        body = "Waiting for your input."
        urgency, icon = "critical", "dialog-warning"

    try:
        subprocess.run(
            ["notify-send", "-a", "Claude Code", "-u", urgency, "-i", icon,
             summary, where + body],
            timeout=5, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        # Noctalia's own command, in case notify-send is not installed.
        subprocess.run(["noctalia", "msg", "notification-show", summary,
                        where + body], timeout=5, check=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
