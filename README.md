# helzoph-claude-marketplace

A personal [Claude Code](https://docs.claude.com/en/docs/claude-code) and
[Codex](https://developers.openai.com/codex) plugin marketplace. The existing
marketplace name is kept for Claude Code compatibility.

## Install in Claude Code

```
/plugin marketplace add helzoph/claude
```

Then browse and install plugins with `/plugin install <plugin-name>@helzoph-claude-marketplace`,
or run `/plugin` to open the interactive marketplace UI.

## Install in Codex

Codex recognizes this repository's `.claude-plugin/marketplace.json` as a
legacy-compatible marketplace catalog. Each plugin also contains a
`.codex-plugin/plugin.json` manifest, so the same skills and hooks can be
installed through Codex.

```bash
# Use the GitHub repository as a marketplace source.
codex plugin marketplace add helzoph/claude

# Inspect available plugins, then install one.
codex plugin list
codex plugin add rationale-toolkit@helzoph-claude-marketplace
```

After installing or updating a plugin, start a new Codex task so it reloads the
plugin's skills and tools. Codex may require an explicit review and trust step
before it runs plugin-bundled hooks.

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
│   ├── rationale-toolkit/
│   │   ├── .claude-plugin/plugin.json  # Claude Code manifest
│   │   └── .codex-plugin/plugin.json   # Codex manifest
│   └── dev-env-router/
│       ├── .claude-plugin/plugin.json  # Claude Code manifest
│       ├── .codex-plugin/plugin.json   # Codex manifest
│       └── hooks/hooks.json             # Shared Claude Code/Codex hook
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

1. Create both `plugins/<plugin-name>/.claude-plugin/plugin.json` and
   `plugins/<plugin-name>/.codex-plugin/plugin.json`.
2. Keep shared components under the plugin root (`skills/`, `hooks/`,
   `agents/`, `.mcp.json`, ...).
3. Register the plugin in `.claude-plugin/marketplace.json` under `plugins`.

The two manifests are intentionally separate: Claude Code owns the existing
marketplace schema, while Codex requires a `.codex-plugin/plugin.json` package
manifest. Keeping one marketplace catalog avoids duplicating plugin entries and
the resulting synchronization drift.

## License

Apache-2.0 — see [LICENSE](LICENSE).
