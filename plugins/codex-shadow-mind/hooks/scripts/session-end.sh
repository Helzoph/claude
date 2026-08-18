#!/bin/sh
# SessionEnd — release locks left behind by shadows that outlived the session.
#
# Codex allows this hook 1 second (3 at most), so it does the minimum: drop the
# slot locks. Reports and logs stay on disk for inspection.

# shellcheck source=./lib.sh
. "$(dirname -- "$0")/lib.sh"

sm_guard_recursion
sm_require_jq
sm_read_payload

rm -rf "$sm_state_dir"/slot.*.lock 2>/dev/null
exit 0
