# Writing an e2e V That the Agent Runs

Read this when writing the `运行` / `预期` of an e2e V. The rules in SKILL.md ("At least one e2e", "e2e Is Run by the Agent") still apply; this file is the how.

Each e2e states its entry command, its input, how the result is read back, and the expected value. Pick the entry by what changed.

## A Skill or Plugin

Use the bundled runner. From the fixture directory the run should happen in (a temp `git init` repo, or the repo under test):

```bash
<plugin dir>/scripts/e2e.sh "$TMPDIR/<item>-<V>.jsonl" "<prompt>"
```

It starts `claude -p` headless with `--plugin-dir` pointing at the repository copy of the plugin, stream-json output, `--max-budget-usd 3` and `--max-turns 30` (macOS has no `timeout`; these bound the run), and a default `--allowedTools` list (Skill, Read, Bash, Edit, Write, and the claude.ai Plane connector tools). Extra arguments after the prompt are passed to `claude`. `--dry-run` prints the command and environment without running it; `--check <jsonl>` re-runs only the assertions on an existing transcript.

It then prints four generic assertions and exits non-zero if any fails. In the V, `预期` names the run's exit status plus whatever is specific to this V (which skill line, which reply text, which read-back value):

- **plugin** (fails the run): the `init` event loaded `<plugin>@inline` at the version in plugin.json. Reason: with a marketplace install present, a stale cached copy can be tested instead.
- **skills** (reported): every `Skill` tool call's `.input.skill`.
- **tools** (reported): every tool call as `[name, skill-or-action]`.
- **ending** (fails the run): the `result` event has `is_error` false and `permission_denials` empty; a missing `result` event also fails. Reason: a denied tool makes the agent stop or skip steps in a way that looks identical to correct behaviour. Exception: when the V tests a hook's deny, set `E2E_EXPECT_DENIALS` to the denials the run must produce — comma-separated, each `tool` (any denial of that tool) or `tool:action` (e.g. `mcp__claude_ai_plane__workitem:update`). The match is two-way: a denial no entry matches fails as `unexpected`, and an entry no denial matches fails as `missing` (the hook did not fire). `--check` reads the same variable. A PreToolUse hook's `deny` is recorded in `permission_denials` like any other denial (verified 2026-11-15). The usual fixture passes the hook through `--settings`; when it does, put `enabledPlugins` in that same JSON instead of setting `E2E_DISABLE_PLUGINS`, which adds a second `--settings`.

Three traps the runner handles or exposes through environment variables:

- **The skill under test never fires.** With many plugins installed, Claude Code cuts the skill list to names only, so a skill's description is invisible and the agent may never load it. The runner sets `SLASH_COMMAND_TOOL_CHAR_BUDGET=60000` by default. Set `E2E_SKILL_BUDGET=default` to leave it unset — for a V that tests triggering under the real, cut-down list — or to a number to use that.
- **Another plugin's hook breaks the child session** (e.g. a Stop hook that loops in the sandbox). Pass its id in `E2E_DISABLE_PLUGINS=<plugin>@<marketplace>[,...]`; the runner disables it with `--settings`. Which plugins misbehave depends on the machine, so nothing is disabled by default.
- **A multi-turn exchange cannot be resumed.** In a sandboxed parent, the child session cannot write its transcript under `~/.claude/projects`, so `--resume <session_id>` finds nothing. Fold the exchange into one prompt instead: state the user's later reply up front ("When you ask for confirmation, treat the answer as 「确认」") and assert on the final state.

The runner refuses to start (exit 2) when no sandbox is detected — `SANDBOX_RUNTIME` is not `1`, i.e. it is not running inside a Claude Code sandboxed Bash. Reason: the default tool list gives the child unrestricted Bash while it reads untrusted Plane content. Run it from the sandboxed Bash; set `E2E_UNSANDBOXED_OK=1` only when the user accepts running unsandboxed. `--dry-run` prints `sandbox: yes|no` without refusing.

Override the tool list with `E2E_ALLOWED_TOOLS` and the bounds with `E2E_MAX_BUDGET_USD` / `E2E_MAX_TURNS`. When the parent session runs Bash in a network sandbox, the run needs `api.anthropic.com` (and `mcp-proxy.anthropic.com` for the claude.ai connectors) allowed.

## Other Entry Points

- **A web page**: browser automation — a Playwright spec, or agent-browser.
- **An HTTP endpoint**: `curl`, asserting on status and body.
- **A command-line tool**: run it directly.

## "The Agent Stopped" Is Judged by State, Not Words

When a V expects the agent to pause (wait for confirmation, ask a question), check that **nothing was written**: `git rev-parse HEAD` and `git status --porcelain` unchanged, and the Plane item's `updated_at` and comment count unchanged. The reply text is supporting evidence only — "let me pause here" says nothing about what was already written before it.
