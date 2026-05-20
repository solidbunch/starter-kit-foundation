---
paths:
  - "web/wp-content/themes/starter-kit-theme/**/*.php"
  - "web/wp-content/plugins/starter-kit-addon/**/*.php"
---

# PHP Standards and Architecture

## This is NOT classic WordPress

No procedural functions, no global functions, no `functions.php` logic dumps.
Everything is PSR-12 OOP. Follow existing patterns — never invent new ones.

## PSR-12 — enforced by `phpcs.xml`

Run `make lint` before committing. Inside the theme/addon repo: `composer lint` / `composer lintfix`.

## File header — every PHP file in `src/`

```php
<?php

namespace StarterKit\Handlers;

defined('ABSPATH') || exit;
```

No `declare(strict_types=1)` — the codebase does not use it. Match the surrounding files.

## Class patterns

**Singleton** — only `App` (entry point), via `AbstractSingleton`. Never make handlers singletons.
Access the DI container anywhere:

```php
App::container()->get(LoggerInterface::class);
```

**Static handler — the dominant pattern.** Handlers are never instantiated; all methods `public static`:

```php
class Front {
    public static function enqueueAssets(): void { ... }
}
add_action('wp_enqueue_scripts', [Front::class, 'enqueueAssets']);   // in Hooks.php only
```

Never `new Front()`, never `$front->method()`.

**Repository — extends `WpPostRepositoryAbstract`.** Every CPT that needs querying gets one;
it defines the abstract `getPostTypeKey()`:

```php
class NewsRepository extends WpPostRepositoryAbstract {
    public static function getPostTypeKey(): string { return PostTypes\News::getKey(); }
}
// Base methods: get() → WP_Post[], getIds() → int[], getAllList() → [ID => title],
// getPagedList(), getById(), getBySlug(), getRecentPosts(), getRelatedPosts(), getOne() ...
```

Prefer repositories for reusable CPT queries. Small local admin closures may use WP query helpers
when a repository would add no value.

**Hooks — all in one place.** `src/Base/Hooks.php` → `initHooks()` is the ONLY place for
`add_action` / `add_filter`. Never register hooks inside handler methods or constructors.

## Config access

```php
Config::get('settingsPrefix')      // top-level key
Config::get('postTypes/SiteID')    // nested — walks the array by '/'
```

## Meta / options — always via Utils, never raw

```php
Utils::getPostMeta($postId, $metaPrefix . 'field');     // WP API,  uses _SK_PREFIX
Utils::getPostMetaFw($postId, $metaPrefix . 'field');   // CF API — complex / association fields
Utils::setPostMeta($postId, $metaPrefix . 'field', $v);
Utils::getOptionFw('gtm_code');   // CF theme option (SK_PREFIX)
Utils::getOption('some_key');     // plain WP option (_SK_PREFIX)
```

Utils auto-adds the prefix and is idempotent. Getters return `$defaultValue` when the value is
`''`, `false`, `null`, or `[]`. NEVER call raw `get_post_meta()` / `update_post_meta()` /
`get_option()` / `carbon_get_post_meta()`.

## Security — mandatory

```php
$clean = sanitize_text_field($_POST['field']);          // input — sanitize early
$html  = wp_kses_post($_POST['content']);
echo esc_html($value); echo esc_url($url); echo esc_attr($attr);   // output — escape late
$wpdb->prepare("SELECT * FROM t WHERE id = %d", $id);   // queries — always prepared
```

## Type hints

PHP 8.1+: typed properties, `mixed`, union types, `?string` nullables, return types on all
public methods.

## Never

- Global / procedural functions or global helpers
- `new SomeHandler()` to register hooks; hooks inside constructors or methods
- Raw `get_post_meta()` / `update_post_meta()` / `get_option()` for CF fields
- Reusable CPT queries outside a Repository
- `var_dump` / `print_r` / `error_log` left in code
- `TODO` / `FIXME` in committed code
