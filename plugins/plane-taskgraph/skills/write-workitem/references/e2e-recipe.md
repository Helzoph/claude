# Writing an e2e V That the Agent Runs

Read this when writing the `运行` / `预期` of an e2e V. The rules in SKILL.md ("At least one e2e", "e2e Is Run by the Agent") still apply; this file is the how.

Each e2e states its entry command, its input, how the result is read back, and the expected value. Pick the entry by what changed.

## A Skill or Plugin

Run Claude Code headless against the plugin directory in the repo, then assert on the transcript with jq:

```bash
P="$(git rev-parse --show-toplevel)/plugins/<plugin>"
claude -p "<prompt>" --plugin-dir "$P" \
  --output-format stream-json --verbose --max-budget-usd 3 \
  --allowedTools <tools this run needs> > /tmp/<item>-<V>-<round>.jsonl
```

To play the user's reply, run the same command with `--resume <session_id>` from the previous round. Every round passes four generic assertions (F is that round's jsonl):

- The repo copy of the plugin was loaded: `jq -r 'select(.subtype=="init") | .plugins[] | select(.name=="<plugin>") | .source + " " + .version' F` prints `<plugin>@inline` and the version in plugin.json. Reason: with a marketplace install present, a stale cached copy can be tested instead.
- Which skills fired: `jq -r 'select(.type=="assistant").message.content[] | select(.type=="tool_use" and .name=="Skill") | .input.skill' F`.
- Which tools ran: `jq -c 'select(.type=="assistant").message.content[] | select(.type=="tool_use") | [.name, (.input.skill // .input.action)]' F`.
- How it ended: `jq -c 'select(.type=="result") | [.is_error, (.permission_denials | length), .session_id]' F` — the first two must be `false` and `0`. Reason: a denied tool makes the agent stop or skip steps in a way that looks identical to correct behaviour.

macOS has no `timeout`; bound a run with `--max-budget-usd`, not by wrapping it.

## Other Entry Points

- **A web page**: browser automation — a Playwright spec, or agent-browser.
- **An HTTP endpoint**: `curl`, asserting on status and body.
- **A command-line tool**: run it directly.

## "The Agent Stopped" Is Judged by State, Not Words

When a V expects the agent to pause (wait for confirmation, ask a question), check that **nothing was written**: `git rev-parse HEAD` and `git status --porcelain` unchanged, and the Plane item's `updated_at` and comment count unchanged. The reply text is supporting evidence only — "let me pause here" says nothing about what was already written before it.
