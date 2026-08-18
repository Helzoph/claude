#!/bin/sh
# PostToolUse (async) — decides whether this is a moment worth reviewing, and
# if so runs the eligible shadows against the recent transcript.
#
# This hook is declared `async: true`, so it never delays a tool call. Its
# findings are delivered by Codex at the next safe point.

# shellcheck source=./lib.sh
. "$(dirname -- "$0")/lib.sh"

sm_guard_recursion
sm_require_jq
sm_require_codex
sm_read_payload
sm_init_state
sm_seed_shadows

enabled=$(sm_config enabled true)
[ "$enabled" = "true" ] || exit 0

interval=$(sm_config_int heartbeat_interval 3)
max_parallel=$(sm_config_int max_parallel 2)
turns=$(sm_config_int transcript_turns 40)
timeout_default=$(sm_config_int timeout_seconds 120)
model=$(sm_config model "")

# --- heartbeat ------------------------------------------------------------
# Reviewing after every single edit is both expensive and useless: mid-refactor
# code is supposed to look broken. Counting edits and firing every Nth gives the
# main agent room to finish a coherent unit of work first.
count=$(sm_bump_counter) || exit 0
[ $((count % interval)) -eq 0 ] || exit 0

# --- transcript -----------------------------------------------------------
[ -n "$sm_transcript" ] || exit 0
transcript=$(sm_render_transcript "$sm_transcript" "$turns")
[ -n "$transcript" ] || exit 0

# Reviewing an unchanged transcript twice produces the same finding twice. The
# digest makes a round a no-op when nothing new has happened since the last one.
digest=$(printf '%s' "$transcript" | cksum | cut -d' ' -f1)
last_digest=$(cat "$sm_state_dir/last-digest" 2>/dev/null || printf '')
[ "$digest" = "$last_digest" ] && exit 0
printf '%s' "$digest" > "$sm_state_dir/last-digest"

shadow_dir=$(sm_shadow_dir)
[ -d "$shadow_dir" ] || exit 0

context_file="$sm_state_dir/context.txt"
{
  printf 'Working directory: %s\n' "$sm_cwd"
  printf 'Last tool: %s\n\n' "$sm_tool"
  printf 'Recent session transcript (reasoning removed, oldest first):\n\n'
  printf '%s\n' "$transcript"
} > "$context_file"

