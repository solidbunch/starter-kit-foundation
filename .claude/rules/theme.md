---
paths:
  - "web/wp-content/themes/starter-kit-theme/**"
---

# Theme: starter-kit-theme

The theme is the **main application codebase** — CPTs, meta, blocks, settings, analytics and
security all live here. Namespace `StarterKit\` → `src/`. PHP patterns: see `php-standards.md`.

## Bootstrap flow

```
functions.php
  → require vendor/autoload.php
  → apply_filters('starter_kit/container', require config/container.php)
  → App::instance()->run($container)
  → Constants::define() + Hooks::initHooks() + CLI::addCommands()
```

## FSE — block theme

```
templates/   Full-page block templates (.html): index, front-page, home, page, single,
             404, page-with-hero, page-without-title
parts/       Template parts (.html): header.html, footer.html
patterns/    Block patterns as PHP files: header.php, footer.php
theme.json   Global styles, color palette, block settings
style.css    Theme identity header only — no real CSS here
blocks/      Gutenberg blocks — see blocks.md
```

## `src/` structure

```
App.php                       Bootstrap (AbstractSingleton)
AbstractSingleton.php
Base/
  Constants.php                Defines SK_PREFIX, SK_HOOKS_PREFIX, SK_REST_API_NS, SK_BLOCKS_* ...
  Hooks.php                    ALL add_action/add_filter — the only hook registry
Helper/  Config.php, Utils.php
Handlers/
  SetupTheme.php               Theme support, image sizes, menus
  Front.php / Back.php         Asset enqueue
  Analytics.php                GTM / Google Analytics
  AdminColumns.php
  PostTypes/                   CPT registration: News (+ Category/Tag taxonomies), TeamMember, Service
  Meta/PostMeta/               CF containers: News, Page
  Meta/TaxonomyMeta/, Meta/UserMeta/
  Settings/ThemeSettings.php   Carbon_Fields::boot() + theme_options container
  Blocks/Init.php              Block auto-discovery and registration
  Optimization/, Security/, Mail/, CLI/
Repository/                    WpPostRepositoryAbstract + per-CPT repositories
```

## Key rules

- Carbon Fields is **booted by the theme** (`ThemeSettings::boot()` on `after_setup_theme`)
- All CPTs / meta / blocks / business logic → here in the theme
- Global styles, colors, spacing → `theme.json`, never inline CSS
- Heavy logic does not belong in a `.html` template — build a block instead (see `blocks.md`)
- The theme is Bootstrap 5 based; use Bootstrap utility classes in markup

## Adding new things

| What | Where |
|------|-------|
| Hook | `src/Base/Hooks.php` → `initHooks()` |
| CPT | `src/Handlers/PostTypes/NewType.php`, register in `Hooks.php` |
| CF container | `src/Handlers/Meta/PostMeta/NewType.php`, hook in `Hooks.php` |
| Repository | `src/Repository/NewTypeRepository.php` extends `WpPostRepositoryAbstract` |
| Page template | `templates/name.html` (block markup) |
| Template part | `parts/name.html` |
| Block pattern | `patterns/name.php` |
| Block | `blocks/NewBlock/` — see `blocks.md` |
| Config key | `config/common/main.php` or appropriate config file |
| WP-CLI command | `src/Handlers/CLI/` |
