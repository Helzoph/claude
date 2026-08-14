---
name: link-env
description: "Wires a project/worktree to a shared baseline .env kept outside the git working tree, with an optional per-worktree override layer, by writing a gitignored mise.local.toml. Picks the baseline from ~/.local/share/dev-env/env/ by name — <repo>.env when it exists, otherwise dev.env — without asking the user which one. Use when a new git worktree has no .env and shouldn't need one copied in by hand, when the same credentials must be reused across several worktrees of one repo, or when a single worktree needs to override a few env values without diverging from the shared baseline. Triggers on: worktree missing .env, sharing env across worktrees, overriding an env var in just one worktree. Do NOT use for toolchain versions (use setup-toolchain). Never create files in the baseline directory — the user provisions those by hand — and never read, print, or copy the contents of any baseline .env; this skill only wires up paths."
---

# mise-toolchain: 跨 worktree 环境变量分层（link-env）

## 要解决的问题

`.env` 是未跟踪文件，`git worktree add` 不会把它带到新 worktree。结果是每建一个 worktree 就要手动复制一份 `.env`，且此后多份副本各自漂移，无从判断哪份是对的。

## 方案：单一真源 + 可选覆盖层

```
~/.local/share/dev-env/env/     baseline 目录 —— 工作区外，全机器共用，只有用户能往里放文件
  ├── dev.env                   通用回退：没有项目专属文件时用它
  └── <repo>.env                项目专属：文件名与仓库名一致时优先选中
<worktree>/.env.local           覆盖层 —— 该 worktree 私有，只写差异的几行，可以不存在
```

在每个 worktree 里写一份 **`mise.local.toml`**：

```toml
[env]
_.file = [
  "~/.local/share/dev-env/env/<选中的那一个>.env",  # baseline，见下面的选择规则
  ".env.local",                                    # 本 worktree 私有覆盖，不存在时静默跳过
]
```

三条已实测确认的 `_.file` 行为（mise 2026.7）：

| 行为 | 结果 |
|---|---|
| 数组内后者覆盖前者 | 是 —— 同名变量以 `.env.local` 为准 |
| 列表中的文件不存在 | 静默跳过，不报错 —— 所以 `.env.local` 可以按需才创建 |
| 路径中的 `~` | 会展开 |

注意最后一条和 Docker Compose 相反：Compose 的 `env_file:` **不展开 `~`**，那边必须写 `${HOME}`。两处配置容易互相照抄，写错时表现为"容器读不到变量但宿主机正常"。

## baseline 选择规则（agent 必须按此判定，不要询问用户选哪个）

设仓库名为 `<repo>`（**仓库名，不是 worktree 目录名**——同一仓库的所有 worktree 必须指向同一个 baseline）：

1. `~/.local/share/dev-env/env/<repo>.env` 存在 → 用它。
2. 否则 `~/.local/share/dev-env/env/dev.env` 存在 → 用它。
3. 两者都不存在 → **停下来告诉用户**，不要继续，也不要转而去读项目自己的 `.env`。

判定只用存在性检查，不读内容：

```bash
REPO=$(basename "$(git rev-parse --path-format=absolute --git-common-dir | xargs dirname)")
ENVDIR=~/.local/share/dev-env/env
test -f "$ENVDIR/$REPO.env" && echo "$REPO.env" || { test -f "$ENVDIR/dev.env" && echo dev.env; }
```

用 `--git-common-dir` 而不是 `--show-toplevel`：在 worktree 里后者返回 worktree 目录名（如 `backend-skeleton`），会选错 baseline。

**选中的是哪一个，就在 `_.file` 里写哪一个——只写一个，不要把 `dev.env` 和 `<repo>.env` 同时列进去。**

这一点必须清楚，因为它有个反直觉的后果（已实测）：两个文件是**替换关系而非补丁关系**。假如 `dev.env` 有 `LLM_API_KEY` 和 `LLM_MODEL`，而 `prison-a.env` 只写了 `LLM_MODEL`，那么选中 `prison-a.env` 后 **`LLM_API_KEY` 会直接消失**，表现为运行时报缺少凭证。

所以项目专属文件必须**自带全部所需变量**，而不是只写差异。如果你想要的是"通用打底 + 项目覆盖"的叠加语义，那要在 `_.file` 里同时列两个（前者打底、后者覆盖）——但这不是本 skill 的默认约定，除非用户明确要求叠加，否则一律按上面的独占规则来。

## 绝对不要代为创建 baseline 文件

`~/.local/share/dev-env/env/` 里的任何 `.env` 文件**只能由用户手动创建**。agent 不得 `touch`、`cp`、`mv`、重定向写入，或以任何方式在该目录下产生文件——包括"从项目现有 `.env` 复制一份过去"这种看起来很自然的操作。

理由：这个目录是凭证的唯一真源。让 agent 经手意味着凭证内容会流经会话上下文；而一个被 agent 凭空创建的、内容是猜测或占位符的 baseline，比文件不存在更糟——后者会立刻报错，前者会一路跑到某个语义不明的 401 才暴露。

