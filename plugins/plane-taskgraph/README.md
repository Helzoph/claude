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
| Which delivery an item is part of | `parent` field, pointing at a parent item (one per delivery) |
| What has to come first | `blocked_by` relation |
| How hard it is to undo | Exactly one Label: `risk:high` / `risk:medium` / `risk:low` |
| Whether it waits on your decision | Label `needs:decision`, mirrored by a `待定` block in the body |
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
| [`write-workitem`](skills/write-workitem/SKILL.md) | filing or editing a single item, "rate the risk of ABC-3", "add this decision to ABC-3", "this item depends on ABC-2", "put ABC-3 under the login delivery" | The source of truth for an item body: the `h3` template (为什么 / 涉及范围 / 风险 / 完成标准 / 验证, plus optional 不做 / 回退 / 待定 / 注意), the `risk:*` and `needs:decision` Label rules, a variant for design / spike items, the short parent-item template (为什么 / 交付, plus optional 不做 / 注意), dependencies as `blocked_by` relations (never prose), and how e2e checks are written so the agent can run them headless. Format rules and the e2e recipe live in `references/` |
| [`write-module`](skills/write-module/SKILL.md) | "which module does this go in", "create a module for X" | Maps an item onto existing functional Modules (attaching it to every one it touches); creates a new Module only after you agree, with a plain-text description template |
| [`plan-to-plane`](skills/plan-to-plane/SKILL.md) | "record this into Plane", "break this into work items" | Groups the design into deliveries (one parent item each, shown to you before writing), orchestrates the two above, then **wires the `blocked_by` relations** as a separate mandatory step and lists every relation back to you |
| [`pick-up-work`](skills/pick-up-work/SKILL.md) | "what can I work on next", "do ABC-12", "is the X module done?" | Computes what can start now (parents and `needs:decision` items excluded, blockers judged against every open item in the project); does an item as an eight-step checklist — reads the body, moves it to a started state, stops on `needs:decision`, asks for a brief confirmation on `risk:high`, commits with a `Refs: ABC-12` trailer, posts a verification-record comment, and only then marks it done and reads the state back — then moves the parent along when its first child starts or its last open child completes |
| [`project-status`](skills/project-status/SKILL.md) | "项目现在什么情况", "有什么要我决定的", "what's going on in ABC" | A read-only, whole-project overview in four columns — 等你决定 (each open choice quoted, so you can answer them all in one reply), 等你确认 (`risk:high` items free to start), 进行中, 被卡住 (with the blocker's ID). Computed fresh every time; never writes to Plane and never saves the overview |

### Script

`skills/pick-up-work/scripts/changed-files.sh <ITEM-ID> [ignored-path ...]`
prints the "changed files" block of a verification record as one line of
HTML, straight from git: every commit whose message carries the trailer line
`Refs: <ITEM-ID>`, each commit's `--name-status`, the union of files, and
`git status --porcelain`. Gitignored files the item touched can be passed as
extra arguments; they are listed with their `git check-ignore -v` line as
evidence, and a path that is not actually ignored is refused.

`scripts/e2e.sh <out.jsonl> <prompt>` runs one headless `claude -p` session
against this repository's copy of the plugin (from the current directory, so
`cd` into the fixture first) and checks the transcript: the repo copy at the
manifest's version was loaded, which skills and tools ran, and that the run
ended with no error and no permission denials (or exactly the denials listed
in `E2E_EXPECT_DENIALS`, for an e2e that tests a hook's deny). `--check <out.jsonl>` re-checks
an existing transcript; `--dry-run` prints the command. It refuses to start
outside a sandbox (`SANDBOX_RUNTIME` is not `1`), because the child agent gets
unrestricted Bash while reading Plane content; `E2E_UNSANDBOXED_OK=1` overrides
that. Environment knobs
(`E2E_SKILL_BUDGET`, `E2E_DISABLE_PLUGINS`, …) are listed at the top of the
script and explained in `skills/write-workitem/references/e2e-recipe.md`.

### Hooks

`hooks/hooks.json` registers three hooks. All are plain bash + `jq` and fail
open: if `jq` (or, for the Stop hook, `git`) is missing or the input does not
parse, they say nothing and let the call through.

- **`check-workitem-body.sh`** (`PreToolUse` on every Plane connection's
  `workitem` tool — matcher `^mcp__.*plane.*__workitem$`, so the plugin's own
  MCP, a server added by hand such as `plane-remote`, and the claude.ai
  connector are all covered, while `workitem_comment` / `workitem_relation` are
  not — `create` / `update` only). It **rejects** the call — Claude sees the
  reason and retries — when the body would break read-back: whitespace or a
  newline next to a block tag, `h3` blocks missing, renamed (`涉及范围（摸底）`),
  invented or out of order (a body whose second `h3` is `交付` is checked
  against the parent template instead), or a body sent only as `description_stripped`. It
  **warns without blocking** when the title or body contains something that
  looks like a work item identifier (`见 ABC-12`) or a numbered step (`第二步`),
  pointing at `blocked_by` instead; identifiers such as `UTF-8` also match, so
  this stays a note, not a rejection.
- **`remind-state-update.sh`** (`Stop`). It asks git — not the text of the
  Bash commands — whether the session's repository got a commit since the turn
  started whose message has a `Refs: <ITEM-ID>` line (the same whole-line form
  `changed-files.sh` looks for). If so, and after the last such commit the turn
  did not both post a comment and change an item's state, it holds the turn
  open once and names what is missing. It fires at most once per stop
  (`stop_hook_active`), so an item left open on purpose costs one sentence.
  Asking git means a command that merely *contains* `git commit … Refs: X-1`
  (a `claude -p` prompt in an e2e run, an `echo`) does not trigger it, and a
  `git commit -F <file>` does.
- **`route-plane-prompt.sh`** (`UserPromptSubmit`). When the message contains
  something that looks like a work item identifier (`FMTLAB-12 能开工吗`) or
  asks what can start (`现在能开工哪些`), it adds one sentence of context naming
  `pick-up-work`; when it asks how a project stands (`项目现在什么情况`,
  `有什么要我决定的`), it names `project-status`. It **never blocks and never
  rewrites** the message — it only adds a note, ending with "if the message is
  not about Plane, ignore this note". It exists because with many plugins
  installed Claude Code lists skills by name only, and these questions then get
  answered by eye. Identifier prefixes that are usually standards (`UTF-8`,
  `ISO-8601`, `SHA-256`, `RFC-7231`, …) are skipped and the phrase lists are
  narrow, because a note on every unrelated message is worse than a missed one.

The skills already state these rules. The hooks exist because edits made
without loading a skill never see them, and the end-of-turn state update is
the step most often dropped. They only reject what is mechanically certain to
be wrong; a guard that blocks too much gets switched off entirely.

Known limits: the Stop hook only checks the session's working directory (the
`cwd` it is given), so a commit made after `cd` into another repository or
worktree is not seen, while a commit made in that directory by a child process
(an e2e `claude -p` run pointed at the same repository) is; a body that is not
in the template (an epic
written by hand, say) is rejected on update until it is converted.

