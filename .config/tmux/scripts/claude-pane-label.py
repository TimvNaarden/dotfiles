#!/usr/bin/env python3
"""Name a tmux pane after the piece of work its Claude Code agent is on.

Three things can name that work, and they are tried in that order.

The worktree comes first. An agent sitting in a worktree of its own is there
because the work has one, and the branch of that worktree is the name a human
already gave it. Two git calls resolve it, so it lands on the pane inside the
hook with nothing to look up and nothing to shorten.

The pull request comes next, for the agents that stayed in the main worktree.
Those share one directory and one branch, so the branch names all of them at
once and none of them apart. What separates them is the pull request each is
actually on, and the transcript says which: a PR the agent keeps naming in its
own tool calls, or one you named in a prompt, is this session's PR. "#2470 Book
Covers" is then both unique and readable. Only when the transcript names none
does the branch's own pull request stand in, and that is the one case where two
panes can still land on the same name.

The conversation comes last. No worktree and no pull request leaves the prompts
you typed, and Haiku turns the most recent few into a name. A few rather than
the newest alone, because a name taken from the last prompt tracks the step
instead of the work and is rewritten every turn.

Neither lookup is quick enough to run inside a hook, so the hook reads the cache
and a detached process fills the misses in seconds later. A pull request's name
is cached per pull request, so every agent on one resolves it once between them,
and a conversation name is cached per session, because that is the only thing it
belongs to.

Usage:
  claude-pane-label.py                   hook, payload on stdin
  claude-pane-label.py --resolve <pane> <session> <worktree> <branch> <transcript>
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import time

CACHE = os.path.expanduser("~/.claude/cache/pane-labels.json")

# A name off a pull request is as stable as the pull request itself. A name off
# the conversation moves with the conversation, and a session that has no pull
# request now may well have opened one by the next prompt.
PR_TTL = 30 * 60
PROMPT_TTL = 10 * 60
# A prompt is the moment a conversation name can have changed, but a burst of
# one-word prompts should not be a burst of Haiku calls.
PROMPT_FLOOR = 45
# The shared name of one pull request. Renaming a PR is rare.
PR_NAME_TTL = 6 * 60 * 60

# The branch is the whole label, so it gets the whole width; "#2470 " eats six
# characters of it, which is why the PR name itself is held shorter.
MAX_LABEL = 36
MAX_LENGTH = 26
MAX_WORDS = 4

# Enough transcript to cover the recent turns without reading a session that has
# run all day. A single turn with a long tool result can be tens of thousands of
# characters, so a couple of thousand lines is a few dozen tool calls.
TAIL_BYTES = 2_000_000
TAIL_LINES = 2000
# And a glance at the opening of one that is longer than that.
HEAD_BYTES = 200_000
HEAD_LINES = 200

# How many of your prompts Haiku is given, newest first.
PROMPTS = 5

# You naming a pull request is a decision; an agent naming one in a tool call is
# a step it took, which is weaker but far more frequent.
USER_WEIGHT = 3
TOOL_WEIGHT = 2
# The newest texts weigh double, so a pull request the session has moved off
# cannot outvote the current one on sheer history.
RECENT_TEXTS = 60
RECENT_WEIGHT = 2
# One recent mention by you clears this on its own (3 x 2); one old tool call
# does not. Two tool calls do, which is what any real work on a PR produces.
MIN_SCORE = 5

# Cheap reject before the regexes below, for the many lines naming no PR at all.
PR_HINT = re.compile(r"\bpr\b|\bpull\b|/pulls?/|#\d{2,6}", re.I)
PR_REFS = (
    re.compile(r"/pulls?/(\d{2,6})\b"),                       # a github URL
    re.compile(r"\bpr[\s#:_/-]{0,2}(\d{2,6})\b", re.I),       # PR 2470, pr#2470, pr2470
    re.compile(r"\bpull\s+request\s+#?(\d{2,6})\b", re.I),
    re.compile(r"\breview[a-z-]*\s+(?:pr\s*)?#?(\d{2,6})\b", re.I),  # /detached-review 2470
    re.compile(r"#(\d{2,6})\b"),
)

# Tool parameters an agent writes a pull request into. Results are never read:
# `gh pr list` prints every open PR, and a session that ran it would otherwise
# adopt whichever one came back first.
INPUT_KEYS = ("command", "url", "prompt")

# A slash command, as the transcript stores what you typed.
COMMAND_NAME = re.compile(r"<command-name>\s*(/[\w:-]+)\s*</command-name>")
COMMAND_ARGS = re.compile(r"<command-args>(.*?)</command-args>", re.S)
# Wrappers around text you did not type: hook output, task notifications, the
# transcript of a local command, a pasted image placeholder.
TAGGED = re.compile(r"^<(?:task-notification|local-command|system-reminder|"
                    r"command-message|user-prompt-submit-hook|bash-)")
# Claude Code's own stand-ins for a message: an interruption, a pasted image.
SYNTHETIC = re.compile(r"^\[(?:Request interrupted|Image|Pasted)", re.I)
# Commands that end a conversation rather than continue it. Everything older
# belongs to the work this session replaced.
RESET = re.compile(r"^/(?:clear|compact|resume|rewind)\b", re.I)

# `fix(books): ...`, the conventional commit prefix of a PR title.
COMMIT_PREFIX = re.compile(r"^[a-z]+(?:\([^)]*\))?!?:\s*")
# Where a sentence stops being the headline and starts being the detail.
DETAIL = re.compile(r"\s*(?:[,;(]|\s\+\s|\s(?:when|while|so|because|that|which|"
                    r"with|for|from|and|plus|in|on|to)\s)", re.I)
# The ClickUp block a PR body opens with: [869cfnnap](https://...): Task name.
CLICKUP = re.compile(
    r"^\s*[-*]?\s*\[[^\]]+\]\(https?://(?:app\.)?clickup\.com/[^)]*\)\s*[:–-]\s*(\S.*?)\s*$",
    re.M)

REFUSALS = ("please run", "not logged in", "i cannot", "i can't", "error:")

# What `git branch --points-at` calls a detached HEAD. It names no branch.
PLACEHOLDER_REF = re.compile(r"^\(.*\)$")


def tmux(*args):
    try:
        out = subprocess.run(["tmux", *args], capture_output=True, text=True,
                             timeout=2, check=False)
    except (OSError, subprocess.SubprocessError):
        return ""
    return (out.stdout or "").strip()


def pane_option(pane, name):
    return tmux("show-option", "-p", "-t", pane, "-qv", name)


def git(path, *args):
    try:
        out = subprocess.run(["git", "-C", path, *args], capture_output=True,
                             text=True, timeout=3, check=False)
    except (OSError, subprocess.SubprocessError):
        return ""
    return out.stdout.strip() if out.returncode == 0 else ""


# --- where the agent is ------------------------------------------------------

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


def placement(worktree):
    """Where this agent works, as (dedicated, branch).

    The path comes from claude-pane-branch.py, but the branch is read here
    rather than taken from the pane: the hooks may run at the same moment, and
    a worktree that has been switched to another branch since the pane was last
    labelled would otherwise keep the name of the branch it used to hold.
    """
    if not worktree or not os.path.isdir(worktree):
        return False, ""
    root = git(worktree, "rev-parse", "--show-toplevel")
    if not root:
        return False, ""
    here = os.path.realpath(root)
    return here != main_worktree(worktree), branch_of(here)


def repo_key(worktree):
    """Per repository, so two repos with a `main` do not share a name."""
    return git(worktree, "config", "--get", "remote.origin.url") or worktree


# --- the cache ---------------------------------------------------------------

def read_cache():
    try:
        with open(CACHE) as handle:
            data = json.load(handle)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def write_cache(key, entry):
    """Merge one entry in. Agents in other panes are writing this too."""
    data = read_cache()
    data[key] = entry
    # Keep the file from growing forever; a week-old entry is a session nobody
    # is running any more.
    cutoff = time.time() - 7 * 24 * 60 * 60
    data = {k: v for k, v in data.items()
            if isinstance(v, dict) and v.get("ts", 0) > cutoff}
    try:
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        handle = tempfile.NamedTemporaryFile(
            "w", encoding="utf-8", delete=False,
            dir=os.path.dirname(CACHE), prefix=".pane-labels-")
        with handle:
            json.dump(data, handle)
        os.replace(handle.name, CACHE)
    except (OSError, ValueError):
        pass


def stale(entry, event):
    """Whether the label is worth resolving again.

    Freshness is about the lookup rather than the answer, so a session that
    resolves to no name at all is cached as such and stops asking every hook.
    """
    if not isinstance(entry, dict):
        return True
    age = time.time() - entry.get("ts", 0)
    if entry.get("source") == "pr" and entry.get("label"):
        return age > PR_TTL
    # A prompt is when the conversation changed, and it is also when a pull
    # request that did not exist a minute ago starts existing.
    if event == "UserPromptSubmit":
        return age > PROMPT_FLOOR
    return age > PROMPT_TTL


# --- reading the transcript --------------------------------------------------

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


def head_lines(path):
    """The opening of a session, for a transcript too long to read whole.

    A pull request is usually named in the first thing you type, and on a
    session that has run all day that prompt scrolled out of the tail hours
    before the work on it was finished.
    """
    try:
        if os.path.getsize(path) <= TAIL_BYTES:
            return []  # The tail already covers the whole file.
        with open(path, "rb") as handle:
            text = handle.read(HEAD_BYTES).decode("utf-8", "replace")
    except OSError:
        return []
    return text.splitlines()[:HEAD_LINES]


def message_text(entry):
    """The text of a message, whether it is stored as a string or as blocks."""
    content = (entry.get("message") or {}).get("content")
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    # tool_result blocks live in user messages too; they are not your words.
    return " ".join(block.get("text", "") for block in content
                    if isinstance(block, dict) and block.get("type") == "text")


def prompt_text(raw):
    """What you actually typed, or empty for a message you did not type."""
    raw = raw.strip()
    if not raw:
        return ""
    name = COMMAND_NAME.search(raw)
    if name:
        args = COMMAND_ARGS.search(raw)
        return " ".join(part for part in (name.group(1),
                                          (args.group(1) if args else "").strip())
                        if part)
    if TAGGED.match(raw) or SYNTHETIC.match(raw):
        return ""
    return " ".join(raw.split())


def tool_inputs(entry):
    """Every string the agent itself wrote into a tool call."""
    content = (entry.get("message") or {}).get("content")
    if not isinstance(content, list):
        return []
    found = []
    for block in content:
        if not isinstance(block, dict) or block.get("type") != "tool_use":
            continue
        params = block.get("input")
        if not isinstance(params, dict):
            continue
        for key in INPUT_KEYS:
            value = params.get(key)
            if isinstance(value, str):
                found.append(value)
    return found


def claim(scores, text, weight, seen):
    """Score the pull requests one piece of text names. One text, one vote each."""
    if not PR_HINT.search(text):
        return
    weight *= RECENT_WEIGHT if seen < RECENT_TEXTS else 1
    numbers = {number for pattern in PR_REFS for number in pattern.findall(text)}
    for number in numbers:
        scores[number] = scores.get(number, 0) + weight


def entries(lines):
    for line in lines:
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        # A sidechain is a subagent's turn. It works on whatever it was handed,
        # which is regularly a different pull request from its parent's.
        if isinstance(entry, dict) and not entry.get("isSidechain"):
            yield entry


def scan(transcript):
    """What the transcript says: (pull request, your last prompts)."""
    prompts = []
    scores = {}
    seen = 0
    cleared = False

    for entry in entries(reversed(tail_lines(transcript))):
        kind = entry.get("type")
        if kind == "user" and not entry.get("isMeta"):
            text = prompt_text(message_text(entry))
            if not text:
                continue
            if RESET.match(text):
                # Everything older belongs to the conversation this one replaced.
                cleared = True
                break
            if len(prompts) < PROMPTS:
                prompts.append(text)
            claim(scores, text, USER_WEIGHT, seen)
            seen += 1
        elif kind == "assistant":
            for text in tool_inputs(entry):
                claim(scores, text, TOOL_WEIGHT, seen)
                seen += 1

    # The opening of a long session, which the tail no longer reaches. Skipped
    # once the tail has found a /clear, because then the whole opening belongs
    # to a conversation this session has already thrown away.
    if not cleared:
        opening = {}
        for entry in entries(head_lines(transcript)):
            kind = entry.get("type")
            if kind == "user" and not entry.get("isMeta"):
                text = prompt_text(message_text(entry))
                if not text:
                    continue
                if RESET.match(text):
                    opening.clear()
                    continue
                claim(opening, text, USER_WEIGHT, RECENT_TEXTS)
            elif kind == "assistant":
                for text in tool_inputs(entry):
                    claim(opening, text, TOOL_WEIGHT, RECENT_TEXTS)
        for number, score in opening.items():
            scores[number] = scores.get(number, 0) + score

    if not scores:
        return None, prompts
    # max() keeps the first of equal scores, and the scan runs newest first, so
    # a tie goes to the pull request named most recently.
    best = max(scores, key=lambda number: scores[number])
    return (int(best) if scores[best] >= MIN_SCORE else None), prompts


# --- turning a headline into a name ------------------------------------------

def condense(text):
    """A headline cut down to something that fits a tab, without Haiku."""
    text = COMMIT_PREFIX.sub("", " ".join(text.split()))
    head = DETAIL.split(text, 1)[0].strip(" -–:;,.")
    # "Page on mobile wider than 100%" breaks at "on" and leaves "Page", which
    # names nothing. One word is not a headline, so the whole line is used.
    if len(head.split()) < 2:
        head = text.strip(" -–:;,.")
    words = [word for word in head.split() if word][:MAX_WORDS]
    if not words:
        return ""
    # Words already carrying capitals are names or acronyms; leave them alone.
    words = [word if word[:1].isupper() or any(c.isupper() for c in word)
             else word.capitalize() for word in words]
    # Drop whole words rather than cutting one in half; "Lecture Materials
    # Dropdown O" is not a shorter name, it is a broken one.
    while len(" ".join(words)) > MAX_LENGTH and len(words) > 1:
        words.pop()
    return " ".join(words)[:MAX_LENGTH].rstrip()


def haiku(instruction, body, fallback):
    """Haiku writes the name; the fallback stands in when it cannot."""
    if tmux("show-option", "-gqv", "@claude_ai_titles") == "off":
        return fallback

    try:
        out = subprocess.run(
            ["claude", "-p", "--model", "claude-haiku-4-5", "--no-session-persistence",
             instruction + "\n\n" + body[:2000]],
            capture_output=True, text=True, timeout=60, check=False,
            # Without this the nested agent runs these hooks again, marks the
            # pane running and fires a notification. --bare would skip the hooks
            # too, but it drops the OAuth credentials.
            env={**os.environ, "CLAUDE_TITLE_REFINER": "1"})
        name = (out.stdout or "").splitlines()[0]
    except (OSError, subprocess.SubprocessError, IndexError):
        return fallback

    name = name.translate({ord(c): None for c in '"\r\n'}).strip(" -–:;,.")
    if not name or len(name) > 40 or any(bad in name.lower() for bad in REFUSALS):
        return fallback
    return name


def shorten(raw):
    return haiku(
        "Name this piece of work in 2 to 4 words, Title Case, no punctuation, "
        "no quotes. It labels a terminal tab, so name the thing being worked "
        "on, not the action. Reply with the name only.",
        raw, condense(raw))


def name_from_prompts(prompts):
    body = "\n".join("- " + prompt[:400] for prompt in prompts)
    return haiku(
        "Below are the last few messages a developer sent a coding agent, "
        "newest first. Name the piece of work they are about in 2 to 4 words, "
        "Title Case, no punctuation, no quotes. Name the thing being worked "
        "on rather than the action, weigh the newest message heaviest, and "
        "ignore anything that is only an aside. It labels a terminal tab. "
        "Reply with the name only.",
        body, condense(prompts[0]))


# --- the pull request --------------------------------------------------------

def pr_for_branch(worktree, branch):
    """The newest pull request for this branch, open ones first."""
    try:
        out = subprocess.run(
            ["gh", "pr", "list", "--head", branch, "--state", "all", "--limit", "5",
             "--json", "number,title,body,state,updatedAt"],
            cwd=worktree, capture_output=True, text=True, timeout=25, check=False)
        found = json.loads(out.stdout or "[]")
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    if not isinstance(found, list) or not found:
        return None
    found.sort(key=lambda pr: (pr.get("state") == "OPEN", pr.get("updatedAt") or ""),
               reverse=True)
    return found[0]


def pr_by_number(worktree, number):
    try:
        out = subprocess.run(
            ["gh", "pr", "view", str(number), "--json", "number,title,body"],
            cwd=worktree, capture_output=True, text=True, timeout=25, check=False)
        found = json.loads(out.stdout or "{}")
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    return found if isinstance(found, dict) and found.get("number") else None


def pr_name(worktree, number, details):
    """The short name of a pull request, resolved once per PR across panes."""
    key = "pr|{}|{}".format(repo_key(worktree), number)
    hit = read_cache().get(key)
    if isinstance(hit, dict) and hit.get("name") and \
            time.time() - hit.get("ts", 0) < PR_NAME_TTL:
        return hit["name"]

    if details is None:
        details = pr_by_number(worktree, number)
    if not details:
        return ""
    # The PR body opens with the ClickUp tasks it closes, and a task name is
    # what the work is called everywhere else; the PR title is the fallback.
    task = CLICKUP.search(details.get("body") or "")
    raw = task.group(1) if task else (details.get("title") or "")
    if not raw:
        return ""
    name = shorten(raw)
    write_cache(key, {"name": name, "raw": raw, "ts": time.time()})
    return name


# --- putting it together -----------------------------------------------------

def resolve(worktree, branch, transcript):
    """The label for a pane that is not in a worktree of its own."""
    number, prompts = (scan(transcript)
                       if transcript and os.path.exists(transcript) else (None, []))

    details = None
    if number is None and branch and worktree and os.path.isdir(worktree):
        details = pr_for_branch(worktree, branch)
        number = details.get("number") if details else None

    if number:
        name = pr_name(worktree, number, details) if worktree else ""
        label = "#{} {}".format(number, name) if name else "#{}".format(number)
        return {"label": label[:MAX_LABEL], "source": "pr", "ts": time.time()}

    if prompts:
        return {"label": name_from_prompts(prompts)[:MAX_LABEL],
                "source": "prompts", "ts": time.time()}

    return {"label": "", "source": "prompts", "ts": time.time()}


def apply(pane, session, label):
    """Put the label on the pane, unless the pane has moved on since."""
    if not label or pane_option(pane, "@claude_session") != session:
        return
    tmux("set-option", "-p", "-t", pane, "@claude_label", label)
    # The marker is what Claude Code itself prefixes a session title with, and
    # claude-window-label.sh strips it back off.
    tmux("select-pane", "-t", pane, "-T", "✳ " + label)
    tmux("refresh-client", "-S")


def spawn(pane, session, worktree, branch, transcript):
    """Resolve out of band; a hook must not wait on gh and Haiku."""
    try:
        subprocess.Popen(
            [os.path.abspath(__file__), "--resolve", pane, session, worktree,
             branch, transcript],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True)
    except (OSError, subprocess.SubprocessError):
        pass


def main():
    # The nested `claude -p` that writes the name inherits TMUX_PANE and would
    # otherwise relabel the pane it is describing.
    if os.environ.get("CLAUDE_TITLE_REFINER"):
        return 0

    if len(sys.argv) > 1 and sys.argv[1] == "--resolve":
        pane, session, worktree, branch, transcript = (sys.argv + [""] * 7)[2:7]
        if not pane or not session:
            return 0
        entry = resolve(worktree, branch, transcript)
        write_cache("session|" + session, entry)
        apply(pane, session, entry["label"])
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

    session = payload.get("session_id") or pane
    event = payload.get("hook_event_name") or ""
    transcript = payload.get("transcript_path") or ""
    # Set by claude-pane-branch.py, which resolves the worktree an agent works
    # in even when it never left the directory it was launched from. The payload
    # cwd stands in for the first turn, before that has run.
    worktree = pane_option(pane, "@claude_worktree") or payload.get("cwd") or ""

    # The pane carries the session so a detached lookup that lands after you
    # have started something else in this pane knows to drop its answer.
    tmux("set-option", "-p", "-t", pane, "@claude_session", session)

    dedicated, branch = placement(worktree)
    if dedicated and branch:
        # A worktree of its own is the whole answer, and it needs no lookup.
        write_cache("session|" + session,
                    {"label": branch[:MAX_LABEL], "source": "worktree",
                     "ts": time.time()})
        apply(pane, session, branch[:MAX_LABEL])
        return 0

    entry = read_cache().get("session|" + session)
    if isinstance(entry, dict) and entry.get("label"):
        # A stale name is still the right name almost always, so it goes up now
        # and the refresh below corrects it if the work has moved on.
        apply(pane, session, entry["label"])
    elif not isinstance(entry, dict):
        # Nothing known about this session yet, and whatever the pane carries
        # names the session before it, so it goes rather than sitting there
        # through the seconds the lookup takes.
        tmux("set-option", "-p", "-t", pane, "@claude_label", "")

    if stale(entry, event):
        spawn(pane, session, worktree, branch, transcript)
    return 0


if __name__ == "__main__":
    sys.exit(main())
