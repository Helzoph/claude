---
name: setup-tiers
description: "Lays out three local environment tiers whose identity is derived from the directory name — worktree dev (no containers), UAT, and production — by writing a just command entrypoint and a project-local guard hook that hard-blocks the irreversible production commands (compose down -v, docker volume rm/prune, git clean -x) and turns a missing prod override into a confirmation prompt. Use when a project runs real data locally and needs a place to test that is not that, when someone has already run a destructive command against the real local data, or when the same repo needs a staging tier alongside production. Triggers on: 'I need a UAT environment', 'set up staging locally', 'stop me from wiping the real database', 'separate prod and test containers'. Do NOT use for Traefik routing setup (that is dev-env-router/onboard) or for env var layering (that is mise-toolchain/link-env). Never point the guard at a directory the user has not named as production."
---

# env-tiers: Setting Up Three Environment Tiers (setup-tiers)

## The Problem

The same repo both runs real data and is where code gets changed. So every `docker compose down -v`, every migration run, every "let me just try this" touches the data that cannot be lost.

Branches do not solve this — branches isolate code, not volumes. If containers started from two branches live in the same directory, `COMPOSE_PROJECT_NAME` is the same, so the volume is the same.

## The Approach: The Directory Name Is the Identity

```
<repo>/                          prod, real data                   http://<repo>.localhost
<repo>-uat/                      UAT, can be torn down any time    http://<repo>-uat.localhost
<repo>/.claude/worktrees/*/      dev, no containers
```

Each tier is a git worktree, and their directory names all differ. Every other property follows from this one:

- Compose derives the project name from the directory name by default → container names and volume names get a prefix automatically (`<repo>_data` vs `<repo>-uat_data`), so **the two data sets are isolated by construction**, with no configuration.
- If the Traefik routing rule is written as ``Host(`${COMPOSE_PROJECT_NAME}.localhost`)``, the hostnames separate automatically too, so **there is no need for a separate UAT override layer to change labels**.
- The guard hook also uses the directory name to decide "which tier this command hits".

**Do not hardcode hostnames in compose**, and do not introduce a second criterion such as `ENV=prod`. Each extra source of truth adds one more possible state where "two places say this is UAT and one says prod", and this kind of inconsistency surfaces exactly at the most dangerous moment. Branches in particular must not be the criterion: a checkout can change the branch, but not the directory.

So the only thing left to really guard is: **the UAT directory must be named `<repo>-uat`**. A wrong name does not raise an error; it just quietly lands on a hostname nobody visits and uses a set of volumes nobody backs up — so the `justfile` below turns it into an immediate failure.

## Four Values to Pin Down Before Starting

These values get hardcoded into the generated files; get one wrong and the guard blocks the wrong thing. **Do not guess**:

| Value | Meaning | How to confirm |
|---|---|---|
| `PROD_DIR` | The prod **directory name** (not a path) | `basename $(git rev-parse --show-toplevel)`, but confirm with the user that this directory really runs prod |
| `UAT_DIR` | The UAT directory name | Defaults to `<PROD_DIR>-uat`; if the user already uses another name, use theirs |
| `DATA_VOLUME` | The data volume name declared in compose | Read the `volumes:` section of the project's `docker-compose.yml`; if there are several volumes, ask the user which one holds the non-reproducible data |
| `PROD_OVERRIDE` | The override file name prod must always include | Usually `docker-compose.prod.yml`; if it does not exist, create it first per the next section |

`PROD_DIR` must be confirmed by the user; do not infer it from cwd and start acting. A guard pointed at the wrong directory fails in two ways: pointed at UAT, everyday experiments get blocked until it is unusable, and the result is the hook being switched off entirely; pointed at a nonexistent directory, the guard silently does nothing, and a guard that silently does nothing is more dangerous than no guard — it makes people believe there is a line of defense.

## Prod and UAT Do Not Run the Same Thing

This is not just a configuration difference; it is two ways of running:

| | UAT | prod |
|---|---|---|
| Frontend | dev server, HMR | static build output + a web server |
| Backend | watch mode, restarts on change | started directly, no watch |
| Source | bind mount, changes take effect immediately | baked into the image, changes only at build time |
| After a code change | auto-reload | **must rebuild with `--build`** |

The differences go in `PROD_OVERRIDE`; the base `docker-compose.yml` stays the UAT/dev setup. This direction must not be reversed: **when the override is missing, the behavior must be "fall back to the dev config", not "fall back to the production config"** — the former misbehaves immediately (the source bind mount comes back, hot reload jumps around), while the latter quietly leaves a container with no watch in a dev directory, and nobody will notice.

The production build has one more thing that is easy to miss: in dev, the same-origin path from frontend to backend is usually provided by the dev server's proxy, and **after a production build it no longer exists**. Without it the symptom is not "cannot connect" but a page that looks normal while every API call returns `index.html`. Check that the project's production web server config has the corresponding forwarding rule.

