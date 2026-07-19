---
name: bootstrap-project
description: Turns a freshly cloned starter-kit-foundation checkout into a named, running project - renames APP_NAME/APP_TITLE/APP_DOMAIN, optionally repoints the theme, runs make secret/env/install, has the architect sanity-check the result, then refreshes CLAUDE.md/rules via project-brief. Triggers on "bootstrap this project", "start a new project from this template", "initialize new project", or Russian "инициализируй новый проект", "забутстрапи проект", "разверни проект из шаблона". Not for editing an already-running project's config - that's config.md / infrastructure.md territory.
---

# Bootstrap Project — turn the template into *your* project

This runs once, right after `git clone` of `starter-kit-foundation`, before the user has followed
`https://starter-kit.io/docs/overview/` by hand. It automates the pre-project setup that
documentation describes, in the order the real Makefile/env pipeline expects. Do not skip steps
or reorder them — later steps (`make install`) read the files earlier steps write.

## Step 0 — Collect the inputs Claude cannot guess

Ask once, via `AskUserQuestion` (batch what you can), whatever the user didn't already give you:

1. **Project slug** — lowercase, hyphen-safe (e.g. `acme-shop`). Becomes `APP_NAME`.
2. **Project title** — human-readable (e.g. `"Acme Shop"`). Becomes `APP_TITLE`.
3. **Local domain** — default `<slug>.loc` if the user has no preference. Becomes `APP_DOMAIN` in
   `.env.type.local`.
4. **Theme plan** — one of:
   - Keep `starter-kit-theme` as-is for now (skip Step 3 entirely)
   - Fork/rename it — and if so, do they already have a new git remote URL, or should that be
     left as a manual follow-up (Claude never creates/pushes a new remote itself)
5. **FSE or classic templates?** — the theme ships as an FSE (Full Site Editing) block theme by
   default. If the user wants a classic PHP-template theme instead (Gutenberg blocks retained,
   just no longer the page-assembly mechanism — see Step 3.5), note that choice now; it only runs
   after `make install`, once the theme actually exists on disk.
6. **GitHub org/repo for this project**, only if they're setting up CI/CD now — else defer (leaves
   `GITHUB_ORG`/`GITHUB_REPO`/`ROLE_NAME`/Terraform vars untouched, flagged as a later task).

Don't ask about anything you can default sensibly (e.g. domain slug) — ask only what's genuinely
ambiguous. This is meant to feel like one command, not a questionnaire.

## Step 1 — Rename the project (env sources, never generated files)

Edit only source files under `config/environment/` — never `.env` or `.env.runtime` (both
regenerated, see root `CLAUDE.md`):

- `config/environment/.env.main`: `APP_NAME=<slug>`, `APP_TITLE="<title>"`
- `config/environment/.env.type.local`: `APP_DOMAIN=<domain>` (repeat for `dev`/`stage`/`prod`
  only if the user asked to configure those environments now)

If the user gave a GitHub org/repo (Step 0, item 6), also update in `.env.main`: `GITHUB_ORG`,
`GITHUB_REPO`, `ROLE_NAME` (`"<slug>-github-actions-role"` pattern), and the `TF_VAR_sk_*` values
that derive from `APP_NAME` (they auto-interpolate via `${APP_NAME}`, so usually nothing to touch
there directly — just verify). Note this changes Terraform-tracked identifiers — mention to the
user this affects `kit-modules/basis` state per `infrastructure.md`, don't silently assume it's
safe if state already exists.

Do not touch `.env.secret` — untouched by rename, regenerated secrets aren't part of identity.

## Step 2 — Regenerate the derived env files

```bash
make secret        # no-op if .env.secret already exists
make env local      # rebuild .env / .env.runtime from the edited sources, no docker yet
```

Confirm the printed values match what was just edited before moving on.

## Step 3 — Theme fork/rename (only if the user chose this in Step 0)

The theme is a **separate VCS repo**, Composer-installed with `preferred-install: source`
(`composer.json` → `repositories[].type: vcs` entry for `starter-kit-theme`, and
`require.solidbunch/starter-kit-theme`). Renaming it for real means:

1. The user forks/clones `starter-kit-theme` into their own new repository — **Claude does not
   create or push a new git remote itself**; if they don't have the URL yet, stop here and leave
   this as a manual follow-up, pointing at the installation docs.
2. Once a URL exists, Claude updates local references only:
   - `composer.json`: the `vcs` repository `url` → the new repo, and
     `require.solidbunch/starter-kit-theme` → the new package name (must match the new repo's own
     `composer.json` `name`, which the user's fork needs to declare)
   - `config/environment/.env.main`: `WP_DEFAULT_THEME=<new-theme-slug>` (must match the theme
     folder name Composer will install under `web/wp-content/themes/`)
3. Do not attempt to rename identifiers *inside* the theme's own code (text domain, function
   prefixes, block namespaces) — that's the theme repo's own concern, out of scope here, and
   belongs in that repo's own `CLAUDE.md`/`AGENTS.md` if it needs automating later.

## Step 4 — Install

Confirm with the user before running (it builds/starts Docker containers):

```bash
make install [local]
```

Then remind them: if `APP_DOMAIN` isn't a `.localhost` domain, add it to `/etc/hosts`
(`127.0.0.1 <domain>`). Admin credentials print in the terminal and land in
`config/environment/.env.secret`.

## Step 4.5 — FSE-to-classic conversion (only if the user chose this in Step 0)

Skip entirely if the user kept the default FSE theme. Runs only after Step 4 — the theme doesn't
exist on disk until Composer installs it, and this conversion edits the theme's own files.

The capability lives in the theme repo, not here — it is **not auto-discovered** from this
foundation session (skill auto-discovery is project-root-only, same caveat as rules). The theme's
actual folder name is whatever `WP_DEFAULT_THEME` (`config/environment/.env.main`) currently holds
— `starter-kit-theme` unless Step 3 renamed it. Read and follow
`web/wp-content/themes/<WP_DEFAULT_THEME>/.claude/skills/convert-to-classic-theme/SKILL.md`
directly, substituting the real value.

## Step 5 — Architect review

Run the `architect` agent to sanity-check the result: does `.env.main`/`.env.type.local` actually
match what was requested, are `composer.json` and `WP_DEFAULT_THEME` consistent with each other if
Step 3 ran, is anything left half-edited. This is a config/wiring review, not a feature plan — say
so explicitly in the agent prompt so it doesn't look for a task board. If Step 4.5 ran, its own
`convert-to-classic-theme` skill already ran its own architect pass over the theme-internal
changes — this step only needs to cover the foundation-level env/composer wiring, not repeat the
theme review.

## Step 6 — Refresh AI guidelines

Invoke the `project-brief` skill to re-scan the now-renamed project and update root `CLAUDE.md` /
`.claude/rules/` — project name/title, domain, and (if changed) the theme's identity need to be
reflected so future sessions don't describe the old template identity. If Step 4.5 ran, its own
skill already handed off to `project-brief` for the theme's own docs (classic-theme rule,
`content-types.md`/`architecture.md` edits) — this step covers the foundation repo's own
`CLAUDE.md`/rules, not a second pass over the theme.

## Step 7 — Report

List every changed file with its full path. Separate clearly:

- **Done automatically**: env rename, regenerated `.env`, install, guideline refresh
- **Left for the user**: new theme repo creation (if deferred), `/etc/hosts` edit, GitHub
  repo/CI secrets setup, `kit-modules` licensing (see `infrastructure.md`) — anything this skill
  couldn't do without an external-system action

Never commit anything in this flow — leave the diff for the user to review and commit themselves.
