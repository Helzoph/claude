# rationale-toolkit

A Claude Code plugin that enforces a rationale-first working style: explain
**why** before **what**, and prove a change works before calling it done.

## What's included

### Skills

| Skill | Triggers on | What it does |
|---|---|---|
| [`rationale-style`](skills/rationale-style/SKILL.md) | Writing, reviewing, or explaining code; design decisions; trade-off analysis | Requires inline `// Rationale: ...` comments on non-trivial logic, and a stated approach/trade-off/risk before implementation. |
| [`verify-outcomes`](skills/verify-outcomes/SKILL.md) | After completing any code change (bug fix, feature, refactor, config) | Assesses how thoroughly a change needs verification, enforces a failing-test-first bug-fix protocol, an 80% coverage gate, and defines a verification report format. Includes toolchain references for TypeScript, Python, Go, and Rust. |

Skills activate automatically when Claude Code judges the task matches their
description — no manual invocation needed.

### Output styles

| Style | What it does |
|---|---|
| [`ELI5`](output-styles/eli5.md) | Explains everything in plain language a beginner can follow — jargon defined inline, everyday analogies over abstract vocabulary — without padding the response or sacrificing accuracy. Code, comments, commit messages, and identifiers keep their normal technical register. |
| [`ELI15`](output-styles/eli15.md) | Assumes the reader writes code but doesn't know this domain: programming fundamentals go unexplained, domain terms get one clause on first use, and the words saved go into behaviour, boundary conditions, and failure modes. Also requires every response that did work to close with what changed, whether it's finished, and what the user must do next. |

Pick **ELI5** when the reader is new to programming. Pick **ELI15** when they can
code but the domain is unfamiliar — and when you want the status of the work
stated explicitly rather than buried in the explanation. ELI15's status section
governs only the *wording* of that report; how deeply to verify and what the
report must contain stay with [`verify-outcomes`](skills/verify-outcomes/SKILL.md).

Unlike skills, an output style is **not** automatic: only one can be active at a
time, so you select it explicitly. Run `/config`, pick **Output style** → the one
you want, then `/clear` — the output style is part of the system prompt, which
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
