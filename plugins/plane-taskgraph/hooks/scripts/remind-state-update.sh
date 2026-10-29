#!/bin/bash
# Stop hook: if this turn committed work for a Plane item (a `Refs: <ITEM-ID>`
# trailer in a `git commit` command) but did not afterwards post a comment and
# change that item's state, block the stop once and say what is missing.
#
# Rationale: the most common failure after doing an item is that the code is
# committed and the turn ends with Plane still saying `backlog`. The skill says
# to mark done, but it is the last step of a long turn and gets dropped. A
# trailer in a commit is the one mechanical sign that item work happened.
#
# It blocks at most once per stop (`stop_hook_active`), and only looks at the
# current turn, so a deliberate "leave it open" (a failed gate, a risk:high
# item waiting for confirmation) costs one sentence of explanation, not a loop.

INPUT=$(cat)

# Rationale: fail open. A missing parser must never stop the agent from ending
# its turn.
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$ACTIVE" = "true" ] && exit 0

TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

# Rationale: `fromjson?` skips a line that is not valid JSON (e.g. one being
# written right now) instead of failing the whole read.
jq -nR -c '
  def is_human_turn:
    .type == "user" and (.isMeta != true) and (
      (.message.content | type) == "string"
      or ([.message.content[]? | select(.type == "text")] | length) > 0
    );
  def trailer_re: "Refs:[ \\t]*[A-Z][A-Z0-9]*-[0-9]+";

  [inputs | fromjson?] as $lines
  | ([$lines | to_entries[] | select(.value | is_human_turn) | .key] | last // -1) as $turn_start
  | [ $lines[($turn_start + 1):][]
      | select(.type == "assistant")
      | .message.content[]?
      | select(.type == "tool_use")
      | {name, input} ] as $uses
  | [ $uses | to_entries[]
      | select(.value.name == "Bash"
               and ((.value.input.command // "") | test("git\\s+commit"))
               and ((.value.input.command // "") | test(trailer_re)))
      | .key ] as $commits
  | select(($commits | length) > 0)
  | ($commits | last) as $last
  | ([ $uses[$commits[]].input.command | scan(trailer_re) | sub("Refs:[ \\t]*"; "") ] | unique) as $ids
  | $uses[($last + 1):] as $after
  | ($after | any((.name | test("__workitem$")) and .input.action == "update" and ((.input.state // "") != ""))) as $state_done
  | ($after | any((.name | test("__workitem_comment$")) and .input.action == "create")) as $record_done
  | select(($state_done and $record_done) | not)
  | {
      decision: "block",
      reason: ("plane-taskgraph: this turn committed work for " + ($ids | join(", ")) + " (Refs trailer), but after the last such commit "
        + ([ (if $record_done then empty else "no verification-record comment was posted" end),
             (if $state_done then empty else "no work item state was changed" end) ] | join(" and "))
        + ". Follow plane-taskgraph:pick-up-work steps 5-8: post the record, move the item to a completed-group state, and read it back with list. If the item deliberately stays open (a gate condition failed, or a risk:high item is waiting for confirmation), say so to the user in one line and stop.")
    }
' "$TRANSCRIPT" 2>/dev/null || exit 0

exit 0
