# rationale-toolkit

A Claude Code plugin that enforces a rationale-first working style: explain
**why** before **what**, and prove a change works before calling it done.

## What's included

### Skills

| Skill | Triggers on | What it does |
|---|---|---|
| [`rationale-style`](skills/rationale-style/SKILL.md) | Writing, reviewing, or explaining code; design decisions; trade-off analysis | Requires inline `// Rationale: ...` comments on non-trivial logic, and a stated approach/trade-off/risk before implementation. |
| [`verify-outcomes`](skills/verify-outcomes/SKILL.md) | After completing any code change (bug fix, feature, refactor, config) | Assesses how thoroughly a change needs verification, enforces a failing-test-first bug-fix protocol, an 80% coverage gate, and defines a verification report format. Includes toolchain references for TypeScript, Python, Go, and Rust. |
| [`yagni-design`](skills/yagni-design/SKILL.md) | Writing new code, adding functionality, architecture decisions | Enforces YAGNI: no speculative abstraction, no premature DRY, no error handling for impossible cases, delete dead code on sight. |

Skills activate automatically when Claude Code judges the task matches their
description — no manual invocation needed.

Dependency-management guardrail hooks (blocking direct `node_modules/.bin/`
calls and direct manifest/lockfile edits) live in the separate
[`pkg-manager-guardrails`](../pkg-manager-guardrails) plugin.

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
