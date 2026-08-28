#!/usr/bin/env python3
"""Retitle the Claude Code session from each prompt you send.

Claude Code names a session once from an AI summary and then rarely revisits it,
so a long session keeps a title describing whatever it opened with. Claude Code
lets a UserPromptSubmit hook return a sessionTitle, so this derives one from the
prompt itself: the title tracks whatever you last asked for.

Only prompts you typed yourself count. Wake-ups from /loop, schedules and the
SDK carry a different source and are ignored, so background activity cannot
rewrite a title describing your actual work.
"""

import json
import re
import sys

MAX_LENGTH = 44


def title_from(prompt):
    # First non-empty line only; a pasted stack trace should not become a title.
    for line in prompt.splitlines():
        line = re.sub(r"\s+", " ", line).strip()
        if line:
            break
    else:
        return None

    if len(line) > MAX_LENGTH:
        # Prefer cutting at a word boundary when one is reasonably close.
        cut = line[:MAX_LENGTH]
        space = cut.rfind(" ")
        line = (cut[:space] if space > MAX_LENGTH * 0.6 else cut).rstrip() + "…"
    return line


def main():
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
    if not title:
        return 0

    json.dump({"hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "sessionTitle": title,
    }}, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
