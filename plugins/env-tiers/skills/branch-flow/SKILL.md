---
name: branch-flow
description: "Runs the branch flow for a three-tier local setup: open worktrees from the production branch (not the UAT branch), merge worktree -> UAT -> prod with merge only — never rebase or cherry-pick — and rebuild UAT with reset --hard when its merge order stops being useful. Use when deciding where to start a Claude Code session or a new worktree in a repo that has both a UAT and a production branch, when a hotfix must reach production without dragging along everything currently sitting in UAT, or when UAT's history has become tangled. Triggers on: 'which branch should this worktree come from', 'ship this one fix without the rest of UAT', 'UAT is a mess, can I reset it', 'should I rebase this onto uat'. Do NOT use for the initial directory/hook setup (that is setup-tiers). Do not propose rebase or cherry-pick as an alternative here — that is the specific thing this flow trades away."
---

# env-tiers: Branch flow and worktree base (branch-flow)

## Prerequisites

Each of the three tiers is a branch, mapped one-to-one to a directory (layout and rationale in `setup-tiers`):

| Tier | Branch | Directory |
|---|---|---|
| Dev | `worktree-*` | `<repo>/.claude/worktrees/*` |
| Integration (UAT) | `uat` | `<repo>-uat/` |
| Prod | `master` / `main` | `<repo>/` |

Below, `master` stands for the prod branch.

## Where to open a session

**By default, open it in the prod directory**, and let the agent open its own worktree when writing code.

This is not because the prod branch is special, but because `baseRef` is set to `head` — **a new worktree grows from the branch the session is on**. Only a session opened in the prod directory gets `master` as the base.

(In repos developed locally, the `baseRef: "head"` setting is not a preference but a requirement: the default `fresh` mode points at `origin/<default>`, and such repos often have no remote, so it points at nothing.)

**The only occasion to open a session in the UAT directory** is handling integration itself — merge conflicts, locating issues found during acceptance testing, rebuilding UAT. At that point UAT's state is exactly what you want.

But **do not open a worktree in the UAT directory**: the base would become `uat`, and the escape hatch described in the next section would be gone. If a bug found in UAT needs its own branch to fix, go back to the prod directory to open it.

## Always open worktrees from master, never from uat

This rule is the core of the whole flow, and the reason is to preserve an **escape hatch**.

When a feature branch is based on `master`, its commits become the common ancestors of both lines. So a hotfix can go live directly via `master merge worktree-x`, and when `master merge uat` happens later, git recognizes that those commits are already there — no duplication, no conflicts.

```
worktree-*  --merge-->  uat  --merge-->  master
     \                                    ^
      \------ hotfix: merge directly ------/
```

If based on `uat`, this diagonal line does not exist: merging any one feature branch drags everything else on uat that **has not finished verification** into master along with it. The only remaining way out is cherry-pick, and that path is dirty (see below).

**Cost**: when two worktrees change the same code, the conflict only surfaces in UAT. Acceptable for a solo developer or a small team; if parallel branches grow numerous enough that conflicts become frequent, this trade-off needs to be recalculated.

## Merge only — no rebase, no cherry-pick

The hotfix path above relies precisely on "**the same commit being an ancestor of both lines**".

`rebase` and `cherry-pick` both produce commits with identical content but different hashes. The path then breaks: git no longer considers the commit on uat and the one on master to be the same thing, and later merges conflict or leave duplicate history.

So in this flow, **the answer to "should I rebase to make the history cleaner" is always no**. Pretty history is not worth this escape hatch.

## UAT can be torn down and rebuilt at any time

The merge order of `uat` has no historical value — it is only a snapshot of "what is currently being verified". When it gets messy, rebuild it:

```bash
git checkout uat && git reset --hard master
git merge worktree-b worktree-c   # re-merge whatever still needs verification
```

**This loses nothing**: the features themselves live on their own `worktree-*` branches, and whatever has already shipped is in `master`. `uat` holds no content unique to it — this is exactly the property that "merge only" buys; if anything was cherry-picked before, it no longer holds.

After a rebuild, the UAT environment must be brought up again: go back to the UAT directory and run `just up`. Whether to wipe the data as well is the user's decision; `reset --hard` only touches code.

## Before merging

Run the gate (`just check`) before entering UAT. Run it in the worktree, not in UAT — the purpose is to surface "the code itself is broken" and "putting it together is broken" separately; otherwise UAT shows a wall of red and you cannot tell who brought it in.

## Agent action checklist for this flow

- Asked to "open a branch to write X" → confirm the current session is in the prod directory; if it is not, say so first, and do not open it in place.
- Asked to "merge X into UAT" → `git checkout uat && git merge worktree-x`, then go to the UAT directory and run `just up` to verify.
- Told "this needs to ship urgently" → run `git merge worktree-x` in the prod directory; **do not** merge into uat first and then into master, and do not cherry-pick either.
- Told "UAT is a mess" → follow the rebuild flow above, but **first list which branches are currently merged into uat** (`git log --merges --oneline master..uat`) for the user to confirm which to keep, then reset.
- Noticing an idea like "a rebase would be cleaner" → do not raise it; the reason is above.
