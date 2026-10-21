#!/bin/sh
# Runs the two conditional Composer steps shared by both pipelines:
#   - dev-only theme switch to the dev-develop branch
#   - IS_DEMO-gated: install starter-kit-addon (demo-only, not a normal dependency — see its own
#     CLAUDE.md) and force-update monitoring-client from dist
#
# Inputs:
#   $1 = environment type (required)
#   $2 = IS_DEMO value (optional, default empty) — passed positionally, not as an env var,
#        because the GitHub caller invokes this through `su -c` and su's environment
#        preservation is not something to depend on.
#
# Precondition: composer on PATH, CWD = repo root.

set -e

if [ "$1" = "dev" ]; then
  echo "Switching theme to dev-develop version for dev environment"
  composer run switch-theme-dev
fi

if [ "$2" = "true" ]; then
  echo "Detected demo mode — installing starter-kit-addon and forcing Composer update from dist"
  composer require solidbunch/starter-kit-addon --no-update
  composer update solidbunch/monitoring-client solidbunch/starter-kit-addon --no-interaction --with-all-dependencies
else
  echo "Skipping composer update — not in demo mode"
fi
