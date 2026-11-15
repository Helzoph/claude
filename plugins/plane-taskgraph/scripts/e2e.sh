#!/bin/bash
# Run one headless Claude Code session against this repository's copy of the
# plugin, then check the transcript with the four generic e2e assertions.
#
# Usage:
#   scripts/e2e.sh [--dry-run] <out.jsonl> <prompt> [extra claude args ...]
#   scripts/e2e.sh --check <out.jsonl>
#
# The session runs in the current directory: cd into the fixture repository
# first. Exit status is 0 only when every assertion passes.
#
# Environment:
#   E2E_SKILL_BUDGET     unset: SLASH_COMMAND_TOOL_CHAR_BUDGET=60000.
#                        "default": leave it unset (test with the budget a
#                        user with many plugins really has). A number: use it.
#   E2E_DISABLE_PLUGINS  comma-separated plugin@marketplace ids to disable in
#                        the child session (e.g. one whose Stop hook loops in
#                        the sandbox).
#   E2E_ALLOWED_TOOLS    replaces the default --allowedTools list.
#   E2E_MAX_BUDGET_USD   default 3.   E2E_MAX_TURNS   default 30.
#   E2E_UNSANDBOXED_OK   1: run even when no sandbox is detected (see below).
#   E2E_EXPECT_DENIALS   comma-separated denials the run must produce, each
#                        `tool` (any denial of that tool) or `tool:action`
#                        (e.g. mcp__claude_ai_plane__workitem:update). For an
#                        e2e that tests a hook's deny. Also read by --check.
#
# Sandbox: the default tool list grants unrestricted Bash to a child agent that
# reads untrusted Plane content. Inside a Claude Code sandboxed Bash the child
# inherits that sandbox (detected by SANDBOX_RUNTIME=1); in a plain terminal it
# does not, so the script refuses to start unless E2E_UNSANDBOXED_OK=1. The
# check guards against running it by accident, not against a forged variable.
#
# Rationale: every e2e needs the same flags and the same four assertions, and
# each one forgotten has cost a run that tested nothing (a skill that never
# fired because its description was cut, a cached marketplace copy loaded
# instead of the repo copy). Writing them once here is what stops that.

set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGIN_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
MANIFEST="$PLUGIN_DIR/.claude-plugin/plugin.json"

