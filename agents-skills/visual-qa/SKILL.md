---
name: visual-qa
description: >-
  Use after any frontend/UI change, and whenever a user reports visual problems
  (misaligned text, squished buttons, overlapping labels, broken spacing).
  Structured visual quality audit: computed-style probes to catch dead CSS
  utilities, screenshots at desktop and mobile widths reviewed with a
  vision-capable model, and a defect checklist covering spacing, alignment,
  overflow, truncation, and contrast. Functional 2xx checks alone do NOT
  satisfy this — a page can work perfectly and look broken.
---

# Visual QA

A page that returns 200 and renders data can still be visually broken. This
skill is the difference between "the flow works" and "the UI is right."

## Step 0 — Rule out dead CSS utilities first (2 minutes, catches whole-app breakage)

Before hunting individual defects, verify utility classes actually compute.
One bad global rule can nullify a whole category of styles app-wide:

```js
// browser evaluate on any page of the app:
() => {
  const probe = document.createElement("div")
  probe.className = "p-4 m-4"          // any spacing utilities the app uses
  document.body.appendChild(probe)
  const cs = getComputedStyle(probe)
  const result = { padding: cs.padding, margin: cs.margin }
  probe.remove()
  return result                          // expect NON-zero values
}
```

If utilities compute to `0px`, stop — you have a systemic root cause, not a
polish problem. Known causes, in likelihood order:

1. **Unlayered CSS overriding layered utilities.** In the CSS cascade,
   unlayered author styles beat `@layer` styles REGARDLESS of specificity.
   Tailwind v4 emits utilities inside `@layer utilities`, so a plain
   `* { margin: 0; padding: 0 }` reset written after `@import "tailwindcss"`
   silently kills every margin/padding utility in the app (real incident:
   Swipe 2026-07-07 — every page looked "misaligned" from one reset rule; fix
   was deleting the reset, since Tailwind's preflight already resets).
   Grep the CSS entrypoint for universal selectors and bare element resets
   outside `@layer`; move them into `@layer base` or delete them.
2. Missing/mis-set Tailwind content/source scanning (utility never generated —
   check the built CSS actually contains the class).
3. A CSS reset library imported after the framework styles.

Also probe one real element the design depends on (e.g. `main`,
a primary button): compare its `className` list against computed styles —
every class that names a property should be reflected.

## Step 1 — Screenshot matrix, reviewed with a VISION model

Take full-page screenshots at minimum two widths — desktop 1440 and mobile 390
— for every changed page (plus every page if the change was global CSS).
Review each screenshot with a vision-capable model (this harness:
`nan/mimo-v2.5` or `nan/gemma4` — NEVER a text-only model, it will fabricate).

Ask the vision model to check, per screenshot:

- **Spacing**: content flush against viewport or container edges; missing
  gaps between stacked elements; cramped controls (text touching borders).
- **Alignment**: labels vs values on the same row; icon vs text baselines in
  buttons; grid cards at unequal heights without a reason.
- **Overflow / truncation**: text escaping its container, clipped characters
  at container edges, horizontal scrollbars, labels colliding with values.
- **Buttons and inputs**: text vertically centered; padding present on all
  sides; disabled states distinguishable; consistent heights within a row.
- **Contrast**: light text over light imagery (headline overlays need a scrim
  or gradient behind them); disabled/placeholder text still legible;
  WCAG-ish judgment is enough — flag anything you squint at.
- **Empty/edge states**: does a filtered-empty state say something different
  from a truly-empty state; do loading skeletons match final layout.

## Step 2 — Stress with real-shaped data

Default seeds hide defects. Exercise the layout with:

- The LONGEST realistic content in every text slot (sentence-length tags,
  multi-line headlines, long URLs, 200-char names) — watch for collisions
  between labels and values on flex rows.
- Zero items, one item, and a full page of items.
- A viewport at the layout's breakpoints (sm/md/lg edges), not just the two
  standard widths.

## Step 3 — Report and fix root-cause-first

Order findings: systemic (dead utilities, broken container) → per-component
(collisions, overflow) → polish (contrast, truncation ellipses). Fix the
systemic layer first, re-screenshot, THEN judge the residual list — most
per-component "bugs" vanish when the systemic cause is fixed.

Do not claim visual QA passed without: the Step 0 probe returning non-zero,
and a vision-model review of at least desktop + mobile screenshots of every
changed page.
