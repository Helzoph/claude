#!/bin/bash
# Block direct node_modules/.bin/ invocations.
# Prefer: system-installed commands > pnpm exec/npx/bunx

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

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
