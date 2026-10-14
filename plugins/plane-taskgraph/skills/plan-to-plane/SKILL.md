---
name: plan-to-plane
description: "Record a design discussion into Plane as a structured task graph: one Module per feature, work items sized to a single reviewable change, ordering expressed as blocked_by relations rather than prose, and one acceptance work item per Module holding its definition of done and the tests that must pass. Use this skill after discussing what to build, whenever the outcome should be written into Plane — triggers on 'record this into Plane', 'create issues for this', 'plan out this feature', 'write the acceptance criteria for this module'. The Plane MCP server ships with this plugin but needs a one-time `claude mcp login plane`. Do NOT use for reading an existing plan back or deciding what to work on next (use pick-up-work instead)."
---

# Record a Design Discussion as a Task Graph in Plane

The goal is not "save the idea" but **save it in a structure that can be read back as-is next time, with no reinterpretation**. Ownership goes through Module, ordering through relations, status through state — always structured fields, **never only in the description**. A plan written into body text gets reinterpreted on the next read, and reinterpreted differently.

## Mapping

| Plane concept | What it holds |
|---|---|
| Project | One code repository |
| Module | One feature — the xxx in "implement xxx for me" that the user can say in one sentence |
| Work item | One change that can be finished in a single sitting and reviewed on its own |
| Acceptance item | Exactly one per module, holding "how far the whole module must go to count as done" (see below) |

Cycle and Label are not used: Cycle is a time dimension (sprint), which this workflow does not have; Label currently has nothing that only it can express.

Module, Label, Cycle, and Estimate are all **project-scoped** and cannot follow a work item across projects. When a feature spans two repositories, the only option is one Module on each side, with the specific items linked by a cross-project `workitem_relation`.

## Prerequisite: Confirm the Project and Make Sure Modules Is Enabled

First run `project(action="list")` to find the target project. **If no matching project exists, stop and ask the user** — do not create one on your own initiative.

A new project **defaults to `module_view: false`, with Modules disabled**; unless you enable it first, the Module creation step fails outright:

```
project(action="update_features", project_id=..., modules=true)
```

For an existing project, confirm it once as well (`project(action="get_features")`) — do not assume it is on.

## Write Order (Step 4 Is a Separate Step and Mandatory)

1. `module(action="create")` — create the feature
2. `workitem(action="create")` — create the items one by one, **plus one acceptance item**
3. `module(action="manage_workitems")` — attach the items to the module (the acceptance item too)
4. `workitem_relation(action="create")` — **wire up dependencies**, including the acceptance item's `blocked_by`

Step 4 can be neither skipped nor moved earlier: relations need item IDs, which exist only once all items are created. **Reporting "done" to the user as soon as the items are created is a failure** — at that point there is not a single dependency, the graph is disconnected, and on read-back every item will be judged ready to start.

## Dependencies: Use Only `blocked_by`, Created From the Blocked Side

There are only 6 built-in relation types: `blocking` / `blocked_by` / `start_before` / `start_after` / `finish_before` / `finish_after`. The last four are for Gantt-chart scheduling and have nothing to do with "can this start"; **do not use them**.

**Always create `blocked_by` from the blocked item**, pointing at the item that blocks it. That way the fact "who is blocking me" lives on the item that needs it.

Plane **stores relations bidirectionally**: after A creates `blocked_by B`, reading B shows `blocking: [A]`. So there is no need to maintain the reverse edge yourself, and do not create a duplicate reverse `blocking` relation.

**"Related but not blocking" is a custom relation, not a built-in type.** It goes through `relation_definition_id` + `relation_definition_label`, with label `"relates to"` (**with a space**, not `relates_to`). The workspace ships with this definition by default; run `workitem_relation(action="list_definitions")` to get its id before using it.

## Record Dependencies Between Work Items, Not Between Modules

A module-level statement like "payments depends on login" is usually false — the truth is often "the item in payments that reads user info depends on the item in login that issues the session", while the rest of the payments module (UI, reconciliation, refunds) has nothing to do with login. Record it as a module-level dependency and the whole module is judged blocked; **work that could run in parallel is misjudged as unable to**, which destroys exactly the capability this approach exists for.

If it comes up that "all of module B must wait for A" but no one can name the specific two items, the dependency has not been thought through yet: **stop and ask the user** — do not record a vague one.

## One Acceptance Item per Module

**Every module must have one, and only one, acceptance item**, holding two things: how far the whole module must go to count as done, and which tests must pass.

Like any other item it is a work item, so it comes with state, comments, and attachments. Therefore:

- **Its state is "has this module passed acceptance"** — no other place is needed to record it, and two conflicting accounts cannot arise.
- Record each acceptance run's result as a **comment**; do not edit the description. The description is the standard (relatively stable); comments are the history (different every time). Mix them and the next reader cannot tell which sentence is a requirement and which is last time's result.

**Why not in the module's description**: through the public API a module description can only store plain text (`description`), with no `description_html`; worse, a module has no state, no comments, and no attachments. The acceptance verdict has nowhere to go and can only become a sentence of prose that nobody ever updates.

### How to Create It

The title is fixed as `<module name> 验收`. `pick-up-work` recognizes it by this suffix; **do not change the suffix** — change it and the item degrades into an ordinary item, the acceptance flow never triggers, yet everything looks normal on the surface.

