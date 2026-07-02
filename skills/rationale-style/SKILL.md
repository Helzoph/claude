---
name: rationale-style
description: "Enforces a rationale-first coding and communication style. Use this skill whenever writing, reviewing, or explaining code — especially when the task involves design decisions, trade-off analysis, architecture choices, or any logic block that needs inline justification. Triggers on: writing new code, refactoring, code review, system design, or any task where reasoning behind choices must be documented."
---

# Rationale Style

## Core Principle

Explain **why** before **what**. Every design choice, trade-off, and logic block must carry visible reasoning. Optimized for long-term maintainability and team-level knowledge transfer.

## Code Rules

Every non-trivial logic block must contain an inline rationale comment:

```
// Rationale: <中文解释，说明设计意图或取舍原因>
```

**Good examples:**

```python
# Rationale: 采用原子写入防止程序崩溃导致数据损坏
with tempfile.NamedTemporaryFile(delete=False) as tmp:
    tmp.write(data)
    os.replace(tmp.name, target_path)

# Rationale: 选用 Redis 弃用 LocalCache 以支持多实例状态同步，接受 ~1ms 额外延迟
cache = RedisCache(host=settings.REDIS_HOST)
```

**Skip rationale for:** trivial assignments, obvious one-liners, boilerplate.

## Communication Rules

Before any implementation, state reasoning in Chinese covering:

- **The chosen approach** and what was rejected
- **The key trade-off** (e.g., consistency vs. latency, simplicity vs. flexibility)
- **The risk** if any assumption proves wrong

**Example:**

> "选用事件驱动架构而非轮询，是为了降低无效 CPU 消耗。代价是引入消息队列依赖，若队列宕机则需要降级策略。"

## Decision Nodes

At every branch where multiple valid options exist, apply this pattern before committing:

1. **Options considered** — list at least 2 alternatives
2. **Rejection reason** — why each alternative was ruled out
3. **Chosen rationale** — what property makes this the best fit given current constraints

## Scope

Apply this style to:

- All new code and modifications
- Architecture and system design discussions
- Code review feedback
- Refactoring explanations

Do **not** over-annotate: scripts under ~20 lines, tests with self-explanatory names, and pure config files are exempt unless they encode non-obvious decisions.
