---
paths:
  - "web/wp-content/themes/**/blocks/**"
  - "web/wp-content/themes/**/templates/**"
  - "web/wp-content/themes/**/parts/**"
  - "web/wp-content/themes/**/patterns/**"
  - "web/wp-content/themes/**/assets/src/styles/**"
  - "web/wp-content/plugins/starter-kit-addon/blocks/**"
  - "web/wp-content/plugins/starter-kit-addon/assets/**"
  - "**/*.scss"
---

# Design verification — a layout fix is confirmed by numbers, never by a screenshot

This rule exists because a run of checkout-funnel layout bugs on this project were each "verified"
from a screenshot and each shipped broken. The browser tooling to measure them was available the
whole time; the gap was process, not tooling. What the layout system actually *is* — Bootstrap
5.3.2, the 1280px container cap, the grid blocks, `wp:post-content` having no container, the
self-containing addon blocks — is documented in the theme's
`.claude/rules/layout.md` and the addon's `CLAUDE.md`. This file is the **procedure**.

## The rule

Any change to markup, layout, or styling is unverified until you have read real numbers off the
rendered page. Load it in Playwright and measure:

```js
// what it actually rendered at
document.querySelector('<selector>').getBoundingClientRect()
// the constraint that produced that
getComputedStyle(document.querySelector('<ancestor>')).maxWidth
// anything hanging off the edge
[...document.querySelectorAll('main *')]
  .filter(el => el.getBoundingClientRect().left <= 0)
```

Report the measured value against the expected one — `272px (expected ~568)` — not "looks right".
A screenshot is supporting evidence attached to a number, never the verdict on its own: a box at
half its intended width looks entirely plausible in a screenshot. That is exactly how the 272px
checkout card passed review.

## Measure at three viewports

1440 (desktop) / 768 (tablet) / 375 (mobile). Measure at each — `.container` is capped at 1280px
from `xl` up (see `layout.md`), so desktop numbers tell you nothing about the other two.

## The checklist for a UI change on this project

- **Width squeeze** — is a `col-*` inside an ancestor that already has a `max-width` in SCSS, or
  inside a second container? Measure the innermost box. Live constraining classes here:
  `.checkout-block` (600px), `.pricing_section` (1440px).
- **Self-containing blocks** — `starter-kit/checkout`, `starter-kit/pricing-table`,
  `starter-kit/purchase-result` each render their own `.container`. Never wrap them in another
  one, in page content *or* inside a block's own PHP view. Fixing one of the two sites and not the
  other is how the checkout bug survived its first fix.
- **Missing container** — no template gives `wp:post-content` a container or padding. Removing a
  page's outermost `starter-kit/container` drops its content flush against the viewport edge.
- **Duplicated title** — `page.html` / `page-with-hero.html` render the post title as `<h1>`. A
  second `<h1>` in the content stacks two titles; use `page-without-title.html` instead.
- **Duplicated numbering** — a list numbered by CSS (`counter-increment` + `::before`) whose item
  text also arrives pre-numbered from an API or a field renders `1. 1. …`. Assert the rendered
  text, not just that the list exists.
- **Console clean** — no JS errors, no failed requests, on load and after the main interaction.

## Who verifies

Not the agent that wrote the CSS. Whoever made the change can measure to confirm they changed what
they intended, but the visual verdict comes from an independent read-only pass on the live page
(the `acceptance-tester` agent's design-review mode). Self-assessment of one's own rendered output
is the failure mode this whole rule is working around.

## Before theorising about caches and CDNs, check the simple thing

See `debug.md` — `starter-kit.loc` resolves only through `/etc/hosts`, there is no edge cache in
front of this site, and a stale-looking page is a build or browser-cache problem, not a CDN one.
