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

Unlike skills, an output style is **not** automatic: only one can be active at a
time, so you select it explicitly. Run `/config`, pick **Output style** → **ELI5**,
then `/clear` — the output style is part of the system prompt, which Claude Code
reads once at session start.

It sets `keep-coding-instructions: true`, so Claude Code's built-in software
engineering behaviour (change scoping, comment conventions, verification) is
preserved. This style changes how work is *explained*, not how it is *done*.

Note that output styles apply to the main conversation only — a subagent runs its
own system prompt and is unaffected.

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
