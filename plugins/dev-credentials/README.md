# dev-credentials

A Claude Code plugin that gives an agent **one** credential it is explicitly
allowed to read — so it can actually run and test things, without ever
needing to touch the project's real secrets.

## The problem

An agent asked to "run this and check it works" against an LLM endpoint has
no working key. The usual outcomes are all bad: it reads the project's
`.env` (pulling real credentials into the conversation), it asks the user to
paste a key (which then lives in the transcript), or it stubs the call out
and reports success without having verified anything.

## The idea

Invert the trust boundary for exactly one file. The user provisions a
budget-capped, revocable key — e.g. a virtual key issued by a local LLM
gateway — and puts it somewhere the agent is told to read:

```
~/.local/share/dev-env/credentials.json
```

Because that key is capped and revocable, leaking it is a non-event: cancel
it and issue another. That property is what makes unrestricted agent access
to this one file reasonable, and it is the assumption the whole plugin rests
on. Put a production key in there and the reasoning collapses.

## What's included

### Skills

| Skill | Triggers on | What it does |
|---|---|---|
| [`use-dev-credentials`](skills/use-dev-credentials/SKILL.md) | Needing a working API key to run a script, write an integration test, or reproduce an API bug | Reads `base_url` / `api_key` from the credentials file and passes them straight into the command being run. Creates the file as a skeleton (never filling in values) when it doesn't exist yet. |

## Design notes

**Why `.json`, not a dotenv file.** A typical global `settings.json` denies
`Read(**/.env)` and `Read(**/.env.*)`. A file named `.env.agent` would be
caught by that rule — blocking the one file that is *supposed* to be
readable. The name deliberately avoids the `.env` prefix.

**Why outside the working tree.** Anything inside a repo is exposed to
`git add -A` and gets duplicated per worktree. One file per machine, shared
by every project, sidesteps both.

**Values are piped, not printed.** The skill inlines `jq` output into the
command's environment rather than `cat`-ing the file. Readable does not mean
worth pasting into a transcript that gets stored and summarised.

**The agent never writes a key.** It creates the skeleton with placeholders
and stops. Filling in the value is the user's step, every time.

## Installation

From within Claude Code:

```
/plugin marketplace add helzoph/claude
/plugin install dev-credentials@helzoph-claude-marketplace
```

## Relationship to the other plugins

Deliberately the mirror image of `mise-toolchain`'s `link-env`, which wires
up `.env` paths and is forbidden from reading their contents. This plugin
reads contents — and is correspondingly restricted to a single file that was
provisioned for the purpose.

A local LLM gateway (see `dev-env-router`'s USAGE.md) is the natural source
of the capped key this plugin expects, but is not required: any revocable,
budget-limited credential works.

## License

Apache-2.0
