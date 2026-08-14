---
name: setup-toolchain
description: "Creates or updates a project's mise.toml [tools] block so the languages and CLI tools it needs are version-pinned, inheriting the machine's own version preferences (e.g. python 3.12 rather than latest) instead of defaulting everything to latest. Use when setting up a new project/worktree's toolchain, when adding a language or tool to an existing mise.toml, or when a project has no pinned versions and 'works on my machine' drift is a concern. Triggers on: pinning tool versions, adding go/python/node/rust to a project, setting up mise for a repo. Do NOT use for env variables or secrets (use link-env instead), and do NOT use this skill to author [tasks] — task orchestration is hand-written domain knowledge, not generated."
---

# mise-toolchain: 工具链版本固定（setup-toolchain）

## 核心思路

项目用到的语言/CLI 版本收口到项目根目录的 `mise.toml`，不再依赖"本机恰好装了什么"。

关键原则：**版本规格继承本机偏好，而不是一律写 `latest`**。用户的全局 `~/.config/mise/config.toml` 已经表达了他对每个工具的版本偏好（例如 `python = "3.12"` 而非 latest），项目配置无视这个偏好去写 `latest`，会导致项目里的版本和用户日常使用的版本不一致——这类不一致往往要到运行期才暴露。

## 判定本机偏好：逐个工具查，不要猜

对每一个要写进 `mise.toml` 的工具，先查本机全局配置里的版本规格：

```bash
mise config get tools.<tool-name>
```

- **有输出**（例如 `3.12`、`latest`、`lts`）：**原样抄进 `mise.toml`**，不要自作主张改写。用户写 `lts` 就保持 `lts`，写 `3.12` 就保持 `3.12`。
- **无输出 / 报错**：本机没有这个工具的偏好，写 `latest`。
- **`mise` 命令本身不存在**（`command -v mise` 失败）：无法读取任何偏好，**所有工具一律写 `latest`**，并明确告知用户"本机未安装 mise，已全部使用 latest；装了 mise 之后可以重跑本 skill 以继承你的版本偏好"。

不要用 `mise ls` 的输出反推版本规格。`mise ls` 显示的是**已解析的具体版本**（如 `python 3.12.13`），把它写进 `mise.toml` 等于把一个本应随补丁更新的规格钉死到补丁号，和用户全局写 `3.12` 的意图不符。`mise config get` 返回的才是规格本身。

## 写入规则

1. **只管 `[tools]`**。不要生成 `[tasks]`、不要生成 `[env]`。
   - `[tasks]` 是项目特有的编排知识（依赖关系、目录切换、失败处理），agent 凭空生成的版本通常是错的，且会覆盖用户手写的内容。
   - `[env]` 归 `link-env` skill 管，且写在 `mise.local.toml` 而非 `mise.toml`——见该 skill。

2. **已存在 `mise.toml` 时禁止整文件覆盖**。只在 `[tools]` 表内增删条目，其余段落（尤其 `[tasks]`、`[env]`、`[settings]`）原样保留。如果要改的是用户已经写过的某个工具的版本，先说明当前值和建议值的差异，等用户确认。

3. **工具范围来自项目实际用到的东西**，不要把全局配置里的工具列表整个搬过来。判断依据是项目里的实际证据：`go.mod`、`pyproject.toml`/`requirements.txt`、`package.json`、`Cargo.toml`、`foundry.toml` 等。项目没用到的工具不要写。

4. **包管理器和辅助 CLI 一般写 `latest`**（`pnpm`、`uv`、`sqlc` 这类），除非本机偏好另有指定——它们的版本对项目行为影响小，钉死反而增加维护负担。语言本体则应当带上 major.minor（`python = "3.12"`、`node = "24"`、`rust = "1.97"`）。

5. **注释说明该工具服务于哪个部分**，尤其是 monorepo / 多语言项目：

   ```toml
   [tools]
   rust   = "1.97"      # backend/core · Axum + sqlx
   python = "3.12"      # backend/quant · FastAPI
   node   = "24"        # frontend · React + Vite
   pnpm   = "latest"    # 前端包管理
   ```

   单语言小项目不需要凑注释，没有信息量的注释（`go = "latest"  # go`）不如不写。

## 写完之后：必须 trust

mise 对**新出现的配置文件**默认不信任，未 trust 时任何 `mise` 命令都会直接失败：

```
mise ERROR error parsing config file: .../mise.toml
mise ERROR Config files in .../mise.toml are not trusted.
```

注意这条报错的第一行会把问题指向"解析失败"，容易让人误以为是 TOML 语法写错了，实际原因是第二行的 trust。所以生成或修改文件后要执行：

```bash
mise trust
```

**每个 worktree 都要单独 trust 一次**（trust 记录按文件路径存储，新 worktree 是新路径）。这也是新 worktree 第一次跑 `mise` 报错的最常见原因。

## 验证

```bash
mise ls          # 确认各工具的 requested_version 与 mise.toml 一致
mise install     # 安装缺失版本（可能耗时较久，需要下载编译）
```

如果 `mise ls` 显示的 `requested_version` 和 `mise.toml` 写的对不上，通常是有更靠近的配置文件覆盖了它（`mise.local.toml`、父目录的 `mise.toml`）。用 `mise cfg` 列出当前生效的全部配置文件及其加载顺序来定位，不要靠猜。
