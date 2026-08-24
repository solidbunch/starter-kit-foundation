---
paths:
  - "docker-compose*.yml"
  - "dockerfiles/**"
  - "sh/system/docker.sh"
  - "sh/system/install.sh"
  - "sh/system/certbot.sh"
---

# Docker stack

Never call `docker`/`docker compose`/`docker buildx` directly for project lifecycle tasks —
always go through `make` (see root `CLAUDE.md` commands table). Direct `docker compose` is fine
only for one-off inspection (`docker compose ps`, `docker compose logs -f <svc>` — though
`make log` already wraps the latter).

## Two compose files

- `docker-compose.yml` — the **always-running** app stack: `mariadb`, `php`, `nginx`, `cron`.
  Started by `make up` / `make install`.
- `docker-compose.toolkit.yml` — **on-demand, one-shot** containers, run with `--rm` and never
  left running: `composer`, `node`, `phpmyadmin`, `certbot`, `mailhog`, `iac`. Invoked by
  `make lint`, `make pma`, `make mailhog`, `make ssl`, `sh/system/install.sh`, `sh/system/certbot.sh`,
  and the Terraform/Ansible wrappers in `kit-modules/basis/sh/`.

## Images — `dockerfiles/<service>/`

Eight images, each built from `dockerfiles/<service>/Dockerfile`, versioned in
`config/environment/.env.main` as `APP_<SERVICE>_IMAGE` and published to
`ghcr.io/solidbunch/starter-kit-<service>`:

