# TypeScript / JavaScript Toolchain

## Package Manager Detection

Before running ANY command, detect the project's package manager from lock files:

| Lock file | Package manager |
|-----------|----------------|
| `pnpm-lock.yaml` | pnpm |
| `bun.lockb` or `bun.lock` | bun |
| `yarn.lock` | yarn |
| `package-lock.json` | npm |

Use the detected package manager (referred to as `<pm>` below) for all subsequent commands. If multiple lock files exist, prefer the one with the most recent modification time.

## Lint + Format

```bash
biome check
```

- Do NOT use `npx biome check` — `biome` is installed globally or via project script.
- If the project has a lint/check script in `package.json`, prefer `<pm> run lint` or `<pm> run check`.
- For auto-fix: `biome check --write`

## Type Check

```bash
tsc --noEmit
```

- If the project uses path aliases or custom tsconfig, check for `tsconfig.json` first.
- For monorepos, run from the relevant package directory or use the workspace-level type check script if available.

## Test

Detect the test runner from project config:

| Indicator | Runner | Command |
|-----------|--------|---------|
| `vitest.config.*` or `vite.config.*` with test config | vitest | `<pm> vitest run` |
| `jest.config.*` or `"jest"` in package.json | jest | `<pm> jest` |
| `"test"` script in package.json | project-defined | `<pm> test` |
| bun project | bun test | `bun test` |

- For running specific tests: `<pm> vitest run <path>` or `<pm> jest <path>`
- For watch mode (development): `<pm> vitest` (no `run` flag)
- Coverage: `<pm> vitest run --coverage` or `<pm> jest --coverage`

## Build

```bash
<pm> run build
```

- Check `package.json` for the actual build script name.

## Dev Server

Common ports: 3000 (Next.js), 5173 (Vite), 4321 (Astro), 3001 (fallback)

Check before starting:
```bash
lsof -i :3000 -i :5173 -i :4321 | grep LISTEN
```

Start command (detect script name from `package.json`):
```bash
<pm> run dev
```

Hot reload: Vite, Next.js dev, Webpack dev server all support HMR — file save triggers update automatically.

## Package Management

- Never edit `package.json`, `pnpm-lock.yaml`, `bun.lockb`, or any lock file directly.
- Install: `<pm> add <pkg>`
- Dev install: `<pm> add -D <pkg>` (bun uses `-d`)
- Remove: `<pm> remove <pkg>`
