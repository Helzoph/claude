# plane-taskgraph

A Claude Code plugin that turns a design conversation into a **structured task
graph in Plane** — one an agent can read back later without reinterpreting it,
then work through item by item, leaving a verification record on each.

## The problem

Talk through a change with an agent, have it file the resulting issues, come
back a week later and say "do ABC-12". If the plan lives in prose — "this one
touches the API layer and has to come after the schema change" — the agent
re-reads that prose and reconstructs a slightly different plan than the one you
agreed on. Nothing errors. The planning was just quietly wasted.

The same happens at the other end: the agent says "tested, done", and a week
later nobody can tell what it ran, against which commit, or which files it
actually changed.

## The idea

Put every part of the plan a machine needs to act on into a **field**, not a
sentence:

| Concept | Where it lives |
|---|---|
| Which functional area an item touches | Module (one per long-lived area, e.g. one plugin) |
| What has to come first | `blocked_by` relation |
| How risky it is | Exactly one Label: `risk:high` / `risk:medium` / `risk:low` |
| Whether it's done | State (its `group`, not its name) |
| Why, scope, done-criteria, how to verify | Description, in a fixed `h3` template |
| What was verified, against which commit | One comment per verification run |

Anything in the structured rows that also appears in prose is a second copy
that will drift, with nothing to catch it.

**Parallelism is derived, never recorded.** A stored "these three can run in
parallel" becomes wrong the moment a dependency is added — and looks exactly
like a correct one. Computed from the graph (unfinished items whose
`blocked_by` are all done), it cannot go stale.

## What's included

### Skills

| Skill | Triggers on | What it does |
|---|---|---|
| [`write-workitem`](skills/write-workitem/SKILL.md) | filing or editing a single item, "rate the risk of ABC-3" | The source of truth for an item body: the `h3` template (为什么 / 涉及范围 / 风险 / 完成标准 / 验证, plus optional 不做 / 回退 / 注意), the `risk:*` Label rules, and how e2e checks are written so the agent can run them headless |
| [`write-module`](skills/write-module/SKILL.md) | "which module does this go in", "create a module for X" | Maps an item onto existing functional Modules (attaching it to every one it touches); creates a new Module only after you agree, with a plain-text description template |
| [`plan-to-plane`](skills/plan-to-plane/SKILL.md) | "record this into Plane", "break this into work items" | Orchestrates the two above for a whole design, then **wires the `blocked_by` relations** as a separate mandatory step and lists every relation back to you |
| [`pick-up-work`](skills/pick-up-work/SKILL.md) | "what can I work on next", "do ABC-12", "is the X module done?" | Computes what can start now; does an item — reads the body, pauses according to its risk Label, commits with a `Refs: ABC-12` trailer, posts a verification-record comment, and only then marks it done |

### Script

`skills/pick-up-work/scripts/changed-files.sh <ITEM-ID> [ignored-path ...]`
prints the "changed files" block of a verification record as HTML, straight
from git: every commit whose message carries the trailer line
`Refs: <ITEM-ID>`, each commit's `--name-status`, the union of files, and
`git status --porcelain`. Gitignored files the item touched can be passed as
extra arguments; they are listed with their `git check-ignore -v` line as
evidence, and a path that is not actually ignored is refused.

### MCP server

Ships `.mcp.json` pointing at Plane's official OAuth endpoint
(`https://mcp.plane.so/http/mcp`). No API key is stored anywhere in this
repository — see Installation for the one-time authorisation step.

## Design notes

**Modules are functional areas, not milestones.** The test is "will this Module
keep receiving new items after this batch is done?" A Module created per request
goes stale, piles up, and stops telling anyone anything. An item that touches
two areas is attached to both, so neither area's read-back misses it.

**Risk is a Label, and it changes what the agent does.** `risk:high` (hard to
undo, or reaches outside the repo) pauses before any write and again before
marking done, and cannot start without a `回退` block. `risk:medium` pauses once,
before marking done. `risk:low` runs through on its own. A missing Label, two
Labels, or a Label that disagrees with the body's 风险 paragraph is treated as
the higher level, and the agent asks. Only an explicit "yes" counts as
confirmation — an unrelated reply does not.

**No verification record, no "done".** Before an item may move to the
`completed` group, the agent posts one comment with four blocks: the verdict
and commit, the changed files (pasted unchanged from `changed-files.sh`, never
hand-written), what ran with exit codes and session ids, and what was not
verified and why. Failed runs are recorded too, and earlier comments are never
edited — they are the history.

**e2e checks are run by the agent, not by you.** Behavioural checks in an
item's 验证 are written as headless `claude -p --plugin-dir …` runs with fixed
assertions on the stream-json output (plugin loaded from the repo, the expected
skill fired, no error, zero permission denials), plus read-backs of Plane
fields. "The agent stopped" is judged by state — git HEAD, the item's
`updated_at`, its comment count — never by what the reply says.

**No separate sign-off item.** A check that spans several items goes into the
验证 of the most-downstream item of the chain, next to the change it checks.

**Dependencies are recorded between work items, never between modules.**
"Payments depends on login" is usually false. The truth is that *one* item in
payments needs the session token, while the refund logic and the reconciliation
job have nothing to do with login. Recorded at module level, the whole module
reads as blocked and work that could have started today is held back.

**Reading dependencies is a whitelist, not a blacklist.** Only
`dependencies.blocked_by` counts as blocking. Custom relation labels are
arbitrary, so "everything except *relates to*" is one new relation definition
away from being silently poisoned. The `blocking` bucket must also be ignored:
it is Plane's auto-generated reverse edge, and counting it inverts every
dependency.

**Old items still read.** Items written before the `h3` template (bold-label
paragraphs such as 完成定义 / 必须通过的测试 / 手动验证) are mapped onto the
current blocks on read-back, so nothing already in Plane goes unrecognised.

**Templates live in the skill, not in Plane.** Plane's work item templates are
applied by picking one in the create modal; they have no effect on anything
created through the API. A copy over there would drift, with nothing to catch
it.

## Known API traps

These were found by running the whole flow against a real workspace. Each one
returns HTTP 200 and stores or reports wrong data:

- **`workitem(update)` returns a stale `state_group`.** Trusting it makes a
  just-completed item read as still open, so the next parallel set is
  under-counted. Re-`list` to confirm.
- **`workitem(update)` replaces `description_html` and `labels` wholesale.**
  Retrieve first and send the full value back, or other blocks and Labels
  silently disappear.
- **A fresh project ships with Modules disabled.** Module calls fail until
  `project(update_features, modules=true)` runs.
- **`description_html` takes raw HTML.** Escaped entities (`&lt;p&gt;`) are
  stored verbatim and render as literal tags. A Module's description, by
  contrast, is plain text only — HTML passed there is shown literally.
- **New work items default to the `backlog` group**, not `unstarted`. So
  `backlog` does not mean "not yet planned" — only `completed` and `cancelled`
  may be filtered out when computing what's available.
- **Long non-ASCII payloads are occasionally corrupted in transit** (a
  character turns into U+FFFD). Every write is read back and checked.

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

If you have many plugins installed, Claude Code may list some skills by name
only (their descriptions do not fit its skill-listing budget), and then a
question like "is the X module done?" is answered without loading
`pick-up-work`. Naming the skill in the request, or raising
`SLASH_COMMAND_TOOL_CHAR_BUDGET`, avoids that.

## Requirements

- A Plane account ([app.plane.so](https://app.plane.so) or self-hosted)
- A workspace with at least one project
- `git` and `bash` for `changed-files.sh`

## License

Apache-2.0
