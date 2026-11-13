---
name: pick-up-work
description: "Answer or act on any request about work already in Plane — what can start now, doing an item, changing an item's state or marking it done ('把 ABC-12 标完成', 'close ABC-12'), or status questions ('is the X module done?', 'X 模块做完了吗', 'X 的进度', 'is the login delivery done?') — instead of calling the Plane tools directly. Reads a task graph back from Plane and computes which work items can start right now, by checking whether each item's blocked_by dependencies are all done and setting aside items that wait on a user decision (needs:decision); then do an item — read its body (current h3 or old strong-heading format), move it to a started state before the first edit, stop on open choices (needs:decision or a 待定 block) and ask the user, pause for a brief confirmation on risk:high, commit with a `Refs: <ITEM-ID>` trailer, post a verification-record comment whose changed-files block is generated from git by a bundled script, and only then mark it done and read the state back, keeping the item's parent (its delivery) in step. Use this skill when picking up work already recorded in Plane — triggers on 'implement the xxx feature', 'do ABC-12', 'what can I work on next', 'what's unblocked', 'I finished ABC-12', 'ABC-12 做完了', and whenever code was just committed for an item that Plane still shows as not done. The Plane MCP server ships with this plugin but needs a one-time `claude mcp login plane`. Do NOT use for writing a new plan into Plane (use plan-to-plane) or for writing an item body (use write-workitem)."
---

# Read the Task Graph Back From Plane and Compute What Can Start Now

**The parallel set is always computed, never stored**, and it cannot be judged by eyeballing the dependency graph — items with multiple blockers are where people most easily miss things.

Definition: the items that are **not done, and whose every `blocked_by` target is done**.

## Read-Back Flow

### 1. Fetch Unfinished Items (2 Calls)

**1a. The open set** — every unfinished item in the project, ids only:

```
workitem(action="list", project_id=..., pql='stateGroup IN openStates()',
  fields='id', per_page=100)
```

Follow `next_cursor` while `next_page_results` is true. Step 4 judges blockers against this set, not against the candidate set below. Reason: a blocker can sit in another Module or another delivery; judged against a candidate set narrowed to one Module, an open blocker elsewhere is simply absent and reads as done, and the item it blocks is offered as ready.

**1b. The candidate set** — the unfinished work in the scope asked about:

```
workitem(action="list", project_id=...,
  pql='module = "<module-uuid>" AND stateGroup IN openStates() AND NOT hasChildren()',
  fields='id,sequence_id,name,state_group,parent,labels')
```

PQL merges "list everything", "exclude finished", and "exclude parents" into one call; what comes back is the candidate set. To read one delivery instead of one Module, replace the `module = …` condition with `childOf("<PARENT-ID>")`.

`NOT hasChildren()` is required. A parent item (write-workitem, "Parent Items") has no `blocked_by` of its own, so without the filter it is always computed as ready to start — and it is not work. Parents are normally not attached to Modules, but one attached by hand would still slip in without this condition.

Always pass `fields`. Without trimming, every item carries its full description, thousands of characters; trimmed to these fields it is a few lines.

### 2. Fetch Dependencies One by One (M Calls, M = Number of Results From the Previous Step)

```
workitem_relation(action="list", workitem_id=...)
```

**Dependencies cannot be fetched in bulk** — `expand=issue_relation` does not work; the response has no relation fields. This is a hard floor: M unfinished items means M calls. A module with 20 items takes about 20 calls per read, which takes a while.

If a module has so many items that one read is clearly a strain, the fix is not to optimize the read but to split the module — the user cannot direct a module of dozens of tasks with a single "implement xxx for me" either.

### 3. Read Only `dependencies.blocked_by`

The response has two buckets:

```
{ dependencies: { blocking: [...], blocked_by: [...], start_before: [...], ... },
  custom:       { "relates to": [...], duplicate: [...], ... } }
```

**Read only `dependencies.blocked_by` and ignore everything else — this is an allowlist, not a denylist.**

- The `custom` bucket holds custom relations, whose labels can be anything. Written as a denylist ("exclude relates to, treat the rest as blocking"), any custom relation definition anyone creates later is silently treated as blocking, and the whole computation becomes invalid without any error.
- **The `blocking` bucket must never be counted.** It is the reverse edge Plane generates automatically — after A `blocked_by` B, B shows `blocking: [A]`. Treat it as a dependency and the direction is reversed entirely.

