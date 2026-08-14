# mise-toolchain

A Claude Code plugin for two things `mise` already does well, but that are
easy to get subtly wrong by hand: pinning a project's toolchain versions,
and sharing one `.env` baseline across many git worktrees.

## Core ideas

**Toolchain versions inherit the machine's own preferences.** If your global
`~/.config/mise/config.toml` says `python = "3.12"`, a project's `mise.toml`
should say `3.12` too — not `latest`. The skill reads that preference with
`mise config get tools.<name>` rather than guessing, and falls back to
`latest` only when there is no preference to inherit (or no `mise` at all).

**One baseline `.env`, many worktrees.** `.env` is untracked, so
`git worktree add` never brings it along. Instead of copying it into every
worktree, a gitignored `mise.local.toml` points at a single baseline kept
outside the working tree, plus an optional per-worktree override layer.

Baselines live in `~/.local/share/dev-env/env/` and are selected by name:
`<repo>.env` when it exists, `dev.env` otherwise. Most projects need nothing
but the shared `dev.env` — a per-project file is only worth creating once a
project has variables the others don't. The two are **alternatives, not
layers**: whichever is selected must carry every variable the project needs.

That directory is provisioned by hand. The skill reads paths out of it and
never writes into it.

## What's included

### Skills

| Skill | Triggers on | What it does |
|---|---|---|
| [`setup-toolchain`](skills/setup-toolchain/SKILL.md) | Pinning tool versions for a project/worktree; adding a language to an existing `mise.toml` | Writes only the `[tools]` table, inheriting per-tool version specs from the machine's global mise config. Never generates `[tasks]` or `[env]`, and never overwrites an existing file wholesale. |
| [`link-env`](skills/link-env/SKILL.md) | A worktree with no `.env`; sharing credentials across worktrees; overriding one value in a single worktree | Writes a gitignored `mise.local.toml` pointing at a baseline picked from `~/.local/share/dev-env/env/` (`<repo>.env`, else `dev.env`), under an optional `.env.local`. Wires paths only — never creates baselines, never reads or copies env contents. |

Skills activate automatically when Claude Code judges the task matches their
description — this is a best-effort semantic match, not a guarantee.

## File split

The two skills deliberately write to different files, so they can never
clobber each other:

| File | Contents | Git | Scope |
|---|---|---|---|
| `mise.toml` | `[tools]` | tracked | shared by all worktrees |
| `mise.local.toml` | `[env]` | gitignored | per-worktree |

This mirrors the Docker Compose convention (`docker-compose.yml` tracked,
`docker-compose.override.yml` gitignored), so one mental model covers both.

## Verified behaviour

Layering semantics were tested against mise 2026.7 rather than assumed:

- Later entries in `_.file` override earlier ones.
- A missing file in the list is skipped silently — so `.env.local` only has
  to exist when a worktree actually needs it.
- `~` in a path is expanded. Note this differs from Docker Compose's
  `env_file:`, which does **not** expand `~` and needs `${HOME}`.

A newly created `mise.toml` / `mise.local.toml` is untrusted until
`mise trust` is run, and the resulting error message leads with
"error parsing config file" — which reads like a TOML syntax problem but
isn't. Both skills call this out.

## Installation

From within Claude Code:

```
/plugin marketplace add helzoph/claude
/plugin install mise-toolchain@helzoph-claude-marketplace
```

## Relationship to dev-env-router

Separate plugins on purpose: toolchain versions are needed the moment a
project starts, whereas dev routing is often added halfway through. Bundling
them would force one to wait on the other.

When a project runs under Docker Compose too, the container side must read
the **same** baseline `.env` — that wiring belongs to `dev-env-router`'s
`onboard` skill. The two plugins cooperate by agreeing on the baseline path,
not by sharing config files.

## License

Apache-2.0
