# StarterKit Foundation

Enterprise WordPress boilerplate: Docker + Terraform + Ansible + CI/CD.
PHP 8.1+ (8.4 in containers), WordPress 6.8.1, MariaDB, Nginx. Four environments: local, dev, stage, prod.

Two layers:

- **Foundation** — Docker, env/secrets, CI/CD, IaC (this repo)
- **Application** — `starter-kit-theme`, a custom FSE block theme (the main codebase)

<!-- This file is always loaded. Topic detail lives in path-scoped rules — see the table below. -->

## Where AI rules live

Foundation rules — in `.claude/rules/`, auto-injected by context (`/memory` shows what is loaded):

| Rule | Loads when |
|------|------------|
| `workflow.md` | always — how to work on this project |
| `debug.md` | always — debugging tools, what never to commit |
| `infrastructure.md` | editing `kit-modules/basis/**`, `*.tf` — Terraform / Ansible |

The **theme** and **addon** carry their own `CLAUDE.md` files inside their repos. Claude Code
auto-loads them on demand when it reads files there — no setup needed:

- `web/wp-content/themes/starter-kit-theme/CLAUDE.md` — theme: PHP, Carbon Fields, FSE, structure
- `web/wp-content/themes/starter-kit-theme/blocks/CLAUDE.md` — Gutenberg blocks
- `web/wp-content/plugins/starter-kit-addon/CLAUDE.md` — addon (demo-only plugin)

## Commands

```bash
make install [local|dev|stage|prod]      # First-time setup: secrets → .env → composer → npm → docker → WP
make up [local|dev|stage|prod]           # Start containers (rebuilds .env first)
make down                                # Stop and REMOVE containers + volumes
make restart [local|dev|stage|prod]      # Restart containers without removing volumes
make watch                               # npm watch + BrowserSync for theme development
make lint                                # Lint theme: PHP (PSR-12) + JS — run before committing theme changes
make secret                              # Generate .env.secret from template (skips if it exists)
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

NEVER edit `.env` directly — it is auto-generated. Edit the source files in `config/environment/`.
Secrets live ONLY in `.env.secret` (not committed). Template: `sh/env/.env.secret.template`.

## Architecture

```
web/wp-content/
  themes/starter-kit-theme/   # FSE theme — main app code: CPTs, blocks, meta, hooks (separate VCS repo)
kit-modules/
  basis/                       # IaC: Terraform (AWS) + Ansible (servers)
  monitoring-client/           # Loki logging client
config/                        # Docker, nginx, php, ssl, cron, environment configs
sh/                            # Shell scripts (never call directly — use make)
.github/workflows/             # CI/CD: deploy + provision pipelines
```

## Hard Rules

NEVER:

- Commit `.env`, `.env.secret`, `.tfstate`, `.pem`, or any file with credentials
- Edit WordPress core `web/wp-core/` or `vendor/` — they are Composer-managed
- Hardcode environment-specific values — use `getenv()` or config files
- Run `git push --force` to `main` or `develop`

(Working process and per-language rules: see `workflow.md`, `debug.md`, and the path-scoped rules.)

## Intentional Quirks

- `WP_DISABLE_WP_CRON=1` — cron runs via dedicated cron container, not on HTTP requests
- `AUTOMATIC_UPDATER_DISABLED=1` / `DISALLOW_FILE_EDIT=1` — all updates via Composer; intentional
- Theme uses `dev-develop` branch in the dev environment (not a stable tag) — this is correct
- `kit-modules/` is git-ignored in root — modules install via Composer into this folder

## Out of Scope (Do Not Modify)

- `web/wp-core/` — WordPress core (Composer-managed)
- `vendor/` — PHP dependencies (Composer-managed)
- `db-data/` — MariaDB data volume (runtime data)
- `cache/` — build cache (auto-generated)
- `logs/` — runtime logs (read only)
- `.env` — auto-generated from source env files, do not edit directly