### MCP server

Ships `.mcp.json` pointing at Plane's official OAuth endpoint
(`https://mcp.plane.so/http/mcp`). No API key is stored anywhere in this
repository — see Installation for the one-time authorisation step.

## Design notes

**Modules are functional areas, not milestones.** The test is "will this Module
keep receiving new items after this batch is done?" A Module created per request
goes stale, piles up, and stops telling anyone anything. An item that touches
two areas is attached to both, so neither area's read-back misses it.

**Deliveries are parent items, one level deep.** A Module never finishes, so
it cannot say "these five items are the login feature". A parent item can: it
has a body (为什么 / 交付), a state, and comments, which is why it is used
instead of Plane's Milestone. A parent is not work — no Module, no `risk:*`
Label, no `blocked_by`, no 完成标准 / 验证 — and `pick-up-work` filters it out
with `NOT hasChildren()`. Its state is copied from the children by the same
rule every time (first child started → started; last open child completed →
completed), and "is delivery X done?" is answered from the children, not from
that copy. Plain parents rather than Plane's Epic type, because Epics need the
`epics` and `work_item_types` project features, which a fresh project does not
have.

**Risk is a Label, and it measures only how hard the change is to undo.**
`risk:high` means one `git revert` is not enough — a data migration without a
down step, a message sent, a `git push`, credentials, deployment. Before any
write the agent stops with a short confirmation: what will change beyond the
repo and how it would be undone (it cannot start without a `回退` block); it
waits again before marking done. `risk:medium` (undone cleanly by
`git revert`, including an additive migration that ships with its down step)
never waits: the agent says so when it starts and lists the item, its files and
its revert command in the final report. `risk:low` runs through on its own. A
missing Label, two Labels, or a Label that disagrees with the body's 风险
paragraph is treated as the higher level, and the agent asks. Only an explicit
"yes" counts as a go-ahead — an unrelated reply or a counter-proposal does not.