### 4. Determine Whether Each Blocker Is Done

Step 1a holds every unfinished item in the project, so: **an id in `blocked_by` that is not in the open set → that blocker is done**. No separate lookup of its state is needed.

⚠️ **Do not trust the state field carried in a `blocked_by` entry**; judge by "is it in the open set". And never by "is it in the candidate set" — that set is narrowed to one Module or delivery (see 1a).

A blocker in another project (a cross-project relation) is in neither set. Look it up with `workitem(action="retrieve_by_identifier", workitem_identifier=..., fields="state_group")` — a `retrieve`, not an `update` response, so its `state_group` is current.

### 5. Derive the Result

Items whose `blocked_by` entries are all done (or that have no `blocked_by` at all) = the items that can start in parallel now — **except items carrying `needs:decision`** (map `labels` ids to names with `label(action="list")` first). Those go in a separate group, `等你决定`, each with the open choices from its `待定` block (one `retrieve` of `description_html` per such item). Reason: the item is unblocked by other work but still blocked by the user; offering it as ready means the agent picks the answer itself, which is exactly what the Label exists to prevent.

**Multiple `blocked_by` entries are AND**: all must be done to unlock; missing even one is not enough.

## Doing an Item

Steps 1–5 answer "what can start". When the user asks to actually do an item, go through these steps in order. Two of them are state writes, and they are the steps most often forgotten — the code gets written, the turn ends, and Plane still says `backlog`. Reason: the board is the only place anyone else (the user, the next agent, `pick-up-work` itself) learns that an item started or finished; a forgotten state write makes the next parallel set wrong.

1. Read the body ("Read the Body").
2. Check for open choices and the risk level, and pause if either says so ("Open Choices: Stop", "Risk Level: When to Pause").
3. **State → `started`** ("Set State Before Starting"). Before the first file edit.
4. Implement; every commit carries `Refs: <ITEM-ID>` ("Commits").
5. Run the `验证` steps and post the verification record ("Verification Record").
6. Pass the gate ("The Gate").
7. **State → `completed`, then read it back** ("Mark Done"). Or, if the gate did not pass, leave it `started` and say why.
8. Report, including the state read back in step 7 ("Report to the User").

The turn that does an item is not finished until step 7 has run or the report says why it did not. If the work spans several turns, state is set in the turn that starts the work and in the turn that finishes it — not left for "later".

### Read the Body

Step 1 trimmed the description to save tokens, so fetch it once here with `workitem(action="retrieve", fields="description_html,labels,parent,...")`.

**If the body's second `h3` is `交付`, this is a parent item, not work** — even when it has no children yet (`hasChildren()` cannot see a parent created a moment ago). Do not do it: list its children (`pql='childOf("<ITEM-ID>")'`) and offer the ones that can start, computed as in steps 1–5.

#### Splitting the Body Into Blocks

Always split `description_html`, **never `description_stripped`** — stripping removes the headings, and block titles become indistinguishable from body lines.

Two formats exist in Plane, and both must be read:

1. **Current format (write-workitem):** each block starts at an `h3` whose text is the block name. Match the tag with attributes allowed — `<h3[^>]*>` — because a body saved from the web editor comes back as `<h3 class="editor-heading-block" data-id="…">`. A block runs until the next `h3`.
2. **Old format** (only when the body has no `h3` at all): each block starts at a paragraph whose leading `<strong>` holds the block name, e.g. `<p><strong>完成标准</strong>: …</p>`; the block runs until the next such `<strong>` name. Map old names onto current blocks:

   | Old name | Current block |
   |---|---|
   | `为什么` / `完成标准` / `注意` | same name |
   | `完成定义` | `完成标准` |
   | `必须通过的测试` + `手动验证` | `验证` (both together) |

After mapping, work with and report blocks **only under their current names** — an old item's `完成定义` *is* its `完成标准`, and its `必须通过的测试` and `手动验证` together *are* its `验证`. Reason: everything downstream (the required-block check, the verification record's per-V list) looks for the current names; carrying an old name forward makes a present block look missing.

