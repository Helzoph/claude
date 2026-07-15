# pkg-manager-guardrails

A Claude Code plugin that keeps dependency management flowing through
package-manager CLIs instead of ad-hoc filesystem edits.

## What's included

### Hooks

| Hook | Event | What it does |
|---|---|---|
| `block-node-modules-bin` | `PreToolUse` (Bash) | Blocks direct `node_modules/.bin/<tool>` invocations and steers Claude toward a system-installed binary or a package-manager runner (`pnpm exec`, `npx`, `bunx`) instead. |
| `block-manifest-lock-edit` | `PreToolUse` (Edit/Write) | Blocks direct edits to lockfiles (`pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`, `bun.lock(b)`, `npm-shrinkwrap.json`) and to the dependency blocks (`dependencies`, `devDependencies`, `peerDependencies`, `optionalDependencies`) inside `package.json`, steering Claude toward `pnpm add/remove/update`, `bun add/remove/update`, or `npm install <pkg>` instead. |

Hook scripts are TypeScript (`.ts`), run directly via `node` (Node.js ≥ 22.18,
which strips erasable TypeScript syntax by default — no build step or
`ts-node`/`tsx` required). Node.js must be on `PATH`.

## Installation

From within Claude Code:

```
/plugin marketplace add helzoph/claude
/plugin install pkg-manager-guardrails@helzoph-claude-marketplace
```

## Why this exists

Manifests and lockfiles are generated/managed artifacts. Hand-editing them
(or reaching into `node_modules/.bin` directly) skips the package manager's
resolution and integrity guarantees, causing local/CI/deploy drift. These
hooks were split out of `rationale-toolkit` because they encode a distinct
concern — dependency-management discipline — separate from the rationale-first
coding style that toolkit enforces.

## License

Apache-2.0
