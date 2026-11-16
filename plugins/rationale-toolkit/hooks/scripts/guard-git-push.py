#!/usr/bin/env python3
"""PreToolUse(Bash) guard: every `git push` asks, force/delete pushes are denied.

Rationale: permission rules match the literal start of a command, so
`Bash(git push --force *)` misses `git -C repo push --force`, `env git push -f`,
`cd x && git push`, or `bash -c "git push +main"` - all of which fall through to
a broad `Bash(git *)` allow. This hook tokenizes the whole command line, finds
every git invocation wherever it sits, skips git's global options, and judges
the subcommand itself.

Bias: when the command cannot be shown safe, prefer "ask" over silence. A false
"ask" costs one prompt; a missed force push rewrites remote history.

Inline code for other interpreters (`python3 -c`, `node -e`, a heredoc fed to
`python3 -`) is re-parsed as shell text, and if it mentions git and push but is
not recognisably a push it still gets "ask".

Known limits: git aliases or remote.*.push/mirror defined earlier in a config
file, and scripts written to a file and run later, are not seen. A literal
mention such as `echo git push` is treated as a push (ask).

Fails open (no verdict) only when the hook input is not the expected JSON: a
broken guard must not block every Bash call.
"""

import codecs
import json
import os
import re
import shlex
import sys

GIT_OPTS_WITH_VALUE = {
    "-C",
    "-c",
    "--git-dir",
    "--work-tree",
    "--namespace",
    "--super-prefix",
    "--config-env",
    "--exec-path",
    "--attr-source",
}
GIT_FLAGS = {
    "-p", "-P", "--paginate", "--no-pager", "--bare", "--no-replace-objects",
    "--no-lazy-fetch", "--no-optional-locks", "--no-advice", "--literal-pathspecs",
    "--glob-pathspecs", "--noglob-pathspecs", "--icase-pathspecs",
}

# Push options that overwrite or delete remote history. Git accepts any
# unambiguous prefix of a long option (`--forc`, `--del`), so match by prefix.
DESTRUCTIVE_LONG = ("--force", "--force-with-lease", "--mirror", "--delete", "--prune")
DESTRUCTIVE_SHORT = set("fd")  # -f force, -d delete; also inside bundles like -fu
MIN_PREFIX = 4  # "--fo", "--de", "--mi", "--pr"

SHELLS = {"sh", "bash", "zsh", "dash", "ksh", "fish"}
INTERPRETER_RE = re.compile(r"^(python[0-9.]*|node|nodejs|perl|ruby|php|osascript|deno|bun|tsx|lua)$")
# Subcommands that update remote refs the same way `push` does.
PUSH_LIKE = {"push", "send-pack", "http-push"}
REMOTE_PUSH_CONFIG_RE = re.compile(r"remote\..*\.(mirror|push)", re.IGNORECASE)
SEPARATORS = set(";&|()<>\n")
MAX_DEPTH = 6

# This guard re-implements just enough of bash to find git, and wherever its
# reading of heredocs, ANSI-C quoting or line continuations may differ from
# bash's, an attacker-shaped command can hide a push in the gap. So main()
# judges the command under several readings and keeps the strictest verdict.
# The reading is process-wide state, set by main() and read during recursion.
READING = {"heredocs": True, "decode": True}
# Set when a line opens heredocs whose delimiters the guard cannot pin down;
# main() then returns at least "ask" whatever the readings say.
UNSURE = {"heredoc": False}


EMPTY_DELIM_RE = re.compile(r"""[ \t]*(''|"")(?=$|[ \t;&|()<>])""")


def raw_heredoc_scan(line):
    """Raw-text facts about this line's heredoc operators.

    Returns (ops, cut). `cut` is where a real comment starts (or the line
    length): bash starts a comment only at `#` that begins a word, so
    `cat <<E#X` has the delimiter "E#X". `ops` holds, for each unquoted `<<`
    before `cut`, (dash, pos): dash is None (no `-`), "glued" (`<<-EOF`,
    `<<-''`) or "spaced" (whitespace or line end after `<<-`), and pos is the
    index just past the operator. shlex loses all three facts: it ends words at
    any `#`, drops the spacing that tells `<<-EOF` from `<< -EOF`, and drops
    the quotes that make `<<''` an empty delimiter.
    """
    ops, quote, i, n = [], None, 0, len(line)
    while i < n:
        c = line[i]
        if quote == "'":
            if c == "'":
                quote = None
        elif c == "\\":
            i += 1  # escaped character, outside single quotes
        elif quote == '"':
            if c == '"':
                quote = None
        elif c in "'\"":
            quote = c
        elif c == "#" and (i == 0 or line[i - 1] in " \t;&|()<>" or line.endswith("<<-", 0, i)):
            return ops, i
        elif line.startswith("<<<", i):
            i += 2  # here-string, not a heredoc
        elif line.startswith("<<", i):
            if line[i + 2:i + 3] != "-":
                ops.append((None, i + 2))
            elif line[i + 3:i + 4] in ("", " ", "\t"):
                ops.append(("spaced", i + 3))
            else:
                ops.append(("glued", i + 3))
            i += 1
        i += 1
    return ops, n


