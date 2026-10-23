---
name: write-workitem
description: "Write or edit the body of a single Plane work item: the fixed h3 template (为什么 / 涉及范围 / 风险 / 完成标准 / 验证 / 不做 / 回退 / 注意), numbered completion criteria C1..Cn, numbered verification steps V1..Vn with an agent-run e2e, and a risk level. Use this skill whenever one work item's description is being created or changed — triggers on 'record a bug in Plane', 'add a work item', 'file an issue for this', 'write up this task', 'make this item's criteria more specific', and whenever plan-to-plane or pick-up-work needs to write or patch an item body. The Plane MCP server ships with this plugin but needs a one-time `claude mcp login plane`. Do NOT use for deciding which Module an item belongs to (use write-module) or for computing what can start next (use pick-up-work)."
---

# Write a Plane Work Item Body

A work item body is read back later by an agent that has none of today's context. It must answer, without reinterpretation: **why** this change exists, **where** it touches, **how bad** a mistake would be, **what observable behaviour** means done, and **which commands prove it**. Every rule below exists because one of those questions went unanswered once.

The block names and sub-labels below are Chinese literals written into Plane. Keep them in Chinese exactly as shown: people read them in the Plane UI, and `pick-up-work` matches them verbatim on read-back. Write the prose inside the blocks in the user's language.

## Creating a New Item

1. **Pick the Module(s) first** — invoke the `plane-taskgraph:write-module` skill and follow its "Attaching an Item" rules against the places this item will list in `涉及范围`. If no existing Module fits, write-module says to stop and ask: do that **before** creating the item. Reason: an item created without a Module is invisible to anyone reading the board by Module, and `pick-up-work` never offers it.
2. Write the body per this skill, then `workitem(action="create", labels=[<the one risk:* label id>])` — see "The Risk Label".
3. Attach it to every Module chosen in step 1 (`module(action="manage_workitems")`) and read back, as write-module describes.
4. Run "After Writing" below.

Skipping step 3 is the common failure: the item exists, looks complete, and is attached to nothing.

## The Template

Blocks appear in this order. The first five are **required**; the last three are optional and are **deleted entirely** (heading included) when empty — an empty heading reads as "someone forgot", not "nothing to say".

| Block | Required | What goes in it |
|---|---|---|
| `为什么` | yes | The problem this change solves, and the decision it follows from |
| `涉及范围` | yes | Every file / component / external system touched, each with what changes and `原因：` why it has to change |
| `风险` | yes | Level (`high` / `medium` / `low`) as the first word, every distinct way a mistake would show up, and how to undo it |
| `完成标准` | yes | Numbered observable behaviours C1..Cn |
| `验证` | yes | Numbered checks V1..Vn that prove the C items |
| `不做` | no | Things deliberately left out, each with `原因：` |
| `回退` | no (required for `high`) | Exact steps to undo, and what cannot be undone |
| `注意` | no | Known traps and decisions already made, each with `原因：` |

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
  <li>… 原因：…</li>
