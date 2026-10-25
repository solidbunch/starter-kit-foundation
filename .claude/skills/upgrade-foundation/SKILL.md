---
name: upgrade-foundation
description: Updates a downstream project (built from starter-kit-foundation) to a newer foundation version - adds the foundation remote, diffs against the target tag, applies foundation-owned files, keeps project-owned config. Run manually via /upgrade-foundation, inside the downstream project only.
---

# Upgrade Foundation — update a downstream project

Run this inside a **downstream project** checkout, never inside `starter-kit-foundation` itself.
Foundation versions are git tags on `https://github.com/solidbunch/starter-kit-foundation`
(tag naming not verified — list them in Step 1 and use what exists).

Nothing here is automated end to end: show each diff to the user before applying it, and do not
commit or push unless asked. Never touch `vendor/`, `web/wp-core/`, `.env`, `.env.runtime`,
the theme repo, or `kit-modules/` — they are not part of a foundation upgrade.

## Step 0 — Preconditions and safety (ask once, batched)

Ask the user in one go: the **target** (a foundation tag — preferred — or `main`), and whether
the project shares git history with foundation (cloned/forked) or was created from a GitHub
template copy (no shared history; if unsure, Step 2 detects it).

1. `git status` must be clean. If not, ask the user to commit or stash first.
2. Work on a dedicated branch: `git switch -c upgrade/foundation-<target>`. Rollback = switch back
   to the previous branch.
3. Database backup — needed before any version change of MariaDB:
   - `make export` writes a dump into `./tmp` (name has a date and time suffix); note the path.
   - To also keep `db-data/`, stop the stack first (copying a live MariaDB data directory can give
     an inconsistent copy). Do **not** use `make down` for this step — it runs `down -v`
     (harmless for the bind-mounted data here, but it is not a stop-only command); use
     `docker compose stop`.
4. Remember the restore path and tell the user: previous branch + the old image tags +
   the `db-data/` copy. A MariaDB version change cannot be undone once the new server has started
   on the data without that copy.

## Step 1 — Add the foundation remote

```bash
git remote get-url foundation 2>/dev/null || git remote add foundation git@github.com:solidbunch/starter-kit-foundation.git
git fetch foundation --tags
git tag -l --sort=-v:refname | head
```

## Step 2 — Find what changed

Detect whether history is shared:

```bash
git merge-base HEAD foundation/main    # empty output or an error = no shared history
```

- **Shared history:** the merge-base is the base. List changes with
  `git diff --name-status <base> <target>` (watch the `D` and `R` entries — deleted and renamed
  files) and read `git log --no-merges --format='%h %s' <base>..<target>`.
- **No shared history:** make a read-only checkout of the target next to the project and compare
  by path:
  ```bash
  git worktree add ../foundation-<target> foundation/<target>   # a tag also works: <target>
  diff -rq ../foundation-<target> . --exclude=.git --exclude=vendor --exclude=web/wp-core \
    --exclude=db-data --exclude=kit-modules --exclude=logs --exclude=cache --exclude=tmp
  diff -u ../foundation-<target>/<path> ./<path>      # per file
  ```
  The differences include the project's own changes — tell the user which side each difference
  comes from only if it is clear; otherwise ask. Remove the worktree at the end
  (`git worktree remove ../foundation-<target>`).

## Step 3 — Apply by ownership

**Foundation-owned (take the foundation version; show the diff first, the project may have
customised it):**
`docker-compose*.yml`, `dockerfiles/`, `sh/`, `Makefile`, `config/nginx/`, `config/php/`,
`config/cron/`, `config/certbot/`, `.github/workflows/`, `.gitlab-ci.yml`, `.gitlab/ci/`,
`web/wp-config/wp-config.php`, `.claude/rules/`, and foundation's own skills under
`.claude/skills/` (`bootstrap-project`, `check-wordpress-docker-image`, `upgrade-foundation`).
Apply file by file; do **not** delete files the project added (its own rules or skills).
`config/ssl/` holds certificates and is project-owned (see below).

