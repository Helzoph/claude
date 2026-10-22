---
name: pick-up-work
description: "Answer or act on any request about work already in Plane — what can start now, doing an item, changing an item's state or marking it done ('把 ABC-12 标完成', 'close ABC-12'), or status questions ('is the X module done?', 'X 模块做完了吗', 'X 的进度') — instead of calling the Plane tools directly. Reads a task graph back from Plane and computes which work items can start right now, by checking whether each item's blocked_by dependencies are all done; then do an item — read its body (current h3 or old strong-heading format), pause for the user according to its risk:* Label, commit with a `Refs: <ITEM-ID>` trailer, post a verification-record comment whose changed-files block is generated from git by a bundled script, and only then mark it done. Use this skill when picking up work already recorded in Plane — triggers on 'implement the xxx feature', 'do ABC-12', 'what can I work on next', 'what's unblocked'. The Plane MCP server ships with this plugin but needs a one-time `claude mcp login plane`. Do NOT use for writing a new plan into Plane (use plan-to-plane) or for writing an item body (use write-workitem)."
---

# Read the Task Graph Back From Plane and Compute What Can Start Now

**The parallel set is always computed, never stored**, and it cannot be judged by eyeballing the dependency graph — items with multiple blockers are where people most easily miss things.

Definition: the items that are **not done, and whose every `blocked_by` target is done**.

## Read-Back Flow

### 1. Fetch Unfinished Items (1 Call)

```
workitem(action="list", project_id=...,
  pql='module = "<module-uuid>" AND stateGroup IN openStates()',
  fields='id,sequence_id,name,state_group')
```

PQL merges "list everything" and "exclude finished" into one call; what comes back is the candidate set.

Always pass `fields`. Without trimming, every item carries its full description, thousands of characters; trimmed to these four fields it is a few lines.

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

Step 1 already filtered out finished items, so: **an id in `blocked_by` that is not in step 1's results → that blocker is done**. No separate lookup of its state is needed.

⚠️ **Do not trust the state field carried in a `blocked_by` entry**; judge by "is it in the candidate set".

### 5. Derive the Result

Items whose `blocked_by` entries are all done (or that have no `blocked_by` at all) = the items that can start in parallel now.

**Multiple `blocked_by` entries are AND**: all must be done to unlock; missing even one is not enough.

## Doing an Item

Steps 1–5 answer "what can start". When the user asks to actually do an item, go through the sections below in order: read the body, check the risk level, start, commit, record, pass the gate, mark done.

### Read the Body

Step 1 trimmed the description to save tokens, so fetch it once here with `workitem(action="retrieve", fields="description_html,labels,...")`.

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

### Risk Level: When to Pause

The level comes from the item's Label — exactly one of `risk:high` / `risk:medium` / `risk:low` (rules in write-workitem). `labels` on an item are **ids**: map them to names with `label(action="list", project_id=...)` first. Reason: comparing an id with `risk:high` never matches, and every item would look unlabelled.

| Level | Pause before any write | Pause before marking done |
|---|---|---|
| `risk:high` | **yes** — after reading the body, before changing state, editing files, or committing | **yes** |
| `risk:medium` | no | **yes** |
| `risk:low` | no | no — mark it done yourself once the gate below passes |

- **Pausing means: stop the turn, say what you are about to do and why it needs a yes, and write nothing.** Continue only on an explicit confirmation from the user ("确认", "可以", "go ahead"). No reply, or a reply about something else, is **not** a confirmation — answer it if asked, and keep waiting.
- **No risk Label, or more than one** → treat as `high`, and ask the user which level it should be. A Label whose name is not exactly one of the three does not count.
- **Label and the first word of `风险` disagree** → treat as the **higher** of the two, and ask which one is right.
- **`high` without a `回退` block** → do not start; ask the user how it would be undone.
- The pause before marking done comes **after** the verification record is posted (see "The Gate"). Reason: the user should be confirming something that has already been verified.

### Set State Before Starting

```
workitem(action="update", workitem_id=..., state=<UUID of a state in the started group>)
```

First run `state(action="list")` to get the UUID of a state whose group is `started` in that project. For `risk:high`, this is a write — it comes after the first confirmation.

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
| `已执行` | Per V number from the body: the command, exit code, and the key output lines. For an e2e, also the `session_id`. |
| `未验证` | V numbers that were not run, each with the reason. Write `无` if all ran. |

#### Generating `改动文件`

Run, inside the target repository (`<skill dir>` is the "Base directory for this skill" shown when this skill loaded):

```bash
bash "<skill dir>/scripts/changed-files.sh" <ITEM-ID> [ignored-path ...]
```

It prints HTML: the current HEAD; every commit whose message has the whole line `Refs: <ITEM-ID>` (so `FMTLAB-1` never matches `FMTLAB-12`) with its `--name-status`; the union of their files; and `git status --porcelain`. Paths are HTML-escaped.

- **Never write or edit this block by hand.** Reason: a hand-written list drops files, adds files, and nobody can tell it disagrees with the real commits.
- If the script exits non-zero with `no commit has trailer`, the commits are missing the trailer. Fix that (amend locally, or commit the work with the trailer) — do not post an empty list, which reads as "nothing changed".
- A file the item changed but `.gitignore` hides (e.g. a gitignored `CLAUDE.md`) appears in neither `git log` nor `git status`. Pass its path as an extra argument; the script adds a `git 看不到的改动` list with the `git check-ignore -v` line as evidence, and refuses paths that are not actually ignored.

#### The Gate

- **No verification-record comment → do not move the item to the `completed` group.** This holds even when the user asks to skip it; say why and stop.
- **Then the risk pause**: `risk:high` and `risk:medium` stop here and wait for an explicit confirmation before moving to `completed`; `risk:low` proceeds.
- **A file outside `涉及范围` whose reason you cannot state → do not mark done; ask the user.**
- **Re-check the version just before marking done.** Run `git rev-parse --short HEAD` again; if it differs from the version in the record, the code changed after verification — run the V steps again and post a new record.
- **A failed run is recorded too**, with verdict `失败`, and the item stays open.
- **Only ever append comments; never edit or delete an earlier one.** Earlier records are the history; an edited record makes a past failure disappear.
- Long logs go into `workitem_attachment` or `workitem_link`; the comment keeps the few lines that show the result. Reason: nobody reads a comment that is mostly log.

## Judge Completion by State Group, Never by State Name

There are exactly five groups: `backlog` / `unstarted` / `started` / `completed` / `cancelled`. **State names can be changed freely; groups cannot**, so judgments can only be based on the group.

**New items land in `backlog` by default**, not `unstarted`. So `backlog` does not mean "not yet in the plan" — when excluding, exclude only `completed` and `cancelled`; do not exclude `backlog` as well.

### "Is Module X Done?"

Answer from the states of the items attached to that Module — nothing else holds this. Run step 1 without the `openStates()` filter, and report the count per state group plus every item not in `completed` / `cancelled`. **Read only; run no tests.** Reason: the question asks for status, and each item's own verification record already says what was verified.

If no Module has that name, say so and list the project's Modules; do not guess from item titles.

## Report to the User

List the batch that can start in parallel (identifier + title + risk Label), and **what each blocked item is waiting on**. The latter matters just as much — only by seeing "what is being waited on" can the user judge whether to adjust priorities.

After dependencies change (one item finished, or a new dependency added), **recompute** — do not reuse the previous result.
