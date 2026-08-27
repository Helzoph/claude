# plane-taskgraph

A Claude Code plugin that turns a design conversation into a **structured task
graph in Plane** — one an agent can read back later without reinterpreting it.

## The problem

Talk through a feature with an agent, have it file the resulting issues, come
back a week later and say "implement the search feature". If the plan lives in
prose — "these three are part of search, and the API layer has to come after
the schema" — the agent re-reads that prose and reconstructs a slightly
different plan than the one you agreed on. Nothing errors. The planning was
just quietly wasted.

## The idea

Put every part of the plan a machine needs to act on into a **field**, not a
sentence:

| Concept | Where it lives |
|---|---|
| Which feature an item belongs to | Module |
| What has to come first | `blocked_by` relation |
| Whether it's done | State (its `group`, not its name) |
| Why, what counts as done, known traps | Description |

Anything in the first three that also appears in prose is a second copy that
will drift, with nothing to catch it.

**Parallelism is derived, never recorded.** A stored "these three can run in
parallel" becomes wrong the moment a dependency is added — and looks exactly
like a correct one. Computed from the graph (unfinished items whose
`blocked_by` are all done), it cannot go stale.

## What's included

### Skills

| Skill | Triggers on | What it does |
|---|---|---|
| [`plan-to-plane`](skills/plan-to-plane/SKILL.md) | "record this into Plane", "create issues for this", after settling on a design | Creates the Module, the work items, attaches them, then **wires the `blocked_by` relations** as a separate mandatory step |
| [`pick-up-work`](skills/pick-up-work/SKILL.md) | "implement the xxx feature", "what can I work on next" | Reads the module back, computes which items are unblocked right now, reports what the blocked ones are waiting on |

### MCP server

Ships `.mcp.json` pointing at Plane's official OAuth endpoint
(`https://mcp.plane.so/http/mcp`). No API key is stored anywhere in this
repository — see Installation for the one-time authorisation step.

## Design notes

**Dependencies are recorded between work items, never between modules.**
"Payments depends on login" is usually false. The truth is that *one* item in
payments needs the session token, while the refund logic and the reconciliation
job have nothing to do with login. Recorded at module level, the whole module
reads as blocked and work that could have started today is held back — which
defeats the entire purpose.

**Reading dependencies is a whitelist, not a blacklist.** Only
`dependencies.blocked_by` counts as blocking. Custom relation labels are
arbitrary, so "everything except *relates to*" is one new relation definition
away from being silently poisoned. The `blocking` bucket must also be ignored:
it is Plane's auto-generated reverse edge, and counting it inverts every
dependency.

**No hook, no script.** A hook can't distinguish "these items genuinely have no
dependencies" from "the dependencies were forgotten" — it could only fire after
every batch, and an alert that is usually wrong gets ignored. Computing the
parallel set in a script would mean re-implementing over REST what the MCP
server already exposes.

**Templates live in the skill, not in Plane.** Plane's work item templates are
applied by picking one in the create modal; they have no effect on anything
created through the API. A copy over there would drift, with nothing to catch
it.

## Known API traps

These were found by running the whole flow against a real workspace. Each one
returns HTTP 200 and stores wrong data:

- **`workitem(update)` returns a stale `state_group`.** Trusting it makes a
  just-completed item read as still open, so the next parallel set is
  under-counted. Re-`list` to confirm.
- **A fresh project ships with `module_view: false`.** Creating a module fails
  until `project(update_features, modules=true)` runs.
- **`description_html` takes raw HTML.** Escaped entities (`&lt;p&gt;`) are
  stored verbatim and render as literal tags.
- **New work items default to the `backlog` group**, not `unstarted`. So
  `backlog` does not mean "not yet planned" — only `completed` and `cancelled`
  may be filtered out when computing what's available.

## Installation

From within Claude Code:

```
/plugin marketplace add helzoph/claude
/plugin install plane-taskgraph@helzoph-claude-marketplace
```

Then authorise the MCP server once:

```
claude mcp login plane
```

If a Plane server is already configured locally, remove it first
(`claude mcp remove plane -s local`) so the two don't collide.

## Requirements

- A Plane account ([app.plane.so](https://app.plane.so) or self-hosted)
- A workspace with at least one project

## License

Apache-2.0
