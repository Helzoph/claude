---
name: verify-outcomes
description: "Guides agents on verifying work outcomes and writing quality tests. Covers depth assessment, test quality principles, and verification protocols with language-specific toolchain references. Use after completing any code change — bug fix, feature, refactor, or config change. Triggers on: task completion, test writing, quality assurance, or when deciding how thoroughly to validate changes."
---

# Verify Outcomes

## Core Principle

Verification must prove the change **does what it should** and **breaks nothing it shouldn't**. Passing type checks and lint is necessary but not sufficient — the agent must verify behavioral correctness proportional to the risk of the change.

## 1. Depth Assessment

Before verifying, assess depth by scanning change signals. Do NOT ask the user — judge autonomously.

### Signal → Depth Mapping

**Thorough** — any of these present:
- Crosses module/package/service boundaries
- Changes public API surface (exports, endpoints, CLI flags)
- Modifies data models, schemas, or state management
- Touches security-related code (auth, crypto, input validation, permissions)
- Alters build/deploy/CI configuration

**Standard** — default for most work:
- Single-module logic changes
- Internal function refactors
- Adding new internal functionality
- Dependency version updates

**Quick** — all of these true:
- Pure rename/format/comment changes
- No logic change whatsoever
- No public API surface affected

### What Each Depth Requires

| Step | Quick | Standard | Thorough |
|------|-------|----------|----------|
| Lint + format | YES | YES | YES |
| Type check | YES | YES | YES |
| Run existing tests | YES | YES | YES |
| Write new tests | NO | YES | YES |
| Boundary/edge case tests | NO | IF APPLICABLE | YES |
| Integration/cross-module tests | NO | NO | YES |
| Run/observe the application | NO | IF UI CHANGE | YES |
| Trace callers/consumers | NO | NO | YES |

## 2. Test Quality

### Principles

- **Test behavior, not implementation** — assert on outputs and side effects, not internal state or call counts.
- **One logical concept per test** — a test name should describe one scenario; if you need "and" in the name, split it.
- **Arrange-Act-Assert** — clear separation, no logic in tests (no if/for/try-catch in test body).
- **Tests must be able to fail** — if you can't describe a realistic input that would make this test fail, the test is useless.

### Boundary Coverage

Every function that accepts input must have tests covering:
- **Zero/empty**: `0`, `""`, `[]`, `{}`, `null`, `undefined` (language-appropriate)
- **Boundary**: off-by-one, max/min values, exactly-at-limit
- **Error path**: invalid input, network failure, timeout, permission denied
- **Concurrency** (if applicable): race conditions, concurrent mutations

### Bug Fix Protocol

When fixing a bug, follow this exact sequence:
1. Write a test that **reproduces the bug** — this test must FAIL on the current code
2. Fix the bug
3. Confirm the test now PASSES
4. Check that no other tests broke

Never skip step 1. A bug fix without a failing-first test has no proof it fixed anything.

### Anti-Patterns — Never Do These

- **Over-mocking**: if you mock more than you test, you're testing the mock. Prefer real instances; mock only at system boundaries (network, filesystem, clock).
- **Snapshot abuse**: snapshots for large objects or UI trees become "approve to make green" noise. Use targeted assertions.
- **Implementation coupling**: testing that function A calls function B exactly 3 times. Internals change; behavior shouldn't.
- **Tautological tests**: `expect(add(1,2)).toBe(add(1,2))` — restating the implementation as the expectation.
- **Catch-all ignoring**: `try { ... } catch { /* test passes */ }` — hiding failures.

### Test Naming

Use pattern: `[unit] [scenario] [expected result]`

```
"parseDate returns null for empty string"
"createUser throws when email is duplicate"
"calculateTotal applies discount before tax"
```

## 3. Verification Protocol

### Step 1: Impact Analysis

Before running anything, identify:
- Which files changed
- Who calls/imports the changed code (trace upward)
- Who consumes the output of the changed code (trace downward)
- Whether any changed interface has external consumers

### Step 2: Static Verification

Run language-specific toolchain checks. Refer to `toolchains/<language>.md` for exact commands.

**Critical rules:**
- Use ONLY the commands documented in the toolchain files. Do NOT guess or improvise commands.
- If the project has a custom script (e.g., `pnpm run lint`), prefer it over raw tool invocation — it may include project-specific flags.
- Check `package.json` scripts / `Makefile` / `justfile` / `taskfile` first for project-defined commands.

### Step 3: Test Execution

- Run the full test suite if it completes in < 60s.
- For larger suites, run only tests related to changed files/modules — but document which tests were skipped and why.
- If tests fail, classify immediately:
  - **Caused by this change** → fix before proceeding, re-run.
  - **Pre-existing failure** → report to user with scope analysis. Do NOT fix without approval.

### Step 4: Runtime Verification (when depth requires it)

#### Dev Server Protocol

Before starting a dev server:
1. **Check if one is already running**: `lsof -i :<port>` for common ports (3000, 3001, 4321, 5173, 8080, 8081).
2. **If running** → do NOT start another. Rely on hot reload (Vite, Next.js dev, Webpack dev server all support it). Just save the file and observe.
3. **If NOT running** → start it, wait for ready, then verify.
4. **Never kill an existing dev server** unless the user explicitly asks.

#### What to Verify at Runtime

- Navigate the golden path (primary user flow) affected by the change.
- Check edge cases in UI (empty states, loading states, error states).
- Open browser devtools — check for console errors, network failures, React/Vue warnings.
- Verify responsive behavior if layout was changed.

### Step 5: Report

After verification, state:
1. What was verified and how (commands run, paths tested)
2. What passed
3. What failed and classification (current change vs pre-existing)
4. What was NOT verified and why (e.g., "integration tests skipped — no test database configured")

Never claim "all tests pass" without having actually run them. Never claim "verified working" for UI without having observed it in a browser.

## 4. Toolchain Reference

Language-specific tool commands are in `toolchains/`:
- `toolchains/typescript.md` — TypeScript / JavaScript projects
- `toolchains/python.md` — Python projects
- `toolchains/go.md` — Go projects
- `toolchains/rust.md` — Rust projects

**Always read the relevant toolchain file before running any check command.** The toolchain files are the single source of truth for which commands to use.
