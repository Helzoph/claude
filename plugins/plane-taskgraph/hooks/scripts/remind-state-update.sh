#!/bin/bash
# Stop hook: if this turn committed work for a Plane item (a commit in the
# session's repository, made since the turn started, whose message has a
# `Refs: <ITEM-ID>` line) but did not afterwards post a comment and change
# that item's state, block the stop once and say what is missing.
#
# Rationale: the most common failure after doing an item is that the code is
# committed and the turn ends with Plane still saying `backlog`. The skill says
# to mark done, but it is the last step of a long turn and gets dropped. A
# trailer in a commit is the one mechanical sign that item work happened.
#
# Rationale: the commit is looked up in git, not in the text of Bash commands.
# Matching command text fired on any command that merely contained
# `git commit ... Refs: X-1` (a `claude -p` prompt, an echo, a heredoc) and
# missed `git commit -F <file>`, whose trailer is not in the command at all.
#
# It blocks at most once per stop (`stop_hook_active`), and only looks at the
# current turn, so a deliberate "leave it open" (a failed gate, a risk:high
# item waiting for confirmation) costs one sentence of explanation, not a loop.

INPUT=$(cat)

# Rationale: fail open. A missing tool must never stop the agent from ending
# its turn.
command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$ACTIVE" = "true" ] && exit 0

TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

# Rationale: only the session's working directory is checked. A commit made
# after `cd` into another repository is not seen; scanning every repository
# the turn touched would mean parsing shell again.
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] && [ -d "$CWD" ] || exit 0

# Turn start = timestamp of the last line a human typed (not a meta line such
# as a hook's own feedback), as whole epoch seconds.
# Rationale: `fromjson?` skips a line that is not valid JSON (e.g. one being
# written right now) instead of failing the whole read.
TURN_START=$(jq -nR -r '
  def epoch: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
  def is_human_turn:
    .type == "user" and (.isMeta != true) and (.timestamp != null) and (
      (.message.content | type) == "string"
      or ([.message.content[]? | select(.type == "text")] | length) > 0
    );
  [inputs | fromjson? | select(is_human_turn) | .timestamp] | last // empty | epoch
' "$TRANSCRIPT" 2>/dev/null)
[ -n "$TURN_START" ] || exit 0

# Rationale: the same whole-line `^Refs: <ID>$` form `changed-files.sh`
# greps for, so a commit this hook counts is one the record will list.
COMMITS=$(git -C "$CWD" log --since="@$TURN_START" -E \
  --grep='^Refs: [A-Z][A-Z0-9]*-[0-9]+$' \
  --format='%ct%x1f%B%x1e' 2>/dev/null) || exit 0
[ -n "$COMMITS" ] || exit 0

jq -nR -c --arg commits "$COMMITS" '
  def epoch: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
  def id_re: "^Refs: [A-Z][A-Z0-9]*-[0-9]+$";

  [ $commits | split("\u001e")[] | ltrimstr("\n") | select(length > 0)
    | split("\u001f")
    | { ct: (.[0] | tonumber),
        ids: [ (.[1] // "") | split("\n")[] | select(test(id_re)) | sub("^Refs: "; "") ] } ] as $list
  | select(($list | length) > 0)
  | ([$list[].ct] | max) as $last
  | ([$list[].ids[]] | unique) as $ids
  # Rationale: transcript time and commit time are compared in whole seconds,
  # so a call in the same second as the last commit counts as after it.
  | [ inputs | fromjson?
      | select(.type == "assistant" and .timestamp != null)
      | select((.timestamp | epoch) >= $last)
      | .message.content[]?
      | select(.type == "tool_use")
      | {name, input} ] as $after
  | ($after | any((.name | test("__workitem$")) and .input.action == "update" and ((.input.state // "") != ""))) as $state_done
  | ($after | any((.name | test("__workitem_comment$")) and .input.action == "create")) as $record_done
  | select(($state_done and $record_done) | not)
  | {
      decision: "block",
      reason: ("plane-taskgraph: this turn committed work for " + ($ids | join(", ")) + " (commits with a Refs trailer since the turn started), but after the last such commit "
        + ([ (if $record_done then empty else "no verification-record comment was posted" end),
             (if $state_done then empty else "no work item state was changed" end) ] | join(" and "))
        + ". Follow plane-taskgraph:pick-up-work steps 5-8: post the record, move the item to a completed-group state, and read it back with list. If the item deliberately stays open (a gate condition failed, or a risk:high item is waiting for confirmation), say so to the user in one line and stop.")
    }
' "$TRANSCRIPT" 2>/dev/null || exit 0

exit 0
