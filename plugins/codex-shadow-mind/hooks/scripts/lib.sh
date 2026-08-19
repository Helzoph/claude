#!/bin/sh
# Shared helpers for the codex-shadow-mind hooks.
#
# Every hook script sources this, reads the hook payload from stdin once, and
# then works off the sm_* variables and functions defined here. Written for
# POSIX sh because hooks run under /bin/sh with no guarantee about the user's
# login shell.

set -u

SM_PLUGIN_ROOT="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
if [ -z "$SM_PLUGIN_ROOT" ]; then
  # Fall back to walking up from this script so a hand-wired install still works.
  SM_PLUGIN_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
fi

SM_DATA_ROOT="${PLUGIN_DATA:-${CLAUDE_PLUGIN_DATA:-$HOME/.codex/shadow-mind}}"

# ---------------------------------------------------------------------------
# Hard guards
# ---------------------------------------------------------------------------

# A shadow is itself a Codex process. Without this, its own edits would fire the
# heartbeat and spawn shadows of shadows. The child is also launched with
# `--disable hooks`; this variable is the belt to that suspenders, and it also
# covers the case where a user runs a shadow prompt by hand.
sm_guard_recursion() {
  if [ "${CODEX_SHADOW_MIND:-}" = "1" ]; then
    exit 0
  fi
}

# Every script needs jq to read its own input. Without it we exit 0 silently:
# a review aid must never be the reason a coding session stops working.
sm_require_jq() {
  command -v jq >/dev/null 2>&1 || exit 0
}

sm_require_codex() {
  command -v codex >/dev/null 2>&1 || exit 0
}

# ---------------------------------------------------------------------------
# Hook payload
# ---------------------------------------------------------------------------

