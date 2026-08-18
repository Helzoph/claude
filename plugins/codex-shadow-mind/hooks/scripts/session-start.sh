#!/bin/sh
# SessionStart — seed shadow definitions on first run and reset per-session state.
#
# State is keyed by session id, so a resumed session keeps its counters while a
# fresh one starts clean.

# shellcheck source=./lib.sh
. "$(dirname -- "$0")/lib.sh"

sm_guard_recursion
sm_require_jq
sm_read_payload
sm_init_state
sm_seed_shadows

source=$(printf '%s' "$SM_PAYLOAD" | jq -r '.source // "startup"' 2>/dev/null)
if [ "$source" = "startup" ] || [ "$source" = "clear" ]; then
  rm -f "$sm_state_dir/edit-count" "$sm_state_dir/last-digest" "$sm_state_dir/gate-used" 2>/dev/null
  rm -f "$sm_state_dir"/reports/*.md 2>/dev/null
  rm -rf "$sm_state_dir"/slot.*.lock "$sm_state_dir/count.lock" 2>/dev/null
fi

exit 0
