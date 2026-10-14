---
name: link-env
description: "Wires a project/worktree to a shared baseline .env kept outside the git working tree, with an optional per-worktree override layer, by writing a gitignored mise.local.toml. Picks the baseline from ~/.local/share/dev-env/env/ by name — <repo>.env when it exists, otherwise dev.env — without asking the user which one. Use when a new git worktree has no .env and shouldn't need one copied in by hand, when the same credentials must be reused across several worktrees of one repo, or when a single worktree needs to override a few env values without diverging from the shared baseline. Triggers on: worktree missing .env, sharing env across worktrees, overriding an env var in just one worktree. Do NOT use for toolchain versions (use setup-toolchain). Never create files in the baseline directory — the user provisions those by hand — and never read, print, or copy the contents of any baseline .env; this skill only wires up paths."
---

# mise-toolchain: Layered Env Vars Across Worktrees (link-env)

## The Problem

`.env` is an untracked file, so `git worktree add` does not carry it into the new worktree. The result: every new worktree needs a hand-copied `.env`, and from then on the copies drift apart independently, with no way to tell which one is correct.

## Approach: Single Source of Truth + Optional Overlay

```
~/.local/share/dev-env/env/     baseline directory — outside the workspace, shared machine-wide, only the user may put files here
  ├── dev.env                   generic fallback: used when there is no project-specific file
  └── <repo>.env                project-specific: preferred when the filename matches the repo name
<worktree>/.env.local           overlay — private to this worktree, holds only the differing lines, may not exist
```

In each worktree, write a **`mise.local.toml`**:

```toml
[env]
_.file = [
  "~/.local/share/dev-env/env/<the-selected-one>.env",  # baseline, see the selection rule below
  ".env.local",                                         # this worktree's private overlay; silently skipped if missing
]
```

Three `_.file` behaviors confirmed by testing (mise 2026.7):

| Behavior | Result |
|---|---|
| Later entries in the array override earlier ones | Yes — for a variable defined in both, `.env.local` wins |
| A listed file does not exist | Silently skipped, no error — so `.env.local` can be created only when needed |
| `~` in the path | Expanded |

Note that the last one is the opposite of Docker Compose: Compose's `env_file:` **does not expand `~`**; there you must write `${HOME}`. The two configs are easy to copy from each other, and getting it wrong shows up as "the container can't see the variable but the host is fine".

## Baseline Selection Rule (the agent must apply this check itself; do not ask the user which one to use)

Let the repo name be `<repo>` (**the repo name, not the worktree directory name** — every worktree of the same repo must point at the same baseline):

1. `~/.local/share/dev-env/env/<repo>.env` exists → use it.
2. Otherwise, `~/.local/share/dev-env/env/dev.env` exists → use it.
3. Neither exists → **stop and tell the user**. Do not continue, and do not fall back to reading the project's own `.env`.

The check uses existence tests only; it does not read contents:

```bash
REPO=$(basename "$(git rev-parse --path-format=absolute --git-common-dir | xargs dirname)")
ENVDIR=~/.local/share/dev-env/env
test -f "$ENVDIR/$REPO.env" && echo "$REPO.env" || { test -f "$ENVDIR/dev.env" && echo dev.env; }
```

Use `--git-common-dir`, not `--show-toplevel`: inside a worktree the latter returns the worktree directory name (e.g. `backend-skeleton`), which selects the wrong baseline.

**Whichever file is selected is the one you write into `_.file` — write only one; do not list both `dev.env` and `<repo>.env`.**

This must be clear because it has a counterintuitive consequence (confirmed by testing): the selected file **replaces the other, it does not patch it**. If `dev.env` has `LLM_API_KEY` and `LLM_MODEL`, and `prison-a.env` contains only `LLM_MODEL`, then once `prison-a.env` is selected, **`LLM_API_KEY` simply disappears**, showing up at runtime as missing credentials.

So a project-specific file must **contain every variable it needs**, not just the differences. If what you want is layered "generic base + project override" semantics, you would list both in `_.file` (the former as the base, the latter as the override) — but that is not this skill's default convention. Unless the user explicitly asks for layering, always follow the exclusive rule above.

## Never Create Baseline Files on the User's Behalf

Any `.env` file in `~/.local/share/dev-env/env/` **may only be created by the user by hand**. The agent must not `touch`, `cp`, `mv`, redirect-write, or in any other way produce a file in that directory — including the seemingly natural "copy the project's existing `.env` over there".

Rationale: this directory is the single source of truth for credentials. Letting the agent handle it means credential contents flow through the session context. And a baseline the agent conjured out of thin air, filled with guesses or placeholders, is worse than a missing file — the latter fails immediately, while the former runs all the way until some ambiguous 401 exposes it.

