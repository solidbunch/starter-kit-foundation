---
name: bootstrap-project
description: Turns a freshly cloned starter-kit-foundation checkout into a named, running project - renames APP_NAME/APP_TITLE/APP_DOMAIN, optionally renames the theme via its own clone-theme CLI, sanity-checks the edits, then runs make secret/env/install and refreshes CLAUDE.md/rules via project-brief. Triggers on "bootstrap this project", "start a new project from this template", "initialize new project", or Russian "инициализируй новый проект", "забутстрапи проект", "разверни проект из шаблона". Not for editing an already-running project's config - that's config.md / infrastructure.md territory.
---

# Bootstrap Project — turn the template into *your* project

This runs once, right after `git clone` of `starter-kit-foundation`, before the user has followed
`https://starter-kit.io/docs/overview/` by hand. It automates the pre-project setup that
documentation describes, in the order the real Makefile/env pipeline expects. Do not skip steps
or reorder them — later steps (`make install`, theme rename) read the files earlier steps write.

## Step 0 — Collect the inputs Claude cannot guess

Ask once, via `AskUserQuestion` (batch what you can), whatever the user didn't already give you:

1. **Project slug** — lowercase, hyphen-safe (e.g. `acme-shop`). Becomes `APP_NAME`.
2. **Project title** — human-readable (e.g. `"Acme Shop"`). Becomes `APP_TITLE`.
3. **Local domain** (required) — default `<slug>.loc` if the user has no preference. Becomes
   `APP_DOMAIN` in `.env.type.local`.
   **Dev/stage/prod domains** (optional) — ask, but let the user decline/skip; if skipped, leave
   those environments untouched (not needed until actually provisioned).
4. **Theme name** — keep `starter-kit-theme` as-is (skip Step 6), or rename it: new theme slug
   (folder name), display name, and package label. This is a cosmetic rename only — the theme's
   internal PHP namespace, hook/settings prefixes, and REST API namespace stay unchanged unless
   the user explicitly asks for a deeper rename too (see Step 6).

Don't ask about anything you can default sensibly (e.g. domain slug) — ask only what's genuinely
ambiguous. This is meant to feel like one command, not a questionnaire.

## Step 1 — Rename the project (env sources, never generated files)

Edit only source files under `config/environment/` — never `.env` or `.env.runtime` (both
regenerated, see root `CLAUDE.md`):

- `config/environment/.env.main`: `APP_NAME=<slug>`, `APP_TITLE="<title>"`
- `config/environment/.env.type.local`: `APP_DOMAIN=<domain>` (repeat for `.env.type.dev`/
  `.env.type.stage`/`.env.type.prod` for any environment the user gave a domain for in Step 0)

`GITHUB_ORG`/`GITHUB_REPO`/`ROLE_NAME`/Terraform vars in `.env.main` are **out of scope for this
skill** — leave them untouched. They only matter for CI/CD and Terraform infra (`kit-modules/basis`),
which is a separate task the user can ask for by name later; `infrastructure.md`/`ci.md` cover that
ground when it comes up.

Do not touch `.env.secret` — untouched by rename, regenerated secrets aren't part of identity.

## Step 2 — Regenerate the derived env files

```bash
make secret        # no-op if .env.secret already exists
make env local      # rebuild .env / .env.runtime from the edited sources, no docker yet
```

Confirm the printed values match what was just edited before moving on.

## Step 3 — Sanity check (before install)

Before running `make install`, re-read `config/environment/.env.main`/`.env.type.local` (and any
other `.env.type.*` touched) and confirm they match what was requested in Step 0, nothing left
half-edited. This is just re-reading the small set of files this skill itself just wrote — no
agent needed.

## Step 4 — Install

Confirm with the user before running (it builds/starts Docker containers):

```bash
make install [local]
```

