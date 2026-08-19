---
name: manage-shadows
description: Inspect, tune, add or disable the background shadow-mind reviewers that watch this Codex session. Use when the user asks which shadows are running, what a shadow reported, why reviews are too frequent or too noisy, or wants a new reviewer for a specific concern.
---

# Managing shadow minds

Shadow minds are read-only reviewer agents that run in the background while the
main agent codes. They are dispatched by a `PostToolUse` hook and their findings
are delivered at the end of the turn.

## Where things live

State root — `$PLUGIN_DATA`, defaulting to `~/.codex/shadow-mind/`:

| Path | Contents |
|---|---|
| `shadows/*.md` | Shadow definitions. Edit these; the plugin's own copies are only the seed. |
| `config.env` | Global tuning, `key = value` per line. |
| `sessions/<id>/reports/` | Findings waiting to be delivered at end of turn. |
| `sessions/<id>/logs/` | Raw `codex exec` output per shadow. Read these when a shadow appears to do nothing. |

## Configuration

`config.env` keys, with defaults. Every key is also overridable as
`CODEX_SHADOW_MIND_<KEY>` in the environment.

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `true` | Master switch for dispatch. |
| `heartbeat_interval` | `3` | Run a review round every Nth file-changing tool call. Reads are not counted — on current Codex almost every tool call is `exec`, and most of those are `cat`/`rg`/`sed -n`. |
| `max_parallel` | `2` | Shadows allowed to run at once. |
| `transcript_turns` | `40` | Transcript lines handed to each shadow. |
| `timeout_seconds` | `120` | Default per-shadow wall clock. |
| `model` | unset | Model for shadows; inherits the session default when unset. |
| `stop_mode` | `block` | `block` sends the agent back to work once per session; `notify` only reports. |

Tuning guidance:

- Findings arrive too often → raise `heartbeat_interval`, or lower individual
  `activation_probability` values.
- Reviews cost too much → set `model` to a cheaper model, or drop `max_parallel`
  to `1`.
- A shadow keeps reporting the same thing → its instructions are too broad;
  narrow the "report only" clause rather than disabling it outright.

## Writing a shadow

A shadow is one Markdown file in `shadows/`. Front matter, then instructions:

```markdown
---
name: test-coverage
description: Checks that changed logic has matching test coverage.
activation_probability: 0.4
timeout_seconds: 120
enabled: true
---

You check whether the change that just happened is covered by tests.
...
Say NO_FINDINGS if coverage is adequate.
```

Front matter fields: `activation_probability` (0–1, chance of running on a given
heartbeat), `timeout_seconds`, `enabled`, and optionally `model` to override the
model for this reviewer alone.

Three rules that decide whether a shadow is useful or just noise:

1. **Give it one concern.** A reviewer asked to check everything reports the
   most obvious thing every time, which the main agent already knows.
2. **Tell it what not to report.** Explicit exclusions are what keep two shadows
   from filing the same finding.
3. **End with the `NO_FINDINGS` instruction.** Without it a shadow will always
   find something to say, and every turn ends in an interruption.

## Operating notes

- Shadows run under `--sandbox read-only` with hooks disabled. They cannot edit
  files and cannot spawn further shadows.
- Hook changes need trust: after editing anything under `hooks/`, run `/hooks`
  in Codex and approve the new hash, otherwise the hook is silently skipped.
- To disable temporarily without touching files:
  `export CODEX_SHADOW_MIND_ENABLED=false`.
