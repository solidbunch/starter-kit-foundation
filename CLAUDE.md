# StarterKit Foundation

Enterprise WordPress boilerplate: Docker + Terraform + Ansible + CI/CD.
PHP 8.1+, WordPress 6.8.1, MariaDB, Nginx. Four environments: local, dev, stage, prod.

## Commands

```bash
make install [local|dev|stage|prod]      # First-time setup: secrets → .env → composer → npm → docker → WP
make up [local|dev|stage|prod]           # Start containers (rebuilds .env first)
make down                                # Stop containers
make watch                               # npm watch + BrowserSync for theme development
make lint                                # PHP (PSR-12) + JS linting — run before every commit
make secret                              # Generate .env.secret from template
make import -f dump.sql                  # Import DB + run WP search-replace
make export                              # Export DB to file
make log [php|nginx|mariadb|cron]        # Stream container logs
make tf [env] [init|plan|apply]          # Terraform: manage AWS infrastructure
make ansible [env] [inventory|playbook]  # Ansible: provision servers
```

## Environment System

Config merges in order (last wins): `.env.main` → `.env.type.{env}` → `.env.secret`

NEVER edit `.env` directly — it is auto-generated. Edit the source files instead.
Secrets live ONLY in `.env.secret` (not committed). Template: `sh/env/.env.secret.template`.

## Architecture

```
web/wp-content/
  themes/starter-kit-theme/   # FSE theme — separate VCS repo, managed via Composer
  plugins/starter-kit-addon/  # Main plugin — custom post types, REST API, Gutenberg blocks
kit-modules/
  basis/                       # IaC: Terraform (AWS) + Ansible (servers)
  monitoring-client/           # Loki logging client
config/environment/            # .env files per environment
sh/                            # Shell scripts (never call directly — use make)
.github/workflows/             # CI/CD: deploy + provision pipelines
```

## PHP Architecture Patterns

This is NOT classic WordPress. No procedural functions, no global functions, no `functions.php` logic dumps.
Everything is PSR-12 OOP. Read existing code before modifying — never invent new patterns.

**Static handler — dominant pattern.** All methods `public static`, never instantiate handlers:
```php
class Front {
    public static function enqueueAssets(): void { ... }
}
// In Hooks.php only:
add_action('wp_enqueue_scripts', [Front::class, 'enqueueAssets']);
```

**Singleton** — only for `App` (entry point). Never make handlers singletons.

**Repository** — every CPT that needs querying gets a repository class:
```php
class PostRepository extends WpPostRepositoryAbstract { ... }
$posts = PostRepository::getAllList();   // returns [ID => title]
$posts = PostRepository::get([...]);    // returns WP_Post[]
```

**ALL hooks in one place**: `src/Base/Hooks.php` → `initHooks()` is the ONLY place for `add_action`/`add_filter`.
Never register hooks inside handler methods or constructors.

**Config access**: `Config::get('section/key')` — walks nested array by `/`.

**Meta access**: always via `Utils::getPostMeta($postId, $key)` — NEVER raw `get_post_meta()` for CF fields.

**Security — mandatory on every input/output:**
```php
$clean = sanitize_text_field($_POST['field']);   // sanitize input early
echo esc_html($value);                           // escape output late
echo esc_url($url);
$wpdb->prepare("SELECT * FROM t WHERE id = %d", $id);  // always prepared statements
```

## Carbon Fields

**Boot**: THEME boots CF (`ThemeSettings::boot()` via `after_setup_theme` in theme Hooks.php). Addon does NOT boot CF — never boot it twice.

**Register fields**: use `carbon_fields_register_fields` hook — never `init` (silently fails):
```php
// In Hooks.php (theme or addon):
add_action('carbon_fields_register_fields', [Meta\PostMeta\MyType::class, 'make']);

// In src/Handlers/Meta/PostMeta/MyType.php:
public static function make(): void {
    $metaPrefix = SK_PREFIX . PostTypes\MyType::getKey() . '_';
    Container::make('post_meta', __('Settings', 'starter-kit'))
        ->where('post_type', '=', PostTypes\MyType::getKey())
        ->add_fields([ Field::make('text', $metaPrefix . 'field_name', __('Label', 'starter-kit')) ]);
}
```