需要新建时，把命令交给用户自己执行：

```bash
# 项目专属 baseline（注意：要写全所有变量，不能只写差异）
$EDITOR ~/.local/share/dev-env/env/<repo>.env
chmod 600 ~/.local/share/dev-env/env/<repo>.env
```

注意 `settings.json` 里那条针对 `env/**` 的 Read deny 会**连带挡住对该目录的 Bash 写操作**（如 `chmod`），这也是上面这些命令必须交给用户执行的又一个原因。存在性检查（`test -f`）不受影响，选择规则照常可用。

## 为什么是 mise.local.toml，不是 mise.toml

`mise.toml` 要进 git。baseline 路径是机器级的绝对路径，写进 `mise.toml` 会带来两个后果：一是配置不可移植（换台机器/别人 clone 就是错的），二是每个 worktree 各自改这一行会造成 merge 冲突，甚至把某个 worktree 的私有路径误提交进主分支。

`mise.local.toml` 是 mise 官方的本地覆盖机制，加载优先级高于 `mise.toml`（`mise cfg` 可以看到完整加载链）。它 gitignore 之后：

- `mise.toml` —— `[tools]`，进 git，跨 worktree 共享（`setup-toolchain` skill 负责）
- `mise.local.toml` —— `[env]`，gitignored，per-worktree（本 skill 负责）

两个 skill 各写各的文件，永不互相覆盖。这个分工和 Docker Compose 侧（`docker-compose.yml` 进 git、`docker-compose.override.yml` gitignored）是同一套心智模型。

## 操作步骤

1. **确认 `.gitignore` 覆盖了这两个文件**，没有就补上：

   ```gitignore
   mise.local.toml
   .env.local
   ```

   这一步必须先做。先写文件后补 gitignore，中间任何一次 `git add -A` 都可能把它们提交进去。

2. **按上面的选择规则挑出 baseline**（`<repo>.env` 优先，回退 `dev.env`），只做存在性检查，不读内容。

   两个都不存在时**停下来告诉用户**，不要代为创建、不要从项目现有 `.env` 复制过去、也不要转而去读项目的 `.env`。交给用户执行的命令：

   ```bash
   $EDITOR ~/.local/share/dev-env/env/dev.env      # 或 <repo>.env
   chmod 600 ~/.local/share/dev-env/env/dev.env
   ```

3. **写 `mise.local.toml`**，内容如上。已存在同名文件时不要整体覆盖，只在 `[env]` 段内合并。

4. **`mise trust`** —— 新文件默认不受信任，未 trust 时 mise 命令会报 "error parsing config file"（首行具有误导性，实际原因是信任而非语法）。

5. **验证**：

   ```bash
   mise env -D | cut -d= -f1 | ugrep '<某个已知的变量名>'
   ```

   **`cut -d= -f1` 这一段不能省。** `mise env -D` 的输出是 `KEY=value`，直接 `ugrep 变量名` 会把匹配行**连值一起**打印出来——凭证就这样进了终端和会话上下文，正是这个 skill 要避免的事。先 `cut` 掉 `=` 后面的部分，就只剩变量名。

   同理也不要直接看 `mise env -D` 的完整输出。

## 需要修改某个 worktree 的 env 时

在该 worktree 建 `.env.local`，**只写要改的那几行**，其余继续继承 baseline：

```bash
echo 'API_BASE_URL=http://localhost:9999' >> .env.local
```

不要复制整份 baseline 再改——那样就退回到"多份副本各自漂移"的原始问题，而且改了什么一眼看不出来。

## 明确不做的事

- **不要用 symlink 把 baseline 链接进 worktree**。symlink 是共享同一个文件，在任一 worktree 里修改会同时影响主仓库和其他所有 worktree，恰好破坏"单个 worktree 独立覆盖"这个需求。
- **不要读取、打印、或复制 baseline 与 `.env.local` 的内容**。本 skill 的职责只是把路径接起来。需要确认某个变量是否生效时，用上面只查变量名的方式。

  这条是**行为约束，不是靠工具拦截兜底的**。`settings.json` 里那条 `Read(//…/dev-env/env/**)` 只约束 Read 工具——实测确认 Bash 里的 `ugrep`、`jq`、`cat` 照样能读出内容。它挡的是"顺手 Read 一眼"，挡不住绕路。所以真正的边界在这条规则本身，不要因为"反正有 deny 规则"就放松。
- **不要把 baseline 路径写进任何进 git 的文件**（`mise.toml`、`docker-compose.yml`、README 示例除外——文档里写占位符即可）。

## 与容器侧的关系

如果项目同时通过 Docker Compose 运行，容器侧要读**同一份 baseline**，否则会出现"宿主机跑得通、容器里跑不通"这类最难排查的问题。容器侧的接法归 `dev-env-router` 插件的 `onboard` skill 管（写在 `docker-compose.override.yml` 里）；两边通过约定同一个 baseline 路径协作，不共享配置文件。
