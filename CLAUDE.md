# StarterKit Foundation

Enterprise WordPress boilerplate: Docker + Terraform + Ansible + CI/CD.
PHP ≥8.4, WordPress core `wordpress-core-no-content` ^6.8.1, MariaDB, Nginx.
Four environments: local, dev, stage, prod.

Three layers:

- **Foundation** — Docker, env/secrets, CI/CD, IaC (this repo)
- **Application** — the theme (`WP_DEFAULT_THEME` in `config/environment/.env.main`, default
  `starter-kit-theme`), a custom FSE block theme (the main app codebase, separate VCS repo)
- **kit-modules** — licensed sub-projects Composer-installs into `kit-modules/` once a valid
  license is configured (`basis`, `monitoring-client`, `monitoring-server`, `proxy`) — see
  `infrastructure.md`

<!-- This file is always loaded. Topic detail lives in path-scoped rules — see the table below. -->

## Where AI rules live

Foundation rules — in `.claude/rules/`, auto-injected by path (`/memory` shows what is loaded):

| Rule                | Loads when                                                                               |
| ------------------- | ---------------------------------------------------------------------------------------- |
| `workflow.md`       | always — how to work on this project                                                     |
| `debug.md`          | always — debugging tools, what never to commit                                           |
| `infrastructure.md` | editing `kit-modules/**`, `*.tf`, `*.tfvars` — Terraform / Ansible / licensing           |
| `docker.md`         | editing `docker-compose*.yml`, `dockerfiles/**`, `sh/system/{docker,install,certbot}.sh` |
| `ci.md`             | editing `.github/workflows/**` — deploy + provisioning pipelines                         |
| `gitlab-ci.md`      | editing `.gitlab-ci.yml`, `.gitlab/ci/**` — parallel GitLab CI deploy pipeline           |
| `config.md`         | editing `config/**` — env files, nginx templates, PHP ini, cron, certbot, SSL            |
| `design-verification.md` | editing blocks, FSE `templates`/`parts`/`patterns`, or any `*.scss` — how a layout change gets verified (measured, not eyeballed) |