# --- dispatch -------------------------------------------------------------
for shadow in "$shadow_dir"/*.md; do
  [ -f "$shadow" ] || continue

  id=$(basename "$shadow" .md)
  case "$id" in .*) continue ;; esac

  [ "$(sm_shadow_field "$shadow" enabled true)" = "false" ] && continue

  # Each shadow fires on its own probability, so a session gets a varied mix of
  # reviewers over time instead of the same full panel on every heartbeat.
  probability=$(sm_shadow_field "$shadow" activation_probability 0.5)
  roll=$(awk -v p="$probability" 'BEGIN { srand(); print (rand() < p) ? "yes" : "no" }')
  [ "$roll" = "yes" ] || continue

  timeout_seconds=$(sm_shadow_field "$shadow" timeout_seconds "$timeout_default")
  case "$timeout_seconds" in ''|*[!0-9]*|0) timeout_seconds=$timeout_default ;; esac

  # No slot free means the parallel budget is already spent. Skipping is correct
  # here: this shadow will get another chance on the next heartbeat.
  # Stale threshold is the timeout rounded up to whole minutes plus one, so a
  # lock is only reclaimed well after its owner must have exited.
  stale_minutes=$(( timeout_seconds / 60 + 2 ))
  sm_acquire_slot "$max_parallel" "$stale_minutes" || break
  slot="$SM_SLOT"

  shadow_model=$(sm_shadow_field "$shadow" model "$model")
  instructions=$(sm_shadow_body "$shadow")
  report="$sm_state_dir/reports/$id.md"
  log="$sm_state_dir/logs/$id.log"

  prompt=$(
    printf '%s\n\n' "$instructions"
    printf -- '---\n\n'
    printf 'You are reviewing another agent that is working in this repository right now.\n'
    printf 'You are READ-ONLY: inspect files and run read-only commands, never edit anything.\n\n'
    printf 'Report only findings that are concrete, specific and actionable, and only if you\n'
    printf 'verified them against the actual repository. If you find nothing worth interrupting\n'
    printf 'the main agent for, reply with exactly: NO_FINDINGS\n\n'
    printf 'Otherwise reply with at most 3 findings as short bullet points, each naming the\n'
    printf 'file or symbol involved and what specifically is wrong.\n\n'
    printf -- '---\n\n'
    cat "$context_file"
  )

  model_args=""
  [ -n "$shadow_model" ] && model_args="--model $shadow_model"

  # `timeout` is a GNU coreutils program, not POSIX, and macOS ships without it
  # — which is where this plugin is developed. Relying on it alone silently
  # disables every per-shadow deadline on the most likely platform, so the
  # fallback is a watchdog we run ourselves.
  timeout_cmd=""
  if command -v timeout >/dev/null 2>&1; then
    timeout_cmd="timeout -k 5 $timeout_seconds"
  elif command -v gtimeout >/dev/null 2>&1; then
    timeout_cmd="gtimeout -k 5 $timeout_seconds"
  fi

  # The subprocess is the enforcement point for read-only review:
  #   --sandbox read-only         the OS refuses writes, not just the prompt
  #   --disable hooks             breaks the PostToolUse -> shadow -> PostToolUse loop
  #   --ephemeral                 keeps shadow chatter out of the user's session list
  #   CODEX_SHADOW_MIND=1         second layer of the same recursion guard
  #   </dev/null                  `codex exec` reads a prompt from stdin when one
  #                               is piped in, so an inherited open stdin makes
  #                               the shadow block until the watchdog kills it.
  #                               It happens to work today only because the hook
  #                               payload was already consumed to EOF.
  (
    # shellcheck disable=SC2086  # both *_args vars are deliberately word-split: empty means "no flag"
    CODEX_SHADOW_MIND=1 \
    $timeout_cmd codex exec \
      --sandbox read-only \
      --disable hooks \
      --ephemeral \
      --skip-git-repo-check \
      --color never \
      -C "$sm_cwd" \
      $model_args \
      -o "$report.tmp" \
      "$prompt" </dev/null >"$log" 2>&1 &
    shadow_pid=$!

    # Watchdog. It sleeps in short slices instead of one long `sleep` so that it
    # exits as soon as the shadow finishes — a single `sleep $timeout` would sit
    # there for the full deadline after every fast review, leaving stray
    # processes for as long as the session lasts.
    if [ -z "$timeout_cmd" ]; then
      (
        waited=0
        while [ "$waited" -lt "$timeout_seconds" ]; do
          kill -0 "$shadow_pid" 2>/dev/null || exit 0
          sleep 2
          waited=$((waited + 2))
        done
        kill "$shadow_pid" 2>/dev/null || :
        sleep 5
        kill -9 "$shadow_pid" 2>/dev/null || :
      ) &
      watchdog_pid=$!
    else
      watchdog_pid=""
    fi

    wait "$shadow_pid" 2>/dev/null

    # Killing the watchdog makes the shell announce the job as Terminated on
    # stderr, which Codex surfaces to the user as a hook warning. Disowning it
    # first keeps a routine cleanup from looking like a failure.
    if [ -n "$watchdog_pid" ]; then
      kill "$watchdog_pid" 2>/dev/null || :
      wait "$watchdog_pid" 2>/dev/null || :
    fi

    # A killed shadow leaves whatever partial text it had written; only a run
    # that finished with something to say should reach the main agent.
    if [ -s "$report.tmp" ] && ! grep -q 'NO_FINDINGS' "$report.tmp"; then
      mv "$report.tmp" "$report"
    else
      rm -f "$report.tmp" 2>/dev/null
    fi
    rm -rf "$slot" 2>/dev/null
  ) &
done

# The hook is async, so waiting costs the main agent nothing and keeps the
# process alive until every shadow has written its report.
wait
exit 0
