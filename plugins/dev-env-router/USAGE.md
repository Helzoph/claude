# dev-env-router 使用手册

面向使用者本人的操作指南。agent 应该遵循的规则在各个 `skills/*/SKILL.md` 里；这份文档是给你自己看的，讲清楚"这套东西整体在干什么、怎么一步步搭起来、有哪些坑"。

## 一句话说明

一台机器上只跑一份 Traefik（反向代理），常驻后台。每个项目/worktree 不再发布端口到宿主机，而是打上 label 让 Traefik 按目录名把它路由到 `http://<目录名>.localhost`。你不需要记任何端口号，也不需要给每个项目手动分配域名。

**仅限本机开发使用**（纯 HTTP，无 TLS）。不要把这套配置套用到生产部署上。

## 架构：两个层级，不要混淆

| | Router（机器级） | Project（项目级） |
|---|---|---|
| 配置文件 | `router/router-compose.yml` | `skills/onboard/templates/project-compose.yml` |
| 实例数量 | 全机器唯一一份，常驻 | 每个项目/worktree 各一份 |
| 存放位置 | `~/.dev-env-router/`（不进任何 git 仓库） | 目标项目自己的仓库里 |
| 谁来发起 | 需要你明确同意才会首次启动 | 你要求接入某个项目时才生成 |

这两个文件**从设计上就是分开的**，不会被同一步操作一起处理。如果发现某次操作试图把 `router-compose.yml` 复制进某个项目仓库，那是不对的，应该停下来。

## 80 和 8080 端口分别是什么

- **80**：项目流量的统一入口。浏览器访问 `http://xxx.localhost` 这种不带端口号的地址时，默认走的就是 80 端口——这也是为什么整套方案能做到"不用记端口"：不是端口消失了，而是固定用了浏览器默认会用的那个端口。换成别的端口，代价是每次访问都要在 URL 里带端口号，等于把"记端口"这件事又加了回来。
- **8080**：只给 Traefik 自己的管理面板（dashboard）用，跟项目流量无关。已绑定在 `127.0.0.1`，不监听局域网，且加了 basicauth，同一网络内其他设备访问不到。

## 首次搭建：一步步来

### 第 0 步：确认 80 端口没被占用

```bash
lsof -i :80
```

如果本机已经有别的服务占着 80（比如另一个本地 Web 服务器），先处理冲突，否则 Traefik 会启动失败。

### 第 1 步：创建外部网络

```bash
docker network create web
```

`router-compose.yml` 和 `project-compose.yml` 都假设这个网络已经存在，不会自动创建，漏了这步会直接报错。

### 第 2 步：生成 basicauth 凭证文件

**这里有个容易踩的坑**：`router-compose.yml` 里把 `~/.dev-env-router/traefik/.htpasswd` 作为文件挂进容器（bind mount）。如果这个文件在启动前不存在，Docker 常见的行为是**把它当成目录自动创建一个空目录**，而不是报错提示"文件不存在"——Traefik 容器会因为挂载路径类型不对而启动失败，报错信息还不直观。所以必须先手动创建好这个文件：

```bash
mkdir -p ~/.dev-env-router/traefik
htpasswd -Bc ~/.dev-env-router/traefik/.htpasswd <你选一个用户名>
```

`-c` 会直接创建（或覆盖）这个文件；不加 `-n` 时命令是交互式的，会提示你输入并确认一次密码（输入过程不回显，这是终端的正常行为，不是卡住了）。**这个密码由你自己设定和记忆**，请当场记好（比如存进密码管理器）——文件里存的是哈希值，不是明文，事后无法从文件里找回原始密码。

```bash
chmod 600 ~/.dev-env-router/traefik/.htpasswd
```

限制这个文件只有你自己能读。

### 第 3 步：复制配置并启动

```bash
mkdir -p ~/.dev-env-router
cp <插件安装路径>/plugins/dev-env-router/router/router-compose.yml ~/.dev-env-router/router-compose.yml
docker compose -f ~/.dev-env-router/router-compose.yml up -d
```

复制一份到 `~/.dev-env-router/` 再启动，而不是直接对插件目录里的文件执行 `-f`——这样以后插件更新、或者这个 marketplace 仓库有变动，都不会影响到正在运行的路由器。

### 第 4 步：验证

浏览器访问 `http://traefik.localhost`，输入第 2 步设置的用户名和密码，能看到 Traefik dashboard 即为成功。这个页面之后会持续有用——它会显示当前所有接入了路由的项目、各自的域名、后端健康状态，是查看"我现在到底跑了哪些东西"的地方，不需要再去 `docker ps` 里猜。

以上 4 步**只需要做一次**，不会随每个新项目/新 worktree 重复。

## 修改 basicauth 密码

忘记密码，或者单纯想换一个，都执行同一条命令（用户名要和第 2 步设置的一致，否则会在文件里新增一行而不是替换）：

```bash
htpasswd -B ~/.dev-env-router/traefik/.htpasswd <第 2 步用的用户名>
```