A block's content is everything between its heading and the next block heading — no more. Reason: if one block bleeds into the next (`注意` read as part of `完成标准`), the item gets marked done against the wrong criteria, and nothing looks wrong.

#### Required Blocks

The body should contain `完成标准` and `验证` (see write-workitem). **If either is missing, stop and ask the user** — do not infer from the title what counts as done.

Reason: the title says only what to do, not how far to go to be done. When criteria guessed from the title differ from the one in the user's head, you stop where you think you are done, and the user gets a half-finished product — **and neither side knows which step went wrong**.

Old items missing these blocks is normal (the template came later). Ask one question to clarify, then add the answer to the body in the current h3 format, following write-workitem's "Editing an Existing Body" — so it need not be asked again next time.

### Open Choices: Stop

An item has open choices when it carries `needs:decision` **or** its body has a `待定` block. Either one alone counts — a mismatch between them is itself a sign the item was edited halfway. Do not start it: list each open choice with its candidates and the lean written there, and stop the turn. Reason: these are choices write-workitem reserves for the user; starting anyway means the agent makes them.

When the user answers, resolve it as write-workitem, "Pending Decisions", describes (one update: answer into `注意` as `已定（YYYY-MM-DD）：…`, drop the `待定` entry, drop `needs:decision` when no entry is left, keep every other Label). Then continue with the risk check below.

**A new open choice found while doing the item** — a number, default, or user-visible wording that neither the body nor the user settled — is handled the same way: stop before writing it, add a `待定` entry (and `needs:decision` if absent) per write-workitem, tell the user, and end the turn. Leave the state `started`; the code written so far stays uncommitted or is committed only if it does not depend on the choice. Reason: picking a value "for now" ships it — nobody revisits a placeholder that works.

### Risk Level: When to Pause

The level comes from the item's Label — exactly one of `risk:high` / `risk:medium` / `risk:low` (rules in write-workitem). `labels` on an item are **ids**: map them to names with `label(action="list", project_id=...)` first. Reason: comparing an id with `risk:high` never matches, and every item would look unlabelled.

| Level | Before any write | Before marking done |
|---|---|---|
| `risk:high` | **brief confirmation** — after reading the body, before changing state, editing files, or committing | **wait for confirmation** |
| `risk:medium` | **tell, don't wait** | no pause — report it, then mark done |
| `risk:low` | no | no — mark it done yourself once the gate below passes |

