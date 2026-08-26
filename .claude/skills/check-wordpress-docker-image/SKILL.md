---
name: check-wordpress-docker-image
description: Checks the official docker-library/wordpress Dockerfile for drift against this repo's dockerfiles/php/Dockerfile (base image tag, wp-cli image tag, extension versions like IMAGICK_VERSION, apk build-deps) and applies the safe mechanical fixes directly. Triggers on "check for WordPress docker image updates", "sync php Dockerfile with upstream", "is our php image up to date", "check docker image drift". Does not touch any other file, and does not commit — leaves changes in the working tree for review.
---

# Check WordPress Docker image — sync `dockerfiles/php/Dockerfile` with upstream

`dockerfiles/php/Dockerfile` is a heavily customized derivative of the official
`docker-library/wordpress` image (Xdebug, healthcheck ping path, custom entrypoint — none of that
exists upstream, don't try to diff those parts). Nothing tracks upstream drift automatically; this
skill is the on-demand check. Run it whenever asked to check for updates — there's no fixed
schedule, this is a manual/on-request tool, not automation.

## Step 1 — Read our current state

Read `dockerfiles/php/Dockerfile`. Note:

- The base image tag (`FROM php:X.Y-fpm-alpineZ.ZZ`) — this determines which upstream path to
  compare against (see Step 2).
- `IMAGICK_VERSION` — the one pinned extension version that has a direct upstream counterpart
  (upstream's own `pecl install imagick-<version>` line). `XDEBUG_VERSION` has no upstream
  equivalent at all — Xdebug isn't part of the official image, it's our own addition — so there's
  nothing to diff it against here; leave it alone.
- The `wordpress:cli-*` image tag used for the WP-CLI `COPY --from=`.
- The full `apk add --no-cache --virtual .build-deps` package list.

## Step 2 — Fetch the upstream Dockerfile

Upstream path pattern: `docker-library/wordpress`, file
`latest/php<X.Y>/fpm-alpine/Dockerfile` (e.g. `latest/php8.4/fpm-alpine/Dockerfile` for PHP 8.4).
Fetch the raw content:

```bash
curl -s "https://raw.githubusercontent.com/docker-library/wordpress/master/latest/php<X.Y>/fpm-alpine/Dockerfile"
```

If PHP minor version doesn't match a directory that exists upstream (e.g. we're ahead of what
`docker-library/wordpress` has published), say so explicitly rather than guessing a fallback path.

Also check the current `wordpress:cli-*` tags via the Docker Hub API to confirm the WP-CLI image
tag we reference is still current:

```bash
curl -s "https://hub.docker.com/v2/repositories/library/wordpress/tags?page_size=100&name=cli-php<X.Y>"
```

## Step 3 — Compare and classify

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

## Step 4 — Apply and report

Apply only the "safe" changes to `dockerfiles/php/Dockerfile`, in the working tree. **Do not
commit** — per this project's workflow, changes are left for the user to review and commit
themselves (see `workflow.md`).

Report back:
- What was changed, with the specific line(s).
- What was found but left for manual review, and why.
- A reminder that per `docker.md`, editing this Dockerfile has no runtime effect anywhere until
  someone runs `make docker build php` + `make docker push php` and updates `APP_PHP_IMAGE` in
  `config/environment/.env.main` — this skill only updates the recipe, not the published image.

## Out of scope

- No git commit, no PR, no CI workflow — this is a manual, on-request check only.
- Don't touch any file other than `dockerfiles/php/Dockerfile`.
- Don't attempt to rebuild or push the image — that's `docker.md`'s territory, and always a
  separate, explicit, manual step.
