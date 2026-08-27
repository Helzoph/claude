---
name: pick-up-work
description: "Read a feature's task graph back from Plane and compute which work items can start right now, by checking whether each item's blocked_by dependencies are all done. Use this skill when picking up work on a feature already recorded in Plane — triggers on 'implement the xxx feature', 'what can I work on next', 'what's unblocked'. The Plane MCP server ships with this plugin but needs a one-time `claude mcp login plane`. Do NOT use for writing a new plan into Plane (use plan-to-plane instead)."
---

# 从 Plane 读回任务图，算出现在能开工的

**可并行集合永远是算出来的，不是存下来的**，也不能靠肉眼看依赖图判断——多阻塞者的 item 是人最容易看漏的地方。

定义：**未完成、且所有 `blocked_by` 指向的 item 都已完成** 的那批 item。

## 读回流程

### 1. 拉未完成的 item（1 次调用）

```
workitem(action="list", project_id=...,
  pql='module = "<module-uuid>" AND stateGroup IN openStates()',
  fields='id,sequence_id,name,state_group')
```

PQL 把"列出全部"和"排除已完成"合成一次调用，返回的就是候选集。

`fields` 一定要带。不裁剪的话每个 item 都带着完整 description，几千字；裁成这四个字段只有几行。

### 2. 逐个拉依赖（M 次调用，M = 上一步返回的条数）

```
workitem_relation(action="list", workitem_id=...)
```

**依赖无法批量取**——`expand=issue_relation` 不工作，返回里没有关系字段。这是硬下限：M 个未完成 item 就是 M 次调用。20 个 item 的 module 读一次要 20 次左右调用，会花不少时间。

如果某个 module 的 item 多到读一次明显吃力，那不是要去优化读法，是这个 module 该拆了——用户也没法用一句"帮我实现 xxx"指挥一个几十件事的模块。

### 3. 只读 `dependencies.blocked_by`

返回结构是两个桶：

```
{ dependencies: { blocking: [...], blocked_by: [...], start_before: [...], ... },
  custom:       { "relates to": [...], duplicate: [...], ... } }
```

**只读 `dependencies.blocked_by`，其余一律忽略——这是白名单，不是黑名单。**

- `custom` 桶装的是自定义关系，label 可以任意取。写成黑名单（"排除 relates to，剩下的当阻塞"）的话，以后任何人新建一条自定义关系定义都会被静默当成阻塞，整个计算作废且不报错。
- **`blocking` 桶绝不能算进去**。它是 Plane 自动生成的反向边——A `blocked_by` B 之后，B 那边会出现 `blocking: [A]`。把它当依赖，方向就整个反过来了。

### 4. 判断阻塞者是否已完成

第 1 步已经把已完成的 item 过滤掉了，所以：**`blocked_by` 里的 id 不在第 1 步结果中 → 该阻塞者已完成**。不用再单独查它的状态。

⚠️ **不要信 `blocked_by` 条目里自带的 state 字段**，按"在不在候选集里"来判断。

### 5. 得出结果

`blocked_by` 全部已完成（或本来就没有 `blocked_by`）的 item = 现在可并行开工的。

**多条 `blocked_by` 是 AND**：全部完成才解锁，差一条都不行。

### 6. 开工前置状态

```
workitem(action="update", workitem_id=..., state=<started 组某个 state 的 UUID>)
```

先 `state(action="list")` 拿到该 project 里 group 为 `started` 的 state UUID。

⚠️ **`update` 的返回里 `state_group` 是陈旧的**——改成 Done 之后，返回里 `state` 和 `completed_at` 都更新了，但 `state_group` 仍是旧值。要复核就重新 `list`。信了它，刚完成的 item 会被当成未完成，**下次算并行集合会少算**。

## 判断完成一律看 state 的 group，不看状态名

group 固定为五个：`backlog` / `unstarted` / `started` / `completed` / `cancelled`。**状态名字可以随便改，group 改不了**，所以判断只能基于 group。

**新建的 item 默认落在 `backlog`**，不是 `unstarted`。所以 `backlog` 不代表"还没进入计划"——排除时只排除 `completed` 和 `cancelled`，别把 `backlog` 也排掉。

## 真正开始做之前：确认这个 item 有完成标准

选定要做的 item 之后，读它的 description（第 1 步为省 token 裁掉了 description，这里单独 `workitem(action="retrieve")` 拿一次）。

description 里应该有 `完成标准` 这一段（见 `plan-to-plane` 的模板）。**没有的话停下来问用户**，不要凭标题推断什么算做完。

原因：标题只说了要做什么，没说做到哪儿算完。凭标题猜的验收标准和用户心里的那个不一致时，你会在自认为完成的地方停下，而用户拿到的是个半成品——**而且双方都不知道错在哪一步**。

老 item 缺这一段是正常的（模板是后来才有的）。补一句问清楚，顺手 `workitem(action="update")` 把它补进 description，下次就不用再问。

## 报告给用户

列出可并行开工的那批（标识符 + 标题），以及**被挡住的那些各自在等谁**。后者同样重要——用户看到"等着的是什么"，才能判断要不要调整优先级。

依赖变化后（做完一个、或加了新依赖），**重新算一遍**，不要沿用上一次的结果。
