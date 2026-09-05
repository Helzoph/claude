# env-tiers

本机三层环境：开发 worktree → UAT → 正式。身份由**目录名**派生，走错一层是当场失败，而不是安静地跑错配置。

## 要解决的问题

同一个仓库既跑着真实数据，又是改代码的地方。于是每一次 `docker compose down -v`、每一次跑迁移、每一次「我试试看」，动的都是不能丢的那份数据。

分支不解决这个问题——分支只隔离代码，不隔离卷。

## 布局

```
<repo>/                          正式，真实数据       http://<repo>.localhost
<repo>-uat/                      UAT，可随时推倒      http://<repo>-uat.localhost
<repo>/.claude/worktrees/*/      开发，不起容器
```

三层各是一个 git worktree。目录名互不相同，这一条带来其余所有性质：Compose 项目名默认取目录名，于是容器名和卷名自动带前缀（`<repo>_data` vs `<repo>-uat_data`），**两套数据天然隔离**，不需要任何配置。域名同理。

代价是要守住一件事：UAT 目录必须叫 `<repo>-uat`。插件生成的 `justfile` 把这件事变成当场失败。

## Skills

| Skill | 做什么 |
|---|---|
| `setup-tiers` | 写命令入口（`justfile`）和正式环境的护栏 hook，占位符按项目填死 |
| `branch-flow` | worktree 从正式分支开、只 merge 不 rebase、UAT 可 `reset --hard` 重建 |
| `stand-up-uat` | 首次搭 UAT，重点是盘点 UAT 从正式环境静默继承的凭证与副作用 |

## 护栏

`setup-tiers` 会在正式环境目录写一个 `PreToolUse` hook。它按**目录名**判断（分支能被 checkout 改掉，目录不会），硬拦三条不可逆操作：

- `docker compose down -v`
- `docker volume rm` / `prune`
- `git clean -x`

外加一条软确认：正式环境目录下不带 prod override 的 `up`/`restart` 转成确认提示——这个错误不毁数据，但它是静默的（源码 bind mount 回来，容器照样起、页面照样开）。

**它不做全面防护，这是刻意的。** 拦得越多，被整体关掉的可能越大，而被关掉等于三条硬拦截一起失去。换个写法照样绕得过去。护栏兜的是「一时手滑」，兜不住「想绕」——真正的兜底仍然是「不在正式环境目录里做试验」。

同理，脚本解析不出输入时（例如 `python3` 不可用）放行而不是拦截：一道 fail-closed 的护栏会堵死这个项目里所有 Bash 调用，结果必然是有人把 hook 关掉。

## 与其他插件的关系

- `dev-env-router/onboard` —— 域名怎么落到 `<目录名>.localhost` 归它管。两边共用「Compose 项目名取目录名」这一个判据，不共享配置文件。
- `mise-toolchain/link-env` —— 各层的环境变量怎么接归它管。但 UAT 的凭证不只是「接上就行」，共享凭证的副作用清单在 `stand-up-uat` 里。

## 适用范围

**仅限本机开发**。这套判据（目录名 = 环境）在部署到远端的场景下不成立，不要照搬。
