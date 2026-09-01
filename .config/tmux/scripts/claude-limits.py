#!/usr/bin/env python3
"""Render Claude Code rate-limit usage for the tmux status line.

Prints both windows with the wall-clock time each one resets at, e.g.

    5h 31% ↻17:19  ·  7d 14% ↻Thu 09:59

Freshness
---------
Claude Code keeps a `cachedUsageUtilization` block in ~/.claude.json, but it
only rewrites it when something actually calls GET /api/oauth/usage, which in
practice means you opened /usage. Ordinary turns leave it untouched, so relying
on that block alone pins the status line to your last /usage run. The live
percentages Claude Code shows in-app come from response headers that never
reach disk.

So this script fetches /api/oauth/usage itself, using the OAuth token Claude
Code stores in ~/.claude/.credentials.json, and keeps its own short-lived cache
in $XDG_CACHE_HOME. The status line renders from whichever cache is fresher and
never blocks: when our copy is older than FRESH_FOR_SECONDS it hands off to a
detached `--refresh` child and prints the value it already has.

The fetch is read-only and never refreshes the token. When the access token has
expired we skip the request entirely and fall back to Claude Code's block;
Claude Code rotates the token on its next request and we pick it up after that.

Modes
-----
    claude-limits.py              render for the status line (never blocks)
    claude-limits.py --refresh    fetch and update the cache, then exit
    claude-limits.py --debug      render plus a freshness report on stderr
"""

import fcntl
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

# Catppuccin Mocha, matching the rest of the status line.
GREEN, YELLOW, RED, MUTED = "#a6e3a1", "#f9e2af", "#f38ba8", "#bac2de"

USAGE_URL = "https://api.anthropic.com/api/oauth/usage"

# Kick a background refresh once our own copy is older than this.
FRESH_FOR_SECONDS = 60
# Show a staleness marker once the figures we render are older than this.
STALE_AFTER_SECONDS = 15 * 60
# Discard figures older than this outright, mirroring Claude Code's own TTL.
MAX_AGE_SECONDS = 60 * 60
# Treat a token as unusable this long before it actually expires.
TOKEN_SKEW_SECONDS = 60
# After a failed fetch, wait this long before trying again.
FAILURE_BACKOFF_SECONDS = 120
FETCH_TIMEOUT_SECONDS = 5


def cache_dir():
    base = os.environ.get("XDG_CACHE_HOME") or (Path.home() / ".cache")
    return Path(base) / "claude-limits"


def config_path():
    return Path(os.environ.get("CLAUDE_CONFIG_JSON", Path.home() / ".claude.json"))


def credentials_path():
    return Path(
        os.environ.get(
            "CLAUDE_CREDENTIALS_JSON", Path.home() / ".claude" / ".credentials.json"
        )
    )


def read_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def now_ms():
    return int(datetime.now(timezone.utc).timestamp() * 1000)


def snapshot_from_own_cache():
    """Our own fetch: {"fetchedAtMs": int, "utilization": {...}}."""
    payload = read_json(cache_dir() / "usage.json")
    if not isinstance(payload, dict):
        return None
    fetched, utilisation = payload.get("fetchedAtMs"), payload.get("utilization")
    if not isinstance(fetched, (int, float)) or not isinstance(utilisation, dict):
        return None
    return {"fetchedAtMs": fetched, "utilization": utilisation, "source": "direct"}


def snapshot_from_claude_code():
    """Claude Code's cache, only refreshed when /usage runs."""
    payload = read_json(config_path())
    if not isinstance(payload, dict):
        return None
    cached = payload.get("cachedUsageUtilization")
    if not isinstance(cached, dict):
        return None
    fetched, utilisation = cached.get("fetchedAtMs"), cached.get("utilization")
    if not isinstance(fetched, (int, float)) or not isinstance(utilisation, dict):
        return None
    return {"fetchedAtMs": fetched, "utilization": utilisation, "source": "claude-code"}


def freshest_snapshot():
    candidates = [s for s in (snapshot_from_own_cache(), snapshot_from_claude_code()) if s]
    if not candidates:
        return None
    best = max(candidates, key=lambda s: s["fetchedAtMs"])
    age = (now_ms() - best["fetchedAtMs"]) / 1000
    if age < 0 or age > MAX_AGE_SECONDS:
        return None
    return best


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


# --- refreshing -------------------------------------------------------------


def access_token():
    """The current OAuth access token, or None when it is missing or expired."""
    payload = read_json(credentials_path())
    if not isinstance(payload, dict):
        return None
    oauth = payload.get("claudeAiOauth")
    if not isinstance(oauth, dict):
        return None
    token, expires = oauth.get("accessToken"), oauth.get("expiresAt")
    if not isinstance(token, str) or not token:
        return None
    if isinstance(expires, (int, float)) and expires - TOKEN_SKEW_SECONDS * 1000 <= now_ms():
        return None
    return token