| Service | Base | Notes |
|---|---|---|
| `mariadb` | `mariadb:11.5.2-noble` | + `pv` for dump progress |
| `php` | `php:8.4-fpm-alpine3.24` | + WP-CLI (copied from `wordpress:cli` image), Xdebug, Imagick, GD w/ AVIF/WebP; UID/GID remap in entrypoint |
| `nginx` | `nginx:1.29-alpine3.23` | + Basic Auth setup script (`15-setup-basic-auth.sh`) — 3.23 is the newest Alpine variant published for nginx 1.29 |
| `cron` | `alpine:3.24` | + `docker-cli` only (no Docker-in-Docker) — runs `docker compose exec` from the host's daemon via the mounted socket |
| `composer` | built `FROM ${APP_PHP_IMAGE}` | + Composer 2.10 binary, git/svn/hg/unzip tooling |
| `node` | `node:18-alpine3.21` | theme asset builds — 3.21 is the newest Alpine variant upstream ever published for Node 18 (Node 18 itself reached EOL 2025-04-30; a major-version bump is a separate, larger task) |
| `certbot` | `alpine:3.24` | + `certbot`, `openssl`, `libpsl-utils` (`psl` CLI, apex/subdomain detection for `sh/system/certbot.sh` — see that script and `kit-modules/basis/CLAUDE.md`'s DNS-provider notes for the rule) — current tag `2.11-alpine3.24-r1` |
| `iac` | `debian:12-slim` | Terraform, Terragrunt, Ansible, AWS CLI, gcloud, pinned versions via build ARGs, + `psl` (Debian package providing the same `psl` CLI as `certbot`'s `libpsl-utils`, used by `kit-modules/basis/sh/dns.sh`) — current tag `1.1.2` (this service pins its own version scheme, not an alpine/upstream tag) |

All images share the same **entrypoint pattern**: a `docker-entrypoint.sh` that runs numbered
scripts from `docker-entrypoint.d/*.sh` (alphabetical) before `exec`-ing the real command — e.g.
PHP's entrypoint remaps `www-data` to `CURRENT_UID`/`CURRENT_GID` so bind-mounted files keep host
ownership; Composer's `30-composer-config.sh` wires up `COMPOSER_AUTH`. Add a new provisioning
step by dropping a new numbered script into the relevant `docker-entrypoint.d/`, not by editing
the shared `docker-entrypoint.sh`.

## Building/publishing images (`make docker`, `sh/system/docker.sh`)

```bash
make docker build [service]     # docker build for one or all 8 services (local, single-arch)
make docker push [service]      # buildx build --platform linux/amd64,linux/arm64 --push, per-service confirm prompt
make docker clean               # full local docker system prune (containers/images/volumes/networks/buildx cache)
make docker-login               # registry auth only — ghcr.io login using CR_TOKEN, no build/push
```

`push` always re-authenticates and creates/reuses the `starter-kit-builder` buildx builder before
pushing. `login`/`docker-login` were split out from `build`/`push` deliberately — don't merge them
back into a combined step.

### Any `dockerfiles/<service>/**` edit requires a manual rebuild + push — CI never builds images

The deploy pipeline (`ci.md`) never runs `docker build` — `job-deploy.yml` only does
`sh/env/init.sh` + `make recreate`, i.e. `docker compose up` against whatever `APP_<SERVICE>_IMAGE`
already resolves to on `ghcr.io`. Editing a `Dockerfile`/`docker-entrypoint.d/*` and merging it
changes nothing at runtime anywhere (dev/stage/prod, or any other machine doing a fresh clone)
until someone manually runs `make docker build <service>` + `make docker push <service>`.
`make docker build <service>` alone only updates the **local** Docker image cache under that tag —
it never touches the registry.

**Never push over an existing tag.** A tag other environments already pulled (dev/stage/prod, a
teammate's machine, CI cache) will silently keep the old layer until something forces a re-pull —
overwriting it in place means different machines run different content under an identical tag,
with no way to tell which, and no rollback target. Always mint a new tag and update the matching
`APP_<SERVICE>_IMAGE` in `config/environment/.env.main` to point at it, same commit as the
Dockerfile change.

Tag convention: `php`/`nginx`/`mariadb` tags are `<upstream-version>-alpine<version>` (e.g.
`8.4-fpm-alpine3.22`), which normally only changes when the upstream base image is bumped. For a
content-only change (Dockerfile/entrypoint edit, no base bump), append a revision suffix:
`8.4-fpm-alpine3.22-r1`, then `-r2`, etc. — bump the trailing `-rN` on every subsequent
content-only change, reset it (drop the suffix) whenever the base version changes. `cron` follows
an adjacent scheme: its own independent version ahead of the alpine tag (`1.5-alpine3.20`), bumped
whenever cron's own scripts change. Match whichever scheme the service already uses; don't invent
a new one for a single service without discussing it first.

If a `docker-compose.yml` change adds a `healthcheck` or a `depends_on: condition: service_healthy`
that a Dockerfile change is meant to satisfy (e.g. a new binary or config the healthcheck test
depends on), the image push is not optional — an old image without it will report unhealthy
forever and anything gated on `condition: service_healthy` (other services' `depends_on`) will
never start. Push before merging, or the next deploy breaks the stack.

## Multi-instance override (`COMPOSE_OVERRIDE`)

`Makefile`'s `COMPOSE_OVERRIDE` var runs `kit-modules/proxy/bin/compose-flags.sh` (if present) and
splices its output into every `docker compose` call (`up`, `down`, `restart`, `recreate`, `import`,
`replace`, `install`, `core-install`). When `kit-modules/proxy` is installed and active
(`APP_MULTI_INSTANCE=1`), this is what drops nginx's host port bindings and joins the shared
`proxy` network — see `infrastructure.md`. A no-op otherwise.

## Volumes — all bind mounts, no Docker-managed volumes

`docker-compose.yml` has no top-level `volumes:` key — every mount on every service is a host
bind mount (`./host/path:/container/path`), not a named/anonymous Docker volume:

- `mariadb` — `./db-data:/var/lib/mysql`
- `php` / `nginx` — `./web/wp-core`, `./web/wp-content`, plus service-specific config/log/cache
  dirs (`./logs/wordpress`, `./cache/php`, `./config/php`, `./config/nginx`, `./config/ssl`, `./sh`)
- `cron` — `/var/run/docker.sock`, `./config/cron/crontabs`, `${WORKING_DIR}`

Practical consequence: `docker compose down -v` has nothing Docker-managed to remove — `-v` is a
no-op here, and all data (DB, uploads, logs, cache, config) survives on the host regardless.
Don't add a named `volumes:` entry for new persistent data without discussing it — it would
change this behavior and break the assumption that `down -v` is always safe.

## PHP-FPM / permissions

The `php` and `nginx` containers bind-mount `./web/wp-core` and `./web/wp-content` directly —
files created inside the container must end up owned by the host user, which is why
`CURRENT_UID`/`CURRENT_GID` (from `id -u`/`id -g`, exported by the `Makefile`) are threaded
through `docker-compose.yml` into the `php`/`cron` containers and consumed by their entrypoints.
Never hardcode a UID/GID in a Dockerfile or compose override.

## SSL

`config/ssl/live/<domain>/{fullchain.pem,privkey.pem}` — either supplied manually (see
`config/ssl/readme.md`) or generated by `make ssl` (`sh/system/certbot.sh`): creates a dummy
self-signed cert so nginx can start, requests a real Let's Encrypt cert via the `certbot`
toolkit container (webroot authenticator, config in `config/certbot/cli.ini`), then restarts
nginx. Renewal runs from the `cron` container's crontab (`config/cron/crontabs/root`), not from
`certbot` itself running a daemon.
