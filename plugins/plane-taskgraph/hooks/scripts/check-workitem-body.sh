#!/bin/bash
# PreToolUse guard for the Plane `workitem` tool (create / update).
#
# Denies a body that would break read-back: whitespace between block tags,
# h3 blocks missing / renamed / out of order, or a body sent only as
# description_stripped. Warns (without blocking) when the title or body looks
# like it encodes a dependency in prose: a work item identifier or "第 N 步".
#
# Rationale: the skill states these rules, but edits made without loading the
# skill never see them. The hook is the one place that runs on every write.
# It only denies what is mechanically certain to break pick-up-work or the
# Plane editor; anything that needs judgment is a warning, because a guard
# that blocks too much gets switched off entirely.

INPUT=$(cat)

# Rationale: a missing parser must fail open. Blocking every Plane write
# because jq is absent is far worse than missing one format check.
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Rationale: any jq failure (malformed input, an unexpected shape) also fails
# open — `|| exit 0` turns a parse error into "no opinion".
echo "$INPUT" | jq -c '
  def required: ["为什么", "涉及范围", "风险", "完成标准", "验证"];
  def optional: ["不做", "回退", "注意"];
  def textof: gsub("<[^>]*>"; "") | gsub("&nbsp;"; " ");

  (.tool_input // {}) as $in
  | ($in.action // "") as $action
  | select($action == "create" or $action == "update")
  | ($in.description_html // "") as $html
  | ($in.description_stripped // "") as $stripped
  | ($in.name // "") as $name

  | ($html | textof | test("\\S")) as $has_body
  | [ $html | scan("<h3[^>]*>([\\s\\S]*?)</h3>") | .[0] | textof | gsub("^\\s+|\\s+$"; "") ] as $heads
  | ($heads[5:] | map(. as $h | optional | index($h))) as $opt_idx

  | [
      (if $html == "" and ($stripped | test("\\S")) then
        "The body was sent as description_stripped. Plane wraps it in plain paragraphs, so the h3 blocks never exist. Send it as description_html."
      else empty end),
      (if $has_body and (
            ($html | test(">\\s*\\n\\s*<"))
         or ($html | test("</?(h3|p|ul|ol|li|div)\\b[^>]*>\\s+<"))
         or ($html | test(">\\s+</?(h3|p|ul|ol|li|div)\\b"))
         ) then
        "description_html has whitespace or a newline between block tags. Plane stores it as text, and the next save from the web editor turns each gap into an empty bullet. Send the whole body as one line with nothing between a closing > and the next <."
      else empty end),
      (if $has_body and (
            ($heads[0:5] != required)
         or ($opt_idx | any(. == null))
         or ($opt_idx != ($opt_idx | unique))
         ) then
        "The h3 blocks are " + ($heads | tojson) + ". They must be exactly " + (required | tojson) + ", then only " + (optional | tojson) + " in that order, each name with no suffix. Convert the whole body to the template, keeping its content."
      else empty end)
    ] as $deny

  | ([$name, ($html | textof)] | join("\n")) as $all
  | [
      (if ($all | test("(?<![A-Za-z0-9_-])[A-Z][A-Z0-9]{1,9}-[0-9]+(?![0-9])")) then
        "The title or body mentions what looks like a work item identifier (" + ([$all | scan("(?<![A-Za-z0-9_-])[A-Z][A-Z0-9]{1,9}-[0-9]+(?![0-9])")] | unique | join(", ")) + ")"
      else empty end),
      (if ($all | test("第\\s*[0-9一二三四五六七八九十]+\\s*步")) then
        "The title or body numbers a step (第 N 步)"
      else empty end)
    ] as $warn

  | if ($deny | length) > 0 then
      {hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: ("Plane work item body rejected by plane-taskgraph:\n- " + ($deny | join("\n- ")) + "\nLoad the plane-taskgraph:write-workitem skill and follow its template and references/plane-html.md, then retry.")
      }}
    elif ($warn | length) > 0 then
      {hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: ("plane-taskgraph: " + ($warn | join("; ")) + ". If this expresses an order between items, it must be a blocked_by relation (workitem_relation create, relation_type=blocked_by, from the blocked item), not prose: remove it from the title/body and create the relation. If it is not a work item (e.g. UTF-8, ISO-8601), ignore this note. See write-workitem, \"Never Put These in the Title or Body\".")
      }}
    else empty end
' 2>/dev/null || exit 0

exit 0