One `Container::make` per CPT. Never call it before `carbon_fields_register_fields` fires.

**Read/write always via Utils**:
```php
Utils::getPostMeta($postId, $metaPrefix . 'field_name');           // read
Utils::setPostMeta($postId, $metaPrefix . 'field_name', $value);   // write
```

**Field type gotchas** — Claude will get these wrong without being told:
- `checkbox` → returns `'yes'` / `''`, NOT `true` / `false`
- `relationship` is deprecated → use `association` instead
- `association` returns `[['id'=>..., 'type'=>..., 'subtype'=>...]]` → use `wp_list_pluck($result, 'id')` for IDs
- `complex` (repeater) returns `array[]` → always null-check before iterating
- `select` options format: `['value' => 'Label']`, dynamic: `->set_options(fn() => [...])`

## Theme (starter-kit-theme)

FSE block theme. Namespace: `StarterKit\` → `src/`. **The theme is where all main application code lives**: CPTs, meta fields, blocks, settings, analytics, security — all registered in the theme's Hooks.php.

```
templates/          Full-page block templates (.html)
parts/              Template parts: header.html, footer.html
theme.json          Global styles and block settings
blocks/             Gutenberg blocks (Button, Row, Section, Heading, News, etc.)
src/
  App.php                      Bootstrap (AbstractSingleton)
  Base/
    Constants.php               Defines SK_PREFIX, SK_HOOKS_PREFIX, SK_REST_API_NS, etc.
    Hooks.php                   ALL add_action/add_filter: CPTs, CF, blocks, front/back, security, mail
  Helper/
    Config.php                  Config::get('section/key')
    Utils.php                   getPostMeta(), setPostMeta(), getOption(), getOptionFw()
  Handlers/
    SetupTheme.php              Theme support, image sizes, menus
    Front.php / Back.php        Asset enqueue
    PostTypes/                  CPT registration (News, TeamMember, Service)
    Meta/PostMeta/              CF containers per CPT
    Settings/ThemeSettings.php  CF::boot() + theme_options container
    Blocks/Init.php             Block auto-discovery and registration
```

Bootstrap flow: `functions.php` → `require vendor/autoload.php` → `apply_filters('starter_kit/container', require config/container.php)` → `App::instance()->run($container)` → `Constants::define()` + `Hooks::initHooks()`

Adding new page templates: create `.html` file in `templates/`.
Adding new template parts: create `.html` file in `parts/`.

## Gutenberg Blocks

Blocks live in `blocks/` — in the **theme** (`starter-kit-theme/blocks/`) for application blocks, or in the **addon** (`starter-kit-addon/blocks/`) for addon-specific blocks. Both use the same structure.

```
blocks/MyBlock/         # PascalCase folder name (prefix _ = skip auto-discovery)
  block.json            # Required metadata
  Block.php             # Extends BlockAbstract — server-side render logic
  src/
    index.jsx           # registerBlockType — editor UI only
    style.scss          # Front + editor styles
    editor.scss         # Editor-only styles (optional)
    view.js             # Frontend JS (optional)
