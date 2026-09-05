---
name: setup-tiers
description: "Lays out three local environment tiers whose identity is derived from the directory name — worktree dev (no containers), UAT, and production — by writing a just command entrypoint and a project-local guard hook that hard-blocks the irreversible production commands (compose down -v, docker volume rm/prune, git clean -x) and turns a missing prod override into a confirmation prompt. Use when a project runs real data locally and needs a place to test that is not that, when someone has already run a destructive command against the real local data, or when the same repo needs a staging tier alongside production. Triggers on: 'I need a UAT environment', 'set up staging locally', 'stop me from wiping the real database', 'separate prod and test containers'. Do NOT use for Traefik routing setup (that is dev-env-router/onboard) or for env var layering (that is mise-toolchain/link-env). Never point the guard at a directory the user has not named as production."
---

# env-tiers: 三层环境搭建（setup-tiers）

## 要解决的问题

同一个仓库既跑着真实数据，又是改代码的地方。于是每一次 `docker compose down -v`、每一次跑迁移、每一次「我试试看」，动的都是不能丢的那份数据。

分支不解决这个问题——分支只隔离代码，不隔离卷。两个分支起的容器如果在同一个目录下，`COMPOSE_PROJECT_NAME` 相同，卷就是同一个。

## 方案：目录名即身份

```
<repo>/                          正式，真实数据            http://<repo>.localhost
<repo>-uat/                      UAT，可随时推倒           http://<repo>-uat.localhost
<repo>/.claude/worktrees/*/      开发，不起容器
```

三层各是一个 git worktree，目录名互不相同。这一条带来所有其余性质：

- Compose 的项目名默认取目录名 → 容器名和卷名自动带前缀（`<repo>_data` vs `<repo>-uat_data`），**两套数据天然隔离**，不需要任何配置。
- Traefik 的路由规则若写成 ``Host(`${COMPOSE_PROJECT_NAME}.localhost`)``，域名也自动分开，**不需要为 UAT 单开覆盖层去改 label**。
- 护栏 hook 判断「这条命令打在哪一层」用的也是目录名。

**不要在 compose 里写死域名**，也不要引入 `ENV=prod` 这类第二判据。多一种真相来源，就多一种「两处说这是 UAT、一处说是正式」的状态，而这类不一致恰好在最危险的那一刻才暴露。分支尤其不能当判据：分支能被 checkout 改掉，目录不会。

真正要守的因此只剩一件事：**UAT 的目录必须叫 `<repo>-uat`**。名字错了不会报错，只会安静地落在一个没人访问的域名上、用一套没人备份的卷——所以下面的 `justfile` 把它变成当场失败。

## 开始之前要问清楚的四个值

这些值会被填死进生成的文件，问错了护栏就挡错东西。**不要猜**：

| 值 | 含义 | 怎么确认 |
|---|---|---|
| `PROD_DIR` | 正式环境的**目录名**（不是路径） | `basename $(git rev-parse --show-toplevel)`，但要向用户确认这个目录跑的确实是正式环境 |
| `UAT_DIR` | UAT 的目录名 | 默认 `<PROD_DIR>-uat`；用户已有别的命名就用他的 |
| `DATA_VOLUME` | compose 里声明的数据卷名 | 读项目的 `docker-compose.yml` 的 `volumes:` 段；多个卷时问用户哪个装的是不可再生的数据 |
| `PROD_OVERRIDE` | 正式环境必须带的 override 文件名 | 通常是 `docker-compose.prod.yml`；不存在就先按下一节建出来 |

`PROD_DIR` 必须由用户确认，不能从 cwd 推定就动手。护栏指错目录有两种坏法：指到 UAT 上，日常试验被拦得没法用，结果是 hook 被整个关掉；指到不存在的目录上，护栏静默失效，而失效的护栏比没有护栏更危险——它会让人以为有一道防线。

## 正式和 UAT 跑的不是同一套东西

这不只是配置差异，是两种运行方式：

| | UAT | 正式 |
|---|---|---|
| 前端 | dev server，HMR | 静态构建产物 + 一个 web server |
| 后端 | watch 模式，改了就重启 | 直接启动，无 watch |
| 源码 | bind mount，改了就生效 | 烤进镜像，只在 build 时变 |
| 改代码后 | 自动重载 | **必须 `--build` 重建** |

差异写在 `PROD_OVERRIDE` 里，基础 `docker-compose.yml` 保持 UAT/开发那一套。这个方向不能反：**漏掉 override 时的行为必须是「退回开发配置」而不是「退回生产配置」**——前者会立刻表现异常（源码 bind mount 回来、热重载乱跳），后者会安静地把一个没有 watch 的容器留在开发目录里，谁都不会发现。

生产构建还有一处容易漏：开发时前端到后端的同源路径通常由 dev server 的 proxy 提供，**生产构建之后它不存在了**。少了它的表现不是「连不上」，而是页面正常、所有接口回 `index.html`。检查项目的生产 web server 配置里是否有对应的转发规则。

## 操作步骤

