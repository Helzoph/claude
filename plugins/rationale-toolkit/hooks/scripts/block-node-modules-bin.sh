#!/bin/bash
# Block direct node_modules/.bin/ invocations.
# Prefer: system-installed commands > pnpm exec / npx / bunx
#
# Rationale: node_modules/.bin/<tool> hardcodes one package manager's layout
# (pnpm's store is not flat, Yarn PnP has no .bin at all) and silently picks a
# vendored version over a newer system one. Routing through the runner keeps the
# call portable across package managers.

INPUT=$(cat)

# Rationale: this hook ships to machines that may not have jq. A missing
# dependency must fail open — blocking every Bash call because a parser is
# absent is far worse than missing one guard.
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if echo "$COMMAND" | grep -qE 'node_modules/\.bin/'; then
  # Extract the binary name from the path
  BIN_NAME=$(echo "$COMMAND" | grep -oE 'node_modules/\.bin/[^ ]+' | head -1 | sed 's|node_modules/\.bin/||')

  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: direct node_modules/.bin/ invocation not allowed. Priority: 1) system-installed '${BIN_NAME}' if available (check with 'which ${BIN_NAME}'), 2) pnpm exec / npx / bunx. Rewrite and retry."
  }
}
EOF
  exit 0
fi

exit 0
