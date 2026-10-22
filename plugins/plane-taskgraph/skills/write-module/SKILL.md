---
name: write-module
description: "Decide which Plane Module(s) a work item belongs to and attach it, or — only after the user agrees — create a new Module with the plain-text description template (职责 / 边界 / 代码位置 / 出错时的表现 / 默认风险). A Module is a long-lived functional area of the codebase (e.g. one plugin), never a milestone or one request. Use this skill whenever a work item is being filed and needs a Module, when a change spans several areas, or when asked to create, describe, or reorganise Modules — triggers on 'which module does this go in', 'create a module for X', 'record a change to <component>'. The Plane MCP server ships with this plugin but needs a one-time `claude mcp login plane`. Do NOT use for writing the work item body itself (use write-workitem)."
---

# Plane Modules as Functional Areas

A Module is **a functional area of the codebase with a long-lived responsibility** — in a plugin marketplace, one plugin; in an app, "auth", "billing", "search". It is **not** a milestone, a release, or "the thing we are doing this week".

The test: **after this change is finished, will this Module keep receiving new items?** If yes, it is a functional Module. If it would be "done" when this batch is done, it is a milestone in disguise — and it will go stale, pile up, and stop telling anyone anything.

## Attaching an Item

1. `module(action="list", project_id=...)` and read the existing Modules' names and descriptions.
2. Map each place named in the item's `涉及范围` to the Module whose `职责` / `代码位置` covers it.
3. **Attach the item to every Module it touches** — one per functional area in `涉及范围`:

   ```
   module(action="manage_workitems", module_id=..., workitem_ids=[...])
   ```

   `manage_workitems` appends; it does not remove existing attachments, so call it once per Module. A PQL filter on either Module then returns the item. Reason: an item attached to only one of two areas is invisible to anyone looking at the other, and `pick-up-work` for that area under-counts.

4. Read back with PQL to confirm, e.g. `module IN ("<module-uuid>")` for each Module.

## When No Existing Module Fits

**Stop and ask the user** — do not create a Module on your own, and do not create the work item yet. Say which part of the change has no home, and propose a name.

Reason: the set of functional Modules should be stable. Creating one per request is exactly how Modules turn back into milestones.

Only after the user agrees, create it with the plain-text template below, then attach the item.

## Description Template (Plain Text)

Section names are Chinese literals, kept as-is because people read them in the Plane UI. Write the content in the user's language. Every line under `边界` and `默认风险` ends with a reason.

```
职责：what this area is responsible for, in one or two sentences
边界：
- what is explicitly NOT this Module's job, and which Module owns it instead. 原因：…
代码位置：
- path/or/glob/**
出错时的表现：
- what users or other areas see when this area is broken
默认风险：medium. 原因：why changes here usually land at this level
```

- `边界` stops scope creep: when a related idea shows up later, it is immediately clear whether it belongs here.
- `代码位置` is what step 2 of "Attaching an Item" maps against.
- `默认风险` is a starting point for items in this Module, not a substitute for rating each item (see write-workitem).

## Plain Text Only

The public API's Module create/update accepts only `name`, `description`, `start_date`, `target_date`, `status`, `lead`, `members`, `external_source`, `external_id`. There is no `description_html` on that path: **any HTML tags you pass in `description` are stored and shown as literal text.** Use line breaks and `- ` bullets only.

## What a Module Does Not Hold

- **Progress.** Leave the Module's own `status` at its default. Progress is the states of its items; recording it twice means the two drift apart.
- **Acceptance verdicts.** Each work item carries its own 完成标准 and 验证; there is no Module-level acceptance.
- **Milestones / dates.** Plane's Milestone feature is not used: it has no body, no state, no comments.

## Prerequisite

A new project defaults to Modules disabled. Check once with `project(action="get_features")`; if `modules` is off, `project(action="update_features", modules=true)` before creating anything.
