---
paths:
  - "web/wp-content/themes/starter-kit-theme/**/*.php"
  - "web/wp-content/plugins/starter-kit-addon/**/*.php"
---

# PHP Architecture

This is NOT classic WordPress. No procedural functions, no global functions, no `functions.php`
logic dumps. Everything is PSR-12 OOP. Read existing code before modifying — never invent patterns.

## Theme & addon layout

The **theme** (`starter-kit-theme/`, namespace `StarterKit\`) is where the main application lives:
CPTs, meta, blocks, settings, analytics, security. The **addon** (`starter-kit-addon/`, namespace
`StarterKitAddon\`) is supplementary (Pricing/DocPage CPTs, Stripe). Both share this `src/` layout:

```
src/
  App.php                      Bootstrap (AbstractSingleton)
  Base/
    Constants.php               Defines SK_PREFIX / SKA_PREFIX, hook + REST namespaces
    Hooks.php                   ALL add_action/add_filter — the only hook registry
  Helper/  Config.php, Utils.php
  Handlers/
    PostTypes/                  CPT registration
    Meta/PostMeta/              Carbon Fields containers
    Settings/                   Theme options (theme only)
    Front.php / Back.php        Asset enqueue
  Repository/                   WpPostRepositoryAbstract subclasses
```

Theme bootstrap: `functions.php` → `require vendor/autoload.php` →
`apply_filters('starter_kit/container', require config/container.php)` →
`App::instance()->run($container)` → `Constants::define()` + `Hooks::initHooks()`

## Patterns

**Static handler — dominant pattern.** All methods `public static`, never instantiate handlers:

```php
class Front {
    public static function enqueueAssets(): void { ... }
}
add_action('wp_enqueue_scripts', [Front::class, 'enqueueAssets']);  // in Hooks.php only
```

**Singleton** — only for `App` (entry point). Never make handlers singletons.

**Repository** — every CPT that needs querying gets a repository class:

```php
class PostRepository extends WpPostRepositoryAbstract { ... }
$posts = PostRepository::getAllList();   // [ID => title]
$posts = PostRepository::get([...]);     // WP_Post[]
```

**ALL hooks in one place**: `src/Base/Hooks.php` → `initHooks()` is the ONLY place for
`add_action`/`add_filter`. Never register hooks inside handler methods or constructors.

**Config access**: `Config::get('section/key')` — walks a nested array by `/`.

## Utils Helper — mandatory for all meta and options

NEVER call `get_post_meta()`, `update_post_meta()`, `get_option()`, `carbon_get_post_meta()`, or
any raw WP meta/option function. Always go through `Utils` — it auto-adds the project prefix and is
idempotent (won't double-prefix).

```php
// CF post meta — use in Block.php, Repository, Handlers
Utils::getPostMeta($postId, $metaPrefix . 'field');        // WP API, uses _SK_PREFIX
Utils::getPostMetaFw($postId, $metaPrefix . 'field');      // CF API — use for complex / association
Utils::setPostMeta($postId, $metaPrefix . 'field', $val);  // writes via WP

// Theme options (CF theme_options registered in ThemeSettings)
Utils::getOptionFw('gtm_code');   // CF theme option, uses SK_PREFIX
Utils::getOption('some_key');     // plain WP option, uses _SK_PREFIX

// Taxonomy / user meta — Fw variants exist for all
Utils::getTermMeta($termId, $metaPrefix . 'field');
Utils::getUserMeta($userId, $metaPrefix . 'field');
```

All Utils getters return `$defaultValue` (default null) when the value is `''`, `false`, `null`, `[]`.

## Security — mandatory on every input/output

```php
$clean = sanitize_text_field($_POST['field']);          // sanitize input early
echo esc_html($value);                                   // escape output late
echo esc_url($url);
$wpdb->prepare("SELECT * FROM t WHERE id = %d", $id);    // always prepared statements
```

## Conventions

- New application CPTs, meta, blocks, business logic → **theme** (`StarterKit\`)
- Addon-specific features (Pricing/DocPage, Stripe) → **addon** (`StarterKitAddon\`)
- Theme hook prefix `SK_HOOKS_PREFIX` (`starter_kit/...`); addon `SKA_HOOKS_PREFIX` (`starter_kit_addon/...`)
- REST: `register_rest_route(SK_REST_API_NS, '/route', ...)` (theme) / `SKA_REST_API_NS` (addon)

| Add a new... | Where |
|--------------|-------|
| Hook | `src/Base/Hooks.php` → `initHooks()` |
| CPT | `src/Handlers/PostTypes/NewType.php`, register in `Hooks.php` |
| CF container | `src/Handlers/Meta/PostMeta/NewType.php`, hook in `Hooks.php` |
| Repository | `src/Repository/NewTypeRepository.php` extends `WpPostRepositoryAbstract` |
| REST endpoint | handler in `src/Handlers/`, route registered in `Hooks.php` |
| Config key | `config/common/main.php` or appropriate config file |

NEVER: register hooks outside `Hooks.php`; write procedural functions or global helpers;
use raw `get_post_meta()` / `get_option()` instead of `Utils`.

## Debugging

Xdebug is **inactive by default** — trigger per request (local only): `?XDEBUG_TRIGGER=1` query
param, or POST field / header `XDEBUG_TRIGGER=1`. Config: `config/php/local.d/xdebug.ini`.

Logs on host: `logs/nginx/error.log`, `logs/wordpress/debug.log` (needs `WP_DEBUG=true`),
`logs/wordpress/xdebug-log.log`.

NEVER leave in committed code: `var_dump()`, `print_r()`, `dd()`, `dump()`, `error_log()`.
