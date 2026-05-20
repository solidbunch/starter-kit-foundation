---
paths:
  - "web/wp-content/plugins/starter-kit-addon/**"
---

# Addon: starter-kit-addon

A **supplementary plugin** — optional / demo features layered on top of the theme. Namespace
`StarterKitAddon\` → `src/`. Installed via Composer (`^1.0.3`). The addon is NOT the main
codebase — the theme is (see `theme.md`). PHP patterns: see `php-standards.md`.

## What belongs here vs the theme

- **Addon** — features tied to the addon's own CPTs (Pricing, DocPage), Stripe integration,
  addon-specific blocks
- **Theme** — all core application code: CPTs, meta, blocks, settings, security

## Bootstrap

```
starter-kit-addon.php → App::instance()->run($container) → Constants::define() + Hooks::initHooks()
```

## `src/` structure

```
App.php
Base/
  Constants.php    Defines SKA_PREFIX, SKA_HOOKS_PREFIX, SKA_REST_API_NS, SKA_BLOCKS_* ...
  Hooks.php        ALL add_action/add_filter for the addon
Handlers/
  PostTypes/       Pricing, DocPage
  Meta/PostMeta/   CF containers (Pricing)
  Stripe/          PaymentHandler — REST routes
  Front.php, TemplateHandler.php, Blocks/
Repository/        PricingRepository, DocPageRepository (extend WpPostRepositoryAbstract)
```

## Conventions

- Same PHP patterns as the theme — see `php-standards.md`
- The addon does NOT boot Carbon Fields (the theme does); it only registers fields — see `carbon-fields.md`
- Addon namespaces use the `SKA_*` constants (hooks `SKA_HOOKS_PREFIX`, REST `SKA_REST_API_NS`,
  blocks `SKA_BLOCKS_*`) — do not confuse with the theme's `SK_*`
- Existing addon meta/repository code references `SK_PREFIX` for meta keys — match the prefix
  used in the nearest existing addon file rather than guessing
- Addon blocks: namespace `StarterKitAddonBlocks\`, same patterns as theme blocks — see `blocks.md`
