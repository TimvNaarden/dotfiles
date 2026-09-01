#!/usr/bin/env python3
"""Retitle the Claude Code session from each prompt you send.

Claude Code generates its own title once per conversation: haikuTitleAttempted
is set on the first turn and only cleared by /clear, /compact or a fork. It is a
good short title, and then it goes stale for the rest of the session.

This hook keeps the title current instead, deriving it from the prompt. A raw
prompt is a sentence rather than a name, so the leading conversational filler is
stripped ("I want you to ...", "Can you ...", "For my ..."), the first clause is
kept, and the result is capped so it fits a tmux tab.

Only prompts you typed yourself count. Wake-ups from /loop, schedules and the
SDK carry a different source and are ignored, so background activity cannot
rewrite a title describing your actual work.
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import time

MAX_LENGTH = 30

# Openers that carry no information about the task itself.
LEADERS = [
    r"^(?:i\s+want\s+you\s+to|i\s+need\s+you\s+to|i\s+would\s+like\s+you\s+to)\b[,:\s]*",
    r"^(?:can|could|would)\s+you\b[,:\s]*",
    r"^(?:please|let'?s|lets|we\s+need\s+to|now|so|also|als|okay|ok|hey|and)\b[,:\s]*",
    r"^(?:for|in|on|with|about)\s+(?:my|the|this)\b\s*",
    r"^(?:my|the|a|an)\b\s*",
    r"^(?:i\s+am|i'm)\s+(?:still\s+)?(?:getting|seeing|having)\b\s*",
    r"^there\s+(?:are|is)\b\s*",
]


def title_from(prompt):
    # First non-empty line only; a pasted stack trace should not become a title.
    line = next((re.sub(r"\s+", " ", l).strip() for l in prompt.splitlines() if l.strip()), "")
    if not line:
        return None

    # Openers stack ("So can you ..."), so strip until nothing more comes off.
    for _ in range(3):
        before = line
        for pattern in LEADERS:
            line = re.sub(pattern, "", line, flags=re.I)
        if line == before:
            break

    # Keep the first clause, but only when enough of it survives to mean
    # something. The lookahead keeps ":3001" and "12.5" from being split.
    boundary = re.search(r"[.?!;,](?=\s|$)", line)
    if boundary and boundary.start() >= 12:
        line = line[: boundary.start()]

    line = line.strip(" -–—:;,.")
    if not line:
        return None

    if len(line) > MAX_LENGTH:
        cut = line[:MAX_LENGTH]
        space = cut.rfind(" ")
        line = (cut[:space] if space > MAX_LENGTH * 0.55 else cut).rstrip() + "…"

    return line[:1].upper() + line[1:]


def spawn_refiner(prompt):
    """Kick off the Haiku pass without waiting for it."""
    pane = os.environ.get("TMUX_PANE")
    if not pane or not os.environ.get("TMUX"):
        return
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "claude-title-refine.sh")
    if not os.path.exists(script):
        return

    # A newer prompt bumps this, so a slow refiner knows its title is stale.
    seq = str(time.time_ns())
    try:
        subprocess.run(["tmux", "set-option", "-p", "-t", pane,
                        "@claude_title_seq", seq], timeout=2, check=False)
        handle = tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False,
                                             prefix="claude-title-", suffix=".txt")
        with handle:
            handle.write(prompt[:4000])
        subprocess.Popen([script, pane, handle.name, seq],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    except (OSError, subprocess.SubprocessError):
        pass


def main():
    if os.environ.get("CLAUDE_TITLE_REFINER"):
        return 0

    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        return 0
    if not isinstance(payload, dict):
        return 0

    # "user" is the default when the field is absent.
    if payload.get("source", "user") != "user":
        return 0

    prompt = payload.get("prompt")
    if not isinstance(prompt, str):
        return 0

    title = title_from(prompt)

    # Hand the prompt to the detached refiner for a proper Haiku-written name.
    # The heuristic title above is the placeholder shown until it returns.
    spawn_refiner(prompt)

    if not title:
        return 0

    json.dump({"hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "sessionTitle": title,
    }}, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
