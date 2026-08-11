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

<emil-design-skills>
- Use `emil-design-eng` for UI polish, component design, and animation decisions.
- Use `animate` when building a new animation, transition, or motion interaction.
- Use `review-animations` when reviewing existing animation or motion code.
- Use `improve-animations` when auditing animation across a codebase and producing an improvement roadmap; it is read-only.
- Use `find-animation-opportunities` when looking for places where motion could improve a UI; it proposes changes and does not implement them.
- Use `animation-vocabulary` when naming or identifying a motion effect from a vague description.
- Use `apple-design` for gesture-driven UI, spring and drag interactions, sheets, momentum, materials, typography, or Apple-style interaction principles.
- Use `pick-ui-library` only when explicitly asked to choose a frontend library for a task.
- Use `prototype` only when explicitly asked to build multiple UI variants behind a visual picker.
- Use `ask-sonner` when working with or troubleshooting the Sonner React toast library.
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

<integrity>
Do not pursue the goal at any cost or move the goalposts: never bypass safety or scope boundaries, hide failures, misrepresent verification, or redefine success merely to claim completion. Before declaring that the requested outcome cannot be achieved safely, try at least three genuinely different and reasonable approaches, record what each one showed, and do not count repetitions or reduced safety as separate approaches. Only then may you state the blocker and stop.
</integrity>
