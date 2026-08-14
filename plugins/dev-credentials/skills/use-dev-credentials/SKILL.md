---
name: use-dev-credentials
description: "Reads a machine-level credentials file (~/.local/share/dev-env/credentials.json) that the user has deliberately provisioned for agent use, to obtain a base URL and API key for actually running or testing code against a real LLM (or other) endpoint. Use whenever a task needs a working API key — running a script that calls a model, writing/executing an integration test, reproducing an API bug, verifying an SDK change — instead of asking the user to paste a key or reading the project's own .env. Also use to create the file for the first time when it does not exist yet. Triggers on: needing an API key to test, 'run this against a real model', no credentials available for a test run. Do NOT use this skill to read a project's real .env or any other secret — this file is the only credential source it is allowed to touch."
---

# dev-credentials: agent 可用的测试凭证

## 这个 skill 是什么

一份**用户主动提供给 agent 使用**的凭证文件。它存在的前提是：里面的 key 已经被用户限定了预算和权限（例如通过 LLM 网关签发的 virtual key），所以 **agent 读取和使用它是被明确授权的**，不需要每次询问。

这和"保护项目 secret"是相反方向的事情，不要混淆：

| | 项目的 `.env` | 本 skill 的凭证文件 |
|---|---|---|
| agent 能否读取 | **不能** | **可以，这就是它的用途** |
| 泄露后果 | 需要立即 rotate 真实凭证 | 有预算上限，作废即可，不影响其他东西 |
| 谁写入 | 用户 | 用户（agent 只创建骨架，不填值） |

## 文件位置与格式

```
~/.local/share/dev-env/credentials.json
```

```json
{
  "llm": {
    "base_url": "http://llm.localhost/openai",
    "api_key": "<用户自己粘贴>",
    "default_model": "<用户在网关里实际配了哪家就填哪个>",
    "note": "网关签发的 dev virtual key，有预算上限"
  }
}
```

顶层按用途分组（`llm`、以后可能有别的），每组至少包含 `base_url` 和 `api_key`。

**`base_url` 末段是协议方言，取决于代码用哪个 SDK**，不是固定值：`/openai` 给 OpenAI SDK 及一切 OpenAI 兼容客户端，`/anthropic` 给 Anthropic SDK，`/genai` 给 Google GenAI SDK。填错的表现是请求体格式对不上而被拒。`/v1` 加不加都行（各家 SDK 拼路径的习惯不同，网关对这层宽容）。

**`default_model` 不要照抄任何示例值**——它必须是用户在网关 Web UI 里实际配置了 provider 的模型。查当前配了哪些：

```bash
curl -s http://llm.localhost/api/providers | jq -r '.providers[].name'
```

只配了一家时模型名直接写（如 `deepseek-v4-flash`）；配了多家而模型名有歧义时，写成 `provider/model` 显式指定。

**为什么放在 `~/.local/share/dev-env/` 顶层、而不是 `env/` 子目录里**：那个子目录整体被 `settings.json` 的一条 deny 规则挡住（见下），而本文件恰恰是**应该**被读的。两者只隔一层目录，位置搞错就会得到一个"文件明明在、却读不了"的困惑结果。

放在工作区外则是另一个原因：项目目录会被 `git add -A` 波及，也会随 worktree 复制。放在这里，一台机器一份，所有项目共用。

**文件名叫什么无所谓**——`Read(**/.env)` 这类规则是**相对模式**，只匹配工作目录内的路径，对 `~/.local/share/dev-env/` 下的文件不起作用。真正起作用的是绝对路径规则：

```
Read(//Users/<用户名>/.local/share/dev-env/env/**)   ← 挡住 baseline 目录
```

注意它只圈了 `env/**`，没圈整个 `dev-env/`。这是被迫的设计——实测确认 **deny 优先于 allow，无法用 allow 给 deny 开例外**。所以不能"deny 整个目录 + allow 放行 credentials.json"，只能让本文件从一开始就落在 deny 范围之外。

## 文件不存在时：创建骨架，不要填值

```bash
mkdir -p ~/.local/share/dev-env
chmod 700 ~/.local/share/dev-env
```

