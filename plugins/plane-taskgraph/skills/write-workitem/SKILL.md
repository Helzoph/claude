---
name: write-workitem
description: "Write or edit the body or title of a single Plane work item: the fixed h3 template (为什么 / 涉及范围 / 风险 / 完成标准 / 验证 / 不做 / 回退 / 注意), numbered completion criteria C1..Cn, numbered verification steps V1..Vn with an agent-run e2e, a risk level, and the item's blocked_by dependencies. Use this skill whenever one work item's description or title is being created or changed — triggers on 'record a bug in Plane', 'add a work item', 'file an issue for this', 'write up this task', 'make this item's criteria more specific', 'add this decision to ABC-3', 'update ABC-3', 'fix the format of ABC-3', 'this item depends on ABC-2', and whenever plan-to-plane or pick-up-work needs to write or patch an item body. Also covers design / spike items whose output is a decision rather than code. The Plane MCP server ships with this plugin but needs a one-time `claude mcp login plane`. Do NOT use for deciding which Module an item belongs to (use write-module) or for computing what can start next (use pick-up-work)."
---

# Write a Plane Work Item Body

A work item body is read back later by an agent that has none of today's context. It must answer, without reinterpretation: **why** this change exists, **where** it touches, **how bad** a mistake would be, **what observable behaviour** means done, and **which commands prove it**. Every rule below exists because one of those questions went unanswered once.

The block names and sub-labels below are Chinese literals written into Plane. Keep them in Chinese exactly as shown: people read them in the Plane UI, and `pick-up-work` matches them verbatim on read-back. Write the prose inside the blocks in the user's language.

Before sending any `description_html`, read `references/plane-html.md` (one-line HTML, allowed tags, and the failures that return HTTP 200 with wrong data).

## Never Put These in the Title or Body

Three facts have structured fields. Writing them as prose is the most common way this workflow breaks:

| Fact | Its field | Forms that are forbidden in title and body |
|---|---|---|
| What must finish first | `blocked_by` relation | `见 ABC-12`, `等 ABC-12 做完`, `依赖 ABC-12`, `ABC-12 已经开了这个口子的话…`, `第二步` / `第 3 步` / `Part 2` in the title |
| Which functional area | Module | `属于 X 模块`, `[X]` prefixes in the title |
| Whether it is done | state | `已完成`, `进行中`, `TODO` |

Reason: `pick-up-work` computes what can start **only** from `blocked_by`. An order written as "第二步" in a title, or as "见 ABC-12" in a body, is invisible to it — the item is offered as ready while the thing it waits on is still open. And a second copy in prose drifts: when the two disagree, nobody knows which is true.

- **An order between items is a `blocked_by` relation**, created as described in "Creating a New Item" step 4 — never a numbered title. If the title would only make sense with a step number, name what the step delivers instead.
- **"See also" without an order** is the custom relation `relates to` (see plan-to-plane, "Dependencies"), not an identifier in prose.
- **Shared context between items** ("the mount point decided in another item") is restated in this item's own words, so it reads alone. If it cannot be restated without the other item's details, that is a `blocked_by`.

## Creating a New Item

1. **Pick the Module(s) first** — invoke the `plane-taskgraph:write-module` skill and follow its "Attaching an Item" rules against the places this item will list in `涉及范围`. If no existing Module fits, write-module says to stop and ask: do that **before** creating the item. Reason: an item created without a Module is invisible to anyone reading the board by Module, and `pick-up-work` never offers it.
2. Write the body per this skill, then `workitem(action="create", labels=[<the one risk:* label id>])` — see "The Risk Label".
3. Attach it to every Module chosen in step 1 (`module(action="manage_workitems")`) and read back, as write-module describes.
4. **Dependencies.** Ask yourself — and the user, if the conversation did not settle it — which existing items must be finished before this one can start. For each, from **this** (the blocked) item: `workitem_relation(action="create", project_id=..., workitem_id=<this item>, workitem_ids=[<blocker ids>], relation_type="blocked_by")`. Then `workitem_relation(action="list", workitem_id=<this item>)` and confirm every blocker appears under `dependencies.blocked_by`. If nothing blocks it, say so in the report ("无 blocked_by") so the absence is a decision, not an omission.
5. Run "After Writing" below.

