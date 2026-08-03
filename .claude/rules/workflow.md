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

## Git flow

- `develop` is the integration branch — it drives the `dev` environment (auto-deployed on push,
  see `ci.md`). `main` is the release branch — it drives `prod` (manual deploy only)
- All feature/fix branches are created from `develop`, and merge back into `develop`
- Releases go `develop` → `main` (merge or fast-forward) once `develop` has been verified on `dev`
- Never branch a feature from `main` — that causes `develop`/`main` divergence and duplicate
  merges. The only exception is a `hotfix/*` branch cut from `main` for a prod-only emergency fix,
  merged back into both `main` and `develop`
- Never `git push --force` to `main` or `develop` (see Hard Rules in the root `CLAUDE.md`)

## Scope control

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
