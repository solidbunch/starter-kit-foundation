# Debugging

## Use the built-in tools — never invent custom debug tooling

The stack ships Xdebug, the WP debug log, and container logs. Never add custom debug packages
or custom debug-output helpers.

## Xdebug

Configured in `config/php/local.d/xdebug.ini`, active only in the `local` environment.
**Inactive by default** — trigger per request:

- Query param: `?XDEBUG_TRIGGER=1`
- POST field: `XDEBUG_TRIGGER=1`
- HTTP header: `XDEBUG_TRIGGER: 1`

Also supports `?XDEBUG_SESSION` (debug only), `?XDEBUG_PROFILE`, `?XDEBUG_TRACE` individually.
Session/trace/profile output: `logs/wordpress/` (`xdebug-log.log`, `trace.*`, `profiler*.out`).

## WordPress debug log

Location: `logs/wordpress/debug.log`. Controlled via `.env`:
`WP_DEBUG=true`, `WP_DEBUG_LOG=true`, `WP_DEBUG_DISPLAY=false`.

Temporary local-only logging — remove before committing:

```php
error_log(print_r($value, true));   // acceptable during local dev ONLY
```

## Container logs

`make log` tails Docker stdout/stderr streams — the first place to look for runtime errors:

```bash
make log          # all services
make log php      # PHP-FPM
make log nginx    # Nginx
make log mariadb  # database
make log cron     # cron container
```

## Log files on host

| Path | Contents |
|------|----------|
| `logs/nginx/access.log` | HTTP access |
| `logs/nginx/error.log` | Nginx errors |
| `logs/wordpress/debug.log` | WP_DEBUG output |
| `logs/wordpress/xdebug-log.log` | Xdebug session log |

## Never leave in committed code

`var_dump()`, `print_r()`, `dd()`, `dump()`, `error_log()`, `WP_DEBUG_DISPLAY=true` in a config
file, or a hardcoded `XDEBUG_TRIGGER` param in a URL.

## Check the simple cause before the sophisticated one

When a change doesn't show up on the page, the explanation is almost always local. Rule them out in
this order before reaching for anything cleverer:

1. Did the asset actually rebuild? (`npm run dev` / `make watch` running, `mix-manifest.json`
   timestamp, the compiled file in `build/` containing your change)
2. Browser cache — hard refresh, or check the response headers for the asset you expect.
3. The right file — is the page loading the theme's bundle or the plugin's, and is the selector
   you edited the one that actually wins?
4. Only then: server-side caching, object cache, a proxy.

**There is no CDN or edge cache in front of this site locally.** `starter-kit.loc` resolves purely
through `/etc/hosts` (`127.0.0.1`, alongside `starter-kit-test.loc` and `licensing.starter-kit.loc`)
— nothing sits between the browser and the local Nginx container. The `cloudflare` plugin is
installed in `web/wp-content/plugins/`, and it sets a `cf-edge-cache` response header itself
(`cloudflare/src/WordPress/Hooks.php:439`) — seeing that header locally is **not** evidence of an
active Cloudflare edge in front of the site. Don't build a caching theory on it.

## Common environment failures (known, recurring — check here before deep-diving)

| Symptom | Cause / fix |
|---|---|
| `Cannot connect to the Docker daemon` | Docker isn't running — `docker info` / `docker ps` to confirm |
| `bind: address already in use` on 80/443 | Another local web server holds the port — check `sudo lsof -i :80`, stop it, or use `APP_MULTI_INSTANCE`/Traefik to co-host |
| Composer: `Could not delete /srv/web/wp-core/wp-content` | `make down`, remove the empty leftover dir, retry `composer update` — happens when core install-path and content dir collide after a partial run |
| GitHub Composer repo hits API rate limit (60/hr unauthenticated) | Add a GitHub token to `.env.secret` (`COMPOSER_AUTH`, see `infrastructure.md`) or switch the affected repo URL to SSH |
| MariaDB: `Bad magic header in tc log` / crash recovery failed | `make down`, delete `db-data/tc.log`, `make up` to let it recreate |
| Containers stuck / won't respond after a bad state | Last resort: `docker stop $(docker ps -q) && docker rm $(docker ps -aq)`, then `make up` — confirm with the user before running, it affects containers outside this project too |
| `.env` looks wrong / stale after editing `config/environment/*` | `.env`/`.env.runtime` are generated, not hand-edited — delete root `.env` and run `make env [env]` to regenerate |

SSH key issues (`Permission denied (publickey)` against GitHub, e.g. for the `starter-kit-theme`
VCS repository or private Composer repos) — verify with `ssh -T git@github.com`, not a StarterKit-
specific problem, standard GitHub SSH setup applies.
