---
name: cleanup
description: "Finds orphaned dev-env-router Compose projects — ones whose backing git worktree directory no longer exists — and removes them only after explicit user confirmation. Use this skill when asked to clean up leftover/orphaned dev containers, free up disk space from old worktrees, or audit which routed projects are stale. Triggers on: 'clean up old containers', 'I deleted a worktree, is there leftover stuff', 'why is my Docker taking so much space'. Never invoke this to silently or automatically delete anything."
---

# dev-env-router: Orphaned Project Cleanup

## This Is a Destructive Operation — The Following Rules Have No Exceptions

This skill locates containers/networks/volumes that may need to be deleted. Following the principle in the user's global CLAUDE.md that dangerous operations require confirmation, **under no circumstances is it allowed** to combine "listing the candidates" and "performing the deletion" in the same reply, no matter how obviously orphaned the candidates look.

**"Confirmation" must be the user's explicit approval of a specific list of project names; vague authorization is not accepted**:
- Blanket replies from the user such as "都删了吧" ("just delete them all"), "看起来都能删" ("looks like they can all go"), "你觉得可以就删" ("delete if you think it's fine"), or "继续吧" ("go ahead") **do not count as confirmation**. You must first restate in full the list of project names you will run `down -v` on, have the user give final confirmation of that specific list, and then execute one by one — even for a batch authorization like "delete everything", go through this restatement step, so that a misjudged entry in the list is not glossed over by a blanket "delete them all".
- Execute only when the user's reply explicitly maps to specific project names (listed one by one, or an explicit "yes, delete these" to the restated list).

## Step 1: Find Candidate Orphaned Projects

1. List all projects currently managed by Compose:
   ```bash
   docker compose ls --format json
   ```

2. List all git worktree directories that still exist (run per repository, or have the user specify which repositories to check):
   ```bash
   git worktree list --porcelain
   ```

3. Compare the two lists: project names that appear in `docker compose ls` but whose corresponding directory is no longer in the `git worktree list` output are **candidate orphans**.

   Note: project names are directory names after Compose normalization, so the comparison must apply the same normalization (lowercase, replace illegal characters); a plain string-equality comparison will not work.

   **This comparison is a heuristic, not an authoritative judgment**: if a project's compose file (or `.env`) explicitly sets `COMPOSE_PROJECT_NAME`, the project name departs from the default directory-name derivation and the comparison breaks — it may misjudge a project still in use as an orphan, or miss a real orphan because of a coincidental name collision. When you suspect this, verify with `docker compose -p <name> config` or by checking the project's compose file/`.env` for an explicit `COMPOSE_PROJECT_NAME` assignment; do not trust the automatic comparison result outright.

## Step 2: List Only, Do Not Execute

Show the candidate orphan list to the user as-is, including: project name, the number of corresponding containers/networks/volumes, and (if it can be found) the original directory path. You must also state: **this list comes from a mechanical comparison based on directory existence and may contain false positives due to normalization errors or an overridden `COMPOSE_PROJECT_NAME`; please verify it yourself before deciding whether to delete**. Explicitly ask the user which entries to clean up and which to keep.

## Step 3: Execute After User Confirmation

Execute only for projects the user has explicitly confirmed (see the confirmation requirements in Step 1):

```bash
docker compose -p <project-name> down -v   # stop and remove the project's containers, networks, and volumes
```

`-p` operates by project name and does not strictly depend on the original compose file still existing (Compose v2 can locate resources by label). But if the host's Compose version is older and the command fails because it cannot find the original compose file, delete manually using label filters instead:

```bash
docker ps -a --filter "label=com.docker.compose.project=<project-name>" -q | xargs -r docker rm -f
docker network ls --filter "label=com.docker.compose.project=<project-name>" -q | xargs -r docker network rm
docker volume ls --filter "label=com.docker.compose.project=<project-name>" -q | xargs -r docker volume rm
```

If the user additionally asks to clean up dangling networks no longer used by any container:

```bash
docker network prune
```

`docker network prune` reaches beyond this candidate list (it affects all dangling networks, not just this project's), so its confirmation bar must be higher than deletion by project name: **you must separately restate the affected scope ("this will remove all unused networks, not limited to this candidate list") and get the user's explicit confirmation for this operation itself before running it**. It must not be covered by a remark like "clean that up too while you're at it" attached to some other confirmation, and it must not be merged into one step with the per-project deletion above.

## Boundaries

- This skill does not judge "whether this project is still worth keeping" — it only does a mechanical directory-existence comparison; the value judgment is left to the user.
- Do not use this skill for projects that are still running and whose worktree directory still exists — those belong to the day-to-day start/stop scope of the `operate` skill.
