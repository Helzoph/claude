---
name: onboard
description: "Onboards a project/worktree that has no Traefik labels yet onto http://<project-dir-name>.localhost, assuming the machine-level shared Traefik router has already been set up by the user (see the plugin's USAGE.md). Use this skill when the user asks to set up local dev routing for a new project/worktree, or wants to stop manually assigning ports across worktrees. Triggers on: setting up a new project/worktree's dev environment, requests to stop tracking ports manually. Do NOT use for starting/stopping/checking an already-onboarded project (use operate instead) — 'is there a shared dashboard' or 'what's running' about an existing setup belongs to operate, not here. Do NOT use this skill to bootstrap the shared router itself — that is a one-time manual setup documented in USAGE.md, not something this skill performs."
---

# dev-env-router: 项目接入（onboard）

## 核心思路

不再手动分配端口/域名。Docker Compose 默认用当前目录名作为 `COMPOSE_PROJECT_NAME`，而 git worktree 的目录名天然互不相同，因此可以直接把目录名当作项目的路由身份：`http://<目录名>.localhost`。所有流量经由**全机器唯一**的 Traefik 实例转发，容器不再需要发布端口到宿主机。

**仅限本机开发使用**（纯 HTTP，无 TLS）。不要把这套配置套用到生产部署上。

## 前提：共享路由器由用户手动搭建，本 skill 默认它已经在跑

共享路由器（`router/router-compose.yml`）的首次搭建是一次性的机器级操作（创建网络、生成 basicauth 凭证、启动容器），文档在插件的 `USAGE.md` 里，**由用户自己手动完成，不属于本 skill 的职责**。本 skill 默认这一步已经做完，不负责检测、引导、或代为执行这套搭建流程。

如果实际操作中发现路由器没有在跑（例如 `docker compose up -d` 后项目访问不通），直接告诉用户去 `USAGE.md` 完成一次性搭建，不要尝试自己代为初始化（会涉及绑定宿主机 80 端口、挂载 `/var/run/docker.sock` 等机器级副作用，不应该被"接入项目"这类请求隐式触发）。

## 接入具体项目 / worktree

对每一个需要接入路由的项目或 worktree：

0. 先排查是否已存在同名孤儿 Compose 项目：如果这个目录名此前被别的 worktree 用过、后来被删除但容器未清理，新项目 `docker compose up -d` 可能与旧容器发生 `COMPOSE_PROJECT_NAME` 撞名（Compose 会认为是在"更新"旧项目而不是新建）。检查方式：
   ```bash
   docker compose ls --format json | grep -i "<预期项目名>"
   ```
   如果发现同名项目、但状态异常或来源不明，先走一遍 `cleanup` skill 排查确认，再回来继续接入，不要直接 `up`。

1. 检查目标项目根目录下是否已存在 `docker-compose.yml` 或 `compose.yml`。
   - **不存在**：直接把 `templates/project-compose.yml` 复制为该项目的 `docker-compose.yml`，再按文件内 TODO 注释填入实际的服务定义（build/image/command、容器内部监听端口）。
   - **已存在**：**禁止直接覆盖**。必须先向用户说明差异，询问合并方式（例如：在现有服务上追加 `networks`/`labels` 字段，还是保留原文件、新增一个专门的 override 文件）。用户明确选择后再动手改。

2. 关键字段核对（合并进已有文件时尤其要检查）：
   - 不要给服务加 `ports:` 映射到宿主机。
   - `networks:` 必须包含外部 `web` 网络。
   - `labels:` 必须包含 `traefik.enable=true`、基于 `${COMPOSE_PROJECT_NAME}` 的路由规则、以及正确的容器内部端口（`loadbalancer.server.port`）。
   - **多服务项目（如 app + db + redis）只给对外提供 HTTP 入口的那一个服务打 Traefik label**，其余内部服务不要加。虽然 `exposedbydefault=false` 兜底了未打 label 的服务不会被意外暴露，但如果照抄模板把 labels 块机械复制到每个 service 上，会导致所有服务都被暴露路由。

3. 启动：在项目目录下执行 `docker compose up -d`（必须在项目根目录执行，以保证 `COMPOSE_PROJECT_NAME` 正确派生自目录名）。

4. 验证：访问 `http://<项目目录名>.localhost`。如果目录名包含大写字母、点号等字符，Compose 会做归一化，实际域名可能与目录名不完全一致——以 dashboard（`http://traefik.localhost`）里显示的实际路由为准。

## 环境变量：容器侧接到共享 baseline

如果项目需要 `.env` 才能启动，**不要把 `.env` 复制进 worktree**。`.env` 是未跟踪文件，`git worktree add` 不会带过来，手动复制会导致每个 worktree 各有一份副本、各自漂移。

正确做法是让容器读工作区外的共享 baseline，写在 `docker-compose.override.yml` 里（该文件必须 gitignore）：

```yaml
services:
  <打了 traefik label 的那个服务>:
    env_file:
      - ${HOME}/.local/share/dev-env/env/<选中的那一个>.env   # baseline
      - path: .env.local                   # 本 worktree 私有覆盖
        required: false                    # 大多数 worktree 没有这个文件
```

### 选哪一份 baseline

跑这条判定，把输出的文件名填进上面的 `env_file`（只做存在性检查，不读内容）：

```bash
REPO=$(basename "$(git rev-parse --path-format=absolute --git-common-dir | xargs dirname)")
ENVDIR=~/.local/share/dev-env/env
test -f "$ENVDIR/$REPO.env" && echo "$REPO.env" || { test -f "$ENVDIR/dev.env" && echo dev.env; }
```

没有任何输出时**停下来问用户**，不要代为创建，也不要转而去读项目自己的 `.env`。

两条硬约束（不因为规则真源在别处就放松）：

- **不要在 `~/.local/share/dev-env/env/` 下创建任何文件**，那个目录只由用户手动维护。
- **不要读取、打印或复制 baseline 与 `.env.local` 的内容**，这里只需要把路径接上。

> **规则真源：`mise-toolchain` 插件的 `link-env` skill。** 上面这条判定的完整版本、以及各条约束背后的理由（为什么两个 baseline 是替换而非补丁关系、为什么 agent 不能代为创建）都写在那里，本节不重复。宿主机侧（`npm run dev` 这类）由 `link-env` 写 `mise.local.toml` 接同一份 baseline——两侧**必须选中同一个文件**，否则会出现"容器里跑得通、宿主机跑不通"这类最难排查的问题。两个插件各写各的文件，不共享配置。

### 容器侧特有的坑

这三条只在 Compose 这边成立，`link-env` 里没有：

- **`env_file` 不展开 `~`**，必须写 `${HOME}` 或绝对路径。写成 `~/...` 时 Compose 会当作字面量目录名去找，报文件不存在。这一点和 mise 的 `_.file` 相反（那边 `~` 会展开），两处配置容易互相照抄写错。
- `required: false` 需要 Compose 2.24+。低版本会因为无法识别长语法而报错。
- 写在 `docker-compose.override.yml` 而不是 `docker-compose.yml`：后者要进 git，写入机器级绝对路径会让配置不可移植，且每个 worktree 改同一行必然产生 merge 冲突。

## 后续

- 日常启停规则见 `operate` skill。
- worktree 删除后的孤儿容器清理见 `cleanup` skill（清理是破坏性操作，不会自动执行）。
