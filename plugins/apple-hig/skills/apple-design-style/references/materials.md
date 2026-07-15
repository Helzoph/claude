# Materials: Liquid Glass

Liquid Glass is a **material that reflects and refracts the content behind it** ("lensing"), not a static blur filter. On the web this can only be approximated — there's no real-time scene refraction — but the visual grammar (blur + saturation lift + specular edge highlight) carries the same read.

**Two variants, used for different things:**
- **Regular** — adaptive, automatically flips between light/dark to stay legible over changing backgrounds. Default choice for toolbars, nav bars, tab bars, standard controls.
- **Clear** — permanently transparent, no adaptive tinting. Only for floating controls over rich media (photo/video viewers) where it's paired with a dimming scrim underneath for legibility — never use `.clear` as a general-purpose default.

```css
.liquid-glass {
  /* Rationale: saturate() 提亮折射内容的色彩，是 Liquid Glass 区别于
     普通 2020 年代 glassmorphism 单纯 blur 的关键视觉特征（"lensing"） */
  background: rgba(255, 255, 255, 0.55);
  backdrop-filter: blur(20px) saturate(180%);
  -webkit-backdrop-filter: blur(20px) saturate(180%);
  border-radius: var(--radius-outer);
  border: 1px solid rgba(255, 255, 255, 0.35);
  box-shadow:
    inset 0 1px 1px rgba(255, 255, 255, 0.6),  /* specular top-edge highlight */
    0 8px 24px rgba(0, 0, 0, 0.12);            /* floating drop shadow */
}

.liquid-glass--dark {
  background: rgba(30, 30, 30, 0.45);
  border-color: rgba(255, 255, 255, 0.12);
  box-shadow:
    inset 0 1px 1px rgba(255, 255, 255, 0.08),
    0 8px 24px rgba(0, 0, 0, 0.4);
}

@media (prefers-reduced-transparency: reduce) {
  .liquid-glass { backdrop-filter: none; background: rgba(255, 255, 255, 0.95); }
}
```

**Hard rules Apple states explicitly (violating these is what made iOS 26 launch criticism land):**
- **Never stack glass on glass.** Two overlapping translucent panels visually compound and lose legibility. Merge them into one container instead.
- **Never put glass over a flat single-color background.** Refraction needs varied content (a gradient, image, or video) to bend — over a solid color it just reads as a flat tinted rectangle, so either give it something to refract or drop the glass.
- **Glass is for the navigation/control layer, not the content layer.** Cards, list rows, and primary reading content should use solid/opaque surfaces; reserve glass for chrome that floats *above* content (nav, toolbars, floating action buttons, transient sheets).

**Floating tab bar pattern:**
```css
.tab-bar-floating {
  position: fixed;
  bottom: 16px;               /* margin, not flush to the viewport edge */
  left: 50%;
  transform: translateX(-50%);
  border-radius: 999px;       /* capsule */
  transition: transform 0.25s ease, opacity 0.25s ease;
}
.tab-bar-floating.is-minimized { transform: translateX(-50%) scale(0.85); }
```
