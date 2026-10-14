---
name: stand-up-uat
description: "Stands up the UAT tier for the first time as a sibling git worktree, and works through what UAT silently inherits from production: credentials shared with prod that cause real-world side effects when UAT exercises them (push notifications reaching a real device, rate limits shared with the prod account), an empty database that needs either migrations or a restored snapshot, and read-only mounts of host login state. Use when creating a UAT/staging worktree for the first time, when UAT was created but does not come up, or when UAT unexpectedly triggered something in the real world. Triggers on: 'set up the UAT worktree', 'UAT sent me a real notification', 'UAT is using up my API quota', 'UAT database is empty'. Do NOT use for the shared justfile and guard hook (that is setup-tiers). Never copy a production .env into UAT without walking the shared-credential checklist first."
---

# env-tiers: First-time UAT setup (stand-up-uat)

## Prerequisites

`setup-tiers` has already been run (the `justfile` and the guard hook are both in place); for the branch flow, see `branch-flow`.

## Create the directory

UAT is a **sibling directory** of the prod repo, not a subdirectory of it:

```bash
git worktree add ../<repo>-uat -b uat
```

The directory name must be exactly `<repo>-uat` (or the `UAT_DIR` the user chose in `setup-tiers`). A wrong name does not raise an error; it just quietly brings up a set of orphan containers that land on a different domain and use different volumes — the `justfile`'s `_guard-dev` turns this into an immediate failure, but only if the name matches what it checks for.

Putting it under the prod directory's `.claude/worktrees/` **does not work**: that location is for dev worktrees, and both the guard and the `justfile` decide by "directory name = tier", not by path.

## What UAT inherits from prod (this section is the key part)

Code and config are easy to think of. What actually causes incidents is the following — none of it shows up in any config file diff, but as soon as UAT runs, it acts on the real world:

### 1. Credential files are not in git; copy them manually

`.env` and the like are gitignored, so `git worktree add` does not bring them along. Copy them manually from the prod directory, or use `mise-toolchain/link-env` to connect both tiers to the same baseline outside the workspace.

**Finish item 2 below before copying.** Copying the whole file over as-is is exactly where the problem comes from.

### 2. Go through them one by one: which credentials are shared between the two tiers, and what happens once they are shared

For **every** external service credential in `.env`, ask: "If UAT runs once with this key, what happens in the real world?" There are three outcomes:

| Outcome | Handling |
|---|---|
| Nothing happens (read-only, sandbox, separate quota) | Share it as is |
| It acts on the real world, but **that is exactly what is being verified** | Share it deliberately, and **record it in the project docs with the date and the reason** |
| It acts on the real world, and that is only a side effect | Switch to a UAT-only key, or leave it empty |

The second category needs elaboration, because it looks like a bug but is actually a decision. Typical example: the push notification key is shared by both tiers, so UAT's test pushes really do reach users' phones. This can be **deliberate** — the push path only counts as verified once it has actually sent something, and failed push delivery is often silent and invisible in the logs. The cost is being interrupted while batch jobs run; when that happens, just comment out UAT's key (provided the code **logs rather than errors** when the key is missing, which is itself a behavior to confirm).

The typical case of the third category is **shared rate limits**: UAT and prod call the same LLM/API provider with the same account, so one round of batch jobs in UAT eats into prod's quota. This category often cannot be isolated (subscriptions are account-level), so record explicitly that "this is currently the only place not cleanly isolated", rather than pretending it does not exist.

**Do not skip this step and copy the whole file.** An omission shows up as "UAT runs and the real world reacts", and the investigation usually suspects the code first.

### 3. Read-only mounts of host login state

Some tools keep their login state in the host's home directory (e.g. `~/.codex/auth.json`), mounted read-only into the container in compose. With such mounts, both tiers share the same file — the login itself is fine, but **account-level quotas are shared**, which puts this in the third category above.

### 4. The database is empty

There are two ways to start it; choose by purpose:

- **Only verifying code paths** → run the migrations once; an empty database is fine.
- **Verifying with real data** → pick a backup from prod and restore it. Note that the backup must be a **consistent snapshot** such as `VACUUM INTO`, not a file produced by `cp` — un-checkpointed transactions in SQLite's WAL do not get copied, so the restored database is missing recent writes, and because it still opens normally, the loss is silent.

After restoring real data into UAT, the risk level of item 2 goes up: batch jobs running in UAT now operate on real content, and the external calls they trigger carry real content too. Before making this choice, re-check the results of the item 2 inventory.

## Bring it up

```bash
cd ../<repo>-uat
just env      # first confirm this directory is recognized as the uat tier
just up
```

If the tier shown by `just env` is not `uat`, stop — most likely the directory name is wrong, or the `__UAT_DIR__` placeholder in the `justfile` was not replaced. In that case `just up` is blocked by `_guard-dev` (that is by design); do not bypass it by hand-typing compose commands, which walks you right into the "bring up a set of orphan containers" trap.

**Do not start bare processes** (`npm run dev` and the like). That bypasses the reverse proxy, and routing breaks outright.

Report the address as a domain, not a port number: `http://<repo>-uat.localhost`. `just up` prints the address when it finishes.

## What you can do in UAT but not in prod

This is the entire reason UAT exists, so its boundaries are spelled out here:

- `docker compose down -v` — here, just hand-type the full command (`just` deliberately does not provide it).
- Run migrations, write to the database, change the schema.
- Restore/overwrite the database.
- Try any "let me just try it" operation.

Conversely, **do not open a worktree in UAT** — the base would become `uat`, breaking the escape hatch in `branch-flow`. To open a separate branch to fix a bug, go back to the prod directory and open it there.
