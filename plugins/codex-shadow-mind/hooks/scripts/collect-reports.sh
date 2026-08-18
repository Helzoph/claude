#!/bin/sh
# Stop — the end-of-turn gate.
#
# Anything the shadows found during the turn is delivered here. Findings that
# arrived while the agent was still working are easy to skim past; at the moment
# it declares itself done, they are exactly the thing that decides whether it
# actually is.

# shellcheck source=./lib.sh
. "$(dirname -- "$0")/lib.sh"

sm_guard_recursion
sm_require_jq
sm_read_payload

[ -d "$sm_state_dir/reports" ] || exit 0

reports=$(find "$sm_state_dir/reports" -name '*.md' -type f 2>/dev/null | sort)
[ -n "$reports" ] || exit 0

body=""
for report in $reports; do
  [ -s "$report" ] || continue
  id=$(basename "$report" .md)
  body="${body}### ${id}
$(cat "$report")

"
done

if [ -z "$body" ]; then
  rm -f "$sm_state_dir"/reports/*.md 2>/dev/null
  exit 0
fi

# Reports are consumed, not accumulated: leaving them in place would replay the
# same findings at the end of every subsequent turn.
rm -f "$sm_state_dir"/reports/*.md 2>/dev/null

mode=$(sm_config stop_mode block)

message="Shadow mind reports from this turn (parallel read-only reviewers):

${body}Address these findings, or state explicitly why each one does not apply, before finishing."

if [ "$mode" = "notify" ]; then
  sm_emit_context "$message"
  exit 0
fi

# `decision: block` sends Codex back to work. A shadow can be wrong, and a
# reviewer that can restart the turn indefinitely is a hang, so the gate fires
# at most once per session and then degrades to plain notification.
gate="$sm_state_dir/gate-used"
if [ -f "$gate" ]; then
  sm_emit_context "$message"
  exit 0
fi
: > "$gate"
sm_emit_block "$message"
exit 0
