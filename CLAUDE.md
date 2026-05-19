# StarterKit Foundation

Enterprise WordPress boilerplate: Docker + Terraform + Ansible + CI/CD.
PHP 8.1+, WordPress 6.8.1, MariaDB, Nginx. Four environments: local, dev, stage, prod.

## Commands

```bash
make install [local|dev|stage|prod]      # First-time setup: secrets → .env → composer → npm → docker → WP
make up [local|dev|stage|prod]           # Start containers (rebuilds .env first)
make down                                # Stop and REMOVE containers + volumes (data lost if not bind-mounted)
make restart [local|dev|stage|prod]      # Restart containers without removing volumes
make watch                               # npm watch + BrowserSync for theme development
make lint                                # Lint theme: PHP (PSR-12) + JS — run before committing theme changes
make secret                              # Generate .env.secret from template (skips if file already exists)
make import dump.sql                     # Import DB from file + run WP search-replace
make export                              # Export DB to file
make replace                             # Run WP search-replace (domain update)
make log [php|nginx|mariadb|cron]        # Stream container logs
make pma                                 # Launch phpMyAdmin (port 8801)
make mailhog                             # Launch MailHog for email testing
make tf [env] [init|plan|apply]          # Terraform: manage AWS infrastructure
make ansible [env] [inventory|playbook]  # Ansible: provision servers
```

## Environment System

Config merges in order (last wins): `.env.main` → `.env.type.{env}` → `.env.type.{env}.override` (optional) → `.env.secret`

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

## Utils Helper — Mandatory for All Meta and Options

NEVER call `get_post_meta()`, `update_post_meta()`, `get_option()`, `carbon_get_post_meta()`, or any raw WP meta/option function. Always go through `Utils`. It auto-adds the project prefix and is idempotent (won't double-prefix).

```php
// CF post meta — use in Block.php, Repository, Handlers
Utils::getPostMeta($postId, $metaPrefix . 'field');              // WP API, uses _SK_PREFIX
Utils::getPostMetaFw($postId, $metaPrefix . 'field');            // CF API (use for complex, association fields)
Utils::setPostMeta($postId, $metaPrefix . 'field', $value);      // writes via WP

// CF theme options (registered in ThemeSettings)
Utils::getOptionFw('gtm_code');       // CF theme option, uses SK_PREFIX
Utils::getOption('some_key');         // plain WP option, uses _SK_PREFIX

// Taxonomy / user meta
Utils::getTermMeta($termId, $metaPrefix . 'field');
Utils::getUserMeta($userId, $metaPrefix . 'field');
// Fw variants exist for all: getTermMetaFw, getUserMetaFw, etc.
```

All Utils methods: when value is `''`, `false`, `null`, or `[]` → returns `$defaultValue` (default: null).

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
    PostTypes/                  CPT registration (News, Portfolio, Pricing, DocPage, TeamMember, Service)
    Meta/PostMeta/              CF containers: News, Pricing, Page
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

**`Block.php` pattern** — extends `BlockAbstract`, declare assets, use `blockServerSideCallback` (3 params), render via `loadBlockView`:
```php
class Block extends BlockAbstract {
    protected array $blockAssets = [
        'editor_script' => ['file' => 'index.js', 'dependencies' => ['wp-i18n', 'wp-element', 'wp-blocks', 'wp-components', 'wp-editor']],
        'editor_style'  => ['file' => 'editor.css', 'dependencies' => []],
        'style'         => ['file' => 'style.css', 'dependencies' => []],
        // 'view_script' => ['file' => 'view.js', 'dependencies' => []], // frontend-only JS
    ];

    public function registerBlockArgs(): void {
        $this->blockArgs['render_callback'] = [$this, 'blockServerSideCallback'];  // NOTE: key assignment, not full array
    }

    public function blockServerSideCallback(array $attributes, string $content, object $block): string {
        $templateData = [
            'title'      => $attributes['title'] ?? '',
            'blockClass' => $this->generateBlockClasses($attributes),  // handles spacers + className
        ];
        return $this->loadBlockView('layout', $templateData);  // loads view/layout.php
    }

    public function blockRestApiEndpoints(): void {
        // register_rest_route(SK_REST_API_NS, '/endpoint', [...]);
    }
}
```

Asset types: `editor_script`/`editor_style` (admin only), `style` (frontend+admin), `view_script`/`view_style` (frontend only), `script` (both).

**`view/layout.php`** — receives `$data` array, is the actual rendered HTML:
```php
defined('ABSPATH') || exit;
$data = $data ?? [];
?>
<div class="my-block <?php echo $data['blockClass']; ?>">
    <h2><?php echo esc_html($data['title']); ?></h2>
</div>
```

**`index.jsx` pattern** for server-side render blocks (most blocks):
```jsx
const {registerBlockType} = wp.blocks;
const {useBlockProps} = wp.blockEditor;
const {serverSideRender: ServerSideRender} = wp;

registerBlockType(metadata, {
    edit: (props) => {
        const blockProps = useBlockProps();
        return <div {...blockProps}><ServerSideRender block={metadata.name} attributes={props.attributes} /></div>;
    },
    save: () => null,  // always null for server-side render
});
```

IMPORTANT: Use global `wp.*` — NOT `@wordpress/` npm imports. They are not in the bundle config.

**Full-page CF-backed block** — the "fill in fields, get a complete section" pattern. Instead of complex block editor layout, register CF fields on the page/CPT and read them in the block callback:
```php
// 1. Register CF container in Meta/PostMeta/MyPage.php (hook in Hooks.php):
public static function make(): void {
    $metaPrefix = SK_PREFIX . 'page_';
    Container::make('post_meta', __('Page Content', 'starter-kit'))
        ->where('post_type', '=', 'page')
        ->add_fields([
            Field::make('text',     $metaPrefix . 'hero_title',    __('Hero Title', 'starter-kit')),
            Field::make('textarea', $metaPrefix . 'hero_subtitle', __('Subtitle', 'starter-kit')),
            Field::make('image',    $metaPrefix . 'hero_image',    __('Hero Image', 'starter-kit')),
            Field::make('complex',  $metaPrefix . 'sections',      __('Sections', 'starter-kit'))
                ->add_fields('section', __('Section', 'starter-kit'), [
                    Field::make('text',      'title',   __('Title', 'starter-kit')),
                    Field::make('rich_text', 'content', __('Content', 'starter-kit')),
                ]),
        ]);
}

// 2. Block.php reads CF meta in callback:
public function blockServerSideCallback(array $attributes, string $content, object $block): string {
    $postId     = get_the_ID();
    $metaPrefix = SK_PREFIX . 'page_';
    $templateData = [
        'heroTitle'    => Utils::getPostMeta($postId, $metaPrefix . 'hero_title'),
        'heroSubtitle' => Utils::getPostMeta($postId, $metaPrefix . 'hero_subtitle'),
        'heroImageId'  => Utils::getPostMeta($postId, $metaPrefix . 'hero_image'),
        'sections'     => Utils::getPostMetaFw($postId, $metaPrefix . 'sections') ?: [],  // Fw for complex
        'blockClass'   => $this->generateBlockClasses($attributes),
    ];
    return $this->loadBlockView('layout', $templateData);
}

// 3. view/layout.php renders the complete section from CF data:
// Admin fills CF fields in the WP editor → block renders the complete page section
```

In editor JSX: just `ServerSideRender` — no editable controls needed. User manages all content via CF admin panel.

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
- Use raw `get_post_meta()`, `update_post_meta()`, `get_option()`, `carbon_get_post_meta()` — always use `Utils::` wrappers
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