def heredoc_delimiters(line):
    """(delimiter, strips tabs) for each heredoc the shell really opens here.

    Only an unquoted `<<` outside a comment counts, so `echo "<<EOF"` or
    `# <<EOF` cannot hide the following lines. A line that does not tokenize
    opens none: its following lines are then judged as commands, the safe side.
    Where the raw scan and shlex disagree, UNSURE is set and none open.
    """
    if "((" in line:
        return []  # `$((1<<2))` is a shift, not a heredoc
    ops, cut = raw_heredoc_scan(line)
    # The raw scan already cut the real comment off; shlex must not apply its
    # own, looser rule (any `#` ends a word) to what is left.
    lexer = shlex.shlex(line[:cut], posix=True, punctuation_chars=";&|()<>")
    lexer.whitespace_split = True
    lexer.commenters = ""
    try:
        tokens = list(lexer)
    except ValueError:
        return []
    openers = [k for k, tok in enumerate(tokens) if tok == "<<"]
    if len(ops) != len(openers):
        # The raw scan and shlex disagree on which `<<` are real.
        UNSURE["heredoc"] = True
        return []
    delimiters = []
    for k, (dash, pos) in zip(openers, ops):
        if k + 1 >= len(tokens):
            continue  # `<<` with no word is a bash syntax error: nothing runs
        nxt = tokens[k + 1]
        # `<<-EOF` strips tabs; `<< -EOF` has the literal delimiter "-EOF",
        # `<< -` the delimiter "-", and `<<''` or `<<-''` the empty delimiter,
        # which ends the body at the first empty line. Only the one dash glued
        # to `<<` is the operator's; shlex splits `<<- -EOF` into "-", "-EOF".
        if dash == "glued" and nxt.startswith("-"):
            nxt = nxt[1:]
        elif dash == "spaced" and nxt == "-" and k + 2 < len(tokens):
            nxt = tokens[k + 2]
        elif dash is not None:
            UNSURE["heredoc"] = True  # raw text and tokens disagree
            return []
        if nxt and set(nxt) <= set(";&|()<>"):
            UNSURE["heredoc"] = True  # operator where a word belongs
            return []
        if not nxt and not EMPTY_DELIM_RE.match(line, pos):
            # An empty delimiter only from a bare '' or "" word; anything else
            # that comes out empty is a reading we cannot trust.
            UNSURE["heredoc"] = True
            return []
        delimiters.append((nxt, dash is not None))
    return delimiters


def split_heredocs(command):
    """Return (command without heredoc bodies, [(opening line, body)])."""
    lines = command.split("\n")
    kept, bodies = [], []
    if not READING["heredocs"]:
        return command, bodies
    i = 0
    while i < len(lines):
        line = lines[i]
        kept.append(line)
        i += 1
        for end, strip_tabs in heredoc_delimiters(line):
            body, start = [], i
            # bash ends the body only at a line equal to the delimiter, after
            # removing leading tabs for `<<-`; spaces or trailing text do not count.
            while i < len(lines) and (lines[i].lstrip("\t") if strip_tabs else lines[i]) != end:
                body.append(lines[i])
                i += 1
            if i >= len(lines):
                i = start  # no terminator: our reading is wrong, judge the lines as commands
                continue
            i += 1  # skip the terminator line
            bodies.append((line, "\n".join(body)))
    return "\n".join(kept), bodies


ANSI_C_RE = re.compile(r"\$'((?:[^'\\]|\\.)*)'")


def decode_ansi_c(match):
    # $'\x67it' is the word "git"; decode it so the subcommand is visible.
    try:
        return shlex.quote(codecs.decode(match.group(1), "unicode_escape"))
    except (UnicodeDecodeError, ValueError):
        return shlex.quote(match.group(1))


