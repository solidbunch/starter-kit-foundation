# Workflow — how to work on this project

This is a mature codebase with strong conventions. Follow them — do not invent.

## Before writing code

- Read the relevant existing files first — never assume structure
- If unsure about a pattern, open the nearest similar file and copy its approach
- `starter-kit-theme` is a separate VCS repo with its own git state, source-installed via
  Composer VCS repository; the dev environment tracks its `dev-develop` branch (switched by the
  CI-only `composer run switch-theme-dev` script, not manually)
- `kit-modules/basis`, `kit-modules/monitoring-client`, `kit-modules/monitoring-server` are
  Composer-installed, git-ignored, and simply absent until installed — don't assume they exist
  on disk without checking

## Before changing the database

- Run `make export` to back up the database before making any changes that touch it — schema
  changes, migrations, direct SQL, bulk data edits, **and** any content change made through the
  wp-admin UI/browser (posts, pages, media, taxonomy terms, options, or any other content) —
  dumps are written to `./tmp` with a date+time suffix (`sh/database/export.sh`), so repeated
  backups on the same day don't overwrite each other

## Scope control

- Never reset a real WordPress user's password (`wp user update <user> --user_pass=...`) without
  explicit permission in chat first — even for legitimate testing needs, ask before overwriting a
  live account's credentials, don't act then report
- Implement only what was asked — nothing more
- If you spot something broken outside the current scope — report it, do not silently fix it
- One task = one commit-ready change
- State explicitly any assumption you made about the codebase

## Before committing

- Run `make lint` (PSR-12 PHP + JS) before committing theme changes
- No `TODO` / `FIXME` and no debug output in committed code (see `debug.md`)
- Add any new secret variable *name* to `sh/env/.env.secret.template` (value stays out of git)
- Test in the `local` environment before pushing to `dev`
- Never hardcode environment-specific values — use `getenv()` / config files
