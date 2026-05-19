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

## Theme (starter-kit-theme)

FSE block theme. Theme has **minimal hooks** — all business logic lives in `starter-kit-addon`.

```
templates/          Full-page block templates (.html): index, front-page, page, single, 404
parts/              Template parts: header.html, footer.html
theme.json          Global styles and block settings
src/
  App.php           Bootstrap (singleton)
  Base/Hooks.php    Theme-side hooks ONLY (textdomain, addThemeSupport)
  Helper/           Config.php, Utils.php — same API as plugin helpers
  Handlers/         SetupTheme.php (image sizes, menus, MIME types)
```

Bootstrap flow: `functions.php` → `App::instance()->run($container)` → `Hooks::initHooks()`

**Never boot Carbon Fields or register CPTs from the theme.** Theme only reads meta via `Utils`.
Adding new page templates: create `.html` file in `templates/`.
Adding new template parts: create `.html` file in `parts/`.

## Gutenberg Blocks

Blocks live in **`starter-kit-addon/blocks/`**, never in the theme.

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
  "name": "ska/my-block",
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
- Put blocks or CPT registration in the theme
- Run `git push --force` to `main` or `develop`

ALWAYS:
- Run `make lint` before committing PHP or JS changes
- Add new secret variable names to `sh/env/.env.secret.template`
- Test in `local` before pushing to `dev`
- Read existing files before modifying — never assume structure
- Report broken code spotted outside current scope — do not silently fix it
- One task = one commit-ready change

## WordPress Conventions

- Plugin hooks use namespace prefix: `starter_kit_addon/action_name`
- New features go in `starter-kit-addon`, not in the theme
- REST endpoints: `register_rest_route('ska/v1', '/your-route', ...)`
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