**Mixed — merge by hand, keep the project's values:**
- `config/environment/.env.main` — take new `APP_*_IMAGE` tags and new variables. Keep what
  `bootstrap-project` set for the project: `APP_NAME`, `APP_TITLE`, `WP_DEFAULT_THEME`,
  `GITHUB_ORG`, `GITHUB_REPO`, `ROLE_NAME`, and any `TF_VAR_*` value the project changed.
  Taking foundation's values for these breaks CI roles and Terraform state.
- `config/environment/.env.type.*` — project-owned values, but foundation may add **new
  variables** there: diff against foundation's version and add new names only.
- `sh/env/.env.secret.template` — foundation-owned; new variable *names* in it must be added to
  the project's own `.env.secret` by the user (see Step 4).
- `composer.json` — foundation may change package sources or constraints; merge by hand, keep
  the project's own requirements. After applying, check `composer.lock` for the kit-modules:
  type `metapackage` means no valid license (see `.claude/rules/infrastructure.md`).
- `CLAUDE.md`, `README.md` — project-specific; port only relevant changes.

**Project-owned (never overwrite):** `.env.secret`, the theme, `db-data/`, `kit-modules/`,
`config/ssl/`, `.claude/qa-login.json` (bootstrap sets the project URL there), project-added
files under `.claude/`.

Apply foundation-owned files with `git checkout <target> -- <path>` (shared history) or by
copying from the worktree (no shared history). For shared history prefer
`git merge --no-commit --no-ff <target>` over a plain merge, then resolve conflicts by ownership
above and leave the result uncommitted for the user. After applying, handle every `D` and `R`
entry from Step 2 explicitly — checkout and copy do not remove files foundation deleted or
renamed. If unsure about a file, say so and ask.

## Step 4 — Version-specific steps

Read the changes and walk the user through whichever of these apply:

- **Image tags changed** (`APP_*_IMAGE` in `.env.main`): each tag must exist in `ghcr.io`
  (check, e.g. `docker manifest inspect <image>`; pulling needs `make docker-login` with
  `CR_TOKEN`). If the project builds images itself, use `make docker build` / `make docker push`.
  A host re-pulls only a **new** tag, never an existing one — if a tag did not change, a changed
  image behind it is not picked up.
- **MariaDB server version changed — any `x.y.z`, including a patch bump:** an image with the
  version guard (`dockerfiles/mariadb/docker-entrypoint.d/10-version-guard.sh`) refuses to start
  when the server version differs from `db-data/mariadb_upgrade_info`. After
  `make recreate <env>` the database container will crash-loop (`restart: unless-stopped`);
  that is expected. Read the reason with `make log mariadb`. To upgrade, start once with
  `MARIADB_AUTO_UPGRADE=1` (the official entrypoint backs up first), then remove it again. The
  guard is described in `.claude/rules/docker.md` ("MariaDB version guard"); the upgrade steps are
  in `https://github.com/solidbunch/starter-kit-docs/blob/main/database-management.md`.
  Where to set the variable so it reaches the container is **not verified**: compose passes it to
  the service, and the service reads `.env.runtime` (built from the non-secret env files, not from
  `.env.secret`) — check `docker-compose.yml` and the docs before telling the user which file.
  An image without the guard starts on old data without running `mariadb-upgrade`.
- **CI files changed** (`.github/workflows/`, `.gitlab/ci/`): list new `secrets.*` / `vars.*`
  (or CI/CD variables) the files reference that the project has not configured; keep
  project-specific values. For a local check use `make localci` only — never call `act` directly.
- **New secret variable names** in `sh/env/.env.secret.template`: tell the user to add them to
  their own `.env.secret` (never overwritten by this skill).
- **`web/wp-config/wp-config.php` changed:** it is copied to `web/wp-core/` on `composer
  install`/`update` — run Composer through the container after applying.
- **`config/nginx/` changed:** run `make validate-nginx`.

## Step 5 — Rebuild and verify

```bash
make env local        # regenerate .env from the source files
make recreate local
make log              # check mariadb, php, nginx
```

Open the site and wp-admin. Then roll out in the project's normal order: `dev` first, `prod` last
(prod is a manual deploy; a MariaDB version change on prod has the same irreversibility as local —
back up first).

## Final report

Always end with:
- every changed file, with its **full path**;
- steps skipped and why;
- anything not verified (for example the MariaDB env-variable location);
- what the user must do next (new secrets, MariaDB upgrade, dev rollout).

Do not commit unless asked.
