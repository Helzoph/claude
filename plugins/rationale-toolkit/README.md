# rationale-toolkit

A Claude Code plugin that enforces a rationale-first working style: explain
**why** before **what**, and prove a change works before calling it done.

## What's included

### Skills

| Skill | Triggers on | What it does |
|---|---|---|
| [`rationale-style`](skills/rationale-style/SKILL.md) | Writing, reviewing, or explaining code; design decisions; trade-off analysis | Requires inline `// Rationale: ...` comments on non-trivial logic, and a stated approach/trade-off/risk before implementation. |
| [`verify-outcomes`](skills/verify-outcomes/SKILL.md) | After completing any code change (bug fix, feature, refactor, config) | Assesses how thoroughly a change needs verification, enforces a failing-test-first bug-fix protocol, an 80% coverage gate, and defines a verification report format. Includes toolchain references for TypeScript, Python, Go, and Rust. |
| [`design-ui`](skills/design-ui/SKILL.md) | Building, changing, or reviewing a user-facing screen or flow | Starts from the user story (who, situation, goal, needed information, how they learn the result), follows familiar conventions and the project's visual style, keeps implementation terms off screen, and verifies by walking the whole story. |

Skills activate automatically when Claude Code judges the task matches their
description — no manual invocation needed.

### Output styles

| Style | What it does |
|---|---|
| [`ELI15`](output-styles/eli15.md) | Assumes the reader writes code but doesn't know this domain: programming fundamentals go unexplained, domain terms get one clause on first use, and the words saved go into behaviour, boundary conditions, and failure modes. Also requires every response that did work to close with what changed, whether it's finished, and what the user must do next. |

The baseline is deliberately "codes, but doesn't know this domain" rather than
"beginner". Explaining fundamentals costs words that would otherwise carry
detail, and for a reader who already programs that trade is a pure loss. Ask for
a simpler register in the prompt on the rare occasion you need one.

ELI15's status section governs only the *wording* of a completion report; how
deeply to verify and what the report must contain stay with
[`verify-outcomes`](skills/verify-outcomes/SKILL.md).

Unlike skills, an output style is **not** automatic: only one can be active at a
time, so you select it explicitly. Run `/config`, pick **Output style** →
**ELI15**, then `/clear` — the output style is part of the system prompt, which
Claude Code reads once at session start.

It sets `keep-coding-instructions: true`, so Claude Code's built-in software
engineering behaviour (change scoping, comment conventions, verification) is
preserved. This style changes how work is *explained*, not how it is *done*.

Note that output styles apply to the main conversation only — a subagent runs its
own system prompt and is unaffected.

### Hooks

| Hook | Event | What it does |
|---|---|---|
| [`block-node-modules-bin`](hooks/scripts/block-node-modules-bin.sh) | `PreToolUse` (Bash) | Denies any Bash command containing `node_modules/.bin/`, naming the binary and pointing at the alternatives: a system-installed command first, then `pnpm exec` / `npx` / `bunx`. |

`node_modules/.bin/<tool>` bakes in one package manager's on-disk layout — pnpm's
store is not flat and Yarn PnP has no `.bin` directory at all — and it silently
prefers a vendored copy over a newer system install. Going through a runner keeps
the same command working across package managers.

The hook fails open: if `jq` is missing it exits without a verdict rather than
blocking every Bash call. Unlike an output style, hooks also apply to subagents.

| Hook | Event | What it does |
|---|---|---|
| [`guard-git-push`](hooks/scripts/guard-git-push.py) | `PreToolUse` (Bash) | Every `git push` asks for approval; force or delete pushes (`--force`, `-f`, `--force-with-lease`, `--mirror`, `--delete`, `-d`, `--prune`, `+ref`, `:ref`) are denied. |

Permission rules match the literal start of a command, so `Bash(git push --force *)`
does not catch `git -C repo push -f`, `cd x && git push -f`, `env git push -f`, or
`bash -c "git push +main"`; a broad `Bash(git *)` allow then lets them through.
The guard tokenizes the whole command line (with `shlex`), finds each `git`
invocation, skips git's global options (`-C`, `-c`, `--git-dir`, …), and judges the
subcommand. `send-pack` and `http-push` count as pushes, and so does
`subtree push`. Abbreviated long options (`--forc`) are denied, and so is mirror
or `+ref` config set through `-c` or `GIT_CONFIG_*` variables. These get "ask":
`-c alias.*`, a subcommand held in a variable (`git $c`), a git held in a
variable (`$g push`), `xargs git`, and writing `remote.*.mirror` /
`remote.*.push` with `git config`; `-o <value>` is skipped as a push option. ANSI-C quoting (`$'\x67it'`) is decoded first.
It also re-parses text a shell will run: `sh -c` / `bash -xc` scripts, `eval`,
backticks, `git submodule foreach`, heredoc bodies fed to a shell, and quoted
text when a shell reads stdin (`echo '…' | bash`, `bash <<< '…'`). Inline code
for `python3 -c`, `node -e`, `perl -e` and the like (or a heredoc fed to them)
has its string literals re-parsed. If that code mentions git and push without
parsing as a push, it gets "ask". Other quoted text is data, so a quoted commit
message that mentions "git push" passes. Only an unquoted, uncommented `<<`
opens a heredoc, and a heredoc with no terminator is read as commands. A line
where the guard cannot tell which heredocs open (or which delimiter carries the
`<<-` dash) gets at least "ask".

The guard's reading of bash can differ from bash itself, and a command can be
shaped to hide a push in that gap. So the guard judges each command three
times and keeps the strictest verdict: once with full parsing, once without
ANSI-C decoding, and once with no heredoc parsing at all. The third reading is
capped at "ask". As a result, a heredoc whose text mentions `git push -f` (a
commit message passed with `-F -`, for example) gets one confirmation prompt.
Not seen: aliases or `remote.*.push` set earlier in a git config
file, and scripts written to a file and run later. It needs `python3`; without it, or on
input that is not JSON, it gives no verdict. A command it cannot tokenize
(unbalanced quotes) that mentions git gets "ask".

## Installation

From within Claude Code:

```
/plugin marketplace add helzoph/claude
/plugin install rationale-toolkit@helzoph-claude-marketplace
```

## Why this exists

These skills encode a working style that previously lived only as a
personal global `CLAUDE.md`: reasoning must be visible before code lands, and
"done" must be backed by an actual verification step, not an assumption.
Packaging them as a plugin makes that style portable and installable per
project, instead of relying on machine-wide config.

## License

Apache-2.0