### 1. 写命令入口

把 `templates/justfile` 复制到**仓库根目录**（会随 git 进到每个 worktree，三层共用同一份），替换三个占位符：`__PROD_DIR__`、`__UAT_DIR__`、`__PROD_OVERRIDE__`。末尾的 `check` 目标是 TODO，换成本项目实际的类型检查/测试/构建命令。

已存在 `justfile` 时**禁止覆盖**。先向用户说明差异，问是合并进现有文件还是保留原文件另建入口，用户明确选择后再动手。

之所以要有这层包装：正式环境漏掉 override 不会报错，`--build` 漏掉也不会报错（容器照样起来、页面照样能开，跑的是上一版代码）。**一个不报错的错误只能靠「每次都记得带参数」来防，而那正是会忘的那种事。**

`just` 刻意不提供 `down -v`。要清数据去 UAT 手敲完整命令。

### 2. 写护栏 hook

把 `templates/guard-prod.sh` 复制到**正式环境目录**的 `.claude/hooks/guard-prod.sh`，替换四个占位符，然后 `chmod +x`。

注意这个文件的位置和 `justfile` 相反：`justfile` 进 git、三层共用；护栏脚本放在 `.claude/` 下（通常被 gitignore），只在正式环境目录生效。如果项目把 `.claude/` 提交进 git，脚本会跟着进到每个 worktree——不影响正确性（它按目录名判断，在别的目录里直接放行），但要告诉用户。

### 3. 注册进正式环境目录的 `.claude/settings.json`

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/guard-prod.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

文件已存在时**只在 `hooks.PreToolUse` 数组里追加**，不要整体覆盖——那里可能已经有别的 hook。

### 4. 顺带把 worktree 基点钉住

同一份 `settings.json` 里加：

```json
"worktree": { "baseRef": "head" }
```

理由属于分支流那一块，见 `branch-flow` skill。一句话版本：新 worktree 要从**当前 session 所在的分支**长出来，而不是从 `origin/<default>`——本地开发的仓库常常没有 remote，默认的 `fresh` 模式会落空。

### 5. 验证护栏确实在拦

改完必须实测，**不要只看代码就宣布装好了**。护栏的失效是静默的。

在正式环境目录下让 agent 跑一条会被拦的命令，例如 `docker compose down -v`——应当看到中文拦截文案且命令没有执行。再在 UAT 目录下跑同一条，应当放行。

两边行为一致（都拦或都放）说明占位符没替换对，回到第 2 步检查 `PROD_DIR` 是不是目录名而不是完整路径。

## 护栏拦什么、不拦什么

三条硬拦截，都是**不可逆且没有 undo** 的：

- `docker compose down -v` —— 删数据卷。备份通常是每天一次，最坏丢掉最近一天。
- `docker volume rm` / `prune` —— `prune` 尤其危险，它不带项目名，会把这台机器上所有未使用的卷一起带走。
- `git clean -x` —— 把被 gitignore 的文件一起删。凭证文件和本地备份目录通常正好都被 gitignore，在 `clean` 眼里是「无主文件」，却是唯一一份。

一条软确认（转成确认提示而不是拦死）：正式环境目录下不带 override 的 `up`/`restart`。这个错误不毁数据，但它是静默的。

**明确不做全面防护。** 拦得越多，被整体关掉的可能越大，而被关掉就等于三条硬拦截一起失去。换个写法（`docker rm -v`、手删 `/var/lib/docker/volumes/`）照样绕得过去。真正的兜底仍然是「不在正式环境目录里做试验」——护栏兜的是「一时手滑」，兜不住「想绕」。

同理，脚本在解析不出输入时（例如 `python3` 不可用）**放行而不是拦截**。一道 fail-closed 的护栏会把这个项目里所有 Bash 调用堵死，结果必然是有人把 hook 关掉。

## 一个已知的判定边界

hook 拿到的 `cwd` 是 session 的工作目录，不是命令实际执行的目录。所以 `cd ../<PROD_DIR> && docker compose down -v` 从 UAT 目录发出时，`cwd` 是无害的。

模板因此加了第二条判据：命令文本里出现 `cd` 到 `PROD_DIR` 时同样按正式环境处理。代价是偶尔误伤（在 UAT 里 `cd ../<PROD_DIR> && git log` 也会被当成正式环境上下文，不过 `git log` 本来就不在拦截名单里，实际很少撞上）。方向是安全的：误伤只是多挨一次拦截。

绕过它仍然不难（变量拼路径、`pushd`、脚本里再套一层）。这就是上一节说的「兜手滑，不兜想绕」。

## 与其他插件的关系

- **`dev-env-router/onboard`** —— 域名怎么落到 `<目录名>.localhost` 归它管。本 skill 只依赖「Compose 项目名取目录名」这一条，两边共用同一个判据，不共享配置文件。
- **`mise-toolchain/link-env`** —— 各层的环境变量怎么接归它管。注意 UAT 的凭证问题不只是「接上就行」，见 `stand-up-uat` skill。
