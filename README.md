# helzoph-claude-marketplace

A personal [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin
marketplace.

## Installation

```
/plugin marketplace add helzoph/claude
```

Then browse and install plugins with `/plugin install <plugin-name>@helzoph-claude-marketplace`,
or run `/plugin` to open the interactive marketplace UI.

## Plugins

| Plugin | Description |
|---|---|
| [`rationale-toolkit`](plugins/rationale-toolkit) | Rationale-first coding style and outcome-verification discipline — explain the why before the what, and prove changes work before calling them done. |
| [`dev-env-router`](plugins/dev-env-router) | Directory-derived identity for local dev environments via Docker Compose + a single shared Traefik router — no manual port bookkeeping across projects and worktrees. |

## Repository layout

```
.
├── .claude-plugin/
│   └── marketplace.json     # Marketplace manifest (this repo's plugin index)
├── plugins/
│   ├── rationale-toolkit/   # Rationale-first style + outcome verification (skills + hooks)
│   └── dev-env-router/      # Directory-derived Docker Compose + Traefik dev routing (skills)
├── reference/
│   └── global-claude.md    # Personal global CLAUDE.md reference (not a plugin component)
├── CLAUDE.md                  # Notes on maintaining reference/global-claude.md
└── setting.json               # Personal machine settings.json reference (not a plugin component)
```

`reference/global-claude.md` and `setting.json` are kept here only as personal
reference / backup documents for this author's own `~/.claude/CLAUDE.md` and
`~/.claude/settings.json`. They are **not** part of the marketplace or the
plugin — Claude Code plugins have no mechanism for auto-injecting global
instructions or machine-level settings (env vars, permissions, statusline).
The parts of that config that *are* plugin-portable (the rationale-first
working style, the outcome-verification protocol, and the
`node_modules/.bin` guard hook) were extracted into `plugins/rationale-toolkit`.

## Adding a new plugin

1. Create `plugins/<plugin-name>/.claude-plugin/plugin.json`.
2. Add its components (`skills/`, `agents/`, `hooks/`, `.mcp.json`, ...).
3. Register it in `.claude-plugin/marketplace.json` under `plugins`.

## License

Apache-2.0 — see [LICENSE](LICENSE).
