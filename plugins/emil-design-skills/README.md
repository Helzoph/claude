# Emil Design Skills

A marketplace plugin packaging the design and engineering skills from
[Emil Kowalski's skills repository](https://github.com/emilkowalski/skills).

## What's included

| Skill | Purpose |
|---|---|
| `emil-design-eng` | Design-engineering principles for polished interfaces and motion |
| `animate` | Build animations by choosing the right purpose, properties, curve, and duration |
| `review-animations` | Review motion code against a high craft bar |
| `improve-animations` | Audit a codebase's motion and produce prioritized implementation plans |
| `find-animation-opportunities` | Identify UI moments that genuinely benefit from motion |
| `animation-vocabulary` | Name motion patterns precisely so they can be implemented well |
| `apple-design` | Apply Apple's principles for fluid, physical interface design |
| `pick-ui-library` | Choose a suitable frontend library for common UI tasks |
| `prototype` | Build and compare genuinely different UI variants |
| `ask-sonner` | Work with and troubleshoot the Sonner toast library |

## Source and synchronization

The skills are synchronized from the upstream repository and retain its MIT
license:

<https://github.com/emilkowalski/skills>

`.github/workflows/sync-emil-design-skills.yml` checks the upstream `main` branch
daily and can also be started manually. When it detects a change, it opens or
updates a pull request instead of writing directly to the default branch. The
sync also records the upstream commit in the plugin version so installed plugin
caches can detect the update.

To run the same sync locally:

```bash
python3 .github/scripts/sync-emil-design-skills.py --source /path/to/skills
```

The three upstream skills that set `disable-model-invocation: true` are
normalized to `false` in this wrapper because the Codex plugin contract rejects
that value.

## Installation

From this marketplace:

```text
/plugin install emil-design-skills@helzoph-claude-marketplace
```
