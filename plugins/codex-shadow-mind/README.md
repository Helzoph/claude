# Codex Shadow Mind

Read-only reviewer agents that run in parallel with the main Codex agent and
report what they find back into its context.

**This plugin is for Codex only.** It is built entirely on Codex hooks —
`PostToolUse` with `async: true` for background dispatch, and `Stop` with
`decision: "block"` to send the agent back to work. Claude Code has no
equivalent `additionalContext`-from-background-review path, so there is no
`.claude-plugin/` manifest here and nothing to install on that side.

For the same reason it is **deliberately absent** from this repository's
`.claude-plugin/marketplace.json`. That file is Claude Code's plugin index and
carries no per-platform field, so anything listed there shows up as installable
in `/plugin` — and installing this one would attach no hooks and no skills.
Codex does not read the marketplace manifest; it discovers the plugin from
`.codex-plugin/plugin.json` in this directory. Do not "fix" the missing entry.

Inspired by [pi-shadow-mind](https://github.com/liuzhengdongfortest/pi-shadow-mind),
rebuilt against Codex's hook and sandbox model.

## The problem

A single agent reviewing its own work reviews it with the same assumptions that
produced it. The failure modes that survive are the ones review is supposed to
catch:

- **Architectural drift** — responsibilities pile into whichever module was open.
- **Invented APIs** — functions, flags and files that are plausible but absent.
- **Documentation drift** — the README still describes the previous behaviour.
- **Premature completion** — "done" for the interesting two thirds of the request.

Catching these after the fact is expensive; the context that would have made the
fix cheap is gone. Shadow minds review while the work is still warm.

## How it works

```
main agent edits code
        │
        ▼
  PostToolUse hook (async — never blocks a tool call)
        │  every Nth edit, and only if the transcript changed
        ▼
  dispatch shadows, up to max_parallel at once
        │  each: codex exec --sandbox read-only --disable hooks --ephemeral
        ▼
  findings written to reports/
        │
        ▼
  Stop hook — replays findings; first time per session it blocks
             the turn and sends the agent back to address them
```

Each shadow receives the recent transcript with reasoning stripped: it reviews
what happened, not what the main agent was thinking about doing. It then reads
the actual repository to verify before reporting.

### Why these mechanics

**Read-only is enforced by the sandbox, not the prompt.** Shadows run under
`--sandbox read-only`, so a reviewer that decides to be helpful and fix
something is stopped by the OS rather than by instructions it might reinterpret.

**Recursion is cut twice.** A shadow is a Codex process; its own tool calls
would fire the same hook. Children run with `--disable hooks` and with
`CODEX_SHADOW_MIND=1` set, and every script exits immediately when it sees that
variable.

**Reviews are throttled three ways.** A heartbeat interval (review every Nth
edit, not every edit — mid-refactor code is supposed to look broken), a
per-shadow activation probability (so a session sees a varied mix of reviewers
rather than the full panel every time), and a parallel slot cap (so token spend
is bounded).

**The completion gate fires once per session.** `decision: "block"` restarts the
turn, and a reviewer that can restart it indefinitely is a hang. After the first
block the gate degrades to plain notification for the rest of the session.

**Every failure path exits 0.** No `jq`, no `codex`, a malformed payload, a
missing transcript — all exit silently. A review aid must never be the reason a
coding session stops working.

## Install

```
codex plugin marketplace add https://github.com/helzoph/claude
codex plugin install codex-shadow-mind
```

Then **trust the hooks** — Codex skips plugin-bundled hooks until you approve
them:

```
/hooks
```

Requires `jq` and the `codex` CLI on `PATH`.

## Bundled shadows

| Shadow | Default | Watches for |
|---|---|---|
| `fact-check` | on, p=0.6 | APIs, files, flags and config keys that do not exist |
| `architecture-review` | on, p=0.4 | God components, misplaced logic, broken boundaries |
| `completion-review` | on, p=0.35 | Requirements silently dropped from the request |
| `docs-drift` | off | Docs the current change just made wrong |

`docs-drift` ships disabled because most changes do not touch documented
behaviour, and a reviewer that reports on every change trains you to ignore it.
Enable it in repositories where the docs actually matter.

## Configuration

Everything lives under `$PLUGIN_DATA` (default `~/.codex/shadow-mind/`). Shadow
definitions are copied there on first run, so edits survive plugin upgrades.

`config.env`:

```sh
heartbeat_interval = 3     # review every Nth edit
max_parallel       = 2     # concurrent shadows
transcript_turns   = 40    # transcript lines per shadow
timeout_seconds    = 120   # per-shadow wall clock
model              =       # blank inherits the session model
stop_mode          = block # or `notify` to never interrupt
```

Any key is also settable as `CODEX_SHADOW_MIND_<KEY>`. To switch it off for one
session: `export CODEX_SHADOW_MIND_ENABLED=false`.

Adding a reviewer means dropping a Markdown file in `shadows/`; the
`manage-shadows` skill covers the format and what separates a useful shadow from
a noisy one.

## Cost

Each activation is a full `codex exec` run — roughly 15–25k tokens against a
small repository in local testing. With the defaults, a session of a dozen edits
triggers a handful of reviews. Lower `max_parallel`, raise `heartbeat_interval`,
or point `model` at something cheaper if that is more than you want to spend.

## Inspecting

State per session lives in `$PLUGIN_DATA/sessions/<session-id>/`:

- `reports/` — findings awaiting delivery
- `logs/` — raw `codex exec` output; read these when a shadow appears to do nothing
- `edit-count`, `last-digest`, `gate-used` — heartbeat and gate state
