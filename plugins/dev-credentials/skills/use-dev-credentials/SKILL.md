---
name: use-dev-credentials
description: "Reads a machine-level credentials file (~/.local/share/dev-env/credentials.json) that the user has deliberately provisioned for agent use, to obtain a base URL and API key for actually running or testing code against a real LLM (or other) endpoint. Use whenever a task needs a working API key — running a script that calls a model, writing/executing an integration test, reproducing an API bug, verifying an SDK change — instead of asking the user to paste a key or reading the project's own .env. Also use to create the file for the first time when it does not exist yet. Triggers on: needing an API key to test, 'run this against a real model', no credentials available for a test run. Do NOT use this skill to read a project's real .env or any other secret — this file is the only credential source it is allowed to touch."
---

# dev-credentials: Test Credentials the Agent May Use

## What This Skill Is

A credentials file that **the user deliberately provides for the agent to use**. It exists on the premise that the keys in it have already been limited in budget and permissions by the user (e.g. a virtual key issued through an LLM gateway), so **the agent is explicitly authorized to read and use it**, without asking each time.

This points in the opposite direction from "protecting project secrets"; do not confuse the two:

| | The project's `.env` | This skill's credentials file |
|---|---|---|
| Can the agent read it | **No** | **Yes — that is its purpose** |
| Consequence of a leak | The real credentials must be rotated immediately | It has a budget cap; just revoke it, nothing else is affected |
| Who writes it | The user | The user (the agent only creates the skeleton, never fills in values) |

## File Location and Format

```
~/.local/share/dev-env/credentials.json
```

```json
{
  "llm": {
    "base_url": "http://llm.localhost/openai",
    "api_key": "<pasted by the user>",
    "default_model": "<whichever model the user actually configured in the gateway>",
    "note": "dev virtual key issued by the gateway, with a budget cap"
  }
}
```

Top-level keys group entries by purpose (`llm`, possibly others later); each group contains at least `base_url` and `api_key`.

**The last segment of `base_url` is the protocol dialect, determined by which SDK the code uses**; it is not a fixed value: `/openai` for the OpenAI SDK and every OpenAI-compatible client, `/anthropic` for the Anthropic SDK, `/genai` for the Google GenAI SDK. Getting it wrong shows up as the request being rejected because the body format doesn't match. `/v1` works with or without (SDKs differ in how they join paths, and the gateway is lenient at this layer).

**Do not copy `default_model` from any example value** — it must be a model for which the user actually configured a provider in the gateway Web UI. To see what is currently configured:

```bash
curl -s http://llm.localhost/api/providers | jq -r '.providers[].name'
```

If only one provider is configured, write the model name directly (e.g. `deepseek-v4-flash`); if several are configured and the model name is ambiguous, write it as `provider/model` to be explicit.

**Why it lives at the top level of `~/.local/share/dev-env/`, not in the `env/` subdirectory**: that subdirectory is blocked as a whole by a deny rule in `settings.json` (see below), whereas this file is precisely the one that **should** be read. The two are only one directory level apart; put the file in the wrong place and you get the confusing result of "the file is clearly there, but it can't be read".

Keeping it outside the workspace is for a different reason: project directories get swept up by `git add -A`, and get copied along with worktrees. Here, there is one copy per machine, shared by all projects.

**The filename doesn't matter** — rules like `Read(**/.env)` are **relative patterns** that only match paths inside the working directory, and have no effect on files under `~/.local/share/dev-env/`. What actually takes effect is the absolute-path rule:

```
Read(//Users/<username>/.local/share/dev-env/env/**)   ← blocks the baseline directory
```

Note that it covers only `env/**`, not all of `dev-env/`. This design is forced — testing confirmed that **deny takes precedence over allow, and allow cannot carve an exception out of deny**. So "deny the whole directory + allow credentials.json" is impossible; the only option is for this file to sit outside the deny scope from the start.

## When the File Doesn't Exist: Create the Skeleton, Don't Fill In Values

```bash
mkdir -p ~/.local/share/dev-env
chmod 700 ~/.local/share/dev-env
```

Then write the JSON structure above, with `api_key` left as the placeholder `"<paste-your-dev-key-here>"`. Fill in `base_url` if it can be determined from context (e.g. if an LLM gateway is running on this machine, use `http://llm.localhost/openai`); otherwise leave a placeholder.

