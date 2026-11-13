#!/bin/bash
# UserPromptSubmit hook: when the user's message mentions a Plane work item
# identifier or asks what can start / how a project stands, add one sentence
# of context naming the skill that answers it. Never blocks, never rewrites.
#
# Rationale: with many plugins installed, Claude Code cuts the skill list to
# names only, and "XX-12 能开工吗" or "项目现在什么情况" is then answered from
# guesswork instead of through pick-up-work / project-status — skipping the
# blocked_by computation and the risk pauses. A hook runs whether or not the
# skill descriptions are visible.
#
# Rationale: it only adds a note. Deciding what the user meant is not
# mechanically certain, so the note says "if it is about a Plane item"; a
# guard that blocked on a guess would get switched off entirely.
#
# Rationale: false positives cost more than misses. A miss still has the skill
# description as a fallback; a false positive adds noise to every unrelated
# message. So identifier prefixes that are usually standards or algorithms
# (UTF-8, ISO-8601, SHA-256, RFC-7231, …) are excluded, and the phrase lists
# are narrow.

INPUT=$(cat)

# Rationale: fail open — a missing parser or bad input means "no note", never
# a blocked message.
command -v jq >/dev/null 2>&1 || exit 0

echo "$INPUT" | jq -r '
  def id_re: "(?<![A-Za-z0-9_-])([A-Z][A-Z0-9]{1,9})-[0-9]+(?![0-9])";
  def not_items: ["UTF","ISO","SHA","RFC","CVE","IEEE","ECMA","HTTP","TLS","SSL","AES","RSA","GPT","MD","ES","PEP","UCS","CP","KB","TS","IP","CJK"];
  def start_re: "能开工|可以开工|开工哪|先做哪|下一个做什么|接下来做什么|下一步做什么|what can (i|we) start|ready to start|what should (i|we) (work on|pick up) next";
  def status_re: "项目.{0,8}(情况|进度|状态|怎么样)|整体进度|有什么(要|需要|等)我(决定|确认|拍板)|有什么在等我|project status|what needs me|what.?s going on in";

  (.prompt // "") as $p
  | select($p | type == "string" and length > 0)
  | [ $p | scan(id_re) | .[0] ] as $prefixes
  | ([ $p | match(id_re; "g") | .string ] | unique) as $all_ids
  | [ $all_ids[] | select((split("-")[0]) as $pre | not_items | index($pre) | not) ] as $ids
  | ($p | test(start_re; "i")) as $asks_start
  | ($p | test(status_re; "i")) as $asks_status
  | [
      (if ($ids | length) > 0 or $asks_start then
        "plane-taskgraph: this message "
        + (if ($ids | length) > 0 then "mentions what looks like a Plane work item identifier (" + ($ids | join(", ")) + ")" else "asks what can be started" end)
        + ". If it is about Plane work — whether an item can start, doing it, or what to pick next — load the plane-taskgraph:pick-up-work skill before answering: it computes blocked_by and the risk pauses, which cannot be judged by eye."
      else empty end),
      (if $asks_status then
        "plane-taskgraph: this message asks how a project stands. If it is about a Plane project, load the plane-taskgraph:project-status skill before answering: it computes the four columns (等你决定 / 等你确认 / 进行中 / 被卡住) from Labels, state and blocked_by."
      else empty end)
    ] as $notes
  | select(($notes | length) > 0)
  | {hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: ($notes | join("\n") + "\nIf the message is not about Plane, ignore this note.")}}
  | tojson
' 2>/dev/null

exit 0
