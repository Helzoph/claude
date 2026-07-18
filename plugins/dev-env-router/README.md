# dev-env-router

A Claude Code plugin that derives local dev environment routing from
directory names, so ports and domains never need to be assigned or
remembered by hand — even across many concurrent git worktrees.

## Core idea

Docker Compose defaults `COMPOSE_PROJECT_NAME` to the current directory
name, and git worktree directory names are naturally unique. A single
machine-level Traefik instance forwards traffic based on that name
(`http://<project-dir-name>.localhost`), while project containers publish
no ports to the host at all.

**Local development only** (plain HTTP, no TLS). Do not reuse these
templates as a production deployment configuration.

## What's included

### Skills

| Skill | Triggers on | What it does |
|---|---|---|
| [`onboard`](skills/onboard/SKILL.md) | Setting up local dev routing for a new project/worktree | Onboards a project by wiring up the `templates/project-compose.yml` template, assuming the shared Traefik router is already running (see USAGE.md). |
| [`operate`](skills/operate/SKILL.md) | Starting/stopping/restarting an already-onboarded project; asking for its URL | Enforces `docker compose up/down` over bare processes, and reports URLs (never port numbers). |
| [`cleanup`](skills/cleanup/SKILL.md) | Cleaning up leftover containers after a worktree is deleted | Finds orphaned Compose projects by diffing against `git worktree list`, and removes them only after explicit, per-project user confirmation — never automatically. |

Skills activate automatically when Claude Code judges the task matches
their description — this is a best-effort semantic match, not a guarantee.
The `SessionStart` hook below exists precisely because that match cannot be
relied on alone.

### Hooks

| Hook | Event | What it does |
|---|---|---|
| `detect-onboarded-project` | `SessionStart` (all matchers) | Checks whether the current directory's Compose file already has a `traefik.enable=true` label. If so, injects a reminder to use `docker compose up/down/restart` (never a bare process) and to report the project's URL as `http://<project-dir-name>.localhost`, regardless of whether the `operate` skill happens to trigger on its own. Silent no-op otherwise. |

Hook script is TypeScript (`.ts`), run directly via `node` (Node.js ≥ 22.18,
which strips erasable TypeScript syntax by default — no build step or
`ts-node`/`tsx` required). Node.js must be on `PATH`.

### Templates

| Template | Scope | Purpose |
|---|---|---|
| [`router/router-compose.yml`](router/router-compose.yml) | Machine-level, one instance total. Lives in the plugin directory itself — never copied into a project or worktree; the user manually copies it to `~/.dev-env-router/` and starts it once, per USAGE.md. | The shared Traefik router: dashboard bound to `127.0.0.1` + basicauth, `providers.docker.exposedbydefault=false`. |
| [`skills/onboard/templates/project-compose.yml`](skills/onboard/templates/project-compose.yml) | Per project/worktree | No host port publishing; joins the external `web` network; Traefik labels derived from `${COMPOSE_PROJECT_NAME}`. |

## Installation

From within Claude Code:

```
/plugin marketplace add helzoph/claude
/plugin install dev-env-router@helzoph-claude-marketplace
```

## Usage guide

See [`USAGE.md`](USAGE.md) (in Chinese) for a step-by-step first-time
setup walkthrough, what ports 80/8080 are for, how to onboard a project,
day-to-day operation, orphan cleanup, and a troubleshooting table.

## Why this exists

Manually tracking which port belongs to which worktree becomes a real
memory burden once more than a couple of projects are open at once. This
plugin replaces that bookkeeping with a name that is already guaranteed
unique — the directory itself — routed through one shared, auditable
Traefik instance instead of ad hoc `-p host:container` mappings.

## License

Apache-2.0
