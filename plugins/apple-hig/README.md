# apple-hig

A Claude Code plugin that applies Apple's current UI/UX design philosophy —
Human Interface Guidelines, iOS 26 "Liquid Glass" era: hierarchy, harmony,
concentric geometry, materials, semantic color, typography, and motion — to
**front-end web UI code** (HTML/CSS/JS and frameworks built on top of it).

## What's included

### Skills

| Skill | Triggers on | What it does |
|---|---|---|
| [`apple-design-style`](skills/apple-design-style/SKILL.md) | Building/restyling web layouts, tab bars, toolbars, navigation bars, sheets, popovers, buttons, cards, or any "iOS-style"/"Apple-style"/"glass"/"frosted" UI request | Encodes Apple's Hierarchy/Harmony/Consistency pillars into web layout rules (floating chrome, concentric corner geometry) in `SKILL.md`, with detailed reference files for the Liquid Glass CSS implementation and its explicit constraints (no glass-on-glass, no glass over flat backgrounds), semantic color/dark-mode rules, typography (tracking/leading scaling), motion guidance (springs vs. easing), and the accessibility checks that iOS 26's own launch got criticized for skipping (contrast, reduced transparency/motion). |

Skills activate automatically when Claude Code judges the task matches their
description — no manual invocation needed.

## Installation

From within Claude Code:

```
/plugin marketplace add helzoph/claude
/plugin install apple-hig@helzoph-claude-marketplace
```

## License

Apache-2.0