# Reads the hook JSON from stdin and exports the fields the scripts care about.
sm_read_payload() {
  SM_PAYLOAD=$(cat)
  [ -n "$SM_PAYLOAD" ] || exit 0

  # One parse, several fields. Anything that is not an object means a Codex
  # version whose payload we do not understand: leave the session alone rather
  # than acting on guesses, and stay quiet on stderr, which Codex surfaces.
  # tool_input is stringified rather than kept as JSON: it is only ever pattern
  # matched, and flattening it here keeps the tab-separated split below simple.
  # `gsub` strips the tabs and newlines that would otherwise break that split.
  _fields=$(printf '%s' "$SM_PAYLOAD" | jq -r '
    select(type == "object")
    | [.session_id // "unknown", .cwd // "", .transcript_path // "", .tool_name // "",
       ((.tool_input // "") | tostring | gsub("[\t\n\r]"; " "))]
    | @tsv' 2>/dev/null)
  [ -n "$_fields" ] || exit 0

  sm_session_id=$(printf '%s' "$_fields" | cut -f1)
  sm_cwd=$(printf '%s' "$_fields" | cut -f2)
  sm_transcript=$(printf '%s' "$_fields" | cut -f3)
  sm_tool=$(printf '%s' "$_fields" | cut -f4)
  sm_tool_input=$(printf '%s' "$_fields" | cut -f5)

  [ -n "$sm_cwd" ] || sm_cwd=$(pwd)

  # Session ids come from Codex, but they land in a path, so refuse anything
  # that could climb out of the state root.
  case "$sm_session_id" in
    */*|*..*|'') sm_session_id="unknown" ;;
  esac

  sm_state_dir="$SM_DATA_ROOT/sessions/$sm_session_id"
}

sm_init_state() {
  mkdir -p "$sm_state_dir/reports" "$sm_state_dir/logs" 2>/dev/null || exit 0
}

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

# Look-up order: env override, then the user's config file, then the default.
# The config file is deliberately flat `key=value` rather than JSON so a user
# can change the cadence without a parser in the loop.
sm_config() {
  _key=$1
  _default=$2
  _env_name="CODEX_SHADOW_MIND_$(printf '%s' "$_key" | tr '[:lower:]' '[:upper:]')"

  eval "_env_value=\${$_env_name:-}"
  if [ -n "$_env_value" ]; then
    printf '%s' "$_env_value"
    return
  fi

  _file="$SM_DATA_ROOT/config.env"
  if [ -f "$_file" ]; then
    _value=$(sed -n "s/^[[:space:]]*${_key}[[:space:]]*=[[:space:]]*//p" "$_file" | tail -n 1 | tr -d '"'"'"'')
    if [ -n "$_value" ]; then
      printf '%s' "$_value"
      return
    fi
  fi

  printf '%s' "$_default"
}

# Same lookup, but a non-numeric or non-positive value falls back to the default
# instead of propagating into arithmetic that would abort the script under set -u.
sm_config_int() {
  _raw=$(sm_config "$1" "$2")
  case "$_raw" in
    ''|*[!0-9]*) printf '%s' "$2" ;;
    0) printf '%s' "$2" ;;
    *) printf '%s' "$_raw" ;;
  esac
}

# Shadow definitions live in the user's data dir so they survive plugin
# upgrades; the plugin's own `shadows/` is only the seed copied in on first run.
sm_shadow_dir() {
  printf '%s' "$SM_DATA_ROOT/shadows"
}

sm_seed_shadows() {
  _dir=$(sm_shadow_dir)
  [ -d "$_dir" ] && return 0
  mkdir -p "$_dir" 2>/dev/null || return 1
  if [ -d "$SM_PLUGIN_ROOT/shadows" ]; then
    for _f in "$SM_PLUGIN_ROOT"/shadows/*.md; do
      [ -f "$_f" ] || continue
      cp "$_f" "$_dir/" 2>/dev/null || :
    done
  fi
}

# ---------------------------------------------------------------------------
# Shadow definition parsing
# ---------------------------------------------------------------------------

# Reads one `key: value` pair out of the front matter of a shadow file.
sm_shadow_field() {
  _file=$1
  _key=$2
  _default=$3
  _value=$(awk -v key="$_key" '
    NR == 1 && $0 == "---" { inside = 1; next }
    inside && $0 == "---" { exit }
    inside {
      pos = index($0, ":")
      if (pos == 0) next
      k = substr($0, 1, pos - 1)
      v = substr($0, pos + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", k)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      gsub(/^["'"'"']|["'"'"']$/, "", v)
      if (k == key) { print v; exit }
    }
  ' "$_file" 2>/dev/null)
  if [ -n "$_value" ]; then printf '%s' "$_value"; else printf '%s' "$_default"; fi
}

# Everything after the front matter is the reviewer's own instructions.
sm_shadow_body() {
  awk '
    NR == 1 && $0 == "---" { inside = 1; next }
    inside && $0 == "---" { inside = 0; started = 1; next }
    !inside { if (started || NR == 1) print }
  ' "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Transcript rendering
# ---------------------------------------------------------------------------

# Renders the tail of the rollout file as plain text: user and assistant
# messages plus tool calls and their output, with reasoning stripped. The
# shadow reviews what actually happened, not what the main agent was thinking
# about doing — chain-of-thought is both noisy and misleading as evidence.
sm_render_transcript() {
  _path=$1
  _turns=$2
  [ -f "$_path" ] || return 1

  tail -n 400 "$_path" | jq -r --argjson keep "$_turns" '
    select(.type == "response_item")
    | .payload
    | if .type == "message" then
        (.content // [] | map(.text // .output_text // "") | join("\n")) as $t
        | select($t | length > 0)
        | select(.role != "developer")
        | "[" + (.role // "?") + "] " + ($t[0:1500])
      elif .type == "function_call" or .type == "custom_tool_call" then
        "[tool " + (.name // "?") + "] " + ((.arguments // .input // "" | tostring)[0:1200])
      elif .type == "function_call_output" or .type == "custom_tool_call_output" then
        "[output] " + ((.output // "" | tostring)[0:1200])
      else empty end
  ' 2>/dev/null | tail -n "$_turns"
}

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

# Emits the JSON shape Codex reads on stdout. Text goes in as developer
# context, which is what makes a finding actionable rather than decorative.
sm_emit_context() {
  jq -n --arg ctx "$1" '{hookSpecificOutput: {additionalContext: $ctx}}'
}

sm_emit_block() {
  jq -n --arg reason "$1" '{decision: "block", reason: $reason}'
}

# ---------------------------------------------------------------------------
# Write detection
# ---------------------------------------------------------------------------

# True when this tool call actually changed something in the repository.
#
# The matcher cannot make this call. Codex 0.147 routes nearly every operation
# through one `exec` tool, so `tool_name` is the same string whether the agent
# is patching a file or paging through one — and on a real session 82% of those
# calls turn out to be pure reads. Counting them all would fire the heartbeat
# roughly every third `sed -n`, burning a full review's worth of tokens on
# nothing having changed. Raising the interval would only dilute that; it would
# still spend reviews during a long stretch of pure browsing.
#
# The check is deliberately shaped to fail toward "read": a missed write just
# means the review happens one edit later, whereas a false positive spends a
# whole shadow run on unchanged code. Validated against 1597 real `exec` calls
# from this machine's session history — no false positives, and the only misses
# (`curl -o /tmp/...`, `docker compose up`) change no source file, which is the
# only thing a shadow reviews.
sm_is_write() {
  # apply_patch is Codex's file-editing tool. Its presence is unambiguous.
  case "$1" in *apply_patch*) return 0 ;; esac

  # Everything else is a shell command, but the payload wrapping it is JS source
  # — so the command has to be extracted before matching. Searching the raw
  # payload reads arrow functions (`=>`) and escaped newlines (`\n`) as output
  # redirection and reports most read-only calls as writes.
  _cmds=$(printf '%s' "$1" | sed -n 's/.*"cmd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  [ -n "$_cmds" ] || return 1

  # Redirection (`>`) is deliberately absent from this list. It is the strongest
  # write signal in a plain shell, and the noisiest one here: heredocs and
  # escape sequences inside the JS wrapper trip it constantly. Explicit commands
  # cover the same ground without the false positives.
  printf '%s' "$_cmds" | grep -qE \
    '(^|[;&|(]|[[:space:]])(mv|cp|rm|rmdir|mkdir|touch|chmod|chown|ln|dd|truncate)[[:space:]]|(^|[;&|(]|[[:space:]])(sed|perl|ruby)[[:space:]]+-[a-zA-Z]*i[[:space:]]|(^|[;&|(]|[[:space:]])tee[[:space:]]|(^|[;&|(]|[[:space:]])git[[:space:]]+(add|commit|apply|checkout|restore|rm|mv|merge|rebase|reset|stash|push|pull|clean|init)|(^|[;&|(]|[[:space:]])(npm|pnpm|yarn|bun|cargo|go|pip|uv)[[:space:]]+(install|add|remove|uninstall|init|new|update|upgrade)'
}

# ---------------------------------------------------------------------------
# Concurrency
# ---------------------------------------------------------------------------

# mkdir is atomic on every POSIX filesystem, which makes it the portable lock.
# Slots cap how many shadows can burn tokens at once; a heartbeat that finds
# every slot taken simply skips its round rather than queueing.
#
# Sets SM_SLOT to the acquired lock path. The caller is responsible for removing
# it — in practice the subshell that owns the shadow process does so, since only
# it knows when its child has exited.
# Increments the heartbeat counter and prints the new value.
#
# This looks like it could be a plain read-add-write, and it cannot: the hook is
# async, so a heartbeat that is off dispatching shadows for half a minute is
# still running when the next edits fire their own hooks. Those overlap, and an
# unlocked counter lets the slow one write back the value it read at the start —
# the counter goes *backwards* and the heartbeat silently stops firing.
#
# The lock covers only the read-modify-write, never the dispatch that follows;
# holding it across the slow part would just make the fast callers time out and
# lose their increments by a different route.
sm_bump_counter() {
  _file="$sm_state_dir/edit-count"
  _lock="$sm_state_dir/count.lock"
  _tries=0

  while [ "$_tries" -lt 50 ]; do
    # Reclaim a lock orphaned by a killed hook. One minute is far longer than
    # the few milliseconds this critical section actually takes.
    if [ -d "$_lock" ] && [ -z "$(find "$_lock" -maxdepth 0 -mmin -1 2>/dev/null)" ]; then
      rm -rf "$_lock" 2>/dev/null || :
    fi
    if mkdir "$_lock" 2>/dev/null; then
      _count=$(cat "$_file" 2>/dev/null || printf '0')
      case "$_count" in *[!0-9]*|'') _count=0 ;; esac
      _count=$((_count + 1))
      printf '%s' "$_count" > "$_file"
      rmdir "$_lock" 2>/dev/null || :
      printf '%s' "$_count"
      return 0
    fi
    sleep 0.02 2>/dev/null || sleep 1
    _tries=$((_tries + 1))
  done

  # Contended past the retry budget. Skipping this round is the safe failure:
  # a missed review beats a wrong count that stalls every future heartbeat.
  return 1
}

sm_acquire_slot() {
  _max=$1
  _stale_minutes=$2
  _i=1
  while [ "$_i" -le "$_max" ]; do
    _lock="$sm_state_dir/slot.$_i.lock"
    # Reap a slot whose owner died without releasing it. Age is the honest
    # signal here: a lock older than the longest a shadow may run cannot still
    # belong to a live one, whereas a recorded pid can be recycled by the OS.
    # `-mmin` rather than `-newermt`, which is a GNU extension.
    if [ -d "$_lock" ] && [ -z "$(find "$_lock" -maxdepth 0 -mmin "-${_stale_minutes}" 2>/dev/null)" ]; then
      rm -rf "$_lock" 2>/dev/null || :
    fi
    if mkdir "$_lock" 2>/dev/null; then
      SM_SLOT="$_lock"
      return 0
    fi
    _i=$((_i + 1))
  done
  return 1
}