不带 `-c` 是因为文件已经存在，不需要（也不应该）重新创建；命令会交互式提示你输入并确认新密码，回车后直接覆盖该用户名对应的哈希值。

Traefik 对 `usersFile` 的热重载并不可靠——这里是单文件 bind mount（见 `router-compose.yml`），社区已知这种挂载方式经常检测不到文件变化。改完密码后，先刷新 `http://traefik.localhost` 试试新密码；如果还是提示旧密码或 401，执行：

```bash
docker compose -f ~/.dev-env-router/router-compose.yml restart traefik
```

重启容器后必定生效。

## 接入一个项目

1. 检查项目根目录下是否已有 `docker-compose.yml` / `compose.yml`。
   - 没有：把插件里的 `skills/onboard/templates/project-compose.yml` 复制过去，按文件里的 TODO 注释填上实际的服务定义（`build`/`image`/`command`，以及容器内部实际监听的端口）。
   - 已有：不要直接覆盖，先看清楚现有内容怎么合并（追加 `networks`/`labels` 字段，还是另起一个 override 文件）。
2. 确认这几点：
   - 不要给服务加 `ports:` 映射到宿主机——所有流量都走 Traefik 转发。
   - `networks:` 要包含外部的 `web` 网络。
   - `labels:` 要有 `traefik.enable=true`、基于 `${COMPOSE_PROJECT_NAME}` 的路由规则、以及正确的容器内部端口。
   - 如果项目有多个服务（app + db + redis 这种），**只给对外提供 HTTP 的那一个服务打 label**，其余服务不要加，否则容易被意外暴露路由。
3. 在项目根目录下执行 `docker compose up -d`（必须在项目根目录执行，域名是从当前目录名派生的）。
4. 访问 `http://<项目目录名>.localhost`。如果目录名里有大写字母或点号，Compose 会做归一化处理，实际域名可能和目录名不完全一样——以 dashboard 里显示的为准，不要猜。

## 日常使用

- 启停统一用 `docker compose up -d` / `docker compose down`，不要直接跑裸进程（比如 `npm run dev`）替代——裸进程不会经过 Traefik，路由不会生效。
- 需要知道服务地址时，就是 `http://<项目目录名>.localhost`，不需要问、也不需要记端口号。
- 想看全局有哪些项目在跑，去 `http://traefik.localhost`（需要 basicauth）。

## 需要特别注意的事情

- **Docker socket 权限**：Traefik 需要读取 `/var/run/docker.sock` 才能自动发现容器，这本质上等价于拥有宿主机 Docker daemon 的完全控制权（能起停任意容器、挂载任意宿主机目录）。这是 Traefik 工作原理决定的，只读挂载也无法进一步收窄。**这套方案只适合个人单用户的本机开发环境**，不要在多人共用的机器或有敏感数据的机器上这样搭。
- **不支持 HTTPS**：这套配置从头到尾都是纯 HTTP，浏览器不会显示锁形图标，也没有证书。任何需要测试 HTTPS 特有行为（比如 Service Worker、某些 cookie 的 `Secure` 属性）的场景，这套方案覆盖不到。
- **worktree 删除后容器不会自动清理**：`git worktree remove` 只删目录，不会帮你 `docker compose down` 对应的容器。长期不管会积累孤儿容器占用磁盘。清理方式见下一节。
- **端口 80 是系统级端口**：如果之后本机新装了别的软件也想用 80（比如某些本地开发服务器的默认配置），会跟 Traefik 冲突，需要手动协调谁用 80。

## 清理孤儿项目

worktree 被删除后，对应的容器可能还在。**清理是破坏性操作，不会自动执行**，只会先列出候选清单，等你明确对着具体项目名确认了才会删除。触发方式是让 agent 走 `cleanup` skill，或者你自己手动比对：

```bash
docker compose ls --format json     # 当前所有 Compose 项目
git worktree list --porcelain       # 当前仍然存在的 worktree 目录
```

两者对不上的项目名就是候选孤儿。确认要删的项目后执行：

```bash
docker compose -p <project-name> down -v
```

## 出问题时先看这里

| 现象 | 大概率原因 |
|---|---|
| `docker compose up` 报网络相关错误 | 忘了 `docker network create web` |
| Traefik 容器起不来，日志提示挂载路径异常 | `.htpasswd` 文件不存在，Docker 把它当目录创建了——删掉那个自动生成的目录，重新按第 2 步生成文件 |
| 端口 80 绑定失败 | 本机有其他服务占用了 80，先 `lsof -i :80` 排查 |
| `http://project.localhost` 打不开 | 检查项目容器有没有起来（`docker compose ps`），检查 label 是否正确；也去 dashboard 确认实际路由 |
| dashboard 打不开或提示 401 | 确认访问的是 `http://traefik.localhost`（不是 IP+端口），且用了第 2 步设置的用户名密码 |
| 目录名和实际访问的域名对不上 | Compose 对项目名做了归一化（转小写、替换特殊字符），以 dashboard 里显示的为准 |
