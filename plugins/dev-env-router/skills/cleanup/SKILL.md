---
name: cleanup
description: "Finds orphaned dev-env-router Compose projects — ones whose backing git worktree directory no longer exists — and removes them only after explicit user confirmation. Use this skill when asked to clean up leftover/orphaned dev containers, free up disk space from old worktrees, or audit which routed projects are stale. Triggers on: 'clean up old containers', 'I deleted a worktree, is there leftover stuff', 'why is my Docker taking so much space'. Never invoke this to silently or automatically delete anything."
---

# dev-env-router: 孤儿项目清理

## 这是破坏性操作——以下规则没有例外

本 skill 会定位到可能需要删除的容器/网络/卷。参照用户全局 CLAUDE.md 中关于危险操作需要确认的原则，**在任何情况下都不允许**在同一轮回复中把"列出候选清单"和"执行删除"合并完成，无论候选清单看起来多么显然是孤儿。

**"确认"必须是用户对具体项目名列表的明确认可，不接受模糊授权**：
- 用户回复"都删了吧"、"看起来都能删"、"你觉得可以就删"、"继续吧"这类笼统表述，**不算确认**。必须先完整复述将要执行 `down -v` 的项目名清单，让用户对这份具体清单做最终确认，再逐一执行——即使是"全部删除"这种批量授权，也要走这道复述步骤，防止清单本身存在误判项而被笼统的"都删了"掩盖过去。
- 只有当用户的回复明确对应到具体项目名（逐条列举，或对复述出的清单明确说"是，就删这些"）时，才可以执行。

## 第一步：找出候选孤儿项目

1. 列出当前所有通过 Compose 管理的项目：
   ```bash
   docker compose ls --format json
   ```

2. 列出当前所有仍然存在的 git worktree 目录（对每个仓库分别执行，或者让用户指定要核对的仓库范围）：
   ```bash
   git worktree list --porcelain
   ```

3. 对比两份列表：`docker compose ls` 里出现、但其对应目录已不在 `git worktree list` 输出中的项目名，即为**候选孤儿**。

   注意：项目名是目录名经 Compose 归一化后的结果，比对时需要做同样的归一化（转小写、替换非法字符），不能直接做字符串相等比较。

   **这个比对是启发式的，不是权威判断**：如果某个项目的 compose 文件（或 `.env`）里显式设置过 `COMPOSE_PROJECT_NAME`，项目名会脱离目录名的默认派生规则，导致比对失效——可能把仍在使用的项目误判为孤儿，也可能让真正的孤儿因为凑巧撞名而被漏判。怀疑存在这种情况时，用 `docker compose -p <name> config` 或检查该项目的 compose 文件/`.env` 里是否有 `COMPOSE_PROJECT_NAME` 显式赋值来核实，不要直接采信自动比对结果。

## 第二步：只列出，不执行

把候选孤儿清单原样展示给用户，包含：项目名、对应的容器/网络/卷数量、（如果能找到）原目录路径。同时必须声明：**这份清单是基于目录存在性的机械比对得出，可能存在归一化误差或 `COMPOSE_PROJECT_NAME` 被覆盖导致的误报，请用户自行核实后再决定是否删除**。明确询问用户要对哪些条目执行清理，哪些保留。

## 第三步：用户确认后执行

仅对用户已明确确认（见第一步的确认要求）的项目执行：

```bash
docker compose -p <project-name> down -v   # 停止并删除该项目的容器、网络、卷
```

`-p` 按项目名操作，不强依赖原 compose 文件仍然存在（Compose v2 支持凭标签定位资源），但如果宿主机的 Compose 版本较旧、该命令因找不到原 compose 文件而失败，改用标签过滤方式手动删除：

```bash
docker ps -a --filter "label=com.docker.compose.project=<project-name>" -q | xargs -r docker rm -f
docker network ls --filter "label=com.docker.compose.project=<project-name>" -q | xargs -r docker network rm
docker volume ls --filter "label=com.docker.compose.project=<project-name>" -q | xargs -r docker volume rm
```

如果用户额外要求清理不再被任何容器使用的悬空网络：

```bash
docker network prune
```

`docker network prune` 影响范围超出本次候选清单（波及该项目之外所有悬空网络），确认门槛应高于按项目名删除：**必须单独复述受影响范围（"这会清理所有未被使用的网络，不限于本次候选清单"），拿到用户针对这一操作本身的明确确认后才能执行**，不能被"顺便一起清理"这类附带在其他确认里的表述覆盖，也不要和上面按项目名删除的操作合并成一步。

## 边界

- 本 skill 不负责判断"这个项目是否还有价值"——只做机械的目录存在性比对，价值判断交给用户。
- 不要用本 skill 处理还在运行中、worktree 目录仍然存在的项目——那属于 `operate` skill 的日常启停范畴。