</ul>
```

### Every List Entry in 涉及范围 / 不做 / 注意 Carries `原因：`

A bare "touch `client.ts`" or "don't do auto-refresh" cannot be re-evaluated later: when circumstances change, nobody knows whether the rule still holds. Write the reason inline after the literal `原因：` so it can be found mechanically.

### 风险

The first word is the level. Then list **each** distinct failure symptom — what the user or the next agent would actually see — and how to undo the change.

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

Numbered `C1`, `C2`, … continuously across the whole block, grouped under up to three literal group labels: `主流程` / `边界与异常` / `不能变的`. Drop a group that has nothing in it.

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

**At least one e2e is required whenever 完成标准 contains behaviour, and it must cover the main C.** Checks and units prove the parts are right; only e2e proves the outcome the user asked for actually appears. When the change truly has no behaviour (documentation only), write one V as `e2e：不适用。原因：…`.

#### e2e Is Run by the Agent

Every e2e step is executed by the agent itself — including any step where "the user replies", which the agent plays. **Never write `（手动）` or a step that needs a human to run it**: a step that needs a human does not get run, and ends up in "未验证" while the item is marked done anyway.

Each e2e states its entry command, its input, how the result is read back, and the expected value. Pick the entry by what changed:

- **A skill or plugin**: run Claude Code headless against the plugin directory in the repo, then assert on the transcript with jq:

  ```bash
  P="$(git rev-parse --show-toplevel)/plugins/<plugin>"
  claude -p "<prompt>" --plugin-dir "$P" \
    --output-format stream-json --verbose --max-budget-usd 3 \
    --allowedTools <tools this run needs> > /tmp/<item>-<V>-<round>.jsonl
  ```

  To play the user's reply, run the same command with `--resume <session_id>` from the previous round. Every round passes four generic assertions (F is that round's jsonl):

  - The repo copy of the plugin was loaded: `jq -r 'select(.subtype=="init") | .plugins[] | select(.name=="<plugin>") | .source + " " + .version' F` prints `<plugin>@inline` and the version in plugin.json. Reason: with a marketplace install present, a stale cached copy can be tested instead.
  - Which skills fired: `jq -r 'select(.type=="assistant").message.content[] | select(.type=="tool_use" and .name=="Skill") | .input.skill' F`.
  - Which tools ran: `jq -c 'select(.type=="assistant").message.content[] | select(.type=="tool_use") | [.name, (.input.skill // .input.action)]' F`.
  - How it ended: `jq -c 'select(.type=="result") | [.is_error, (.permission_denials | length), .session_id]' F` — the first two must be `false` and `0`. Reason: a denied tool makes the agent stop or skip steps in a way that looks identical to correct behaviour.

  macOS has no `timeout`; bound a run with `--max-budget-usd`, not by wrapping it.

- **A web page**: browser automation — a Playwright spec, or agent-browser.
- **An HTTP endpoint**: `curl`, asserting on status and body.
- **A command-line tool**: run it directly.

#### "The Agent Stopped" Is Judged by State, Not Words

When a V expects the agent to pause (wait for confirmation, ask a question), check that **nothing was written**: `git rev-parse HEAD` and `git status --porcelain` unchanged, and the Plane item's `updated_at` and comment count unchanged. The reply text is supporting evidence only — "let me pause here" says nothing about what was already written before it.

#### 人工检查

Only for what genuinely needs human eyes — whether a page reads well, whether a design looks right. Write it as its own V labelled `人工检查`, and say why the agent cannot do it. A 人工检查 is not an e2e and never replaces one.

### 不做 / 回退 / 注意

- `不做`: scope that was considered and deliberately excluded. Writing it down is what lets a later "should this also…" be answered without re-litigating.
- `回退`: required when the level is `high`. If you cannot write how to undo a `high` change, stop and ask the user before creating the item.
- `注意`: traps and constraints the implementer would otherwise hit.

## Never Put These in the Body

Which Module it belongs to, what it depends on, and what state it is in. Each has a structured field (Module, `blocked_by` relation, state). A second copy in prose drifts, and when the two disagree nobody knows which is true.

## Sizing an Item

- One item delivers **one observable behaviour**. If 完成标准 needs two unrelated main-flow C items, it is two items.
- Cut the high-risk part into its own item, so the rest is not held to `high` pauses.
- No line-count limit. Lines changed do not track risk.
- An integration check that spans items goes into the **most-downstream** item of the dependency chain. If no item sits downstream of all the parts, stop and ask the user — the split is probably wrong.

## HTML Format

- `h3` is used only for block names. No `h1`–`h6` inside blocks.
- Allowed tags: `h3`, `p`, `strong`, `ul`, `li`, `code`. Nothing else has been verified to survive the Plane editor.
- Write tags as raw HTML. In text, write `<`, `>`, `&` as `&lt;`, `&gt;`, `&amp;`.
- Read back with `description_html`, never `description_stripped` — stripping removes the `h3` tags and the blocks become indistinguishable lines.
- A body that has been saved from the Plane web editor comes back with attributes on every element (`<h3 class="editor-heading-block" data-id="…">`) and without the outer `<div>`. Match tags with patterns that allow attributes, e.g. `<h3[^>]*>`.

## Silent Failures (HTTP 200, Wrong Data)

- **Escaped tags** (`&lt;p&gt;`) are stored literally and render as visible tag text.
- **Unknown tags** (custom XML-style tags) are stripped on write — their content vanishes, and the call still succeeds.
- **`state_group` returned by `create` / `update` is stale** (null on create, the pre-change value on update). Confirm state with `list`.
- **A stale browser tab wins.** After an API edit, a Plane tab that was open before the edit will save its old copy over the whole body the next time the user edits there.
- **Long Chinese payloads occasionally come back with U+FFFD (`�`) in place of a character.** Always read the body back after writing and search it for U+FFFD; if found, rewrite (rephrasing the affected sentence helps).

## Editing an Existing Body

`update` replaces the **entire** `description_html`. So:

1. `workitem(action="retrieve", fields="description_html,updated_at")` **immediately before** editing. Never edit from a copy read earlier in the session — the user may have changed the item in the web UI since, and your update would silently erase that.
2. Apply the change to that fresh copy, keeping blocks you are not touching byte-for-byte.
3. Write it back, then read it back and confirm the change landed, nothing else moved, and there is no U+FFFD.
4. Tell the user to **refresh** any Plane tab that has this item open before editing it there. Reason: the stale-tab overwrite happens in the browser; nothing on the API side can prevent it.

## After Writing

Read the item back (`description_html`) and check: the `h3` sequence is 为什么, 涉及范围, 风险, 完成标准, 验证, then only 不做 / 回退 / 注意; every C and V is numbered; at least one V is e2e (or `e2e：不适用` with a reason); no U+FFFD; exactly one `risk:*` Label, matching the first word of 风险. For a new item, also confirm it is attached to its Module(s). Then report the item's identifier, title, risk Label, and Module(s) to the user.
