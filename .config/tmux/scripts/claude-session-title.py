#!/usr/bin/env python3
"""Keep the Claude Code session title in step with the tmux tab.

Claude Code titles a conversation once: haikuTitleAttempted is set on the first
turn and only cleared by /clear, /compact or a fork. It is a good short title,
and then it goes stale for the rest of the session. That title is also what
Claude Code writes into the pane title, so a stale one sits in the pane border
disagreeing with the tab beside it.

claude-pane-label.py already resolves what this pane is: the branch of the
worktree the agent works in, the pull request it is on, or a name Haiku took
from the conversation. Handing that same name back as the session title is what
keeps the two in agreement, and it means the answer is written once rather than
raced for by two scripts.

Only the first turns of a session have no label yet, because resolving one takes
a lookup. Those get a title off the prompt instead: the leading conversational
filler is stripped ("I want you to ...", "Can you ..."), the first clause is
kept, and the result is capped so it fits a tab.

Only prompts you typed yourself count. Wake-ups from /loop, schedules and the
SDK carry a different source and are ignored, so background activity cannot
rewrite a title describing your actual work.
"""

import json
import os
import re
import subprocess
import sys

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


def pane_label():
    """The name of the work this pane is for, once it has been resolved."""
    pane = os.environ.get("TMUX_PANE")
    if not pane or not os.environ.get("TMUX"):
        return ""
    try:
        out = subprocess.run(["tmux", "show-option", "-p", "-t", pane, "-qv",
                              "@claude_label"],
                             capture_output=True, text=True, timeout=2, check=False)
    except (OSError, subprocess.SubprocessError):
        return ""
    return out.stdout.strip()


def emit(title):
    json.dump({"hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "sessionTitle": title,
    }}, sys.stdout)
    return 0


def main():
    # The nested `claude -p` that writes the name inherits TMUX_PANE and would
    # otherwise retitle the session it is describing.
    if os.environ.get("CLAUDE_TITLE_REFINER"):
        return 0

    # The label outranks the prompt, and it is already on the pane.
    label = pane_label()
    if label:
        return emit(label)

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
    return emit(title) if title else 0


if __name__ == "__main__":
    sys.exit(main())
