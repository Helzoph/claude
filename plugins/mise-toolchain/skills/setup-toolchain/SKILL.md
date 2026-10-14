---
name: setup-toolchain
description: "Creates or updates a project's mise.toml [tools] block so the languages and CLI tools it needs are version-pinned, inheriting the machine's own version preferences (e.g. python 3.12 rather than latest) instead of defaulting everything to latest. Use when setting up a new project/worktree's toolchain, when adding a language or tool to an existing mise.toml, or when a project has no pinned versions and 'works on my machine' drift is a concern. Triggers on: pinning tool versions, adding go/python/node/rust to a project, setting up mise for a repo. Do NOT use for env variables or secrets (use link-env instead), and do NOT use this skill to author [tasks] — task orchestration is hand-written domain knowledge, not generated."
---

# mise-toolchain: Pinning Toolchain Versions (setup-toolchain)

## Core Idea

The language/CLI versions a project uses are consolidated into `mise.toml` at the project root, instead of relying on "whatever happens to be installed on this machine".

Key principle: **version specs inherit the machine's preferences rather than defaulting to `latest`**. The user's global `~/.config/mise/config.toml` already expresses their version preference for each tool (e.g. `python = "3.12"` rather than latest). A project config that ignores this preference and writes `latest` makes the project's versions diverge from the ones the user works with day to day — and this kind of mismatch often only surfaces at runtime.

## Determining the Machine's Preferences: Check Each Tool, Don't Guess

For every tool to be written into `mise.toml`, first look up its version spec in the machine's global config:

```bash
mise config get tools.<tool-name>
```

- **Output present** (e.g. `3.12`, `latest`, `lts`): **copy it verbatim into `mise.toml`**; do not rewrite it on your own initiative. If the user wrote `lts`, keep `lts`; if they wrote `3.12`, keep `3.12`.
- **No output / error**: the machine has no preference for this tool; write `latest`.
- **The `mise` command itself does not exist** (`command -v mise` fails): no preferences can be read, so **write `latest` for every tool**, and explicitly tell the user: "mise is not installed on this machine, so latest was used for everything; once mise is installed you can rerun this skill to inherit your version preferences".

Do not reverse-engineer version specs from `mise ls` output. `mise ls` shows **resolved concrete versions** (e.g. `python 3.12.13`); writing that into `mise.toml` pins a spec that should follow patch updates down to the patch number, which contradicts the intent of the user's global `3.12`. Only `mise config get` returns the spec itself.

## Writing Rules

1. **Handle only `[tools]`**. Do not generate `[tasks]` and do not generate `[env]`.
   - `[tasks]` is project-specific orchestration knowledge (dependencies, directory changes, failure handling); a version the agent invents from scratch is usually wrong, and it overwrites what the user wrote by hand.
   - `[env]` belongs to the `link-env` skill, and is written in `mise.local.toml`, not `mise.toml` — see that skill.

2. **When `mise.toml` already exists, overwriting the whole file is forbidden**. Only add or remove entries inside the `[tools]` table, and leave every other section (especially `[tasks]`, `[env]`, `[settings]`) untouched. If you need to change the version of a tool the user has already written, first explain the difference between the current value and the proposed value, and wait for the user to confirm.

3. **The set of tools comes from what the project actually uses**; do not copy over the whole tool list from the global config. Base the decision on actual evidence in the project: `go.mod`, `pyproject.toml`/`requirements.txt`, `package.json`, `Cargo.toml`, `foundry.toml`, etc. Do not write tools the project does not use.

4. **Package managers and auxiliary CLIs generally get `latest`** (things like `pnpm`, `uv`, `sqlc`), unless the machine's preferences say otherwise — their versions have little effect on project behavior, and pinning them only adds maintenance burden. Languages themselves should carry major.minor (`python = "3.12"`, `node = "24"`, `rust = "1.97"`).

5. **Add a comment saying which part each tool serves**, especially in monorepos / multi-language projects:

   ```toml
   [tools]
   rust   = "1.97"      # backend/core · Axum + sqlx
   python = "3.12"      # backend/quant · FastAPI
   node   = "24"        # frontend · React + Vite
   pnpm   = "latest"    # frontend package manager
   ```

   Small single-language projects do not need comments for the sake of it; a comment with no information (`go = "latest"  # go`) is worse than none.

## After Writing: You Must Trust

mise distrusts **newly appearing config files** by default, and until they are trusted, any `mise` command fails outright:

```
mise ERROR error parsing config file: .../mise.toml
mise ERROR Config files in .../mise.toml are not trusted.
```

Note that the first line of this error points at "parse failure", which easily misleads you into thinking the TOML syntax is wrong; the real cause is the trust issue in the second line. So after generating or modifying the file, run:

```bash
mise trust
```

**Each worktree must be trusted separately** (trust records are stored by file path, and a new worktree is a new path). This is also the most common reason a new worktree errors the first time it runs `mise`.

## Verification

```bash
mise ls          # confirm each tool's requested_version matches mise.toml
mise install     # install missing versions (may take a while: downloads and compiles)
```

If the `requested_version` shown by `mise ls` does not match what `mise.toml` says, a closer config file is usually overriding it (`mise.local.toml`, a `mise.toml` in a parent directory). Use `mise cfg` to list every config file currently in effect and its load order to pin it down; do not guess.