Use this template for `description_html`:

```html
<p><strong>完成定义</strong>: what state the whole module must reach to count as done</p>
<p><strong>必须通过的测试</strong></p>
<ul>
  <li>A specific test/command — which behavior it covers</li>
</ul>
<p><strong>手动验证</strong></p>
<ul>
  <li>The few checks automation cannot reach and a human must confirm</li>
</ul>
```

**Write "必须通过的测试" so it can be executed directly** — specific test file names, test function names, or commands that can be pasted into a terminal as-is. Writing "unit tests pass" is the same as writing nothing: the next reader does not know which tests, and so cannot judge whether the batch that ran is enough.

**Write only the acceptance this module introduces**; do not copy the whole repository's test suite in. It is "what new guarantees this module brings", not a regression checklist.

If "手动验证" has no content, delete the whole section.

### Dependencies: The Acceptance Item Is `blocked_by` Every Other Item in the Module

This is the only mechanically determined dependency in a module — **fan in from all other items**. Its effect is that it naturally sorts last in `pick-up-work`: as long as any piece of work is unfinished, it is blocked; once everything is done, it surfaces on its own as ready to start, reminding you to run acceptance.

Do not reverse it by making other items depend on it.

### When Not to Create It

For a module that a single item can finish, the acceptance item is pure redundancy — that item's own "完成标准" is already everything. In that case **the module probably should not exist either**; just create one work item.

## Do Not Record "Which Ones Can Run in Parallel"

Parallelism is an inference from the dependency graph, not an independent fact. Once a new dependency is added later, a stored "these can run in parallel" silently becomes wrong, yet it looks exactly like a correct one. As long as dependencies are recorded accurately, the parallel set can be computed at any time (see `pick-up-work`).

## Description Templates

The section labels in these templates and in the acceptance-item template above, plus the acceptance-item title suffix `验收`, are literal strings written into Plane, and they stay in Chinese on purpose: people read them in the Plane UI, and `pick-up-work` matches them verbatim on read-back. Translating them would make items already in Plane go unrecognized.

**Do not write**: which feature it belongs to (Module handles that), what it depends on (relations handle that), what status it is in (state handles that). Once any of these three appears a second time in the body, it will drift from the field, and when they disagree nobody knows which one is true.

### Work Item (`description_html`)

```html
<p><strong>为什么</strong>: what problem this change solves</p>
<p><strong>完成标准</strong>: what conditions must hold for it to count as done</p>
<p><strong>注意</strong>: known pitfalls, constraints, decisions already made</p>
```

**"完成标准" must not be omitted.** It is the only one of the three sections that does not get written naturally — "为什么" comes with the discussion, "注意" either exists or it does not, but if acceptance criteria have no fixed slot, the writing drifts until only a paragraph of background is left. On the next read-back there is no way to judge whether the item is actually done.

Being unable to write completion criteria usually means the item has not been thought through yet, or is cut too large. **Stop and ask the user; do not paper over it with a single "implement xxx".**

If the "注意" section has no content, delete the whole section — do not leave an empty shell.

### Module (description, plain text)

```
目标：what this feature must achieve
不包含：things explicitly placed outside the scope
```

The "不包含" section guards against boundary drift. A feature sprouting unplanned items as work goes on is the most common way this workflow gets out of control; with out-of-scope things written down, when a related idea pops up later you can tell immediately whether it is a new feature or something that was meant to be done all along.

⚠️ **A module's description can only be plain text; do not stuff HTML into it.** The Module does have `description_html` in the database, but it is not on the public API's create/update serializer allowlist — which accepts only `name` / `description` / `start_date` / `target_date` / `status` / `lead` / `members` / `external_source` / `external_id`. HTML tags passed in are stored as literal text.

**Acceptance criteria do not go here** — a module has no state and no comments, so it cannot hold "has it passed acceptance". They belong to the acceptance item.

### Format Constraints

`description_html` **accepts only raw HTML**; escaped entities such as `&lt;p&gt;` are stored verbatim and shown as literal tags in the UI, while the API still returns 200.

Use only these basic tags: `<p>` / `<strong>` / `<ul>` / `<li>`. How far the Plane editor supports more complex tags has not been verified; do not use them.

## Two Silent Failures (Returns 200, Data Is Wrong)

**`description_html` needs raw HTML, not escaped entities.** Passing `&lt;p&gt;` stores it verbatim, the UI shows literal tags, and the API still returns success. Write `<p>…</p>`.

**Do not trust the `state_group` returned by `workitem(action="create")` / `workitem(action="update")`.** create returns `null`, and update returns **the old value from before the change**. To confirm state, go back through the `list` family of endpoints.

## Wrap-Up

Report the created structure to the user: the module name, each item's identifier (e.g. `ABC-1`) and title, and **every relation**. List relations separately — the user being able to see at a glance whether the dependency graph is right is the only human checkpoint in this workflow.

List the acceptance item separately, **together with its "必须通过的测试" entries**. Those entries are what the user is most likely to change — adding a missed test, or cutting one that is not actually needed.

Do not casually assert "these can run in parallel" along the way. To compute it, actually run through the `pick-up-work` flow; **do not judge by eye** — items with multiple blockers are exactly where people most easily miss things.
