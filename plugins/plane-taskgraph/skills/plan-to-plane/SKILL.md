---
name: plan-to-plane
description: "Record a design discussion into Plane as a structured task graph: one Module per feature, work items sized to a single reviewable change, ordering expressed as blocked_by relations rather than prose, and one acceptance work item per Module holding its definition of done and the tests that must pass. Use this skill after discussing what to build, whenever the outcome should be written into Plane — triggers on 'record this into Plane', 'create issues for this', 'plan out this feature', 'write the acceptance criteria for this module'. The Plane MCP server ships with this plugin but needs a one-time `claude mcp login plane`. Do NOT use for reading an existing plan back or deciding what to work on next (use pick-up-work instead)."
---

# 把设计讨论落成 Plane 里的任务图

目标不是"把想法存下来"，而是**存成下次能原样读回、不需要重新解读的结构**。归属走 Module、先后走 relation、状态走 state——一律用结构化字段，**不许只写在 description 里**。写在正文的规划，下次读回来会被重新解读一遍，而且解读得不一样。

## 映射

| Plane 概念 | 装什么 |
|---|---|
| Project | 一个代码仓库 |
| Module | 一个 feature——用户能用一句话说"帮我实现 xxx"的那个 xxx |
| Work item | 一次能坐下来做完、能单独 review 的改动 |
| 验收 item | 每个 module 恰好一个，装"整个 module 做到什么程度算完"（见下） |

Cycle 和 Label 不用：Cycle 是时间维度（sprint），这套流程里没有；Label 目前没有它才能表达的东西。

Module、Label、Cycle、Estimate 都是 **project-scoped**，不能跟着 work item 跨 project。一个 feature 横跨两个仓库时，只能两边各建一个 Module，用跨 project 的 `workitem_relation` 把具体的 item 连起来。

## 前置：确认 project，并确保 Modules 功能是开的

先 `project(action="list")` 找目标 project。**没有对应 project 时停下来问用户**，不要自作主张新建。

新建的 project **默认 `module_view: false`，Modules 功能是关的**，不先打开的话建 Module 那步会直接失败：

```
project(action="update_features", project_id=..., modules=true)
```

对已有 project 也先确认一次（`project(action="get_features")`），不要假设开着。

## 写入顺序（第 4 步是独立一步，必做）

1. `module(action="create")` —— 建 feature
2. `workitem(action="create")` —— 逐个建 item，**外加一个验收 item**
3. `module(action="manage_workitems")` —— 把 item 挂进 module（验收 item 也要挂）
4. `workitem_relation(action="create")` —— **连依赖**，含验收 item 的 `blocked_by`

第 4 步不能省，也不能提前：relation 要用 item 的 ID，只有 item 全部建完才拿得到。**item 建完就向用户报告"好了"是不合格的**——那时依赖还一条都没有，图是散的，读回时每个 item 都会被判定成可开工。

## 依赖：只用 `blocked_by`，从被阻塞方发起

内置 relation type 只有 6 个：`blocking` / `blocked_by` / `start_before` / `start_after` / `finish_before` / `finish_after`。后四个是甘特图排期用的，跟"能不能开工"无关，**不用**。

**永远从被阻塞的那个 item 发起 `blocked_by`**，指向阻塞它的 item。这样"我被谁挡着"这条信息就长在需要它的那个 item 上。

Plane **双向存储**：从 A 发起 `blocked_by B` 之后，读 B 会看到 `blocking: [A]`。所以不需要自己维护反向边，也不要重复建一条反向的 `blocking` 关系。

**"相关但不阻塞"是自定义关系，不是内置类型。** 它走 `relation_definition_id` + `relation_definition_label`，label 是 `"relates to"`（**带空格**，不是 `relates_to`）。workspace 默认自带这条定义，用之前先 `workitem_relation(action="list_definitions")` 拿 id。

## 依赖记在 work item 之间，不记在模块之间

「支付依赖登录」这种模块级说法通常是假的——真相往往是"支付里读用户信息那个 item 依赖登录里签发 session 那个 item"，支付模块其余的活（UI、对账、退款）跟登录无关。记成模块级依赖，整个模块会被判定为阻塞中，**本可并行的活被误判成不能并行**，恰好毁掉这套方案要的能力。

如果出现"整个模块 B 必须等 A"、但说不出具体是哪两个 item——说明这个依赖还没想清楚，**停下来问用户**，不要记一条糊的进去。

## 每个 module 一个验收 item

**每个 module 都要有一个、且只有一个验收 item**，装两件事：整个 module 做到什么程度算完，以及哪些测试必须通过。

它跟别的 item 一样是 work item，所以自带 state、评论、附件。于是：

- **state 就是"这个 module 验收过了没有"**——不需要另找地方记，也不会出现两份说法打架。
- 每次跑验收的结果记成**评论**，不要改 description。description 是标准（相对稳定），评论是历史（每次都不同）。混在一起，下次读的人分不出哪句是要求、哪句是上回的结果。

**为什么不写在 module 的 description 里**：module 描述经公开 API 只能存纯文本(`description`)，没有 `description_html`；更要命的是 module 没有 state、没有评论、没有附件。验收结论无处可放，只能变成一句谁也不会更新的散文。