然后写入上面的 JSON 结构，`api_key` 留成占位符 `"<paste-your-dev-key-here>"`，`base_url` 如果能从上下文确定就填（例如本机跑着 LLM 网关就填 `http://llm.localhost/openai`），确定不了就留占位符。

写完后 `chmod 600` 该文件，并**明确告诉用户去哪里填、填什么**。不要试图代为生成或猜测 key 值。

## 读取方式

```bash
jq -r '.llm.base_url' ~/.local/share/dev-env/credentials.json
```

**关键：把值直接传给要执行的命令，不要 `cat` 整个文件、不要 `echo` key 本身。**

理由是这个文件虽然可读，但 key 的明文一旦进入会话上下文，就会留在对话记录里、也可能被后续的上下文压缩带到别处。而实际使用完全不需要看到它：

```bash
# 好：值只在进程环境里存在，不出现在输出中
OPENAI_BASE_URL=$(jq -r '.llm.base_url' ~/.local/share/dev-env/credentials.json) \
OPENAI_API_KEY=$(jq -r '.llm.api_key' ~/.local/share/dev-env/credentials.json) \
  python test_script.py

# 坏：key 明文进入上下文
cat ~/.local/share/dev-env/credentials.json
```

## `.localhost` 域名：curl 能解析，语言运行时不一定

实测确认的坑：`curl http://llm.localhost` 正常返回 200，但 Python 的 `socket.getaddrinfo('llm.localhost', 80)` 抛 `gaierror: nodename nor servname provided`。原因是 curl 内置了"`.localhost` 一律指向环回地址"的特殊处理（RFC 6761），而 `getaddrinfo` 依赖系统解析，macOS 的 `/etc/hosts` 里默认只有 `localhost` 一条，没有子域通配。

所以**用 curl 验证通过，不代表项目代码能跑通**。遇到这个报错时不要去查网关或 key，那两样都是好的。三种处理：

1. **让用户加一行 hosts**（一次性，对所有语言生效，需要 sudo，agent 不要代劳）：
   ```bash
   echo '127.0.0.1 llm.localhost' | sudo tee -a /etc/hosts
   ```
2. **改用 IP + Host 头**（已实测可走通 Traefik 路由）：请求发往 `http://127.0.0.1/`，带 `Host: llm.localhost`。适合一次性验证，但要改代码。
3. 若网关另有直连端口，绕开 Traefik 直接连。

诊断用这条，能一眼区分是解析问题还是网关问题：

```bash
python3 -c "import socket; print(socket.getaddrinfo('llm.localhost',80)[0][4])"
```

## 使用前的检查

1. **文件存在吗**：不存在就走上面的创建流程，然后停下来等用户填值——不要继续尝试其他获取凭证的途径（尤其不要转而去读项目的 `.env`）。
2. **值还是占位符吗**：不要只比对 `<paste-your-dev-key-here>` 这一个字面量——骨架里三个字段的占位符各不相同，且用户可能自己改过写法。判据是**值被尖括号包着**：

   ```bash
   jq -r '.llm | to_entries[] | select(.value | tostring | test("^<.*>$")) | .key' \
     ~/.local/share/dev-env/credentials.json
   ```

   有任何输出就说明那些字段还没填。此时直接告诉用户去填哪几个，不要拿占位符去发请求（会得到一个含义不明的 401 或 provider 解析失败，反而更难排查）。这条检查只看键名和"是否形如占位符"，不会把真实值打进上下文。

## 明确不做的事

- **不要把这个文件的路径或内容写进任何项目文件**。项目代码应该读 `OPENAI_BASE_URL` / `OPENAI_API_KEY` 这类标准环境变量，由调用方在运行时注入。这样项目本身不依赖这个文件的存在，别人 clone 下来也能跑。
- **不要把它当成项目 `.env` 的替代品**。它只服务于"agent 需要跑一下试试"的场景。项目自己运行时的配置归 `mise-toolchain/link-env` 管。
- **不要在这个文件里存需要 rotate 的真实凭证**。它的整个安全模型建立在"里面的 key 泄露了也不疼"之上——一旦放进生产 key，这个前提就没了，后续所有"可以放心读"的规则都不再成立。
- **发现文件里像是放了真实凭证时**（例如 `sk-ant-api03-` 开头的原厂 key 而非网关签发的 virtual key），**提醒用户换成受限 key**，并在换掉之前不要使用它。