usage() {
  sed -n '5,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || { echo "e2e.sh: jq is required" >&2; exit 2; }
[ -f "$MANIFEST" ] || { echo "e2e.sh: no $MANIFEST" >&2; exit 2; }

PLUGIN_NAME=$(jq -r '.name' "$MANIFEST")
PLUGIN_VERSION=$(jq -r '.version' "$MANIFEST")

# --- assertions -------------------------------------------------------------

check() {
  local f=$1 fail=0
  [ -s "$f" ] || { echo "FAIL transcript: $f is missing or empty"; return 1; }

  # 1. The repo copy was loaded, not a cached marketplace install.
  local loaded
  loaded=$(jq -r --arg n "$PLUGIN_NAME" \
    'select(.type=="system" and .subtype=="init") | .plugins[]? | select(.name==$n) | .source + " " + (.version // "")' \
    "$f" 2>/dev/null | head -n 1)
  if [ "$loaded" = "$PLUGIN_NAME@inline $PLUGIN_VERSION" ]; then
    echo "PASS plugin: $loaded"
  else
    echo "FAIL plugin: expected '$PLUGIN_NAME@inline $PLUGIN_VERSION', got '${loaded:-<not loaded>}'"
    fail=1
  fi

  # 2. Which skills fired (reported; the V's own 预期 decides which must).
  local skills
  skills=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Skill") | .input.skill' \
    "$f" 2>/dev/null | paste -sd ' ' -)
  echo "INFO skills: ${skills:-<none>}"

  # 3. Which tools ran, with the skill or action for each.
  echo "INFO tools:"
  jq -c 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | [.name, (.input.skill // .input.action // null)]' \
    "$f" 2>/dev/null | sed 's/^/  /'

  # 4. How it ended. A denied tool makes the agent skip steps in a way that
  # looks exactly like correct behaviour, so a denial is a failure -- unless it
  # is declared in E2E_EXPECT_DENIALS. The match is two-way: every denial must
  # match a declared entry (else "unexpected"), and every entry must match a
  # denial (else "missing": the hook under test did not fire).
  local ending
  ending=$(jq -c --arg e "${E2E_EXPECT_DENIALS:-}" '
    select(.type=="result")
    | ($e | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))) as $exp
    | [(.permission_denials // [])[] | {t: .tool_name, a: (.tool_input.action // null | if . == null then null else tostring end)}] as $d
    | def hit($x): $x == .t or (.a != null and $x == (.t + ":" + .a));
      [.is_error, ($d | length), .num_turns, .total_cost_usd,
       [$d[] | . as $one | select(any($exp[]; . as $x | $one | hit($x)) | not) | [.t, .a]],
       [$exp[] | . as $x | select(any($d[]; hit($x)) | not)],
       $exp]' "$f" 2>/dev/null | tail -n 1)
  if [ -z "$ending" ]; then
    echo "FAIL ending: no result event (the run was cut off)"
    fail=1
  else
    local is_error denials unexpected missing
    is_error=$(jq -r '.[0]' <<<"$ending")
    denials=$(jq -r '.[1]' <<<"$ending")
    unexpected=$(jq -r '.[4] | length' <<<"$ending")
    missing=$(jq -r '.[5] | length' <<<"$ending")
    if [ "$is_error" = "false" ] && [ "$unexpected" = "0" ] && [ "$missing" = "0" ]; then
      echo "PASS ending: is_error=false permission_denials=$denials (turns, cost: $(jq -c '.[2:4]' <<<"$ending"))"
      [ "$denials" = "0" ] || echo "  expected: $(jq -c '.[6]' <<<"$ending")"
    else
      echo "FAIL ending: is_error=$is_error permission_denials=$denials"
      jq -c '.[4][]' <<<"$ending" | sed 's/^/  unexpected denied: /'
      jq -r '.[5][]' <<<"$ending" | sed 's/^/  missing expected denial: /'
      fail=1
    fi
  fi

  echo "--- reply"
  jq -r 'select(.type=="result") | .result // empty' "$f" 2>/dev/null | tail -n 40
  return $fail
}

# --- arguments --------------------------------------------------------------

DRY_RUN=0
case "${1:-}" in
  --check)
    [ $# -eq 2 ] || usage
    check "$2"; exit $? ;;
  --dry-run) DRY_RUN=1; shift ;;
  -h|--help|"") usage ;;
esac
[ $# -ge 2 ] || usage
OUT=$1; PROMPT=$2; shift 2

TOOLS=${E2E_ALLOWED_TOOLS:-"Skill,Read,Bash,Edit,Write,mcp__claude_ai_plane__workitem,mcp__claude_ai_plane__label,mcp__claude_ai_plane__module,mcp__claude_ai_plane__state,mcp__claude_ai_plane__project,mcp__claude_ai_plane__workitem_relation,mcp__claude_ai_plane__workitem_comment,mcp__claude_ai_plane__get_pql_reference"}

CMD=(claude -p "$PROMPT" --plugin-dir "$PLUGIN_DIR"
  --output-format stream-json --verbose
  --max-budget-usd "${E2E_MAX_BUDGET_USD:-3}" --max-turns "${E2E_MAX_TURNS:-30}"
  --allowedTools "$TOOLS")

if [ -n "${E2E_DISABLE_PLUGINS:-}" ]; then
  SETTINGS=$(jq -cn --arg ids "$E2E_DISABLE_PLUGINS" \
    '{enabledPlugins: ($ids | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)) | map({(.): false}) | add)}')
  CMD+=(--settings "$SETTINGS")
fi
CMD+=("$@")

# Rationale: with many plugins installed, the skill list is cut to names only
# and a skill under test may never fire; 60000 makes descriptions visible.
# "default" is for testing exactly that cut-down case.
ENV=()
case "${E2E_SKILL_BUDGET:-}" in
  default) ;;
  "") ENV+=(SLASH_COMMAND_TOOL_CHAR_BUDGET=60000) ;;
  *) ENV+=("SLASH_COMMAND_TOOL_CHAR_BUDGET=$E2E_SKILL_BUDGET") ;;
esac

SANDBOXED=no
[ "${SANDBOX_RUNTIME:-}" = "1" ] && SANDBOXED=yes
if [ $SANDBOXED = no ]; then
  if [ "${E2E_UNSANDBOXED_OK:-}" = "1" ]; then
    echo "e2e.sh: WARNING no sandbox detected; the child agent gets unrestricted Bash (E2E_UNSANDBOXED_OK=1)" >&2
  elif [ $DRY_RUN -eq 0 ]; then
    echo "e2e.sh: refusing to run: no sandbox detected (SANDBOX_RUNTIME is not 1)." >&2
    echo "  The child agent would get unrestricted Bash while reading untrusted Plane content." >&2
    echo "  Run it from a Claude Code session's sandboxed Bash, or set E2E_UNSANDBOXED_OK=1 to accept the risk." >&2
    exit 2
  fi
fi

if [ $DRY_RUN -eq 1 ]; then
  printf 'sandbox: %s\n' "$SANDBOXED"
  printf 'cwd: %s\n' "$PWD"
  printf 'env:'; [ ${#ENV[@]} -gt 0 ] && printf ' %q' "${ENV[@]}"; printf '\n'
  printf 'cmd:'; printf ' %q' "${CMD[@]}"; printf ' > %q\n' "$OUT"
  exit 0
fi

# macOS has no `timeout`; --max-budget-usd and --max-turns bound the run.
env "${ENV[@]+"${ENV[@]}"}" "${CMD[@]}" >"$OUT" 2>"$OUT.stderr"
echo "claude exit: $? (stderr in $OUT.stderr)"
check "$OUT"
