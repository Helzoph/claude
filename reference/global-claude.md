# Global Claude Instructions

## Skill routing

<rationale-toolkit>
- Use `rationale-style` when writing, modifying, reviewing, or explaining code, especially when a design decision or trade-off needs justification.
- Use `verify-outcomes` after any code, configuration, or workflow change, and when testing or quality assurance is requested.
</rationale-toolkit>

<dev-env-router>
- Use `cleanup` when auditing or removing orphaned dev-env-router containers or stale worktree environments; require explicit confirmation before removal.
- Use `onboard` when connecting a new project or worktree without Traefik labels to the shared local router.
- Use `operate` when starting, stopping, or restarting an already onboarded project, or when reporting its routed URL.
</dev-env-router>

<mise-toolchain>
- Use `setup-toolchain` when pinning language/CLI versions in a project's `mise.toml`.
- Use `link-env` when a worktree needs env vars from the shared baseline in `~/.local/share/dev-env/env/`. It is the single source of truth for the baseline selection rule; `dev-env-router/onboard` applies the same rule on the container side.
- Never read, print, or copy the contents of any file under `~/.local/share/dev-env/env/`, and never create files there — the user provisions those by hand.
</mise-toolchain>

<dev-credentials>
- Use `use-dev-credentials` when a task needs a real API key to actually run or test something. Read `~/.local/share/dev-env/credentials.json` — reading it is authorized, unlike `env/` above — and pass values straight into the command instead of printing them.
- Never fall back to a project's own `.env` for credentials.
</dev-credentials>

<emil-design-skills>
- For any frontend UI, component, animation, or interaction work, pick the matching skill from `emil-design-skills` first — read its own description to choose. Do not hand-roll styling or motion when a skill covers it.
- Exception: `pick-ui-library` and `prototype` are opt-in — use them only when the user explicitly asks to choose a library or to build multiple variants.
</emil-design-skills>

## Tool preferences

<tool-preferences>
- Use `ugrep` instead of `grep`; fall back only when `ugrep` is unavailable.
- Use `bfs` instead of `find`; fall back only when `bfs` is unavailable.
</tool-preferences>

## Principle

<yagni>
Follow YAGNI: implement only the current requirement. Avoid speculative abstractions, configuration, extension points, and automation; prefer the smallest maintainable solution.
</yagni>

<reuse-first>
Before adding a helper, config, dependency, script, or pattern, search the project for one that already does the job, and use it. Extend the existing thing rather than introducing a parallel one; when several existing approaches conflict, follow the one most used in the code you are touching. Introduce something new only when nothing fits, and say in one line what you looked for and why it did not fit. Skip this only when the user explicitly asks for a fresh or separate implementation.
</reuse-first>

<integrity>
Do not pursue the goal at any cost or move the goalposts: never bypass safety or scope boundaries, hide failures, misrepresent verification, or redefine success merely to claim completion. Before declaring that the requested outcome cannot be achieved safely, try at least three genuinely different and reasonable approaches, record what each one showed, and do not count repetitions or reduced safety as separate approaches. Only then may you state the blocker and stop.
</integrity>
