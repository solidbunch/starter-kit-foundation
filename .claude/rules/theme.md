---
paths:
  - "web/wp-content/themes/starter-kit-theme/templates/**"
  - "web/wp-content/themes/starter-kit-theme/parts/**"
  - "web/wp-content/themes/starter-kit-theme/patterns/**"
  - "web/wp-content/themes/starter-kit-theme/theme.json"
---

# FSE Theme — Templates & Patterns

`starter-kit-theme` is a Full Site Editing block theme. Site structure is composed from block
markup, not PHP templates.

```
templates/   Full-page block templates (.html): index, front-page, home, page, single, 404,
             page-with-hero, page-without-title
parts/       Template parts (.html): header.html, footer.html
patterns/    Block patterns as PHP files: header.php, footer.php
theme.json   Global styles, color palette, block settings
```

- **New page template** → add a `.html` file in `templates/` (e.g. `page-with-hero.html`). The file
  contains block markup (`<!-- wp:... -->`), not PHP.
- **New template part** → add a `.html` file in `parts/`.
- **New block pattern** → add a PHP file in `patterns/` with the pattern registration header comment.
- **Global styles, colors, spacing** → edit `theme.json`, not inline CSS.
- Heavy logic does NOT belong in a template — build a block instead (see `blocks.md`).
- The theme is Bootstrap 5 based; use Bootstrap utility classes in markup.
