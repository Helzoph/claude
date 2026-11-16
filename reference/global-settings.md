# global-settings.json 说明

`global-settings.json` 是 `~/.claude/settings.json` 的公开参考版。JSON 不能写注释，所以每处取舍的原因记在这里。

## 和本机 settings.json 的差别

- 去掉了 `env`：里面是本机代理地址和调试开关，跟机器绑定，不适合公开。
- 去掉了 `hooks`：全是 Orca 自动装的 hook，路径写死在本机用户目录下，装 Orca 时会自动加回来。
- `helzoph-claude-marketplace` 改成 GitHub 来源（`helzoph/claude`）；本机用的是指向本地仓库目录的 `directory` 来源，路径不能公开。

## 1. 挡住 `~/.local/share/dev-env/env/`

deny 里的 `Read(~/.local/share/dev-env/env/**)` 和 `Edit(~/.local/share/dev-env/env/**)`。

- `Edit(...)` 同时覆盖 Edit 和 Write 工具。
- 2026-11-16 实测：`Read(...)` deny 会被同步成沙箱的读禁止，所以沙箱里的 `cat`/`ugrep` 也读不到；但 `**/.env` 这种相对模式只在工作目录内生效，工作目录外的文件必须写 `~/` 或 `//` 开头的路径。
- 未验证：`~/` 写法是否同样被同步进沙箱。应用后用诱饵文件测一次：在 `env/` 外层不行，就换成 `Read(//Users/<你的用户名>/.local/share/dev-env/env/**)`。
- 例外：命令带 `dangerouslyDisableSandbox` 跑在沙箱外时不受沙箱限制，只剩 Read/Edit 工具的拦截和 `global-claude.md` 里那一行文字。
- `credentials.json` 在 `env/` 外层，不受影响（deny 压过 allow，所以它不能放进 `env/`）。

## 2. `git push`：从 `deny` 改成 `ask`（2026-11-16 决定）

- ask 里的 `Bash(git push *)` 和 `Bash(git push)`：每次 push 都弹确认框，对应 `global-claude.md` `<outward-actions>` 里"每次 push 都要批准"。两条都要写，裸 `git push` 不带参数，第一条匹配不到。
- `ask` 压过 `allow`，所以 `allow` 里的 `Bash(git *)` 不会让 push 绕过确认。
- 强制推送（`--force`、`-f`、`--force-with-lease`）留在 deny：deny 压过 ask，这几种直接拒绝，不弹窗。
- 未验证：auto mode 下 `ask` 规则是否一定弹窗，还是交给分类器判断。改完后让 Claude 试推一次确认。
