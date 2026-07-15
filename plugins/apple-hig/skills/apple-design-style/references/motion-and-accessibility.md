# Motion

- **Motion must be purposeful, not decorative.** Every animation should keep the user oriented or give feedback about an action's result — never add motion just because it's available.
- **Prefer spring-based motion for anything interruptible/gesture-driven** (drag, swipe, sheet drag-to-dismiss); a fixed-duration ease curve can't respond mid-interaction and produces a visible "jump" if interrupted. For simple state-announcement transitions (e.g., a tab switch, a fade-in), an ease curve is fine and often calmer.
- **Realism matters.** Motion that defies expectations (something that slides in from the right but can only be dismissed downward) disorients users — enter and exit should use symmetric, predictable paths.
- **Always respect `prefers-reduced-motion`.** Replace slides/springs/parallax with a short opacity cross-fade; never disable feedback entirely, just make it non-vestibular.

```css
@media (prefers-reduced-motion: reduce) {
  .sheet { transition: opacity 200ms ease; transform: none !important; }
}
```

# Accessibility Is Not Optional

iOS 26's own launch drew sustained criticism from accessibility auditors and UX researchers (NN/g and others) for exactly the failure modes below — treat these as required checks, not nice-to-haves:

- **Verify contrast, don't assume it.** Auditors measured live contrast ratios as low as 1.5:1 against Apple's own translucent chrome — far under the 4.5:1 WCAG minimum for normal text. Any text sitting on a glass/translucent surface must be checked against its *worst-case* background (brightest and darkest content likely to sit behind it), not just the design-mock background.
- **Never place primary readable text directly over unprocessed photo/video.** Pair it with a scrim/dimming layer, or move it off the media entirely.
- **Always implement all three accessibility media queries**, not just one:
  ```css
  @media (prefers-reduced-transparency: reduce) { /* raise opacity, drop blur */ }
  @media (prefers-contrast: more)               { /* solid background, defined border */ }
  @media (prefers-reduced-motion: reduce)       { /* cross-fade instead of slide/spring */ }
  ```
- **Chrome/glass elements still need real touch targets** — minimum ~44×44px hit areas regardless of how visually minimal the glass rendering looks.
