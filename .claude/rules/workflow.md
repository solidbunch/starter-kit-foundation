# Workflow — how to work on this project

This is a mature codebase with strong conventions. Follow them — do not invent.

## Before writing code

- Read the relevant existing files first — never assume structure
- If unsure about a pattern, open the nearest similar file and copy its approach
- Verify which repo/branch you are in: theme and addon are separate VCS repos with their own
  git state; the dev environment tracks the theme's `dev-develop` branch

## Scope control

- Implement only what was asked — nothing more
- If you spot something broken outside the current scope — report it, do not silently fix it
- One task = one commit-ready change
- State explicitly any assumption you made about the codebase

## Before committing

- Run `make lint` (PSR-12 PHP + JS) before committing theme or addon changes
- No `TODO` / `FIXME` and no debug output in committed code (see `debug.md`)
- Add any new secret variable name to `sh/env/.env.secret.template` (value stays out of git)
- Test in the `local` environment before pushing to `dev`
- Never hardcode environment-specific values — use `getenv()` / config files