When a new one is needed, hand the commands to the user to run themselves:

```bash
# Project-specific baseline (note: must include every variable, not just the differences)
$EDITOR ~/.local/share/dev-env/env/<repo>.env
chmod 600 ~/.local/share/dev-env/env/<repo>.env
```

Note that the Read deny on `env/**` in `settings.json` **also blocks Bash write operations on that directory** (such as `chmod`), which is one more reason the commands above must be handed to the user. Existence checks (`test -f`) are unaffected, so the selection rule still works.

## Why mise.local.toml, Not mise.toml

`mise.toml` goes into git. The baseline path is a machine-level absolute path; writing it into `mise.toml` has two consequences: first, the config is not portable (wrong on another machine or for anyone else who clones it); second, each worktree editing this line on its own causes merge conflicts, and can even get one worktree's private path committed to the main branch by mistake.

`mise.local.toml` is mise's official local override mechanism, loaded with higher priority than `mise.toml` (`mise cfg` shows the full load chain). Once it is gitignored:

- `mise.toml` — `[tools]`, in git, shared across worktrees (owned by the `setup-toolchain` skill)
- `mise.local.toml` — `[env]`, gitignored, per-worktree (owned by this skill)

The two skills each write their own file and never overwrite each other. This split follows the same mental model as the Docker Compose side (`docker-compose.yml` in git, `docker-compose.override.yml` gitignored).

## Steps

1. **Confirm `.gitignore` covers both files**; add them if not:

   ```gitignore
   mise.local.toml
   .env.local
   ```

   This step must come first. If you write the files first and add the gitignore entries afterwards, any `git add -A` in between may commit them.

2. **Pick the baseline using the selection rule above** (`<repo>.env` first, falling back to `dev.env`), with existence checks only, never reading contents.

   If neither exists, **stop and tell the user**. Do not create one on their behalf, do not copy the project's existing `.env` over, and do not fall back to reading the project's `.env`. Commands to hand to the user:

   ```bash
   $EDITOR ~/.local/share/dev-env/env/dev.env      # or <repo>.env
   chmod 600 ~/.local/share/dev-env/env/dev.env
   ```

3. **Write `mise.local.toml`** with the content shown above. If a file with that name already exists, do not overwrite it wholesale; merge only within the `[env]` section.

4. **`mise trust`** — new files are untrusted by default, and until trusted, mise commands fail with "error parsing config file" (the first line is misleading; the real cause is trust, not syntax).

5. **Verify**:

   ```bash
   mise env -D | cut -d= -f1 | ugrep '<some-known-var-name>'
   ```

   **The `cut -d= -f1` part must not be omitted.** `mise env -D` outputs `KEY=value`; running `ugrep <var-name>` on it directly prints the matching line **along with its value** — that is exactly how credentials end up in the terminal and the session context, which is precisely what this skill is meant to prevent. Cutting off everything after `=` first leaves only the variable names.

   Likewise, do not look at the full output of `mise env -D` directly.

## When a Worktree's Env Needs Changing

Create `.env.local` in that worktree containing **only the lines you want to change**; everything else keeps inheriting from the baseline:

```bash
echo 'API_BASE_URL=http://localhost:9999' >> .env.local
```

Do not copy the entire baseline and then edit it — that takes you back to the original "multiple copies drifting apart" problem, and what changed is no longer obvious at a glance.

## Explicit Don'ts

- **Do not symlink the baseline into the worktree**. A symlink shares the same file, so editing it in any worktree simultaneously affects the main repo and every other worktree, which breaks exactly the "independent per-worktree override" requirement.
- **Do not read, print, or copy the contents of the baseline or `.env.local`**. This skill's only job is wiring up paths. When you need to confirm a variable is in effect, use the names-only method above.

  This is a **behavioral constraint, not something backstopped by tool-level blocking**. The `Read(//…/dev-env/env/**)` rule in `settings.json` constrains only the Read tool — testing confirmed that `ugrep`, `jq`, and `cat` in Bash can still read the contents. It stops a casual "quick Read", not a workaround. So the real boundary is this rule itself; do not relax it because "there's a deny rule anyway".
- **Do not write the baseline path into any file that goes into git** (`mise.toml`, `docker-compose.yml`; README examples are the exception — a placeholder is fine in docs).

## Relationship to the Container Side

If the project also runs via Docker Compose, the container side must read **the same baseline**; otherwise you get "works on the host, fails in the container", one of the hardest kinds of problem to debug. Wiring up the container side belongs to the `onboard` skill of the `dev-env-router` plugin (written in `docker-compose.override.yml`); the two sides cooperate by agreeing on the same baseline path and do not share config files.
