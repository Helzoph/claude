---
name: plan-to-plane
description: "Record a design discussion into Plane as a task graph: attach work items to functional Modules, create the items, and wire their blocked_by dependencies so the graph can be read back and the parallel set computed later. Use this skill when a plan that involves several items and an order between them should be written into Plane — triggers on 'put this plan into Plane', 'record this design as tasks', 'break this into work items'. Item bodies follow write-workitem and Modules follow write-module. The Plane MCP server ships with this plugin but needs a one-time `claude mcp login plane`. Do NOT use for reading back what to do next (use pick-up-work), or for filing a single item with no ordering (use write-workitem)."
---

# Record a Design Discussion as a Task Graph in Plane

The goal is not "save the idea" but **save it in a structure that can be read back as-is next time, with no reinterpretation**. Ownership goes through Module, ordering through relations, status through state, risk through a Label — always structured fields, **never only in the description**. A plan written into body text gets reinterpreted on the next read, and reinterpreted differently.

## Mapping

| Plane concept | What it holds |
|---|---|
| Project | One code repository |
| Module | One **functional area** of the codebase with a long-lived responsibility (e.g. one plugin) — see `write-module` |
| Work item | One change that delivers one observable behaviour and can be reviewed on its own — body per `write-workitem` |
| Label | **Only** the risk level: `risk:high` / `risk:medium` / `risk:low` — rules in `write-workitem` |

Cycle is not used: it is a time dimension (sprint), which this workflow does not have.

Module, Label, Cycle, and Estimate are all **project-scoped** and cannot follow a work item across projects. When a change spans two repositories, the only option is items in each project, linked by a cross-project `workitem_relation`.

## Prerequisite: Confirm the Project and Make Sure Modules Is Enabled

First run `project(action="list")` to find the target project. **If no matching project exists, stop and ask the user** — do not create one on your own initiative.

A new project **defaults to Modules disabled**; unless you enable it first, Module calls fail outright:

```
project(action="update_features", project_id=..., modules=true)
```

For an existing project, confirm it once as well (`project(action="get_features")`) — do not assume it is on.

## Write Order (Step 4 Is a Separate Step and Mandatory)

1. **Modules** — invoke `plane-taskgraph:write-module` and map every item to existing functional Modules. If one is missing, write-module says to stop and ask; do so before creating anything.
2. **Items** — invoke `plane-taskgraph:write-workitem` and create the items one by one, each with its body and exactly one `risk:*` Label.
3. **Attach** — `module(action="manage_workitems")` for each Module, as write-module describes.
4. **Dependencies** — `workitem_relation(action="create")` for every `blocked_by`.

Step 4 can be neither skipped nor moved earlier: relations need item IDs, which exist only once all items are created. **Reporting "done" to the user as soon as the items are created is a failure** — at that point there is not a single dependency, the graph is disconnected, and on read-back every item will be judged ready to start.

## Dependencies: Use Only `blocked_by`, Created From the Blocked Side

There are only 6 built-in relation types: `blocking` / `blocked_by` / `start_before` / `start_after` / `finish_before` / `finish_after`. The last four are for Gantt-chart scheduling and have nothing to do with "can this start"; **do not use them**.

**Always create `blocked_by` from the blocked item**, pointing at the item that blocks it. That way the fact "who is blocking me" lives on the item that needs it.

Plane **stores relations bidirectionally**: after A creates `blocked_by B`, reading B shows `blocking: [A]`. So there is no need to maintain the reverse edge yourself, and do not create a duplicate reverse `blocking` relation.

**"Related but not blocking" is a custom relation, not a built-in type.** It goes through `relation_definition_id` + `relation_definition_label`, with label `"relates to"` (**with a space**, not `relates_to`). The workspace ships with this definition by default; run `workitem_relation(action="list_definitions")` to get its id before using it.

## Record Dependencies Between Work Items, Not Between Modules

A module-level statement like "payments depends on login" is usually false — the truth is often "the item in payments that reads user info depends on the item in login that issues the session", while the rest of payments has nothing to do with login. Record it at Module level and **work that could run in parallel is misjudged as unable to**, which destroys exactly the capability this approach exists for.

If it comes up that "all of B must wait for A" but no one can name the specific two items, the dependency has not been thought through yet: **stop and ask the user** — do not record a vague one.

## Where Integration Checks Go

There is no separate sign-off item per Module. A check that spans several items goes into the `验证` of the **most-downstream** item of the dependency chain (see write-workitem, "Sizing an Item"). If no item sits downstream of all the parts, stop and ask the user — the split is probably wrong.

## Do Not Record "Which Ones Can Run in Parallel"

Parallelism is an inference from the dependency graph, not an independent fact. Once a new dependency is added later, a stored "these can run in parallel" silently becomes wrong, yet it looks exactly like a correct one. As long as dependencies are recorded accurately, the parallel set can be computed at any time (see `pick-up-work`).

## Wrap-Up

Report the created structure to the user:

- each item's identifier (e.g. `ABC-1`), title, its `risk:*` Label, and its Module(s). Reason: this is where a wrongly rated level is most likely to be noticed;
- **every relation**, listed separately (`ABC-2 blocked_by ABC-1`). Seeing at a glance whether the dependency graph is right is the only human checkpoint in this workflow;
- any `risk:*` Label that had to be created in the project.

Do not casually assert "these can run in parallel" along the way. To compute it, actually run through the `pick-up-work` flow; **do not judge by eye** — items with multiple blockers are exactly where people most easily miss things.
