#!/usr/bin/env python3
"""Record on the tmux pane which worktree its Claude Code agent works in.

Every agent here is launched from the same directory, so the branch of that
directory is the user's branch, identical on every pane and useless as a label.
The branch that identifies a pane is the one of the worktree its agent actually
works in, and tmux cannot see that: the pane's shell never leaves the launch
directory, because the Bash tool resets its cwd after every command.

Two things reveal the real worktree, and they are tried in that order:

  1. The session cwd from the hook payload. EnterWorktree switches it, so this
     is exact whenever the agent took the sanctioned route.
  2. The transcript. An agent that stays in the launch directory reaches its
     worktree by path, so the worktree it keeps naming is the one it works in.

Naming is counted rather than looked for once, because a single mention is not a
claim on a branch: sessions read each other's worktrees all the time, in a diff
against a neighbour or a `git worktree list`. Only what the agent itself wrote
counts, so tool inputs are read and tool results are not, and the winner has to
out-name the main worktree, so a session comparing its own work against a
neighbouring branch keeps its own. Earlier versions looked for `git worktree
add` instead, which missed every agent that entered a worktree it had not
created and every session whose creation had scrolled out of the tail.

The results land on the pane as @claude_branch and @claude_worktree, which
claude-window-label.sh and claude-pane-goal.py read.

Usage: hook on SessionStart, UserPromptSubmit and Stop, payload on stdin.
"""

import json
import os
import re
import subprocess
import sys

# Enough transcript to cover the recent turns without reading a session that
# has been running all day. A turn spanning a long tool result can be tens of
# thousands of characters, so a few hundred lines is a handful of tool calls.
TAIL_BYTES = 2_000_000
TAIL_LINES = 2000

# Reading or writing a file in a worktree is working in it. A shell command
# naming one is weaker evidence: it covers `git -C <path> diff` against a
# neighbouring branch as much as a build run in your own tree.
FILE_WEIGHT = 3
COMMAND_WEIGHT = 1

# Tool inputs from the newest turns weigh more, so a worktree the agent has
# moved on from cannot outvote the one it is in now on sheer history.
RECENT_INPUTS = 100
RECENT_WEIGHT = 2

# One passing mention is a glance at a neighbour, not a claim, and a single
# recent file read scores 6 on its own. A claim therefore costs two file touches
# or a file touch and a command, which the sessions here clear by a wide margin:
# the narrowest genuine winner measured scored 10 and most score in the hundreds.
MIN_SCORE = 8

# Tool parameters that carry a path. `command` is handled separately because a
# single command can name several.
PATH_KEYS = ("file_path", "path", "notebook_path")

# What `git branch --points-at` calls a detached HEAD. It names no branch.
PLACEHOLDER_REF = re.compile(r"^\(.*\)$")


def git(path, *args):
    try:
        out = subprocess.run(["git", "-C", path, *args], capture_output=True,
                             text=True, timeout=3)
    except (OSError, subprocess.SubprocessError):
        return ""
    return out.stdout.strip() if out.returncode == 0 else ""


def branch_of(path):
    """Branch name, empty outside a repo.

    A detached HEAD is what a PR-review worktree looks like, and a bare sha
    names nothing a human recognises, so the branches sitting on that commit are
    asked first and the sha is only the last resort.
    """
    name = git(path, "branch", "--show-current")
    if name:
        return name
    if not git(path, "rev-parse", "--git-dir"):
        return ""

    for args in (["branch", "--points-at", "HEAD", "--format=%(refname:short)"],
                 ["branch", "-r", "--points-at", "HEAD", "--format=%(refname:short)"]):
        for line in git(path, *args).splitlines():
            line = line.strip()
            # "(no branch)" is the detached checkout itself, and origin/HEAD is a
            # symref to the default branch rather than a name for this commit;
            # every other remote branch drops its remote prefix.
            if not line or line.endswith("/HEAD") or PLACEHOLDER_REF.match(line):
                continue
            return line.split("/", 1)[1] if args[1] == "-r" else line

    sha = git(path, "rev-parse", "--short", "HEAD")
    return "@" + sha if sha else ""


