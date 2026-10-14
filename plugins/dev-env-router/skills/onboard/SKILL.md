---
name: onboard
description: "Onboards a project/worktree that has no Traefik labels yet onto http://<project-dir-name>.localhost, assuming the machine-level shared Traefik router has already been set up by the user (see the plugin's USAGE.md). Use this skill when the user asks to set up local dev routing for a new project/worktree, or wants to stop manually assigning ports across worktrees. Triggers on: setting up a new project/worktree's dev environment, requests to stop tracking ports manually. Do NOT use for starting/stopping/checking an already-onboarded project (use operate instead) — 'is there a shared dashboard' or 'what's running' about an existing setup belongs to operate, not here. Do NOT use this skill to bootstrap the shared router itself — that is a one-time manual setup documented in USAGE.md, not something this skill performs."
---

# dev-env-router: Onboarding a Project (onboard)

## Core Idea

Stop assigning ports/domains by hand. Docker Compose uses the current directory name as `COMPOSE_PROJECT_NAME` by default, and git worktree directory names are naturally distinct, so the directory name can serve directly as the project's routing identity: `http://<dir-name>.localhost`. All traffic goes through a **single machine-wide** Traefik instance, so containers no longer need to publish ports to the host.

**Local development only** (plain HTTP, no TLS). Do not apply this setup to production deployments.

## Prerequisite: The Shared Router Is Set Up Manually by the User; This Skill Assumes It Is Already Running

First-time setup of the shared router (`router/router-compose.yml`) is a one-time, machine-level operation (create the network, generate basicauth credentials, start the container). It is documented in the plugin's `USAGE.md`, **is done manually by the user, and is not this skill's responsibility**. This skill assumes that step is done, and does not detect, guide, or perform that setup on the user's behalf.

If you find in practice that the router is not running (e.g. the project is unreachable after `docker compose up -d`), tell the user to complete the one-time setup in `USAGE.md`. Do not try to initialize it yourself (it involves binding host port 80, mounting `/var/run/docker.sock`, and other machine-level side effects that must not be triggered implicitly by a request like "onboard a project").

## Onboarding a Specific Project / Worktree

For each project or worktree that needs to be onboarded to the router:

0. First check whether an orphaned Compose project with the same name already exists: if this directory name was previously used by another worktree that was deleted without cleaning up its containers, `docker compose up -d` in the new project may collide with the old containers on `COMPOSE_PROJECT_NAME` (Compose will treat it as "updating" the old project rather than creating a new one). Check with:
   ```bash
   docker compose ls --format json | grep -i "<expected-project-name>"
   ```
   If you find a project with the same name whose state is abnormal or whose origin is unclear, run through the `cleanup` skill to investigate and confirm first, then come back and continue onboarding. Do not run `up` directly.

1. Check whether `docker-compose.yml` or `compose.yml` already exists in the target project's root directory.
   - **Does not exist**: copy `templates/project-compose.yml` as the project's `docker-compose.yml`, then fill in the actual service definition (build/image/command, the port the service listens on inside the container) following the TODO comments in the file.
   - **Already exists**: **never overwrite it directly**. You must first explain the differences to the user and ask how to merge (e.g. append `networks`/`labels` fields to the existing service, or keep the original file and add a dedicated override file). Only make changes after the user explicitly chooses.

2. Verify the key fields (especially when merging into an existing file):
   - Do not add `ports:` mappings to the host on any service.
   - `networks:` must include the external `web` network.
   - `labels:` must include `traefik.enable=true`, a routing rule based on `${COMPOSE_PROJECT_NAME}`, and the correct in-container port (`loadbalancer.server.port`).
   - **In multi-service projects (e.g. app + db + redis), put Traefik labels only on the one service that provides the external HTTP entry point**; do not add them to the other internal services. Although `exposedbydefault=false` acts as a fallback so unlabeled services are not accidentally exposed, mechanically copying the template's labels block onto every service will expose routes for all of them.

3. Start: run `docker compose up -d` in the project directory (it must be run from the project root so that `COMPOSE_PROJECT_NAME` is correctly derived from the directory name).

4. Verify: visit `http://<project-dir-name>.localhost`. If the directory name contains uppercase letters, dots, or similar characters, Compose normalizes it and the actual domain may not exactly match the directory name — treat the actual route shown in the dashboard (`http://traefik.localhost`) as authoritative.

## Environment Variables: Wiring the Container Side to the Shared Baseline

If the project needs a `.env` to start, **do not copy `.env` into the worktree**. `.env` is an untracked file that `git worktree add` does not bring along; copying it by hand leaves each worktree with its own copy, each drifting independently.

The correct approach is to have the container read the shared baseline outside the workspace, configured in `docker-compose.override.yml` (this file must be gitignored):

```yaml
services:
  <the-service-with-traefik-labels>:
    env_file:
      - ${HOME}/.local/share/dev-env/env/<the-selected-one>.env   # baseline
      - path: .env.local                   # private overlay for this worktree
        required: false                    # most worktrees don't have this file
```

### Which Baseline to Pick

Run this check and put the printed filename into the `env_file` above (it only checks existence; it does not read contents):

```bash
REPO=$(basename "$(git rev-parse --path-format=absolute --git-common-dir | xargs dirname)")
ENVDIR=~/.local/share/dev-env/env
test -f "$ENVDIR/$REPO.env" && echo "$REPO.env" || { test -f "$ENVDIR/dev.env" && echo dev.env; }
```

If it prints nothing, **stop and ask the user**. Do not create one on their behalf, and do not fall back to reading the project's own `.env`.

Two hard constraints (not relaxed just because the source of truth for the rule lives elsewhere):

- **Do not create any file under `~/.local/share/dev-env/env/`**; that directory is maintained manually by the user only.
- **Do not read, print, or copy the contents of the baseline or `.env.local`**; all that is needed here is wiring up the path.

> **Source of truth for the rule: the `link-env` skill in the `mise-toolchain` plugin.** The full version of the check above, and the reasoning behind each constraint (why the two baselines replace rather than patch each other, why the agent must not create them on the user's behalf), are written there and not repeated in this section. On the host side (things like `npm run dev`), `link-env` writes `mise.local.toml` to wire up the same baseline — both sides **must select the same file**, otherwise you get the hardest kind of problem to debug: "works in the container, fails on the host". The two plugins each write their own files and share no configuration.

### Container-Side Pitfalls

These three apply only on the Compose side and are not in `link-env`:

- **`env_file` does not expand `~`**; you must write `${HOME}` or an absolute path. If written as `~/...`, Compose treats it as a literal directory name and reports that the file does not exist. This is the opposite of mise's `_.file` (which does expand `~`), so the two configs are easy to get wrong by copying from one to the other.
- `required: false` requires Compose 2.24+. Older versions fail because they don't recognize the long syntax.
- Write it in `docker-compose.override.yml`, not `docker-compose.yml`: the latter goes into git, so writing machine-level absolute paths into it makes the config non-portable, and every worktree editing the same line will inevitably cause merge conflicts.

## Next Steps

- For day-to-day start/stop rules, see the `operate` skill.
- For cleaning up orphaned containers after a worktree is deleted, see the `cleanup` skill (cleanup is destructive and is never run automatically).