Then remind them: if `APP_DOMAIN` isn't a `.localhost` domain, add it to `/etc/hosts`
(`127.0.0.1 <domain>`). Admin credentials print in the terminal and land in
`config/environment/.env.secret`.

## Step 5 — Theme rename (only if the user chose this in Step 0)

The theme ships its own WP-CLI command for this: `wp clone-theme`. It copies the active theme's
folder to a new slug and search-replaces 7 identifiers throughout the copy (skipping images,
`node_modules`, `vendor`). It needs a running, installed WordPress with the current theme active —
that's why this step runs after Step 4, not before.

Read the theme's current values first (they may differ from the defaults below if this project was
already renamed once): `web/wp-content/themes/<current-slug>/config/common/main.php` → `themeName`,
`package`, `themeSlug`, `themeNamespace`, `hooksPrefix`, `settingsPrefix`, `restApiNamespace`.

Run it non-interactively — it's a plain sequence of stdin prompts, one value per line, in this
exact order. Reuse the current values from `config/common/main.php` for the last four lines to
keep this a **cosmetic-only rename** (only change theme name / package / slug), unless the user
explicitly asked for the internal PHP namespace and prefixes to change too:

```bash
docker compose exec -T --user www-data php wp clone-theme <<'EOF'
<new theme display name>
<new package label>
<new-theme-slug>
<themeNamespace — unchanged unless asked>
<hooksPrefix — unchanged unless asked>
<settingsPrefix — unchanged unless asked>
<restApiNamespace — unchanged unless asked>
EOF
```

Then:

1. Activate it: `docker compose exec -T --user www-data php wp theme activate <new-theme-slug>`
2. Update `config/environment/.env.main`: `WP_DEFAULT_THEME=<new-theme-slug>`, then `make env local`
   to regenerate `.env`/`.env.runtime` so build scripts target the new theme folder.
3. The new folder is a **plain local copy — not Composer-managed**. The old
   `web/wp-content/themes/<old-slug>/` directory is untouched on disk, and root `composer.json`'s
   `require.solidbunch/starter-kit-theme` still points at it. Don't silently delete the old folder
   or edit that `composer.json` entry — flag both as a manual decision for the user in Step 8
   (removing/repointing it affects `composer.lock` state).
4. Grep the new theme's own guides for leftover references to the old slug/package name and fix
   any hits directly (plain find-and-replace) — it's a normal file edit in this working copy, the
   theme having its own git remote doesn't change that:
   `grep -rn <old-slug> web/wp-content/themes/<new-slug>/CLAUDE.md
   web/wp-content/themes/<new-slug>/blocks/CLAUDE.md web/wp-content/themes/<new-slug>/.claude/`.
   List these edits separately in the Step 8 report since they land in a different repo's working
   tree than the rest of the bootstrap changes.

## Step 6 — Refresh AI guidelines

Invoke the `project-brief` skill to re-scan the now-renamed project and update root `CLAUDE.md` /
`.claude/rules/` — project name/title, domain, and (if changed) the theme's identity need to be
reflected so future sessions don't describe the old template identity.

## Step 7 — Report

List every changed file with its full path. Separate clearly:

- **Done automatically**: env rename, regenerated `.env`, install, theme rename (if it ran),
  guideline refresh
- **Left for the user**: `/etc/hosts` edit, GitHub repo/CI secrets setup, `kit-modules` licensing
  (see `infrastructure.md`), the orphaned old theme folder + `composer.json` entry (if Step 5 ran)
  — anything this skill couldn't do without an external-system action or a destructive decision

Also mention: the theme ships as FSE (Full Site Editing) by default. If the user wants classic
PHP templates instead (Gutenberg blocks retained, only the page-assembly mechanism changes), point
them at `web/wp-content/themes/<WP_DEFAULT_THEME>/.claude/skills/convert-to-classic-theme/SKILL.md`
— runnable any time now that the theme exists on disk, not something this skill needs to gate on.

Never commit anything in this flow — leave the diff for the user to review and commit themselves.