def normalize(command):
    # Backticks are command substitution, like $( ); make them separators.
    # Locale ($"..") quoting reads like a plain double quote here.
    if READING["decode"]:
        command = ANSI_C_RE.sub(decode_ansi_c, command)
    else:
        command = command.replace("$'", "'")
    return command.replace("`", " ; ").replace('$"', '"')


def tokenize(command):
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()<>")
    lexer.whitespace_split = True
    lexer.commenters = ""
    return list(lexer)


def segments(tokens):
    current = []
    for tok in tokens:
        if tok and set(tok) <= SEPARATORS:
            if current:
                yield current
            current = []
        else:
            current.append(tok)
    if current:
        yield current


def worst(a, b):
    order = {None: 0, "ask": 1, "deny": 2}
    return a if order[a] >= order[b] else b


def is_destructive_long(arg):
    name = arg.split("=", 1)[0]
    if name.startswith("--no-") or len(name) < MIN_PREFIX:
        return False
    return any(opt.startswith(name) for opt in DESTRUCTIVE_LONG)


PUSH_OPTS_WITH_VALUE = {"-o", "--push-option", "--repo", "--receive-pack", "--exec"}


def is_destructive(args):
    skip = False
    for arg in args:
        if skip:
            skip = False
            continue
        if arg in PUSH_OPTS_WITH_VALUE:
            skip = True  # `-o -f` passes "-f" to the server, not to push
            continue
        if arg == "--":
            continue
        if arg.startswith("--"):
            if is_destructive_long(arg):
                return True
        elif arg.startswith("-") and len(arg) > 1:
            if DESTRUCTIVE_SHORT & set(arg[1:]):
                return True
        elif arg.startswith("+") or (arg.startswith(":") and len(arg) > 1):
            # +src:dst forces that ref; :dst deletes the remote ref.
            return True
    return False


def shell_script_args(seg, start):
    """Script strings run by a shell invocation at seg[start]: `bash -xc '...'`."""
    scripts = []
    j = start + 1
    while j < len(seg):
        arg = seg[j]
        if arg == "--":
            j += 1
            continue
        if arg.startswith("-") and not arg.startswith("--") and "c" in arg[1:]:
            # The script is the next non-option argument.
            k = j + 1
            while k < len(seg) and (seg[k] == "--" or seg[k].startswith("-")):
                k += 1
            if k < len(seg):
                scripts.append(seg[k])
            return scripts, True
        if arg.startswith("-"):
            j += 1
            continue
        return scripts, True  # runs a script file: not visible here
    return scripts, False  # no script argument: reads stdin


def judge_git(seg, i, env_config=()):
    """Verdict for the git invocation at seg[i]."""
    j = i + 1
    # GIT_CONFIG_PARAMETERS / GIT_CONFIG_KEY_n=... act like `-c`.
    config_values = list(env_config) + [t for t in seg[:i] if t.startswith("GIT_CONFIG")]
    unknown_option = False
    while j < len(seg):
        arg = seg[j]
        if arg in GIT_OPTS_WITH_VALUE:
            if j + 1 < len(seg):
                config_values.append(seg[j + 1])
            j += 2
        elif arg.startswith("-"):
            config_values.append(arg)
            if arg not in GIT_FLAGS and "=" not in arg:
                unknown_option = True  # may take a value we would misread as the subcommand
            j += 1
        else:
            break
    if j >= len(seg):
        # `... | xargs git`: the subcommand arrives on stdin.
        return "ask" if "xargs" in (os.path.basename(t) for t in seg[:i]) else None
    if unknown_option and seg[j] not in PUSH_LIKE and j + 1 < len(seg) and seg[j + 1] in PUSH_LIKE:
        j += 1
    sub = seg[j]
    rest = seg[j + 1 :]

    if any("alias." in v for v in config_values):
        return "ask"  # `git -c alias.p=push p` - the real subcommand is hidden
    if "$" in sub or not sub:
        return "ask"  # `git $cmd` - unknown until the shell expands it
    if sub == "config" and any("alias" in a for a in rest) and any("push" in a for a in rest):
        return "ask"
    if sub == "config" and any(REMOTE_PUSH_CONFIG_RE.search(a) for a in rest):
        return "ask"  # makes a later bare `git push` mirror or force
    if sub == "remote" and any(a.startswith("--mirror") for a in rest):
        return "ask"
    if sub == "subtree" and "push" in rest:
        return "deny" if is_destructive(rest) else "ask"
    if sub in PUSH_LIKE:
        if is_destructive(rest):
            return "deny"
        if any("mirror" in v or "+" in v for v in config_values):
            return "deny"  # -c remote.x.mirror=true / -c remote.x.push=+ref
        return "ask"
    if sub == "submodule" and "foreach" in rest:
        script = " ".join(rest[rest.index("foreach") + 1 :])
        return classify(script, 1)
    return None


