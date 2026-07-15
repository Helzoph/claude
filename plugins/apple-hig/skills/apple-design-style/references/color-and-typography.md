# Color: Semantic Roles, Not Hex Values

Apple's system colors are defined **by purpose, not by appearance** — a "label" color, not "#1C1C1E". Hard-coding literal color values breaks automatically when context (theme, elevation, accessibility contrast mode) changes.

```css
:root {
  --color-label-primary: rgba(0, 0, 0, 0.92);
  --color-label-secondary: rgba(0, 0, 0, 0.6);
  --color-background-primary: #ffffff;
  --color-background-elevated: #ffffff; /* raised surfaces are brighter, not just stacked */
}
@media (prefers-color-scheme: dark) {
  :root {
    --color-label-primary: rgba(255, 255, 255, 0.92);
    --color-label-secondary: rgba(255, 255, 255, 0.6);
    --color-background-primary: #000000;
    --color-background-elevated: #1c1c1e; /* dark mode: elevated = brighter, not lighter tint of base */
  }
}
```

- **Dark mode is not a literal inversion.** Background colors get dimmer as they recede (base) and brighter as they elevate (elevated surfaces), while foreground/label colors get brighter — but not every color simply flips.
- **Vibrancy: text/icons on top of glass need boosted contrast, not flat gray.** A flat mid-gray label that looks fine on a solid background often fails against a translucent, content-shifting one. Pull the foreground color's contrast up relative to the material behind it, or place text on a small solid-fill chip inside the glass rather than directly on the raw translucent surface.
- **Use color sparingly.** Reserve it for calling attention to one important action or state — pattern-match to Apple's own restraint rather than tinting every surface.

# Typography

- **Hierarchy is built from weight + size + line-height together, not size alone.** A heading and a body style differ in all three, not just font-size.
- **Tracking (letter-spacing) is size-specific.** Large display text wants slightly *negative* tracking (glyphs read too loose at scale); body text stays near `0` or slightly positive for legibility at small sizes. One fixed `letter-spacing` for every heading level is wrong somewhere.
- **Leading (line-height) scales inversely with size.** Tight leading on large headings, looser leading on body copy for comfortable multi-line reading.
- **Respect the user's font-size preference.** Equivalent of Dynamic Type on the web: size spacing/layout in `rem`/`em`, not fixed `px`, so the layout doesn't break when a user increases their base font size.
- **Default to the system font stack** (`-apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif`) before reaching for a custom face — it already carries platform-tuned optical sizing and legibility.

```css
:root { font: 100%/1.5 -apple-system, BlinkMacSystemFont, system-ui, sans-serif; }
.display {
  font-size: clamp(2rem, 5vw, 4rem);
  line-height: 1.05;         /* tight leading at large size */
  letter-spacing: -0.02em;   /* negative tracking as text grows */
}
```
