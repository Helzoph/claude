---
name: yagni-design
description: "Enforces YAGNI (You Aren't Gonna Need It) design discipline. Use this skill when writing new code, adding functionality, or making architecture decisions. Triggers on: creating new abstractions, interfaces, or extension points; refactoring toward reusability; deciding whether to add error handling; adding new files or modules."
---

# YAGNI Design

## Core Principle

Only build what the current task requires. Do not build for hypothetical future requirements.

## Rules

- **No speculative abstraction** — do not add interfaces, base classes, plugin systems, or config options for a use case that does not exist yet.
- **No premature DRY** — 3 similar lines of code are better than an abstraction built to avoid them. Duplication is cheap; the wrong abstraction is expensive.
- **No error handling for impossible cases** — only handle errors that can actually occur given the current callers and inputs. Do not add defensive checks for scenarios the code cannot reach.
- **Delete dead code on sight** — unused functions, exports, flags, or config that no longer have a caller should be removed, not commented out or left "just in case."

## How to Apply

Before adding an abstraction, extension point, or generalization, ask: does a second concrete use case exist *right now* in this codebase? If not, don't build it — write the concrete version instead.