def classify(command, depth=0):
    """Return 'deny', 'ask', or None for one command string."""
    if depth > MAX_DEPTH:
        return "ask" if "git" in command else None

    command = command.replace("\\\n", "")  # bash drops backslash-newline: `pu\<nl>sh` is push
    command, heredocs = split_heredocs(command)
    try:
        tokens = tokenize(normalize(command))
    except ValueError:
        return "ask" if "git" in command else None

    verdict = None
    stdin_shell = False
    interpreter = False
    env_config = [t for t in tokens if t.startswith("GIT_CONFIG")]  # incl. `export GIT_CONFIG_...`
    for seg in segments(tokens):
        for i, tok in enumerate(seg):
            base = os.path.basename(tok)
            if base in SHELLS:
                scripts, has_arg = shell_script_args(seg, i)
                for script in scripts:
                    verdict = worst(verdict, classify(script, depth + 1))
                if not has_arg:
                    stdin_shell = True
            elif base == "eval":
                verdict = worst(verdict, classify(" ".join(seg[i + 1 :]), depth + 1))
            elif base == "git":
                verdict = worst(verdict, judge_git(seg, i, env_config))
            elif INTERPRETER_RE.match(base):
                interpreter = True
            elif i + 1 < len(seg) and seg[i + 1] == "push" and ("$" in tok or "\\" in tok):
                verdict = worst(verdict, "ask")  # `g=git; $g push`, escaped git
            if verdict == "deny":
                return "deny"

    # A heredoc body is plain text unless a shell reads it as a script.
    for opening, body in heredocs:
        words = [os.path.basename(t) for t in opening.split()]
        if any(w in SHELLS for w in words):
            verdict = worst(verdict, classify(body, depth + 1))
        elif any(INTERPRETER_RE.match(w) for w in words):
            verdict = worst(verdict, judge_code(body, depth))

    # `echo '...' | bash`, `bash <<< '...'`: any quoted text may be the script.
    # `python3 -c '...'`: the code is not shell, but its git calls often are.
    if stdin_shell or interpreter:
        for tok in tokens:
            if " " in tok or "\n" in tok:
                verdict = worst(verdict, judge_code(tok, depth) if interpreter else classify(tok, depth + 1))
    return verdict


def judge_code(code, depth):
    """Verdict for code another interpreter runs: shell rules, else ask on git+push."""
    verdict = classify(code, depth + 1)
    # String literals in the code (`os.system('git push -f')`) are often shell.
    try:
        literals = [t for t in tokenize(normalize(code)) if " " in t or "\n" in t]
    except ValueError:
        literals = []
    # `subprocess.run(['git', 'push', '-f'])`: read the argument list as words.
    literals.append(re.sub(r"[\"',\[\]]", " ", code))
    for literal in literals:
        verdict = worst(verdict, classify(literal, depth + 2))
    if verdict is None and "git" in code and "push" in code:
        return "ask"
    return verdict


def main():
    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        return
    if not isinstance(payload, dict):
        return
    tool_input = payload.get("tool_input")
    command = tool_input.get("command") if isinstance(tool_input, dict) else None
    if not isinstance(command, str):
        return

    verdict = classify(command)
    # Same command without ANSI-C decoding: a `$'` that bash leaves literal
    # (inside "..." or '...') must not swallow a following -f.
    READING.update(heredocs=True, decode=False)
    verdict = worst(verdict, classify(command))
    # No heredoc reading at all: a body we wrongly treated as data is judged
    # as commands. Capped at "ask", since real heredoc text (a commit message
    # that mentions git push -f) would otherwise be denied.
    READING.update(heredocs=False, decode=True)
    if classify(command) is not None or UNSURE["heredoc"]:
        verdict = worst(verdict, "ask")
    if verdict == "deny":
        reason = (
            "BLOCKED: force or delete push (--force, -f, --force-with-lease, --mirror, "
            "--delete, -d, --prune, +refspec, :refspec, or the same via -c config). "
            "Rewriting or deleting remote history is the user's to run by hand; stop and report instead."
        )
    elif verdict == "ask":
        reason = (
            "git push publishes commits (or the command hides which git subcommand runs); "
            "it needs the user's approval every time."
        )
    else:
        return

    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": verdict,
                "permissionDecisionReason": reason,
            }
        },
        sys.stdout,
    )


if __name__ == "__main__":
    main()