Skipping step 3 or 4 is the common failure: the item exists, looks complete, and is attached to nothing / waits on nothing.

When several items with an order between them are being filed together, use `plan-to-plane` instead — it creates all items first and wires every relation afterwards.

## The Template

Blocks appear in this order. The first five are **required**; the last three are optional and are **deleted entirely** (heading included) when empty — an empty heading reads as "someone forgot", not "nothing to say". **No other `h3` is allowed**, and block names carry no suffix: `涉及范围（初步）` is not `涉及范围`. Reason: `pick-up-work` and the bundled hook match the names exactly; an invented block is content nobody reads back.

| Block | Required | What goes in it |
|---|---|---|
| `为什么` | yes | The problem this change solves, and the decision it follows from |
| `涉及范围` | yes | Every file / component / external system touched, each with what changes and `原因：` why it has to change |
| `风险` | yes | Level (`high` / `medium` / `low`) as the first word, every distinct way a mistake would show up, and how to undo it |
| `完成标准` | yes | Numbered observable behaviours C1..Cn |
| `验证` | yes | Numbered checks V1..Vn that prove the C items |
| `不做` | no | Things deliberately left out, each with `原因：` |
| `回退` | no (required for `high`) | Exact steps to undo, and what cannot be undone |
| `注意` | no | Known traps, and decisions already made, each with `原因：` |

The template is indented here only to be readable. **Send it as one line** — see `references/plane-html.md`.

```html
<h3>为什么</h3>
<p>…</p>
<h3>涉及范围</h3>
<ul>
  <li><code>path/to/file</code>：what changes. 原因：why this place has to change.</li>
</ul>
<h3>风险</h3>
<p>medium。出错时有两种表现：</p>
<ul>
  <li>symptom one;</li>
  <li>symptom two.</li>
</ul>
<p>撤回方式：<code>git revert</code>.</p>
<h3>完成标准</h3>
<ul>
  <li>主流程<ul>
    <li>C1：observable behaviour.</li>
  </ul></li>
  <li>边界与异常<ul>
    <li>C2：…</li>
  </ul></li>
  <li>不能变的<ul>
    <li>C3：…</li>
  </ul></li>
</ul>
<h3>验证</h3>
<ul>
  <li>V1 e2e：short title<ul>
    <li>准备：state that must exist before running (optional).</li>
    <li>运行：exact command, or 步骤 for a multi-turn run.</li>
    <li>预期：output, count, or read-back field value to compare against.</li>
    <li>覆盖：C1；风险「symptom one」.</li>
  </ul></li>
</ul>
<h3>不做</h3>
<ul>
  <li>… 原因：…</li>
</ul>
<h3>注意</h3>
<ul>
  <li>已定（2026-10-29）：… 原因：…</li>
  <li>… 原因：…</li>
</ul>
```

### Every List Entry in 涉及范围 / 不做 / 注意 Carries `原因：`

A bare "touch `client.ts`" or "don't do auto-refresh" cannot be re-evaluated later: when circumstances change, nobody knows whether the rule still holds. Write the reason inline after the literal `原因：` so it can be found mechanically.

### Decisions Go in 注意, Dated

A decision made while discussing the item ("use a sidecar, not a shared volume") is one `注意` entry starting with the literal `已定（YYYY-MM-DD）：`, followed by `原因：`. Not a paragraph in `为什么`, not a new `h3`. Reason: one fixed place means a later reader finds every decision by searching `已定`, and the date shows which decisions predate a change in circumstances.

### 风险

The first word is the level. Then list **each** distinct failure symptom — what the user or the next agent would actually see — and how to undo the change. A risk mentioned only in `注意` is not written down: `风险` is what V items are checked against.

| Level | Criteria |
|---|---|
| `high` | Irreversible, or reaches outside the repository: data migration or deletion; external side effects (sending messages, charging money, publishing, `git push`); credentials or permissions; CI, deployment, production config; public interfaces, or an architecture pattern others will copy |
| `medium` | Changes user-visible behaviour or core logic, but `git revert` undoes it cleanly |
| `low` | Changes no behaviour: docs, comments, tests, features behind a disabled flag, internal scripts |

