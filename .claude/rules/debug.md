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

Session log: `logs/wordpress/xdebug-log.log`.

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
