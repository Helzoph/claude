---
name: apple-design-style
description: "Applies Apple's current UI/UX design philosophy (Human Interface Guidelines, 'Liquid Glass' era: iOS 26 / iPadOS 26 / macOS Tahoe) to front-end web UI code (HTML/CSS/JS/React/Vue/etc.) — hierarchy, harmony, concentric geometry, materials, semantic color, and purposeful motion. Use when building or restyling web navbars, tab bars, toolbars, sheets, popovers, buttons, cards, or any UI described as 'iOS-style' / 'Apple-style' / 'glass' / 'frosted'. This is a web/CSS skill only — not for native Swift/SwiftUI/UIKit development. Triggers on: any front-end layout or styling task where the goal is to follow Apple's design language."
---

# Apple UI/UX Design Philosophy for Web Front-End (Liquid Glass Era)

## Core Principle

Since iOS 26, Apple's Human Interface Guidelines (HIG) organize the entire design system around three pillars:

- **Hierarchy** — "Establish a clear visual hierarchy where controls and interface elements elevate and distinguish the content beneath them." Content is primary; chrome (nav bars, toolbars, tab bars) is a secondary floating layer that must never compete with or bury it.
- **Harmony** — Interface geometry aligns with device/container geometry ("concentric design of the hardware and software"). Shapes nest instead of clashing.
- **Consistency** — "Adopt platform conventions to maintain a consistent design that continuously adapts across window sizes and displays." Don't reinvent standard patterns (nav placement, back affordances, standard control shapes).

These three pillars supersede (but don't contradict) Apple's older triad of **Clarity, Deference, Depth** — this skill translates both generations of guidance into concrete web rules. Everything in the reference files below — materials, color, typography, motion — exists to serve Hierarchy/Harmony/Consistency, not as decoration for its own sake.

## 1. Layout: Hierarchy + Harmony

- **Floating chrome, not docked chrome.** Tab bars, toolbars, and navigation bars are separate floating layers above the content, with margin around them — not full-width bars flush to the screen edge with a hard divider line. Content scrolls *under* chrome; chrome doesn't push content or reflow layout.
- **Concentric corner geometry.** Any element nested inside a container derives its radius from the container's — never the reverse, never an arbitrary constant copied across components:
  ```css
  .outer { --radius-outer: 24px; border-radius: var(--radius-outer); }
  .inner {
    /* Rationale: 子元素圆角必须由父容器圆角推导，才能在容器尺寸变化时保持"同心"视觉，
       这是 Apple HIG 明确定义的规则，而非美观上的巧合 */
    --radius-inner: calc(var(--radius-outer) - var(--gap));
    border-radius: var(--radius-inner);
  }
  ```
  Watch for corners that feel "pinched" (child radius too small) or "flared" (child radius too large relative to the parent) — both break the sense of nested balance.
- **Capsule as the default interactive shape.** Full-height-radius capsules (`border-radius: 999px` / `50%` of height) are Apple's default for buttons, pills, segmented controls, and floating bars — they support concentricity naturally, since a capsule scales cleanly at any size. Reserve fixed rounded rectangles for dense, information-heavy layouts (inspectors, data tables) where a capsule would waste space.
- **Shrink-on-scroll for bottom chrome.** Tab bars/toolbars minimize into a compact floating pill on scroll-down and expand on scroll-up or at rest — they should never fully vanish (the user must always have a way back).
- **One glass surface per visual group.** Don't place multiple independent floating panels edge-to-edge; merge adjacent controls into a single container so they read as one material. Overlapping independent translucent layers compound their blur and become muddy and illegible.

## 2. Reference Files — Read Before Implementing

This skill's remaining guidance lives in `references/` and must be read in full before writing the relevant code — do not guess at CSS values or accessibility rules from memory:

- **`references/materials.md`** — Liquid Glass material: regular vs. clear variants, the CSS approximation (`backdrop-filter` + saturate + specular highlight), and Apple's explicit hard rules (no glass-on-glass, no glass over flat backgrounds, glass is nav-layer-only). Read before styling any translucent/floating surface.
- **`references/color-and-typography.md`** — Semantic color roles (not hex values), dark-mode elevation rules, vibrancy/contrast on translucent surfaces, and typography scaling (tracking/leading by size, Dynamic-Type-equivalent `rem` sizing). Read before choosing any color value or type scale.
- **`references/motion-and-accessibility.md`** — Spring vs. easing motion guidance, and the three required accessibility media queries (`prefers-reduced-transparency`, `prefers-contrast`, `prefers-reduced-motion`) — the exact checks iOS 26's own launch was criticized for skipping (contrast ratios measured as low as 1.5:1 against the 4.5:1 WCAG minimum). Read before adding any animation or before considering a UI "done."

## 3. Common Mistakes to Flag

- Flat `blur()`-only backgrounds with no saturation boost — reads as generic 2020s glassmorphism, not Apple's current material.
- A nested element's corner radius hard-coded instead of derived from its parent's.
- Chrome docked flush to the viewport edge with a 1px divider line — this is the pre-2025 look, not the current one.
- Multiple adjacent glass panels rendered as separate overlapping layers instead of one merged surface.
- Text color that looks fine in the static mock but hasn't been checked against a busy/bright background behind the glass.
- Any of the three accessibility media queries missing (transparency, contrast, motion).
- Hard-coded hex colors instead of semantic custom properties that adapt to light/dark and elevation.
