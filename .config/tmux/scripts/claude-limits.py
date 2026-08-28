#!/usr/bin/env python3
"""Render Claude Code rate-limit usage for the tmux status line.

Reads the utilisation block Claude Code caches in ~/.claude.json and prints
both windows with the wall-clock time each one resets at, e.g.

    5h 31% ↻17:19  ·  7d 14% ↻Thu 09:59

The numbers are only as fresh as Claude Code's own cache; this script adds no
caching of its own so it never lags further behind than the source data.
"""

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

# Catppuccin Mocha, matching the rest of the status line.
GREEN, YELLOW, RED, MUTED = "#a6e3a1", "#f9e2af", "#f38ba8", "#bac2de"

# Show a staleness marker once the cached figures are older than this.
STALE_AFTER_SECONDS = 15 * 60


def colour_for(percent):
    if percent >= 80:
        return RED
    if percent >= 50:
        return YELLOW
    return GREEN


def reset_label(raw, now):
    """HH:MM for a reset within a day, otherwise a weekday prefix."""
    if not raw:
        return ""
    try:
        moment = datetime.fromisoformat(raw.replace("Z", "+00:00")).astimezone()
    except (ValueError, TypeError):
        return ""
    delta = (moment - now).total_seconds()
    if delta < 0:
        return ""
    if delta < 24 * 3600 and moment.date() == now.date():
        return moment.strftime("%H:%M")
    return moment.strftime("%a %H:%M")


def segment(label, block, now):
    if not isinstance(block, dict):
        return None
    percent = block.get("utilization")
    if not isinstance(percent, (int, float)):
        return None
    percent = int(round(percent))
    text = f"#[fg={MUTED}]{label} #[fg={colour_for(percent)}]{percent}%"
    resets = reset_label(block.get("resets_at"), now)
    if resets:
        text += f"#[fg={MUTED}] ↻{resets}"
    return text


def main():
    path = Path(os.environ.get("CLAUDE_CONFIG_JSON", Path.home() / ".claude.json"))
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return 0

    cached = payload.get("cachedUsageUtilization")
    if not isinstance(cached, dict):
        return 0
    utilisation = cached.get("utilization")
    if not isinstance(utilisation, dict):
        return 0

    now = datetime.now(timezone.utc).astimezone()
    parts = [
        segment("5h", utilisation.get("five_hour"), now),
        segment("7d", utilisation.get("seven_day"), now),
    ]
    parts = [part for part in parts if part]
    if not parts:
        return 0

    line = f"#[fg={MUTED}]  ·  ".join(parts)

    fetched = cached.get("fetchedAtMs")
    if isinstance(fetched, (int, float)):
        age = now.timestamp() - fetched / 1000
        if age > STALE_AFTER_SECONDS:
            line += f"#[fg={MUTED}] ~{int(age // 60)}m"

    print(line + "#[default]")
    return 0


if __name__ == "__main__":
    sys.exit(main())
