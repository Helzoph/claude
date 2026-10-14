#!/usr/bin/env bash
# Prod guard. Written rules (CLAUDE.md and the like) rely on the agent's self-discipline; this one does not.
#
# ── The criterion is the directory name, not the branch name, not an env var ──
# A checkout can change the branch, but not the directory. And Docker Compose
# derives the project name from the directory name by default, so container and
# volume names carry that prefix — the directory name is already the factual
# criterion for "which data set this command will touch". Introducing a second
# criterion (ENV=prod, branch name) creates states where "one place says this is
# UAT and another says prod", and this kind of inconsistency surfaces exactly at
# the most dangerous moment.
#
# ── Only block operations that are irreversible and have no undo ──────────────
# The more it blocks, the more likely it gets switched off entirely. So there are
# only three hard blocks + one soft confirmation here; comprehensive protection
# is not the goal. A different phrasing (`docker rm -v`, deleting
# /var/lib/docker/volumes/ by hand) still gets around it — the real backstop is
# still "do not experiment in the prod directory".
#
# Placeholders are filled in by the env-tiers/setup-tiers skill:
#   __PROD_DIR__      the prod directory name (directory name, not a path)
#   __DATA_VOLUME__   the volume name declared in compose; the actual volume name is <PROD_DIR>_<DATA_VOLUME>
#   __PROD_OVERRIDE__ the compose override file name prod must always include
#   __UAT_DIR__       the UAT directory name, used only in message text
set -uo pipefail

PROD_DIR="__PROD_DIR__"
DATA_VOLUME="__DATA_VOLUME__"
PROD_OVERRIDE="__PROD_OVERRIDE__"
UAT_DIR="__UAT_DIR__"

FULL_VOLUME="${PROD_DIR}_${DATA_VOLUME}"

INPUT=$(cat)

# Without python3 both variables are empty, and an empty CMD below means allow —
# fail-open is deliberate: if a guard that cannot parse its input were made
# fail-closed, it would block every Bash call in this project, and the inevitable
# result is someone switching the hook off outright, losing the three hard blocks
# along with it.
CWD=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("cwd",""))' 2>/dev/null || echo "")
CMD=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || echo "")

[ -z "$CMD" ] && exit 0

# ── Is this command aimed at prod ─────────────────────────────────────────────
#
# Primary criterion: the session's directory name equals PROD_DIR. Worktree
# directory names all differ, so they are excluded by construction, with no need
# for an extra path-prefix exception.
#
# Secondary criterion: the cwd the hook receives is the session's working
# directory, not the directory where the command actually runs.
# `cd ../<PROD_DIR> && docker compose down -v` would pass the primary criterion
# with a harmless cwd. So when the command text contains a `cd` into that
# directory, it is treated as prod as well. The cost is an occasional false
# positive (e.g. `cd ../<PROD_DIR> && git log` in UAT), and a false positive just
# costs one extra block, so the direction is safe.
in_prod=0
[ "$(basename "$CWD")" = "$PROD_DIR" ] && in_prod=1
printf '%s' "$CMD" | grep -qE "\bcd[[:space:]]+[^[:space:];&|]*/?${PROD_DIR}(/|[[:space:]]|$)" && in_prod=1

[ "$in_prod" -eq 0 ] && exit 0

# ── Hard blocks: would wipe real data, with no undo ───────────────────────────

# compose down with -v/--volumes
if printf '%s' "$CMD" | grep -qE 'docker[[:space:]]+compose\b' \
   && printf '%s' "$CMD" | grep -qE '\bdown\b' \
   && printf '%s' "$CMD" | grep -qE '(^|[[:space:]])(-v|--volumes)([[:space:]]|$)'; then
  cat >&2 <<MSG
Blocked: this is the prod directory, and \`down -v\` would delete ${FULL_VOLUME} — real data.
Recovery can only roll back to the last backup; writes since then cannot be recovered from anywhere else.

To restart prod, use:
  just up
To wipe data for an experiment, go to ${UAT_DIR}/.
MSG
  exit 2
fi

# Deleting/pruning volumes directly. prune does not take a project name and takes
# every unused volume on this machine with it.
if printf '%s' "$CMD" | grep -qE 'docker[[:space:]]+volume[[:space:]]+(rm|prune)'; then
  cat >&2 <<MSG
Blocked: ${FULL_VOLUME} is prod's real data; deleting it means rolling back to the last backup.
If you really need to delete it, run it yourself in a terminal, not through the agent.
MSG
  exit 2
fi

# git clean -x deletes gitignored files too — credential files and local backup
# directories are usually exactly the gitignored ones, so in clean's eyes they are
# "unowned files", yet they are precisely what can least be lost.
if printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]+clean\b' \
   && printf '%s' "$CMD" | grep -qE '[[:space:]]-[a-zA-Z]*[xX]'; then
  cat >&2 <<'MSG'
Blocked: `git clean -x` deletes gitignored files — credentials and local database snapshots
usually fall into this category; in clean's eyes they are unowned files, yet they are the only copy.
MSG
  exit 2
fi

# ── Soft confirmation: would silently revert prod to the dev config ───────────
#
# `up` without the override makes compose read only the base file, so the source
# bind mount comes back, and during a later `git merge` the frontend and backend
# hot-reload back and forth between half-new, half-old code. This mistake does not
# destroy data, but it is silent — the containers still start, the page still
# opens. So ask, rather than hard-block.
if printf '%s' "$CMD" | grep -qE 'docker[[:space:]]+compose\b' \
   && printf '%s' "$CMD" | grep -qE '\b(up|restart)\b' \
   && ! printf '%s' "$CMD" | grep -q "$PROD_OVERRIDE"; then
  PROD_OVERRIDE="$PROD_OVERRIDE" python3 - <<'PY'
import json, os
override = os.environ["PROD_OVERRIDE"]
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": (
        f"This is the prod directory, but {override} is not included. Starting this way reverts to the dev config — the source bind mount "
        "comes back, and a later git merge will make services hot-reload back and forth between half-new, half-old code. Start it this way anyway?\n"
        f"  prod: docker compose -f docker-compose.yml -f {override} up -d --build"
    ),
}}))
PY
  exit 0
fi

exit 0