**Choices you have not made are a separate Label: `needs:decision`.** Any
number, default, rule or user-visible wording you did not state goes into the
item's `待定` block — each with the candidates and the agent's lean — and the
item carries `needs:decision`. Such an item is never offered as ready to start;
`pick-up-work` lists it under `等你决定` instead. When you answer, one update
moves the answer into `注意` as `已定（date）`, removes the `待定` entry and
drops the Label. This is kept apart from risk on purpose: a choice that needs
you is not the same thing as a change that is hard to undo, and folding the two
together made `high` mean "talk to me first" for things a revert could fix.

The split follows two Anthropic write-ups:
[Solving code review at Anthropic](https://claude.dev/blog/solving-code-review-at-anthropic/)
and
[Redesigning source control](https://www.anthropic.com/engineering/redesigning-source-control).

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

**Order lives in relations, never in text.** `见 ABC-12`, `等 ABC-12 做完`,
"第二步" in a title, a `[Module]` prefix, or "已完成" in the body all restate
something Plane already models — and the copy in prose is the one that goes
stale, because nothing reads it. Every ordering is a `blocked_by` relation
created from the blocked item; a pure "see also" is the `relates to` relation.

**Design items use the same template.** A spike or design item gets one
完成标准 per question it must answer and 验证 entries that check the written
decision; its e2e line says why it does not apply. Decisions reached while an
item is open go into 注意 as `已定（YYYY-MM-DD）：… 原因：…`, not into 为什么.

**State is part of doing the item.** The item moves to a `started` state
before the first file is touched and to a `completed` state only after the
record is posted — then the state is read back, because the update response
lies (see below). The final report quotes that read-back state; a report
without it means the step was skipped.

**No separate sign-off item.** A check that spans several items goes into the
验证 of the most-downstream item of the chain, next to the change it checks.

**Dependencies are recorded between work items, never between modules.**
"Payments depends on login" is usually false. The truth is that *one* item in
payments needs the session token, while the refund logic and the reconciliation
job have nothing to do with login. Recorded at module level, the whole module
reads as blocked and work that could have started today is held back.

**A blocker is judged against every open item, not the scope asked about.**
Reading one Module or one delivery narrows the candidate set; an open blocker
in another Module is then simply absent from it, and "absent" used to read as
"done". The open set is fetched project-wide (ids only) for that check.

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
- **Whitespace between HTML tags becomes empty bullets.** Plane stores the
  newlines and indentation between tags verbatim; once the item is saved from
  the web editor, each gap turns into an empty `<li>` or `<p>`. Bodies and
  comments are sent as one line, and `changed-files.sh` prints one line.
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