### 建法

标题固定为 `<module 名> 验收`。`pick-up-work` 靠这个后缀认出它，**别改这个后缀**——改了它就退化成一个普通 item，验收流程不会被触发，但表面上一切正常。

`description_html` 用这个模板：

```html
<p><strong>完成定义</strong>：整个 module 达到什么状态算做完</p>
<p><strong>必须通过的测试</strong></p>
<ul>
  <li>具体的测试/命令 —— 覆盖哪个行为</li>
</ul>
<p><strong>手动验证</strong></p>
<ul>
  <li>自动化测不到、必须人工确认的那几条</li>
</ul>
```

**「必须通过的测试」要写到能直接执行**——具体的测试文件名、测试函数名，或者能照抄进终端的命令。写"单元测试通过"等于没写：下次读的人不知道是哪些测试，也就没法判断跑完的那批够不够。

**只写这个 module 引入的验收**，不要把全仓库的测试套件抄进来。它是"这个 module 带来了什么新保证"，不是回归清单。

「手动验证」没有内容就整段删掉。

### 依赖：验收 item `blocked_by` 该 module 的每一个其他 item

这是 module 里唯一一条机械规则的依赖——**扇入所有其他 item**。作用是让它在 `pick-up-work` 里自然排到最后：只要还有一件活没做完，它就是被挡住的；全做完了，它自己浮上来成为可开工项，提醒你去验收。

不要反过来让别的 item 依赖它。

### 什么时候不建

单个 item 就能做完的 module，验收 item 是纯冗余——那个 item 自己的「完成标准」已经是全部。这种情况下**这个 module 大概也不该存在**，直接建一个 work item 就好。

## 不要记录"哪些可以并行"

并行是依赖图的推论，不是一条独立事实。一旦后来加了新依赖，存下来的"这几个可并行"就悄悄变成错的，但它长得跟对的一模一样。只要依赖记准，可并行集合任何时候都能算出来（见 `pick-up-work`）。

## description 模板

**不写**：属于哪个 feature（Module 管）、依赖谁（relation 管）、什么状态（state 管）。这三样一旦在正文里出现第二份，就会跟字段对不上，而对不上的时候没人知道哪份是真的。

### Work item（`description_html`）

```html
<p><strong>为什么</strong>：这个改动要解决什么问题</p>
<p><strong>完成标准</strong>：满足什么条件算做完</p>
<p><strong>注意</strong>：已知的坑、约束、已经拍板的决策</p>
```

**「完成标准」不许省。** 它是三段里唯一不会自然写出来的——"为什么"跟着讨论就有了，"注意"没有就是没有，但验收标准如果不留固定位置，写着写着就只剩一段背景描述。下次读回时无从判断这个 item 到底做完没有。

写不出完成标准，通常说明这个 item 还没想清楚，或者切得太大。**停下来问用户，不要用一句"实现 xxx"糊过去。**

「注意」段没有内容就整段删掉，不要留空壳。

### Module（description，纯文本）

```
目标：这个 feature 要达成什么
不包含：明确划到范围外的东西
```

「不包含」这段是防边界漂移的。feature 做着做着长出计划外的 item，是这套流程最常见的失控方式；把范围外的东西写下来，后面再冒出相关想法时能立刻看出它是新 feature 还是本来就该做的。

⚠️ **module 的 description 只能是纯文本，不要塞 HTML。** 数据库里 Module 确实有 `description_html`，但公开 API 的 create/update serializer 白名单里没有它——只收 `name` / `description` / `start_date` / `target_date` / `status` / `lead` / `members` / `external_source` / `external_id`。传 HTML 标签会被当字面文本存下来。

**验收标准不写在这里**——module 没有 state 也没有评论，装不下"验收过了没有"。它归验收 item。

### 格式约束

`description_html` **只接受裸 HTML**，传 `&lt;p&gt;` 这类转义实体会被原样存下、在 UI 里显示成字面标签，而接口照样返回 200。

只用 `<p>` / `<strong>` / `<ul>` / `<li>` 这几个基础标签。Plane 编辑器对更复杂标签的支持范围没有验证过，不要用。

## 两个静默失败（返回 200，数据是错的）

**`description_html` 要裸 HTML，不能传转义实体。** 传 `&lt;p&gt;` 会被原样存下，UI 里显示成字面标签，接口照样返回成功。写 `<p>…</p>`。

**不要信 `workitem(action="create")` / `workitem(action="update")` 返回里的 `state_group`。** create 返回 `null`，update 返回的是**改之前的旧值**。要确认状态，重新走 `list` 系列接口。

## 收尾

把建好的结构报告给用户：module 名、每个 item 的标识符（如 `ABC-1`）和标题、以及**每一条 relation**。relation 要单独列出来——用户能一眼看出依赖图对不对，是这套流程唯一的人工校验点。

验收 item 单独列出来，**连同它「必须通过的测试」那几条一起**。用户最可能要改的就是这几条——补一个漏掉的测试，或者砍掉一条其实没必要的。

不要顺带断言"这几个可以并行"。要算就走 `pick-up-work` 的流程真算一遍，**不要肉眼判断**——多阻塞者的 item 正是人最容易看漏的地方。