## Steps

### 1. Write the command entrypoint

Copy `templates/justfile` to the **repo root** (it goes into git and so into every worktree; all three tiers share the same copy) and replace the three placeholders: `__PROD_DIR__`, `__UAT_DIR__`, `__PROD_OVERRIDE__`. The `check` target at the end is a TODO; replace it with this project's actual type-check/test/build commands.

If a `justfile` already exists, **do not overwrite it**. First explain the differences to the user and ask whether to merge into the existing file or keep the original and create a separate entrypoint; act only after the user explicitly chooses.

Why this wrapper is needed: forgetting the override in prod does not raise an error, and forgetting `--build` does not raise an error either (the containers still start, the page still opens, and it runs the previous version of the code). **An error that does not raise an error can only be prevented by "remembering the flags every time", and that is exactly the kind of thing that gets forgotten.**

`just` deliberately does not provide `down -v`. To wipe data, go to UAT and type the full command by hand.

### 2. Write the guard hook

Copy `templates/guard-prod.sh` to `.claude/hooks/guard-prod.sh` in the **prod directory**, replace the four placeholders, then `chmod +x`.

Note that this file's location is the opposite of the `justfile`'s: the `justfile` goes into git and is shared by all three tiers; the guard script lives under `.claude/` (usually gitignored) and takes effect only in the prod directory. If the project commits `.claude/` to git, the script will follow into every worktree — this does not affect correctness (it decides by directory name and allows straight through in other directories), but tell the user.

### 3. Register it in the prod directory's `.claude/settings.json`

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/guard-prod.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

If the file already exists, **only append to the `hooks.PreToolUse` array**; do not overwrite it wholesale — other hooks may already be there.

### 4. Also pin the worktree base

In the same `settings.json`, add:

```json
"worktree": { "baseRef": "head" }
```

The reasoning belongs to the branch-flow side; see the `branch-flow` skill. The one-line version: a new worktree should grow from **the branch the current session is on**, not from `origin/<default>` — repos developed locally often have no remote, and the default `fresh` mode then comes up empty.

### 5. Verify the guard actually blocks

After the change you must test it for real; **do not declare it installed just from reading the code**. Guard failures are silent.

In the prod directory, have the agent run a command that should be blocked, for example `docker compose down -v` — you should see the block message and the command should not run. Then run the same command in the UAT directory; it should be allowed.

If both sides behave the same (both block or both allow), the placeholders were not replaced correctly; go back to step 2 and check that `PROD_DIR` is the directory name and not the full path.

## What the Guard Blocks and What It Does Not

Three hard blocks, all **irreversible and with no undo**:

- `docker compose down -v` — deletes the data volume. Backups are usually daily, so at worst the most recent day is lost.
- `docker volume rm` / `prune` — `prune` is especially dangerous: it does not take a project name and takes every unused volume on this machine with it.
- `git clean -x` — deletes gitignored files too. Credential files and local backup directories are usually exactly the gitignored ones; in `clean`'s eyes they are "unowned files", yet they are the only copy.

One soft confirmation (turned into a confirmation prompt instead of a hard block): `up`/`restart` without the override in the prod directory. This mistake does not destroy data, but it is silent.

**Comprehensive protection is explicitly a non-goal.** The more it blocks, the more likely it gets switched off entirely, and being switched off means losing all three hard blocks at once. A different phrasing (`docker rm -v`, deleting `/var/lib/docker/volumes/` by hand) still gets around it. The real backstop is still "do not experiment in the prod directory" — the guard catches "a slip of the hand", not "a deliberate workaround".

Likewise, when the script cannot parse its input (for example, `python3` is unavailable), it **allows rather than blocks**. A fail-closed guard would block every Bash call in this project, and the inevitable result is someone switching the hook off.

## A Known Detection Boundary

The `cwd` the hook receives is the session's working directory, not the directory where the command actually runs. So when `cd ../<PROD_DIR> && docker compose down -v` is issued from the UAT directory, `cwd` is harmless.

The template therefore adds a second criterion: when the command text contains a `cd` into `PROD_DIR`, it is treated as prod as well. The cost is an occasional false positive (in UAT, `cd ../<PROD_DIR> && git log` is also treated as prod context, though `git log` is not on the block list anyway, so in practice this rarely comes up). The direction is safe: a false positive just costs one extra block.

Getting around it is still not hard (building the path from variables, `pushd`, wrapping it in another script). This is the "catches slips, not deliberate workarounds" from the previous section.

## Relationship to Other Plugins

- **`dev-env-router/onboard`** — owns how hostnames resolve to `<directory name>.localhost`. This skill depends only on "the Compose project name is derived from the directory name"; both sides share the same criterion and do not share config files.
- **`mise-toolchain/link-env`** — owns how each tier's environment variables are wired up. Note that UAT's credential problem is not just "wire it up and done"; see the `stand-up-uat` skill.
