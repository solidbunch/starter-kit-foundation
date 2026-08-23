#!/bin/sh
# Installs the deploy SSH private key and client config into ~/.ssh before the deploy step runs.
#
# Dual-shape contract, resolved by an explicit SSH_INPUT_MODE flag — never by content-sniffing:
#   SSH_INPUT_MODE=file    -> SSH_KEY/SSH_CONFIG are PATHS to already-materialized files
#                              (GitLab File-type CI/CD variables). Validated readable, then cp'd.
#   SSH_INPUT_MODE=literal -> SSH_KEY/SSH_CONFIG are the literal key/config material itself
#                              (GitHub secrets). Written with printf, not echo.
# Any other value, or an unset SSH_INPUT_MODE, aborts before anything under ~/.ssh is touched.
#
# Inputs (env vars): SSH_KEY, SSH_CONFIG, SSH_INPUT_MODE (all required, non-empty).
#
# Never echoes SSH_KEY, SSH_CONFIG, or SSH_INPUT_MODE's subject values — only names which
# variable failed and why. No `set -x`.

set -e

if [ "$SSH_INPUT_MODE" != "file" ] && [ "$SSH_INPUT_MODE" != "literal" ]; then
  echo "Error: SSH_INPUT_MODE must be 'file' or 'literal'"
  exit 1
fi

if [ -z "$SSH_KEY" ]; then
  echo "Error: SSH_KEY is empty"
  exit 1
fi

if [ -z "$SSH_CONFIG" ]; then
  echo "Error: SSH_CONFIG is empty"
  exit 1
fi

if [ "$SSH_INPUT_MODE" = "file" ]; then
  if [ ! -f "$SSH_KEY" ] || [ ! -r "$SSH_KEY" ]; then
    echo "Error: SSH_INPUT_MODE=file but SSH_KEY does not point to a readable file"
    exit 1
  fi
  if [ ! -f "$SSH_CONFIG" ] || [ ! -r "$SSH_CONFIG" ]; then
    echo "Error: SSH_INPUT_MODE=file but SSH_CONFIG does not point to a readable file"
    exit 1
  fi
fi

mkdir -p ~/.ssh

if [ "$SSH_INPUT_MODE" = "file" ]; then
  cp "$SSH_KEY" ~/.ssh/id_rsa
  cp "$SSH_CONFIG" ~/.ssh/config
else
  printf '%s\n' "$SSH_KEY" > ~/.ssh/id_rsa
  printf '%s\n' "$SSH_CONFIG" > ~/.ssh/config
fi

chmod 400 ~/.ssh/id_rsa
chmod 600 ~/.ssh/config
