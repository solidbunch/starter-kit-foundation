#!/bin/sh
set -e

# Safe to remove before caching: deploy never reads these paths (it greps
# config/environment/.env.type.$ENVIRONMENT_TYPE, which is tracked in git, not a secret),
# rsync already excludes every .env* variant, and the target server regenerates them itself
# via `make secret` + `sh/env/init.sh`.
rm -f .env
rm -f .env.runtime
rm -f config/environment/.env.secret