After writing, `chmod 600` the file, and **tell the user explicitly where to fill in what**. Do not try to generate or guess key values on their behalf.

## How to Read It

```bash
jq -r '.llm.base_url' ~/.local/share/dev-env/credentials.json
```

**Key point: pass values straight into the command being run; do not `cat` the whole file, and do not `echo` the key itself.**

The reason: although this file is readable, once the plaintext key enters the session context it stays in the conversation transcript, and may be carried elsewhere by later context compaction. And actual use never requires seeing it:

```bash
# Good: the values exist only in the process environment and never appear in output
OPENAI_BASE_URL=$(jq -r '.llm.base_url' ~/.local/share/dev-env/credentials.json) \
OPENAI_API_KEY=$(jq -r '.llm.api_key' ~/.local/share/dev-env/credentials.json) \
  python test_script.py

# Bad: the plaintext key enters the context
cat ~/.local/share/dev-env/credentials.json
```

## `.localhost` Domains: curl Resolves Them, Language Runtimes May Not

A pitfall confirmed by testing: `curl http://llm.localhost` returns 200 normally, but Python's `socket.getaddrinfo('llm.localhost', 80)` raises `gaierror: nodename nor servname provided`. The cause is that curl has built-in special handling that "always points `.localhost` at the loopback address" (RFC 6761), whereas `getaddrinfo` relies on system resolution, and macOS's `/etc/hosts` by default has only a single `localhost` entry, with no subdomain wildcard.

So **passing a curl check does not mean the project code will work**. When you hit this error, do not go investigating the gateway or the key; both are fine. Three ways to handle it:

1. **Have the user add a hosts line** (one-time, works for all languages, requires sudo; the agent must not do it on their behalf):
   ```bash
   echo '127.0.0.1 llm.localhost' | sudo tee -a /etc/hosts
   ```
2. **Use the IP + a Host header instead** (confirmed by testing to route through Traefik): send the request to `http://127.0.0.1/` with `Host: llm.localhost`. Suitable for one-off checks, but requires changing code.
3. If the gateway has a separate direct port, bypass Traefik and connect directly.

Use this for diagnosis; it tells at a glance whether it is a resolution problem or a gateway problem:

```bash
python3 -c "import socket; print(socket.getaddrinfo('llm.localhost',80)[0][4])"
```

## Pre-Use Checks

1. **Does the file exist**: if not, follow the creation flow above, then stop and wait for the user to fill in values — do not go on trying other ways to obtain credentials (in particular, do not fall back to reading the project's `.env`).
2. **Are the values still placeholders**: do not compare only against the single literal `<paste-your-dev-key-here>` — the three fields in the skeleton each have different placeholders, and the user may have rewritten them in their own style. The criterion is **the value is wrapped in angle brackets**:

   ```bash
   jq -r '.llm | to_entries[] | select(.value | tostring | test("^<.*>$")) | .key' \
     ~/.local/share/dev-env/credentials.json
   ```

   Any output means those fields have not been filled in yet. In that case, tell the user directly which ones to fill in; do not send requests with placeholders (you would get an ambiguous 401 or a provider resolution failure, which is harder to debug). This check looks only at key names and "whether it looks like a placeholder", so it never prints real values into the context.

## Explicit Don'ts

- **Do not write this file's path or contents into any project file**. Project code should read standard environment variables like `OPENAI_BASE_URL` / `OPENAI_API_KEY`, injected by the caller at runtime. That way the project itself does not depend on this file existing, and anyone else who clones it can still run it.
- **Do not treat it as a substitute for the project's `.env`**. It serves only the "the agent needs to try running this" scenario. The project's own runtime configuration belongs to `mise-toolchain/link-env`.
- **Do not store real credentials that would need rotating in this file**. Its entire security model rests on "a leaked key here doesn't hurt" — once a production key goes in, that premise is gone, and none of the "safe to read" rules that follow hold anymore.
- **If the file appears to contain real credentials** (e.g. a first-party key starting with `sk-ant-api03-` rather than a gateway-issued virtual key), **remind the user to replace it with a restricted key**, and do not use it until it has been replaced.
