---
paths:
  - "web/wp-content/themes/**/blocks/**"
  - "web/wp-content/themes/**/templates/**"
  - "web/wp-content/themes/**/parts/**"
  - "web/wp-content/themes/**/patterns/**"
  - "web/wp-content/themes/**/assets/src/styles/**"
  - "**/*.scss"
---

# Design verification — a layout fix is confirmed by numbers, never by a screenshot

This rule exists because layout bugs on this project have shipped after being "verified" from a
screenshot alone. The browser tooling to measure them was available the whole time; the gap was
process, not tooling. What a layout system actually *is* — grid mechanics, container widths,
which blocks wrap their own container — is documented per-codebase: the theme's own mechanics are
in the theme's `.claude/rules/layout.md`; a plugin's own mechanics belong in that plugin's own
`CLAUDE.md`, not here. This file is only the **procedure** — it applies the same way regardless of
which codebase the markup you're checking lives in.

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

Report the measured value against the expected one — e.g. `272px (expected ~568)` — not "looks
right". A screenshot is supporting evidence attached to a number, never the verdict on its own: a
box at half its intended width looks entirely plausible in a screenshot.

## Measure at three viewports

1440 (desktop) / 768 (tablet) / 375 (mobile). A container capped below the full viewport width
(check the relevant codebase's own layout docs for its actual cap) means desktop numbers alone
tell you nothing about the other two.

## The checklist for a UI change on this project

- **Width squeeze** — is a `col-*` (or equivalent grid unit) inside an ancestor that already has a
  `max-width` in SCSS, or inside a second container? Measure the innermost box — don't trust the
  block names in the editor; check the actual codebase's layout docs for which classes constrain
  width there.
- **Self-containing blocks** — some blocks render their own container as part of their markup.
  Never wrap one of those in another container, in page content *or* inside the block's own
  PHP view — fixing only one of the two sites is a known way for this class of bug to resurface.
- **Missing container** — check whether the template actually wraps its content in a container;
  removing the wrong outer block can drop content flush against the viewport edge with no padding.
- **Duplicated title** — if the template already renders the post title as an `<h1>`, a second
  `<h1>` typed into the content stacks two titles.
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
