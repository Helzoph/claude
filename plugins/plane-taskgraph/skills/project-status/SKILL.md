---
name: project-status
description: "Give a read-only, whole-project overview of work in Plane in four columns — 等你决定 (items waiting on the user's decision, with each open choice quoted so they can all be answered in one reply), 等你确认 (risk:high items that are free to start and will pause for the user's go-ahead), 进行中 (started), and 被卡住 (open items waiting on an open blocker, with the blocker's identifier). Use whenever the user asks about a whole project rather than one item, module, or delivery — '项目现在什么情况', 'FMTLAB 怎么样了', '整体进度', '有什么要我决定的', '有什么在等我', 'what's going on in ABC', 'project status', 'what needs me'. Computed fresh from Labels, state, and blocked_by on every call; never writes to Plane and never saves the overview. Do NOT use for whether one module or delivery is done, for what to start next, or for doing an item (use pick-up-work), and do not answer the open choices here."
---

# Whole-Project Overview in Four Columns

The user wants one answer to "where does this project stand, and what needs me". Four columns cover it; everything is **computed on every call, never stored**, and nothing is written.

**Read-only.** This skill calls only `list`, `retrieve`, and `retrieve_by_identifier` style reads. It never changes state, Labels, or bodies, never posts a comment, and never writes the overview to a file or a Plane page. Reason: a saved overview goes stale the moment anything moves, and a stale one looks exactly like a correct one. If the user wants to act on what they see — answer an open choice, start an item — that goes through `pick-up-work`, which has the rules for it.

## The Four Columns

Each open, non-parent item goes into **at most one** column: test the rules in this order and stop at the first match.

| Order | Column | Rule |
|---|---|---|
| 1 | `等你决定` | carries `needs:decision` |
| 2 | `被卡住` | has at least one `blocked_by` target that is still open |
| 3 | `进行中` | its state group is `started` |
| 4 | `等你确认` | state group `backlog` or `unstarted`, carries `risk:high`, and every blocker is closed (rule 2 already failed) |

An item matching none of them (e.g. an unblocked `risk:medium` item nobody started) is not listed. Reason for the order: the user's decision blocks an item no matter what else is true, so it wins; a blocked item cannot start, so it must never be offered as "等你确认" — that is the misplacement this order exists to prevent.

**Excluded everywhere:** closed items (state group `completed` or `cancelled`) and parent items (items with children). Reason: a parent is not work (write-workitem, "Parent Items"); its children are listed on their own.

## Read Flow

1. **Project.** `project(action="list")` and match the name or identifier the user gave. If it matches none, or more than one, ask — do not guess.
2. **Label ids.** `label(action="list", project_id=...)`; note the ids of `needs:decision` and `risk:high`. A missing Label means no item carries it — the column is simply empty.
3. **Open set** — every open item in the project, used to judge blockers:
   `workitem(action="list", project_id=..., pql='stateGroup IN openStates()', fields='id,sequence_id,name,state_group,labels', per_page=100)`.
   Follow `next_cursor` while `next_page_results` is true.
4. **Candidates** — the same query with `AND NOT hasChildren()` appended. These are the items that can appear in a column. If the user named a Module or a delivery, narrow this query (`module = "<uuid>"` or `childOf("<PARENT-ID>")`), never the open set. Reason: a blocker can sit outside the narrowed scope; judged against a narrowed set, an open blocker reads as closed (same trap as pick-up-work, step 1a).
5. **Blockers** — for each candidate, `workitem_relation(action="list", workitem_id=...)` and read **only** `dependencies.blocked_by` (never `blocking`, never `custom`; see pick-up-work, step 3). A blocker is open iff its id is in the open set. A blocker in another project is in neither set: `workitem(action="retrieve_by_identifier", workitem_identifier=..., fields="state_group")`. These are one call per candidate and cannot be batched.
6. **Open choices** — for each item in `等你决定`, `workitem(action="retrieve", fields="description_html")` and take the `待定` block (from its `<h3[^>]*>待定</h3>` to the next `h3`) as written. If the Label is there but the block is missing, say so for that item instead of inventing choices.
7. **Classify** with the table above, then report.

## Report

Always all four columns, in this order — the order the user acts on them:

```
等你决定
- <ID> <title>
  <each 待定 entry verbatim: the question, the candidates, the lean>
等你确认
- <ID> <title>
进行中
- <ID> <title>
被卡住
- <ID> <title> — 卡在 <blocker ID>, <blocker ID>
```

- **An empty column is written as `无`**, never left out. Reason: a missing column cannot be told apart from a column that was forgotten.
- Quote each open choice as written so the user can answer all of them in one reply; do not restate, rank, or pick one.
- Identifiers as `<PROJECT>-<sequence_id>`. Under `被卡住`, list every open blocker, not just the first.
- After the columns, one line with the count of open items that are in no column (free to start, nobody needs to act), if any. Count only — no list. Reason: the four columns are what needs the user; "what to start next" is pick-up-work's answer.
- End by naming the next steps, without taking them: answer the open choices in the next reply, or ask to start an item.

Never save this report anywhere. If asked again later, compute it again.