def main_worktree(path):
    common = git(path, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if not common:
        return ""
    # <main>/.git for a normal checkout, and for a bare repo the repo itself.
    root = os.path.dirname(common) if os.path.basename(common) == ".git" else common
    return os.path.realpath(root)


def worktrees_of(path):
    """Every registered worktree, longest path first.

    Longest first because the linked worktrees here live under the main one and
    one worktree path can prefix another's, so a path has to be offered to the
    specific candidate before the general one.
    """
    found = []
    for line in git(path, "worktree", "list", "--porcelain").splitlines():
        if line.startswith("worktree "):
            found.append(os.path.realpath(line[len("worktree "):]))
    return sorted(set(found), key=len, reverse=True)


def tail_lines(path):
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as handle:
            if size > TAIL_BYTES:
                handle.seek(size - TAIL_BYTES)
                handle.readline()  # Drop the partial line the seek landed in.
            return handle.read().decode("utf-8", "replace").splitlines()[-TAIL_LINES:]
    except OSError:
        return []


def tool_inputs(line):
    """Every string the agent itself wrote into a tool call, with its weight.

    Inputs only. `git worktree list` prints every worktree on the machine, so a
    session that read one would otherwise adopt whichever neighbour it listed.
    """
    try:
        entry = json.loads(line)
    except ValueError:
        return []
    content = (entry.get("message") or {}).get("content")
    if not isinstance(content, list):
        return []

    found = []
    for block in content:
        if not isinstance(block, dict) or not block.get("name"):
            continue
        params = block.get("input")
        if not isinstance(params, dict):
            continue
        for key in ("command",) + PATH_KEYS:
            value = params.get(key)
            if isinstance(value, str):
                found.append((value, COMMAND_WEIGHT if key == "command" else FILE_WEIGHT))
    return found


def claimed_by(text, worktrees, names, main):
    """The one worktree a tool input names, longest path first, or empty.

    One input counts once. `.../worktrees/pr2425` is a prefix of
    `.../worktrees/pr2425-fix`, so a path is offered to the longer candidate
    first and the first match ends it.

    The main worktree only counts when something below it is named. Its bare
    root is where `gh pr view` and `git log` are run from, including by the
    agents working in the linked worktrees underneath it, so counting the root
    itself would hand almost every pane the folder branch again.
    """
    for worktree in worktrees:
        name = names[worktree]
        if worktree == main:
            # Something below the root, never the root itself.
            pattern = rf"(?<![\w./-]){re.escape(name)}/"
            suffix = "/"
        else:
            pattern = rf"(?<![\w./-]){re.escape(name)}(?![\w-])"
            suffix = ""
        if worktree + suffix in text or re.search(pattern, text):
            return worktree
    return ""


def worktree_from_transcript(transcript, worktrees, main):
    """The linked worktree this session works in, by how often it names it."""
    names = {worktree: os.path.basename(worktree) for worktree in worktrees}
    # Cheap reject for the many transcript lines that name no worktree at all;
    # parsing every line of a long session is not cheap.
    hint = re.compile("|".join(re.escape(name) for name in set(names.values())))

    scores = {worktree: 0 for worktree in worktrees}
    seen = 0
    for line in reversed(tail_lines(transcript)):
        if not hint.search(line):
            continue
        for text, weight in reversed(tool_inputs(line)):
            seen += 1
            claimed = claimed_by(text, worktrees, names, main)
            if claimed:
                scores[claimed] += weight * (RECENT_WEIGHT if seen <= RECENT_INPUTS else 1)

    # max() keeps the first of equal scores, and worktrees is longest-path
    # first, so a tie goes to the more specific path.
    best = max(worktrees, key=lambda worktree: scores[worktree])
    if best == main or scores[best] < MIN_SCORE or scores[best] <= scores[main]:
        return ""
    return best


def resolve(cwd, transcript):
    """The worktree the agent works in, as (path, branch)."""
    if not cwd or not os.path.isdir(cwd):
        return "", ""
    main = main_worktree(cwd)
    if not main:
        return "", ""

    here = os.path.realpath(git(cwd, "rev-parse", "--show-toplevel") or cwd)
    if here != main:
        # EnterWorktree moved the session; no guessing needed.
        return here, branch_of(here)

    worktrees = worktrees_of(cwd)
    if len(worktrees) > 1 and transcript and os.path.exists(transcript):
        found = worktree_from_transcript(transcript, worktrees, main)
        if found:
            return found, branch_of(found)

    return main, branch_of(cwd)


def main():
    # The nested `claude -p` that writes the tab title inherits TMUX_PANE and
    # would otherwise relabel the pane it is describing.
    if os.environ.get("CLAUDE_TITLE_REFINER"):
        return 0

    pane = os.environ.get("TMUX_PANE")
    if not pane or not os.environ.get("TMUX"):
        return 0

    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        payload = {}
    if not isinstance(payload, dict):
        payload = {}

    worktree, branch = resolve(payload.get("cwd") or os.getcwd(),
                               payload.get("transcript_path"))

    try:
        for option, value in (("@claude_branch", branch),
                              ("@claude_worktree", worktree)):
            subprocess.run(["tmux", "set-option", "-p", "-t", pane, option, value],
                           capture_output=True, timeout=2, check=False)
        subprocess.run(["tmux", "refresh-client", "-S"],
                       capture_output=True, timeout=2, check=False)
    except (OSError, subprocess.SubprocessError):
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
