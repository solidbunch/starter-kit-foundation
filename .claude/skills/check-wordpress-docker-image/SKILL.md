---
name: check-wordpress-docker-image
description: Checks the official docker-library/wordpress Dockerfile for drift against this repo's dockerfiles/php/Dockerfile (base image tag, wp-cli image tag, extension versions like IMAGICK_VERSION, apk build-deps), and separately checks whether our PHP version is still officially supported by our WordPress version per make.wordpress.org's compatibility table. Triggers on "check for WordPress docker image updates", "sync php Dockerfile with upstream", "is our php image up to date", "check docker image drift", "is our PHP version still supported by WordPress". Discovers real upstream paths and data via API/fetch — never assumes a URL pattern still holds. Does not touch any other file, and does not commit — leaves changes in the working tree for review.
---

# Check WordPress Docker image — sync `dockerfiles/php/Dockerfile` with upstream

`dockerfiles/php/Dockerfile` is a heavily customized derivative of the official
`docker-library/wordpress` image (Xdebug, healthcheck ping path, custom entrypoint — none of that
exists upstream, don't try to diff those parts). Nothing tracks upstream drift automatically; this
skill is the on-demand check. Run it whenever asked to check for updates — there's no fixed
schedule, this is a manual/on-request tool, not automation.

**Discover, don't guess.** Every URL/path below is confirmed to exist via an API call or a real
fetch before you rely on its content — a directory listing, a fetched page, a JSON response. Never
hand-construct a path from a remembered pattern and fetch it blind; upstream repo layouts and doc
pages change, and a `curl` that happens to 200 on a stale guess is not the same as having actually
looked. If a discovery step comes back empty, differently shaped than expected, or 404s, say so
explicitly and stop rather than falling back to a guessed path.

## Step 1 — Read our current state

Read `dockerfiles/php/Dockerfile`. Note:

- The base image tag (`FROM php:X.Y-fpm-alpineZ.ZZ`) — the `X.Y` drives Step 2's discovery.
- `IMAGICK_VERSION` — the one pinned extension version that has a direct upstream counterpart
  (upstream's own `pecl install imagick-<version>` line). `XDEBUG_VERSION` has no upstream
  equivalent at all — Xdebug isn't part of the official image, it's our own addition — so there's
  nothing to diff it against here; leave it alone.
- The `wordpress:cli-*` image tag used for the WP-CLI `COPY --from=`.
- The full `apk add --no-cache --virtual .build-deps` package list.

Also read `composer.lock`, the `solidbunch/wordpress-core-no-content` package's `version` field —
this is our actual current WordPress version, needed for Step 3. Don't assume it from
`composer.json`'s version constraint; the lock file is the resolved truth.

## Step 2 — Discover and fetch the upstream Dockerfile

Don't assume `latest/php<X.Y>/fpm-alpine/Dockerfile` exists just because it did last time. Confirm
it via the GitHub Contents API, one directory level at a time:

```bash
# What PHP versions does upstream actually publish right now?
curl -s "https://api.github.com/repos/docker-library/wordpress/contents/latest"

# Does our X.Y appear in that listing? If not, stop and report it — we're ahead of or behind
# what upstream has, don't fall back to a nearby version silently.

# Given it does, what variants exist for that PHP version?
curl -s "https://api.github.com/repos/docker-library/wordpress/contents/latest/php<X.Y>"

# Confirm fpm-alpine/Dockerfile is actually a file in that listing, then fetch it:
curl -s "https://raw.githubusercontent.com/docker-library/wordpress/master/latest/php<X.Y>/fpm-alpine/Dockerfile"
```

Also confirm the current `wordpress:cli-*` tags via the Docker Hub API (this is already a real
query, not a guess — keep it that way):

```bash
curl -s "https://hub.docker.com/v2/repositories/library/wordpress/tags?page_size=100&name=cli-php<X.Y>"
```

## Step 3 — Check PHP/WordPress compatibility (separate from Dockerfile drift)

This is a distinct check from Step 2/4 below — it's not about our Dockerfile lagging upstream's
recipe, it's about whether our PHP version is still one WordPress itself officially supports for
the WordPress version we run. A Dockerfile can be perfectly in sync with upstream and still be
running a PHP version WordPress has dropped, or one WordPress hasn't added support for yet.

Fetch the compatibility matrix:

```
https://make.wordpress.org/core/handbook/references/php-compatibility-and-wordpress-versions/
```

It's a table: rows are WordPress versions, columns are PHP versions, cells are `Y`/`N`. Find the
row for the WordPress version from Step 1 (`composer.lock`'s resolved version). If that exact
version isn't a row (e.g. we're on a patch release not individually listed), use the nearest
listed minor/major row and say so explicitly in the report rather than silently picking one. Check
the column for our PHP `X.Y` (from Step 1's `FROM` line):

- **Y** — supported, nothing to report here.
- **N**, or our PHP version doesn't appear as a column at all (too new for this table, or long
  since dropped) — report this clearly, separately from any Dockerfile drift findings. This is a
  compatibility finding, not a mechanical fix — never "apply" anything for it, it always needs a
  human decision (bump WordPress, or don't move to that PHP version yet).

## Step 4 — Compare and classify (Dockerfile drift)

Diff conceptually (not a literal file diff — the files have very different structure because of
our customizations). For each difference, classify:

**Safe — apply directly:**
- Version-string bumps: `IMAGICK_VERSION` (upstream's `pecl install imagick-<version>`),
  base PHP image tag, `wordpress:cli-*` image tag.
- `apk` build-dep package additions or removals that mirror upstream's list 1:1 (e.g. upstream
  added a new `-dev` package to its `apk add --virtual .build-deps` block).

**Needs human review — do NOT apply, report instead:**
- Anything restructuring build logic, adding/removing build stages, or touching
  security-relevant behavior.
- Anything in upstream that has no clear 1:1 equivalent in our customized structure.

## Step 5 — Apply and report

Apply only the "safe" changes from Step 4 to `dockerfiles/php/Dockerfile`, in the working tree.
**Do not commit** — per this project's workflow, changes are left for the user to review and
commit themselves (see `workflow.md`).

Report back, as two clearly separated sections:
- **Dockerfile drift**: what was changed (with specific lines), what was found but left for manual
  review and why, and a reminder that per `docker.md`, editing this Dockerfile has no runtime
  effect anywhere until someone runs `make docker build php` + `make docker push php` and updates
  `APP_PHP_IMAGE` in `config/environment/.env.main` — this skill only updates the recipe, not the
  published image.
- **PHP/WordPress compatibility** (Step 3's result): supported, or flagged with the specific
  WordPress row and PHP column that triggered it.

## Step 6 — If a newer PHP major/minor exists upstream, propose a plan — never apply it

Step 2's discovery may turn up a PHP version upstream that's newer than ours (e.g. `php8.5` exists
alongside `php8.4`). Bumping the PHP version itself is a fundamentally different kind of change
from Step 4's mechanical drift fixes — it's not "our recipe fell behind upstream's same recipe,"
it's "we'd be changing what we build entirely," and it fans out across files this skill doesn't
touch, some of them outside this repo. Never apply any of this — only lay out the plan in the
report, as its own section, so whoever reads it knows exactly what a real bump would involve.

Discover the actual current state of each of these before writing the plan — don't recite this
list from memory, re-`grep` it every time, file paths and contents can have moved:

1. `dockerfiles/php/Dockerfile` — `FROM php:X.Y-fpm-alpineZ.ZZ`. Confirm what Alpine version
   upstream pairs with the new PHP version (Step 2's discovery) — it's often not the same Alpine
   tag as before.
2. `composer.json`'s `"php"` platform requirement (root of this repo).
3. `config/environment/.env.main`'s `APP_PHP_IMAGE` — this points at an **already-built, already-
   pushed** image tag; changing the Dockerfile alone does nothing until a new image is built and
   pushed under a new tag and this variable is updated to match (see `docker.md`'s tag convention:
   a base-version change resets the `-rN` content-revision suffix, it doesn't increment it).
4. `dockerfiles/composer/Dockerfile` — no direct version reference, it builds `FROM ${APP_PHP_IMAGE}`,
   so it follows automatically once (3) is updated. Still worth confirming this is still true (it
   could change) rather than asserting it from this doc.
5. `.gitlab-ci.yml`'s `APP_COMPOSER_IMAGE` (or wherever the GitLab pipeline pins a PHP-tagged
   image) — grep for the current PHP version string across `.gitlab-ci.yml` and `.gitlab/ci/**`,
   don't assume only one line references it.
6. `web/wp-content/themes/<theme>/composer.json`'s `"php"` requirement — **this is a separate git
   repository** (see the root `CLAUDE.md`'s "Where AI rules live" section), not something this
   skill or a foundation-only session can edit as part of the same change. Flag it as "needs its
   own PR in the theme repo," don't attempt to touch it even if the working checkout happens to
   have it present locally.
7. Any other custom plugin, `kit-modules/`-style module, or WordPress-content package this
   particular project has added on top of the base stack may carry its own `"php"` (or similar)
   version constraint too — don't assume the list above is exhaustive for every project. Say so in
   the plan as a general caution, and actually check whatever custom code this specific project
   has (its own plugins, its own modules) rather than skipping this because it's not enumerable in
   advance.
8. Re-run this skill's own Step 4 logic once conceptually against the *new* target PHP version's
   upstream Dockerfile — a version bump usually brings its own build-dep changes on top of the
   ones already found for the current version, and those should be folded into the same plan
   rather than discovered twice.

Report this as an explicit, ordered checklist (which files, in what order, and the note about the
theme repo needing its own separate change) — never as an applied diff. Per `docker.md`, also flag
that the actual cutover is gated on `make docker build php` + `make docker push php` under the new
tag, tested before `APP_PHP_IMAGE` is repointed at it.

## Out of scope

- No git commit, no PR, no CI workflow — this is a manual, on-request check only.
- Don't touch any file other than `dockerfiles/php/Dockerfile`, and even there, only for Step 4's
  mechanical drift fixes — never for a Step 6 PHP version bump.
- Don't attempt to rebuild or push the image — that's `docker.md`'s territory, and always a
  separate, explicit, manual step.
- Never auto-apply anything from the Step 3 compatibility check or the Step 6 version-bump plan —
  both always need a human call, and Step 6 spans files this skill doesn't touch at all.
