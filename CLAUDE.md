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

## Code Style (PHP)

- PSR-12 strict. Run `make lint` — it fails CI if broken.
- PSR-4 autoloading. Namespaces match directory structure exactly.
- Full type hints on all properties, parameters, and return types — no exceptions.
- DI container (PHP-DI) + Laminas ConfigAggregator for config merging across environments.
- WordPress hooks are entry points only; business logic lives in Services, not in hooks.

## Hard Rules

NEVER:
- Commit `.env`, `.env.secret`, or any file with credentials
- Edit WordPress core `web/wp-core/` — it is a Composer dependency
- Edit `vendor/` directly — update `composer.json` instead
- Hardcode environment-specific values — use `getenv()` or config files
- Run `git push --force` to `main` or `develop`

ALWAYS:
- Run `make lint` before committing PHP or JS changes
- Add new secret variable names to `sh/env/.env.secret.template` when introducing new secrets
- Test in `local` environment before pushing to `dev`
- Use kit-module pattern for new cross-cutting features (type: `kit-module` in composer.json)

## WordPress Conventions

- Plugin hooks use namespace: `starter_kit_addon/action_name`
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