def write_atomically(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    handle = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(handle, "w", encoding="utf-8") as stream:
        json.dump(payload, stream)
    os.replace(tmp, path)


def in_failure_backoff():
    marker = read_json(cache_dir() / "failure.json")
    if not isinstance(marker, dict):
        return False
    failed = marker.get("failedAtMs")
    if not isinstance(failed, (int, float)):
        return False
    return (now_ms() - failed) / 1000 < FAILURE_BACKOFF_SECONDS


def record_failure(reason):
    try:
        write_atomically(cache_dir() / "failure.json", {"failedAtMs": now_ms(), "reason": reason})
    except OSError:
        pass


def fetch_utilization(token):
    request = urllib.request.Request(
        USAGE_URL,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="GET",
    )
    with urllib.request.urlopen(request, timeout=FETCH_TIMEOUT_SECONDS) as response:
        return json.loads(response.read().decode("utf-8"))


def refresh(verbose=False):
    """Fetch and cache. Returns an exit code. Safe to run concurrently."""
    directory = cache_dir()
    try:
        directory.mkdir(parents=True, exist_ok=True)
        lock = os.open(directory / "refresh.lock", os.O_WRONLY | os.O_CREAT, 0o600)
    except OSError as error:
        if verbose:
            print(f"cannot open lock: {error}", file=sys.stderr)
        return 0
    try:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            if verbose:
                print("another refresh holds the lock, skipping", file=sys.stderr)
            return 0

        # Another process may have refreshed while we waited for the lock.
        existing = snapshot_from_own_cache()
        if existing and (now_ms() - existing["fetchedAtMs"]) / 1000 < FRESH_FOR_SECONDS:
            if verbose:
                print("cache already fresh, skipping", file=sys.stderr)
            return 0

        if in_failure_backoff():
            if verbose:
                print("in failure backoff, skipping", file=sys.stderr)
            return 0

        token = access_token()
        if token is None:
            record_failure("no usable access token")
            if verbose:
                print("no usable access token, falling back to Claude Code's cache", file=sys.stderr)
            return 0

        try:
            payload = fetch_utilization(token)
        except (urllib.error.URLError, urllib.error.HTTPError, OSError, ValueError) as error:
            record_failure(str(error))
            if verbose:
                print(f"fetch failed: {error}", file=sys.stderr)
            return 1

        if not isinstance(payload, dict):
            record_failure("unexpected payload shape")
            if verbose:
                print(f"unexpected payload: {payload!r}", file=sys.stderr)
            return 1

        write_atomically(directory / "usage.json", {"fetchedAtMs": now_ms(), "utilization": payload})
        try:
            (directory / "failure.json").unlink()
        except OSError:
            pass
        if verbose:
            print(f"cached keys: {sorted(payload)}", file=sys.stderr)
        return 0
    finally:
        os.close(lock)


def kick_background_refresh():
    """Hand off to a detached child so the status line never waits on I/O."""
    try:
        subprocess.Popen(
            [sys.executable, os.path.realpath(__file__), "--refresh"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        pass


# --- rendering --------------------------------------------------------------


def render(debug=False):
    snapshot = freshest_snapshot()
    age = None if snapshot is None else (now_ms() - snapshot["fetchedAtMs"]) / 1000

    if snapshot is None or age >= FRESH_FOR_SECONDS:
        if not in_failure_backoff():
            kick_background_refresh()

    if debug:
        own, theirs = snapshot_from_own_cache(), snapshot_from_claude_code()
        for name, candidate in (("direct", own), ("claude-code", theirs)):
            if candidate is None:
                print(f"{name}: absent or unreadable", file=sys.stderr)
            else:
                seconds = (now_ms() - candidate["fetchedAtMs"]) / 1000
                print(f"{name}: {seconds / 60:.1f}m old", file=sys.stderr)
        print(f"token usable: {access_token() is not None}", file=sys.stderr)
        print(f"failure backoff: {in_failure_backoff()}", file=sys.stderr)
        print(f"rendering from: {'nothing' if snapshot is None else snapshot['source']}", file=sys.stderr)

    if snapshot is None:
        return 0

    utilisation = snapshot["utilization"]
    now = datetime.now(timezone.utc).astimezone()
    parts = [
        segment("5h", utilisation.get("five_hour"), now),
        segment("7d", utilisation.get("seven_day"), now),
    ]
    parts = [part for part in parts if part]
    if not parts:
        return 0

    line = f"#[fg={MUTED}]  ·  ".join(parts)
    if age is not None and age > STALE_AFTER_SECONDS:
        line += f"#[fg={MUTED}] ~{int(age // 60)}m"

    print(line + "#[default]")
    return 0


def main(argv):
    if "--refresh" in argv:
        return refresh(verbose="--debug" in argv)
    return render(debug="--debug" in argv)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
