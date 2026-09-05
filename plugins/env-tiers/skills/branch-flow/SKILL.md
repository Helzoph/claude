---
name: branch-flow
description: "Runs the branch flow for a three-tier local setup: open worktrees from the production branch (not the UAT branch), merge worktree -> UAT -> prod with merge only — never rebase or cherry-pick — and rebuild UAT with reset --hard when its merge order stops being useful. Use when deciding where to start a Claude Code session or a new worktree in a repo that has both a UAT and a production branch, when a hotfix must reach production without dragging along everything currently sitting in UAT, or when UAT's history has become tangled. Triggers on: 'which branch should this worktree come from', 'ship this one fix without the rest of UAT', 'UAT is a mess, can I reset it', 'should I rebase this onto uat'. Do NOT use for the initial directory/hook setup (that is setup-tiers). Do not propose rebase or cherry-pick as an alternative here — that is the specific thing this flow trades away."
---

# env-tiers: 分支流与 worktree 基点（branch-flow）

## 前提

三层各是一个分支，和目录一一对应（布局与理由见 `setup-tiers`）：

| 层 | 分支 | 目录 |
|---|---|---|
| 开发 | `worktree-*` | `<repo>/.claude/worktrees/*` |
| 集成（UAT） | `uat` | `<repo>-uat/` |
| 正式 | `master` / `main` | `<repo>/` |

下面用 `master` 指代正式分支。

## 在哪开 session

**默认在正式环境目录开**，写代码时让 agent 自己开 worktree。

这不是因为正式分支特殊，而是因为 `baseRef` 设成了 `head`——**新 worktree 从 session 所在的分支长出来**。在正式目录开，基点才是 `master`。

（`baseRef: "head"` 这条配置在本地开发的仓库里不是偏好而是必需：默认的 `fresh` 模式指向 `origin/<default>`，而这类仓库常常没有 remote，指过去会落空。）

**唯一该在 UAT 目录开 session 的场合**是处理集成本身——合并冲突、验收中发现的问题定位、UAT 重建。那时你要的就是 UAT 的状态。

但**在 UAT 目录里不要开 worktree**：那样基点会变成 `uat`，下一节那条逃生通道就没了。如果在 UAT 里发现的 bug 需要单独一条分支修，回正式目录开。

## worktree 一律从 master 开，不从 uat 开

这条是整个流程的核心，理由是保住一条**逃生通道**。

功能分支基于 `master`，它的 commit 就成了两条线的共同祖先。于是急件可以 `master merge worktree-x` 直接上线，之后再 `master merge uat` 时 git 认得出这些 commit 已经在了，不重复、不冲突。

```
worktree-*  --merge-->  uat  --merge-->  master
     \                                    ^
      \------------ 急件直接 merge --------/
```

若基于 `uat` 开，这条斜线就不存在了：merge 任何一个功能分支，都会把 uat 上其它**还没验完**的东西一起拖进 master。剩下的唯一出路是 cherry-pick，而那条路是脏的（见下）。

**代价**：两个 worktree 改同一块代码时，冲突要到 UAT 才暴露。单人或小团队可接受；如果并行分支多到冲突频繁，这个取舍要重新算。

## 只用 merge，不要 rebase、不要 cherry-pick

上面那条急件通道靠的就是「**同一个 commit 同时是两条线的祖先**」。

`rebase` 和 `cherry-pick` 都会造出内容相同、但 hash 不同的 commit。通道随之失效：git 不再认为 uat 上那个 commit 和 master 上那个是同一件事，后续合并会冲突，或者留下重复历史。

所以在这套流程里，**「要不要 rebase 一下让历史干净点」这个问题的答案恒为否**。历史好看不值这条通道。

## UAT 可以随时推倒重建

`uat` 的合并顺序没有历史价值——它只是「当前正在验哪些东西」的一个快照。乱了就重建：

```bash
git checkout uat && git reset --hard master
git merge worktree-b worktree-c   # 把还要验的重新合上
```

**这不会丢东西**：功能本体都在各自的 `worktree-*` 分支上，已经上线的部分在 `master` 里。`uat` 上没有任何一份独有的内容——这正是「只用 merge」换来的性质，如果之前 cherry-pick 过，就不成立了。

重建后 UAT 环境要重新起：回 UAT 目录跑 `just up`。数据是否要一起清由用户决定，`reset --hard` 只动代码。

## 合并前

进 UAT 之前跑闸门（`just check`）。这一步在 worktree 里跑，不在 UAT 里跑——目的是让「代码本身有问题」和「集成到一起有问题」分开暴露，否则 UAT 里一堆红色，分不清是谁带来的。

## agent 在这套流程里的动作清单

- 被要求「开个分支写 X」→ 确认当前 session 在正式环境目录；不在就先说明，不要就地开。
- 被要求「把 X 合进 UAT」→ `git checkout uat && git merge worktree-x`，然后去 UAT 目录 `just up` 验。
- 被要求「这个急着上线」→ 在正式目录 `git merge worktree-x`，**不要**先合进 uat 再合进 master，也不要 cherry-pick。
- 被要求「UAT 乱了」→ 按上面的重建流程，但**先列出当前 uat 上合了哪些分支**（`git log --merges --oneline master..uat`）给用户确认要保留哪些，再 reset。
- 看到「rebase 一下更干净」这类想法 → 不要提，理由见上。