The **theme** carries its own `CLAUDE.md` files inside its repo. Claude Code auto-loads them on
demand when it reads files there — no setup needed. Paths below use the shipped default theme
folder name (`starter-kit-theme` = `WP_DEFAULT_THEME`'s default in `config/environment/.env.main`)
— if this project renamed the theme (`bootstrap-project` Step 3), substitute the current
`WP_DEFAULT_THEME` value everywhere below instead:

- `web/wp-content/themes/starter-kit-theme/CLAUDE.md` — theme: PHP, Carbon Fields, FSE, structure
- `web/wp-content/themes/starter-kit-theme/blocks/CLAUDE.md` — Gutenberg blocks

The theme also carries its own skills, **not** auto-discovered from here (skill auto-discovery is
project-root-only, same caveat as rules — see `project-brief`'s known gotchas): read and follow
these directly by path, not by name, from a foundation session — full list under `## Skills` below.

Each **kit-module** is also its own separate VCS repo (see `infrastructure.md` for the
install/licensing mechanism) and carries its own `CLAUDE.md`, auto-loaded on demand when Claude
reads a file under that module's directory — no setup needed. `infrastructure.md` documents these
modules from the *outside* (how the foundation integrates with them: install paths, licensing
gate, `make` command surface); each module's own `CLAUDE.md` documents its *internals* (own
conventions, own gotchas) and points back to `infrastructure.md` rather than repeating it:

- `kit-modules/basis/CLAUDE.md` — Terraform apply order, Ansible partial-ordering convention,
  known `stage`-env gap
- `kit-modules/monitoring-client/CLAUDE.md` — fluent-bit pipeline (tail → Lua filter → Loki)
- `kit-modules/monitoring-server/CLAUDE.md` — Grafana + Loki stack; large enough to split into its
  own `@import`-ed topic files (`stack.md`, `env-and-lifecycle.md`, `iac.md`) under its own
  `.claude/rules/`, same reasoning as the theme's topic-file split
- `kit-modules/proxy/CLAUDE.md` — Traefik reverse proxy; see `.claude/rules/infrastructure.md` for
  how the foundation wires `APP_MULTI_INSTANCE` and `make proxy` into this module

## Skills

`.claude/skills/bootstrap-project/` — run once after cloning this template to turn it into a
named project (rename `APP_NAME`/`APP_TITLE`/`APP_DOMAIN`, optionally repoint the theme,
`make secret`/`env`/`install`, architect review, then refresh this file via `project-brief`).

**Theme skills** (separate VCS repo, not auto-discovered from here — see "Where AI rules live"
above for why; read and follow these directly by path, not by name):

- creating a new Gutenberg block:
  `web/wp-content/themes/starter-kit-theme/.claude/skills/create-gutenberg-block/SKILL.md`
- converting the theme from FSE to classic PHP templates (keeps Gutenberg/blocks, only the
  page-assembly mechanism changes; block editor becomes per-post-type opt-in):
  `web/wp-content/themes/starter-kit-theme/.claude/skills/convert-to-classic-theme/SKILL.md`
  — runnable any time post-install; `bootstrap-project`'s final report also points to it.
- turning a static HTML design handoff (designer mockup — blog, landing, listing pages) into
  classic PHP templates, reusing existing blocks/repositories/the Page Builder Carbon Fields
  contract instead of reinventing them; requires the theme already classic (post
  `convert-to-classic-theme`):
  `web/wp-content/themes/starter-kit-theme/.claude/skills/create-classic-template/SKILL.md`
- creating a new custom post type:
  `web/wp-content/themes/starter-kit-theme/.claude/skills/create-post-type/SKILL.md`

## Commands

```bash
make install [local|dev|stage|prod]      # First-time setup: secrets → .env → composer → npm → docker → WP
make up [local|dev|stage|prod]           # Start containers (rebuilds .env first)
make down                                # Stop and remove containers + network; all data persists (every volume is a host bind mount)
make restart [local|dev|stage|prod]      # Restart running containers in place (no recreate, no data change)
make recreate [local|dev|stage|prod]     # Rebuild .env then `docker compose up -d --force-recreate`
make core-install                        # Run WP core install script inside the php container (used by CI deploy)
make run <service> [cmd]                 # One-off container run via docker-compose.toolkit.yml (sh/dev/run.sh)
make exec <service> [cmd]                # Exec into a running container (sh/dev/run.sh)
make watch                               # npm watch + BrowserSync for theme development
make lint                                # Lint theme: PHP (PSR-12) + JS — run before committing theme changes
make secret                              # Generate .env.secret from template (skips if it exists)
make env [env]                           # Rebuild root .env from source files only (no docker)
make import dump.sql                     # Import DB from file + run WP search-replace
make export                              # Export DB to file
make replace                             # Run WP search-replace (domain update)
make migrate -s src -d dst               # Migrate DB/files between environments
make log [php|nginx|mariadb|cron]        # Stream container logs
make pma                                 # Launch phpMyAdmin (docker-compose.toolkit.yml)
make mailhog                             # Launch MailHog for email testing
make ssl                                 # Bootstrap/renew Let's Encrypt SSL cert (see config.md)
make local-cert [force]                  # Locally-trusted (mkcert) HTTPS cert for local dev, single- or multi-instance mode (sh/system/local-cert.sh)
make tf [env] [init|plan|apply|destroy]  # Terraform: manage AWS infrastructure (kit-modules/basis)
make ansible [env] [inventory|playbook]  # Ansible: provision servers (kit-modules/basis)
make basis                               # Interactive shell in the IaC container
make monitoring [on|off]                 # Run monitoring-client scenario (alias: make mon)
make proxy [start|stop|logs|deploy env]  # Reverse proxy (Traefik) for multi-instance hosts (kit-modules/proxy)
make db-tunnel [start|stop|status] [port] # Local TCP tunnel to an instance's MariaDB (sh/system/db-tunnel.sh)
make validate-nginx                      # nginx config syntax check (`nginx -t`) in a throwaway container, no stack needed
make docker [build|push|clean] [service] # Build/push/clean Foundation Docker images
make docker-login                        # Registry auth only (ghcr.io) — no build/push
```

## Environment System

Config merges in order (last wins): `config/environment/.env.main` →
`.env.type.{local|dev|stage|prod}` → `.env.type.{env}.override` (optional) → `.env.secret` →
written out as `.env.runtime` (non-secret) and root `.env` (full), by `sh/env/init.sh`.

NEVER edit `.env` or `.env.runtime` directly — both are auto-generated. Edit the source files in
`config/environment/`. Secrets live ONLY in `.env.secret` (not committed, gitignored). Template
with placeholder names: `sh/env/.env.secret.template` — add any new secret's *name* there, never
its value.

## Architecture

```
web/wp-config/wp-config.php     # SOURCE of truth for wp-config.php — tracked in git, reads DB/keys from env vars
web/wp-core/                    # WordPress core, Composer-managed/gitignored — wp-config.php here is a COPY
web/wp-content/
  themes/starter-kit-theme/    # FSE theme (WP_DEFAULT_THEME) — main app code: CPTs, blocks, meta, hooks (separate VCS repo)
  plugins/                     # wpackagist plugins (contact-form-7, redirection, svg-support, wordpress-seo, ...)
kit-modules/                    # Composer-installed sub-projects (each its own VCS repo), git-ignored, licensed — see infrastructure.md
  basis/                        # IaC: Terraform (AWS) + Ansible (servers)
  monitoring-client/             # Ships container logs to Loki (fluent-bit)
  monitoring-server/             # Grafana + Loki server stack (standalone deployable)
  proxy/                         # Traefik reverse proxy for multi-instance hosts — required like the others, active only when APP_MULTI_INSTANCE=1
config/                          # Docker, nginx, php, ssl, cron, environment configs — see config.md
dockerfiles/                     # 8 service images (mariadb, php, nginx, cron, composer, node, certbot, iac) — see docker.md
sh/                              # Shell scripts (never call directly — use make)
.github/workflows/               # CI/CD: job-deploy + job-provision, called by 3 trigger workflows — see ci.md
```

Package sources (`composer.json` `repositories`): wpackagist.org (community plugins),
`solidbunch.github.io/wordpress-core` (WP core mirror), `licensing.starter-kit.io` (licensed
SolidBunch packages: basis, monitoring-client/server, proxy — all required, resolve to real code
once licensed — see `infrastructure.md` for how licensing gates these), and a direct VCS repo for
the theme
(`starter-kit-theme` by default, `WP_DEFAULT_THEME`) — source-installed, so it's a real local git
checkout, not a `dist` tarball.

## Hard Rules

NEVER:

- Commit `.env`, `.env.runtime`, `.env.secret`, `.tfstate`, `.pem`, or any file with credentials
- Edit WordPress core `web/wp-core/` or `vendor/` — they are Composer-managed
- Edit `web/wp-core/wp-config.php` directly — it's overwritten from `web/wp-config/wp-config.php`
  on every `composer install`/`update` (`post-script` → `cp -r web/wp-config/* web/wp-core`).
  Edit the source file in `web/wp-config/`, not the copy
- Hardcode environment-specific values — use `getenv()` or config files
- Run `git push --force` to `main` or `develop`
- Add detailed setup, configuration, CI/CD, or deployment instructions to this repo's root
  `README.MD` — it stays a short overview plus links; detailed documentation lives in the separate
  `starter-kit-docs` repo (https://github.com/solidbunch/starter-kit-docs, published at
  https://starter-kit.io/docs/overview/), and in-repo AI-facing detail lives in `.claude/rules/*`.
  This governs **this repository's own root README only** — it
  does not apply to the per-project `README.md` that `bootstrap-project` Step 7 generates for a
  downstream project, which is expected to be a detailed local-install + CI/CD guide for that
  project's own repo

(Working process and per-language rules: see `workflow.md`, `debug.md`, and the path-scoped rules.)

## Intentional Quirks

- `WP_DISABLE_WP_CRON=1` — cron runs via dedicated cron container, not on HTTP requests
- `AUTOMATIC_UPDATER_DISABLED=1` / `DISALLOW_FILE_EDIT=1` / `DISALLOW_FILE_MODS=1` — all updates
  via Composer; intentional
- Theme uses `dev-develop` branch in the dev environment via `composer run switch-theme-dev`
  (CI-only script), not a stable tag — this is correct
- `kit-modules/` is git-ignored in root — `basis`, `monitoring-client`, `monitoring-server`,
  `proxy` are all required packages that resolve to real code whenever a valid license is
  configured; `proxy` additionally needs `APP_MULTI_INSTANCE=1` to actually activate once
  installed — see `infrastructure.md`. A directory being present doesn't guarantee it's current
  either — check `composer.lock` type (`metapackage` = no valid license) as the source of truth,
  not just what's on disk
- `monitoring-client` is only force-updated from `dist` in CI when `IS_DEMO=true` (demo/showcase
  deployments) — normal deploys use the locked version

## Out of Scope (Do Not Modify)

- `web/wp-core/` — WordPress core (Composer-managed)
- `vendor/` — PHP dependencies (Composer-managed)
- `db-data/` — MariaDB data volume (runtime data)
- `cache/` — build cache (auto-generated)
- `logs/` — runtime logs (read only)
- `.env` / `.env.runtime` — auto-generated from source env files, do not edit directly
