---
name: stand-up-uat
description: "Stands up the UAT tier for the first time as a sibling git worktree, and works through what UAT silently inherits from production: credentials shared with prod that cause real-world side effects when UAT exercises them (push notifications reaching a real device, rate limits shared with the prod account), an empty database that needs either migrations or a restored snapshot, and read-only mounts of host login state. Use when creating a UAT/staging worktree for the first time, when UAT was created but does not come up, or when UAT unexpectedly triggered something in the real world. Triggers on: 'set up the UAT worktree', 'UAT sent me a real notification', 'UAT is using up my API quota', 'UAT database is empty'. Do NOT use for the shared justfile and guard hook (that is setup-tiers). Never copy a production .env into UAT without walking the shared-credential checklist first."
---

# env-tiers: UAT 首次搭建（stand-up-uat）

## 前置

`setup-tiers` 已经跑过（`justfile` 和护栏 hook 都在位），分支流见 `branch-flow`。

## 建目录

UAT 是正式仓库的**兄弟目录**，不是它的子目录：

```bash
git worktree add ../<repo>-uat -b uat
```

目录名必须正好是 `<repo>-uat`（或用户在 `setup-tiers` 里定的那个 `UAT_DIR`）。名字错了不会报错，只会安静地起一套落在别的域名、用别的卷的孤儿容器——`justfile` 的 `_guard-dev` 会把这件事变成当场失败，但前提是名字对得上它的判断。

放在正式目录的 `.claude/worktrees/` 下**不行**：那个位置是给开发 worktree 的，护栏和 `justfile` 都按「目录名 = 层」来判断，而不是按路径。

## UAT 从正式环境继承了什么（这一节是重点）

代码和配置容易想到。真正会出事的是这几样——它们没有出现在任何配置文件的 diff 里，但 UAT 一跑起来就会作用到真实世界：

### 1. 凭证文件不在 git 里，要手动拷

`.env` 之类被 gitignore，`git worktree add` 不会带过去。从正式目录手动拷一份，或者用 `mise-toolchain/link-env` 把两层接到同一份工作区外的 baseline 上。

**拷之前先过完下面第 2 条。** 直接整份拷过去正是问题的来源。

### 2. 逐条盘点：哪些凭证是两层共用的，共用之后会发生什么

对 `.env` 里的**每一个**外部服务凭证，问一句「UAT 用这个 key 跑一次，真实世界会发生什么」。三种结果：

| 结果 | 处理 |
|---|---|
| 什么都不会发生（只读、沙箱、独立配额） | 直接共用 |
| 会作用到真实世界，但**正是要验的东西** | 有意共用，**写进项目文档并注明日期和理由** |
| 会作用到真实世界，且只是副作用 | 换成 UAT 专用的 key，或留空 |

第二类要展开说，因为它看起来像 bug 而其实是决定。典型例子：推送通知的 key 两层共用，于是 UAT 的测试推送会真打到用户手机上。这可以是**有意的**——推送链路只有真发一次才算验过，而推送不达往往是静默失败，看日志看不出来。代价是跑批量任务时会被打扰，届时把 UAT 的那个 key 注释掉即可（前提是代码在缺 key 时**打日志而不是报错**，这本身是要确认的行为）。

第三类的典型是**共享速率限制**：UAT 和正式用同一个账号打同一个 LLM/API 供应商，UAT 跑一轮批量任务就挤占了正式环境的额度。这一类往往隔离不掉（订阅是账号级的），那就明确记下来「这是目前唯一没隔离干净的地方」，而不是假装它不存在。

**不要跳过这一步直接整份拷贝。** 遗漏的表现是「UAT 一跑，真实世界有反应」，而排查方向通常会先怀疑代码。

### 3. 宿主机登录态的只读挂载

有些工具的登录态在宿主机的 home 目录里（例如 `~/.codex/auth.json`），compose 里以只读方式挂进容器。这类挂载两层共用同一个文件——登录本身没问题，但**账号级的配额是共享的**，属于上面第三类。

### 4. 数据库是空的

两种起法，按目的选：

- **只验代码路径** → 跑一遍迁移，空库即可。
- **要用真实数据验** → 从正式环境的备份里挑一份恢复进去。注意备份必须是 `VACUUM INTO` 这类**一致性快照**，不能是 `cp` 出来的文件——SQLite 的 WAL 里未 checkpoint 的事务复制不到，恢复出来的库会缺最近的写入，而它能正常打开，缺失是静默的。

恢复真实数据进 UAT 之后，第 2 条的风险等级会上升：现在 UAT 里跑的批量任务面对的是真实内容，触发的外部调用也带着真实内容。做这个选择前确认一遍第 2 条的盘点结果。

## 起

```bash
cd ../<repo>-uat
just env      # 先确认这里被识别成 uat 层
just up
```

`just env` 显示的层不是 `uat` 就停下——多半是目录名不对，或 `justfile` 里的 `__UAT_DIR__` 占位符没替换。这时候 `just up` 会被 `_guard-dev` 拦住（那是设计好的），不要绕过它手敲 compose 命令，那正好会踩进「起一套孤儿容器」的坑。

**不要起裸进程**（`npm run dev` 之类）。那会绕过反向代理，路由直接失效。

报地址报域名，不要报端口号：`http://<repo>-uat.localhost`。`just up` 结束时会把地址打出来。

## UAT 里可以做、正式环境里不可以做的事

这是 UAT 存在的全部理由，说清楚它的边界：

- `docker compose down -v` —— 在这里手敲完整命令即可（`just` 刻意不提供这个）。
- 跑迁移、写库、改 schema。
- 恢复/覆盖数据库。
- 试任何「我试试看」的操作。

反过来，**在 UAT 里不要开 worktree**——基点会变成 `uat`，破坏 `branch-flow` 里那条逃生通道。要单独开分支修 bug，回正式目录开。