Rate the item by the **most dangerous** place listed in `涉及范围`. When unsure, go one level higher: rating too low means an irreversible change ships without being discussed; rating too high costs one discussion.

**Every symptom listed in 风险 must be covered by at least one V item.** A risk that is written down but never checked is decoration.

### The Risk Label

The level is also a Label, so it shows in lists and can be queried (`label IN ("risk:high")`). Exactly three names, character for character:

```
risk:high    risk:medium    risk:low
```

- **Every item carries exactly one of them**, and it matches the first word of `风险` (`risk:high` ↔ `high`, …). No `Risk-High`, no `risk:med`. Reason: `pick-up-work` decides when to pause by this Label; zero, two, or a misspelt one means it cannot tell the level.
- **Get the ids first**: `label(action="list", project_id=...)`. Labels are per project. If any of the three is missing, create it with exactly that name (`label(action="create")`) and tell the user at the end which ones you created.
- **Changing an existing item's level**: `retrieve` its current `labels`, drop the old `risk:*` id, add the new one, keep every other Label id, and send the new `labels` **in the same `update` as the edited 风险 text**. Reason: `labels` in `update` replaces the whole list — sending only the risk Label erases the user's other Labels — and two separate updates leave a window where Label and text disagree.
- **Adding a level to an old item that has none**: add the Label (keep the others) and leave the title alone.
- Never put the level in the title (no bracketed letter prefix) or in `priority`. Reason: priority is how urgent, risk is how hard to undo; and a second copy of the level drifts from the Label.
- **`high` requires a `回退` block.** If you cannot write how to undo it, stop and ask before creating the item.

### 完成标准

Numbered `C1`, `C2`, … continuously across the whole block, in order, grouped under up to three literal group labels: `主流程` / `边界与异常` / `不能变的`. Drop a group that has nothing in it. When adding a C to an existing item, put it in its group and **renumber**, updating every `覆盖` that pointed at a shifted number. Reason: `C12` sitting between `C3` and `C4` makes a gap look like a missing criterion.

Each C is a behaviour someone can observe — an output, a state, a file content, a UI element — not an activity ("implement X", "refactor Y"). Numbers exist so every V can say which C it covers, and gaps become visible.

If you cannot write a single observable C, the item is not understood yet or is cut too large. **Stop and ask the user**; do not paper over it with "implement xxx".

### 验证

Numbered `V1`, `V2`, …. Each V starts with its type and a short title, followed by a sub-list using these literal labels:

- `准备` (optional) — state that must exist first: fixtures, test data, a temp repository.
- `运行` — the exact command; or `步骤` when it is a sequence (a multi-turn run).
- `预期` — something directly comparable: an exact output line, a count, an exit code, a field value read back. Never "works", "no errors", "looks right" — those cannot be checked against a run.
- `覆盖` — which C numbers, and which 风险 symptom(s) by quoting them in 「」.

**A `预期` of "no output" or a count of 0 needs a positive control in the same V** — run the same pattern on input that must match (e.g. `git show <commit before the change>:<path>`) and expect a count ≥ 1. Reason: a mistyped pattern also prints nothing, so the check passes without testing anything. One real case: `ugrep` reads patterns as ERE, where `a\|b` matches a literal `|`; write `a|b`, or pass `-G` for the `\|` form.

Three types, and only three:

| Type | Means |
|---|---|
| 检查 | Inspects without running the behaviour: grep, jq on a file, lint, type-check |
| 单元 | Runs one function or script in isolation |
| e2e | Enters through the real entry point and reads back the real result |

**At least one e2e is required whenever 完成标准 contains behaviour, and it must cover the main C.** Checks and units prove the parts are right; only e2e proves the outcome the user asked for actually appears. When the change truly has no behaviour (documentation only, or a design item below), write one V as `e2e：不适用。原因：…`.

#### e2e Is Run by the Agent

Every e2e step is executed by the agent itself — including any step where "the user replies", which the agent plays. **Never write `（手动）` or a step that needs a human to run it**: a step that needs a human does not get run, and ends up in "未验证" while the item is marked done anyway.

