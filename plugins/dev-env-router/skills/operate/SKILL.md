---
name: operate
description: "Day-to-day start/stop/restart rules for a project already onboarded to dev-env-router (has a docker-compose.yml with Traefik labels), and how to report its URL. Use this skill whenever starting, stopping, or restarting a dev service in an already-onboarded project, or when asked what a specific onboarded project's URL is. Triggers on: 'start the dev server', 'run the app', 'stop this project's containers'. Do NOT use for first-time setup of a project without Traefik labels (use onboard instead), or for a broad 'what's running across all my projects' question (check the Traefik dashboard directly per this skill's own instructions, that is not a separate trigger)."
---

# dev-env-router: 日常操作规则

适用于已经通过 `onboard` skill 接入路由的项目。

## 前置检查：先确认项目已接入

执行任何启停命令之前，先确认目标项目确实已经接入本方案，不要凭"用户说了启动/运行"就直接假设已接入：

```bash
grep -q 'traefik.enable=true' docker-compose.yml compose.yml 2>/dev/null && echo onboarded || echo not-onboarded
```

如果检测结果是 `not-onboarded`，不要在这里临时补 label 或强行执行 `docker compose up`，改为引导用户走 `onboard` skill 完成接入。

## 启动 / 停止

必须在项目根目录下用 Docker Compose 命令，**不允许**起裸进程（如直接 `npm run dev`、`python manage.py runserver`）替代：

```bash
docker compose up -d      # 启动
docker compose down       # 停止
docker compose restart    # 重启
```

Rationale：`COMPOSE_PROJECT_NAME`（进而域名）依赖当前工作目录派生，必须在项目根目录下执行才能保证路由身份正确；裸进程也不会经过 Traefik 转发，会让这套路由方案失效。

## 报告地址：只报域名，不报端口

任何时候向用户说明"服务在哪"，一律使用 `http://${COMPOSE_PROJECT_NAME}.localhost` 形式的 URL，不报告、不询问任何端口号——端口对使用者来说不应该是一个需要关心的概念。

`${COMPOSE_PROJECT_NAME}` 就是项目目录名（经 Compose 归一化后的版本）。不确定实际域名时，去 dashboard 确认，不要凭猜测报告。如果 dashboard 里找不到该项目的路由，先检查是否漏打 `traefik.enable=true` label（回到上面的前置检查步骤），而不是重复尝试猜测域名。

## 查看全局状态

不要用 `docker ps` 逐个猜测容器归属。所有接入了路由的项目会自动出现在共享 Traefik 的 dashboard 里：

```
http://traefik.localhost
```

需要 `~/.dev-env-router/traefik/.htpasswd` 对应的 basicauth 凭证登录。这里能看到当前所有正在运行的项目、各自的域名路由、后端健康状态。

## 边界

- 本 skill 不负责首次接入（见 `onboard`）、也不负责已删除 worktree 的孤儿容器清理（见 `cleanup`，属于破坏性操作，不在日常操作范围内）。
- 若项目还没有 Traefik label（未接入本方案），先引导用户走 `onboard` skill，不要在 operate 阶段临时补 label。
- 本 skill 不负责共享路由器（Traefik 本身）的重启/升级/凭证轮换——那是用户按插件 `USAGE.md` 手动搭建、手动维护的机器级基础设施，不属于任何 skill 的职责。用户说"重启 Traefik"而不是"重启我这个项目"时，不要在项目目录下执行 `docker compose restart`；如果需要重启路由器本身，引导用户参照 `USAGE.md` 自行操作（该服务的启动命令是幂等的，直接复用已有配置即可）。