```

**`block.json` required fields:**
```json
{
  "apiVersion": 3,
  "name": "starter-kit/my-block",
  "title": "My Block",
  "category": "starter-kit"
}
```

**`Block.php` pattern:**
```php
class Block extends BlockAbstract {
    public function registerBlockArgs(): void {
        $this->blockArgs = ['render_callback' => [$this, 'renderBlock']];
    }
    public function renderBlock(array $attributes, string $content): string {
        return '<div class="my-block">' . esc_html($attributes['title'] ?? '') . '</div>';
    }
}
```

**`index.jsx` pattern** — `save: () => null` always (server-side render):
```jsx
import metadata from '../block.json';
registerBlockType(metadata, {
    edit: ({ attributes, setAttributes }) => <div {...useBlockProps()}>Editor view</div>,
    save: () => null,
});
```

IMPORTANT: Use global `wp.*` — NOT `@wordpress/` npm imports. They are not in the bundle config.

## Debugging

Xdebug is **inactive by default** — trigger per request (local environment only):
```
?XDEBUG_TRIGGER=1            # query param
POST field: XDEBUG_TRIGGER=1
Header: XDEBUG_TRIGGER: 1
```
Config: `config/php/local.d/xdebug.ini`

Log file locations on host:
```
logs/nginx/access.log           HTTP access log
logs/nginx/error.log            Nginx errors
logs/wordpress/debug.log        WP_DEBUG output (requires WP_DEBUG=true in .env)
logs/wordpress/xdebug-log.log   Xdebug session log
```

Acceptable during local dev only — NEVER commit:
```php
error_log(print_r($value, true));
```

NEVER leave in committed code: `var_dump()`, `print_r()`, `dd()`, `dump()`, `error_log()`.

## Hard Rules

NEVER:
- Commit `.env`, `.env.secret`, or any file with credentials
- Edit WordPress core `web/wp-core/` — it is a Composer dependency
- Edit `vendor/` directly — update `composer.json` instead
- Hardcode environment-specific values — use `getenv()` or config files
- Use raw `get_post_meta()` / `update_post_meta()` for Carbon Fields fields — use Utils wrappers
- Register hooks outside `src/Base/Hooks.php`
- Write procedural functions or global helpers
- Run `git push --force` to `main` or `develop`

ALWAYS:
- Run `make lint` before committing PHP or JS changes
- Add new secret variable names to `sh/env/.env.secret.template`
- Test in `local` before pushing to `dev`
- Read existing files before modifying — never assume structure
- Report broken code spotted outside current scope — do not silently fix it
- One task = one commit-ready change

## Adding New Things

Primary location is the **theme** (`starter-kit-theme/`). Use the addon only for addon-specific features.

| What | Where (in theme or addon) |
|------|--------------------------|
| New hook | `src/Base/Hooks.php` → `initHooks()` |
| New CPT | `src/Handlers/PostTypes/NewType.php`, register in `Hooks.php` |
| New CF container | `src/Handlers/Meta/PostMeta/NewType.php`, hook in `Hooks.php` |
| New repository | `src/Repository/NewTypeRepository.php` extends `WpPostRepositoryAbstract` |
| New REST endpoint | handler in `src/Handlers/`, route registered in `Hooks.php` |
| New config key | `config/common/main.php` or appropriate config file |
| New block | `blocks/NewBlock/` (PascalCase) in theme or addon `blocks/` folder |

## WordPress Conventions

- New application CPTs, meta, blocks, business logic → **theme** (`StarterKit\` namespace)
- Addon-specific features (tied to Pricing/DocPage CPTs, Stripe, etc.) → **addon** (`StarterKitAddon\` namespace)
- Theme hook prefix: `SK_HOOKS_PREFIX` constant (e.g., `starter_kit/action_name`)
- Addon hook prefix: `SKA_HOOKS_PREFIX` constant (e.g., `starter_kit_addon/action_name`)
- REST endpoints: `register_rest_route(SK_REST_API_NS, '/route', ...)` (theme) or `register_rest_route(SKA_REST_API_NS, '/route', ...)` (addon)
- `DISALLOW_FILE_EDIT=1` and `AUTOMATIC_UPDATER_DISABLED=1` are intentional — do not remove

## Intentional Quirks

- `WP_DISABLE_WP_CRON=1` — cron runs via dedicated cron container, not on HTTP requests
- `AUTOMATIC_UPDATER_DISABLED=1` — all updates via Composer, never via WP admin
- Theme uses `dev-develop` branch in dev environment (not a stable tag) — this is correct
- `kit-modules/` is git-ignored in root — modules install via Composer into this folder

## Out of Scope (Do Not Modify)

- `web/wp-core/` — WordPress core (Composer-managed)
- `vendor/` — PHP dependencies (Composer-managed)
- `db-data/` — MariaDB data volume (runtime data)
- `cache/` — build cache (auto-generated)
- `logs/` — runtime logs (read only)
- `.env` — auto-generated from source env files, do not edit directly