- **`risk:medium` — tell the user, never wait.** When starting, say in one line that this is a `medium` item and which places it touches, then keep going in the same turn. In the final report, list it separately: the item, the files changed, and how to undo it (`git revert <commit>`). Then mark it done yourself. Reason: medium is undone cleanly by `git revert`, so the user needs to know it happened, not to approve it.
- **`risk:high` — brief confirmation before any write.** In a few lines: what will change outside the repository or beyond one `git revert` (the reason it is `high`), and how it would be undone, taken from `回退`. Then stop the turn and write nothing. Reason: `high` means the change cannot be undone with one `git revert`, so the user approves the one irreversible step knowingly; the design choices themselves were already settled through `待定` before the item could start, so there is nothing else to discuss here.
  - Start only on an explicit go-ahead ("确认", "可以", "go ahead"). No reply, or a reply about something else, is **not** a go-ahead — answer it if asked, and keep waiting.
  - If the user proposes changes instead, that is not consent: update the body to the agreed version (write-workitem's "Editing an Existing Body"), show the new confirmation, and keep waiting. Reason: the verification record is checked against the body; an outdated body makes the agreed work look out of scope.
- **Waiting for confirmation** (high, before marking done): stop the turn and write nothing; the same explicit go-ahead rule applies.
- **No risk Label, or more than one** → treat as `high`, and ask the user which level it should be. A Label whose name is not exactly one of the three does not count.
- **Label and the first word of `风险` disagree** → treat as the **higher** of the two, and ask which one is right.
- **`high` without a `回退` block** → do not start; ask the user how it would be undone.
- The `high` pause before marking done comes **after** the verification record is posted (see "The Gate"). Reason: the user should be confirming something that has already been verified.

### Set State Before Starting

```
workitem(action="update", workitem_id=..., state=<UUID of a state in the started group>)
```

First run `state(action="list")` to get the UUID of a state whose group is `started` in that project — and, in the same call, the UUID of a `completed`-group state for "Mark Done", so the last step needs no lookup. For `risk:high`, this is a write — it comes after the first confirmation. For `medium` and `low`, it is the first write, before any file edit.

**Then the parent.** If the item has a `parent` and that parent is in `backlog` or `unstarted`, move the parent to the same `started` state in the same step. Reason: the parent's state is a copy of its children's (write-workitem, "Parent Items"); a delivery whose child is in progress must not read as untouched on the board.

⚠️ **The `state_group` in `update`'s response is stale** — after changing to Done, the response's `state` and `completed_at` are updated but `state_group` is still the old value. To double-check, `list` again. Trust it and a just-finished item is treated as unfinished, **so the next parallel-set computation comes up short**.

### Commits: One Trailer per Item

Every commit made for an item ends its message with the trailer line

```
Refs: <ITEM-ID>
```

e.g. `Refs: FMTLAB-12`. Commit locally; do **not** `git push`. Reason: the trailer is what binds commits to the item — it survives merges and does not depend on branch start points or time ranges — and `changed-files.sh` (below) finds commits by it. A commit without it is invisible to the record.

### Verification Record (Required Before `completed`)

After running the item's `验证` steps, post **one** comment (`workitem_comment(action="create", comment_html=...)`, HTML) with exactly these four `h3` blocks, in this order:

| Block | Content |
|---|---|
| `验证记录` | First line: the verdict, `通过` or `失败`. Then who ran it and the code version (`git rev-parse --short HEAD`). |
| `改动文件` | The output of `changed-files.sh`, pasted **unchanged**. Then a `范围对照` paragraph: files changed outside the item's `涉及范围`, and places in `涉及范围` that were not touched — each with `原因：`. |
| `已执行` | Per V number from the body: the command, exit code, and the key output lines. For an e2e run through `claude -p`, also its `session_id`; other e2e entries (a CLI, `curl`, a browser run) have none, so do not write one. |
| `未验证` | V numbers that were not run, each with the reason. Write `无` if all ran. |

Send the whole comment as **one line**, with nothing between a closing `>` and the next `<` — the same rule as an item body (write-workitem's "HTML Format"). Reason: newlines between tags turn into empty bullets once the comment is saved from the web editor.

#### Generating `改动文件`

Run, inside the target repository (`<skill dir>` is the "Base directory for this skill" shown when this skill loaded):

```bash
bash "<skill dir>/scripts/changed-files.sh" <ITEM-ID> [ignored-path ...]
```

It prints HTML: the current HEAD; every commit whose message has the whole line `Refs: <ITEM-ID>` (so `FMTLAB-1` never matches `FMTLAB-12`) with its `--name-status`; the union of their files; and `git status --porcelain`. Paths are HTML-escaped, and the output is a single line so it can be spliced into the comment as-is.

- **Never write or edit this block by hand.** Reason: a hand-written list drops files, adds files, and nobody can tell it disagrees with the real commits.
- If the script exits non-zero with `no commit has trailer`, the commits are missing the trailer. Fix that (amend locally, or commit the work with the trailer) — do not post an empty list, which reads as "nothing changed".
- A file the item changed but `.gitignore` hides (e.g. a gitignored `CLAUDE.md`) appears in neither `git log` nor `git status`. Pass its path as an extra argument; the script adds a `git 看不到的改动` list with the `git check-ignore -v` line as evidence, and refuses paths that are not actually ignored.

#### The Gate

- **No verification-record comment → do not move the item to the `completed` group.** This holds even when the user asks to skip it; say why and stop.
- **Then the risk pause**: `risk:high` stops here and waits for an explicit confirmation before moving to `completed`; `risk:medium` and `risk:low` proceed (medium is still listed in the final report).
- **A file outside `涉及范围` whose reason you cannot state → do not mark done; ask the user.**
- **Re-check the version just before marking done.** Run `git rev-parse --short HEAD` again; if it differs from the version in the record, the code changed after verification — run the V steps again and post a new record.
- **A failed run is recorded too**, with verdict `失败`, and the item stays open.
- **Only ever append comments; never edit or delete an earlier one.** Earlier records are the history; an edited record makes a past failure disappear.
- Long logs go into `workitem_attachment` or `workitem_link`; the comment keeps the few lines that show the result. Reason: nobody reads a comment that is mostly log.

### Mark Done

Once the gate passes (and, for `risk:high`, the user confirmed):

```
workitem(action="update", project_id=..., workitem_id=..., state=<UUID of a completed-group state>)
workitem(action="list", project_id=..., pql='id = "<ITEM-ID>"', fields='id,sequence_id,state_group')
```

PQL's `id` takes the human identifier (`"ABC-12"`), not the UUID.

The `list` is required: `update`'s response carries a stale `state_group`, so only the `list` result proves the move happened. Quote that `state_group` in the report.

**Then the parent.** If the item has a `parent`, count its children that are still open — after the read-back above, so the item just finished is not counted:

```
workitem(action="count", project_id=..., pql='childOf("<PARENT-ID>") AND stateGroup IN openStates()')
```

- `0`, and at least one child is `completed` → move the parent to the same `completed` state and read it back with `list`, exactly as for the item. Quote both read-back states in the report.
- `0`, but every child is `cancelled` → do not move the parent; ask the user whether the delivery is cancelled. Reason: nothing was delivered, so `completed` would be false, and dropping a whole delivery is the user's call.
- More than `0` → leave the parent as it is, and say in the report how many children are still open.

`childOf` takes the human identifier (`"ABC-5"`). The item's `parent` field is a uuid; if you do not already have the parent's identifier, `workitem(action="retrieve", workitem_id=<parent uuid>, fields="sequence_id")` gives its number.

If the gate did **not** pass (a failed V, a file outside `涉及范围` without a reason, the user not yet confirming a `high` item), the item stays in `started`. Do not move it back to `backlog` / `unstarted`. Say in the report which gate condition is open. Reason: `started` is the truth — work exists — and the record comment already says what failed.

When the user changes their mind about an item mid-way ("don't do this after all"), ask whether it should go to `cancelled`; do not leave it `started` with nobody working on it.

## Judge Completion by State Group, Never by State Name

There are exactly five groups: `backlog` / `unstarted` / `started` / `completed` / `cancelled`. **State names can be changed freely; groups cannot**, so judgments can only be based on the group.

**New items land in `backlog` by default**, not `unstarted`. So `backlog` does not mean "not yet in the plan" — when excluding, exclude only `completed` and `cancelled`; do not exclude `backlog` as well.

### "Is Module X Done?"

Answer from the states of the items attached to that Module — nothing else holds this. Run step 1b without the `openStates()` filter, and report the count per state group plus every item not in `completed` / `cancelled`. **Read only; run no tests.** Reason: the question asks for status, and each item's own verification record already says what was verified.

If no Module has that name, say so and list the project's Modules; do not guess from item titles.

### "Is Delivery X Done?"

Same, by parent instead of Module. Find the parent among `pql='isTopLevel() AND hasChildren()'` by title; then `pql='childOf("<PARENT-ID>")'` with no state filter, and report the count per state group plus every child not in `completed` / `cancelled`. Answer from the children, not from the parent's own state — the parent's state is only a copy, and a missed sync would make it lie.

If both a Module and a parent match the name, say which one you answered for. If neither matches, list the open parents and the Modules; do not guess.

## Report to the User

List the batch that can start in parallel (identifier + title + risk Label), grouped under each item's parent title when it has one (one `list` with `pql='hasChildren()'`, `fields='id,sequence_id,name'` maps the `parent` uuids from step 1b to titles), then the `等你决定` group (each item with its open choices), and **what each blocked item is waiting on**. The last two matter just as much — only by seeing "what is being waited on" can the user judge whether to adjust priorities.

After dependencies change (one item finished, or a new dependency added), **recompute** — do not reuse the previous result.

After doing an item, the report also states, per item: its state as read back by `list` in "Mark Done" (`state_group: completed`, or `started` plus the open gate condition), the commit(s), and the verification verdict. A report without the read-back state means step 7 was skipped — go back and run it.