How to write the entry command and assertions — headless `claude -p --plugin-dir` for a skill or plugin, browser automation, `curl`, a CLI — and how to judge "the agent stopped" by state rather than words: `references/e2e-recipe.md`. Read it before writing any e2e V.

#### 人工检查

Only for what genuinely needs human eyes — whether a page reads well, whether a design looks right. Write it as its own V labelled `人工检查`, and say why the agent cannot do it. A 人工检查 is not an e2e and never replaces one.

### 不做 / 回退 / 注意

- `不做`: scope that was considered and deliberately excluded. Writing it down is what lets a later "should this also…" be answered without re-litigating.
- `回退`: required when the level is `high`. If you cannot write how to undo a `high` change, stop and ask the user before creating the item.
- `注意`: traps and constraints the implementer would otherwise hit, and dated decisions (see "Decisions Go in 注意, Dated").

## Design / Spike Items

An item whose output is a decision ("decide how plugins mount their config"), not code, uses the **same eight blocks** — no `已定下的` / `要回答的问题` headings. Map it like this:

- `涉及范围`: the places the decision will affect, each with `原因：`. If this is still a guess, say so in the entry ("待摸底") — do not put the caveat in the heading.
- `完成标准`: one C per question that must be answered — `C1：「plugins 的配置挂在哪」有结论，写进 <doc path or this item's 注意>`. A question is a C; its answer is not.
- `验证`: `检查` V items that find each conclusion where C says it is written (e.g. a `ugrep` on the doc with a positive control), plus `e2e：不适用。原因：产出是决定，不是行为`.
- `风险`: usually `low` (nothing ships). Rate higher only if the decision is acted on inside this item.
- Decisions already reached before the item is done go in `注意` as `已定（YYYY-MM-DD）：…`, like any other item.

The items that implement the decision are separate items with `blocked_by` this one.

## Sizing an Item

- One item delivers **one observable behaviour**. If 完成标准 needs two unrelated main-flow C items, it is two items.
- Cut the high-risk part into its own item, so the rest is not held to `high` pauses.
- No line-count limit. Lines changed do not track risk.
- An integration check that spans items goes into the **most-downstream** item of the dependency chain. If no item sits downstream of all the parts, stop and ask the user — the split is probably wrong.

## Editing an Existing Body

`update` replaces the **entire** `description_html`. So:

1. `workitem(action="retrieve", fields="description_html,name,updated_at")` **immediately before** editing. Never edit from a copy read earlier in the session — the user may have changed the item in the web UI since, and your update would silently erase that.
2. Apply the change to that fresh copy, keeping blocks you are not touching byte-for-byte. If the item does not follow the template (an invented `h3`, a missing required block, whitespace between tags), the bundled hook rejects the update: convert the whole body to the template in this same edit, keeping its content, and tell the user what moved where.
3. If the edit adds or removes an order between items, change the `blocked_by` relation too ("Creating a New Item" step 4) — never only the prose.
4. Write it back, then run "After Writing".
5. Tell the user to **refresh** any Plane tab that has this item open before editing it there. Reason: the stale-tab overwrite happens in the browser; nothing on the API side can prevent it.

## After Writing

Read the item back (`description_html`, `name`, `labels`) and check each of these mechanically, not by eye:

- The `h3` sequence (match `<h3[^>]*>`) is exactly 为什么, 涉及范围, 风险, 完成标准, 验证, then only 不做 / 回退 / 注意 in that order.
- C and V are numbered continuously from 1, in order; every V has `预期` and `覆盖`; at least one V is e2e (or `e2e：不适用` with a reason).
- No newline between tags, and no whitespace next to a block tag (see `references/plane-html.md`); no U+FFFD.
- Exactly one `risk:*` Label, matching the first word of 风险.
- **Search the title and body for this project's identifier (`<IDENT>-\d+`) and for `第.{1,3}步`.** Every hit is either removed (it is a dependency → relation; a step number → rename) or restated in this item's own words. Then `workitem_relation(action="list")` shows every blocker the item actually has.
- For a new item: attached to its Module(s), and step 4's `blocked_by` read back.

Then report the item's identifier, title, risk Label, Module(s), and its `blocked_by` list (or "无 blocked_by") to the user.
