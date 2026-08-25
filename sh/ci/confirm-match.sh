#!/bin/sh
# Executed, not sourced. Exact-match confirmation guard shared by every "type the exact value to
# proceed" gate in this repo — replaces job-provision.yml's CONFIRM_DESTROY guard and
# job-bootstrap-state.yml's CONFIRM-region-match guard.
#
# Usage: sh ./sh/ci/confirm-match.sh '<expected>' '<actual>' '<label>'
#   <expected>: the value the caller must type exactly
#   <actual>:   the value the caller actually typed
#   <label>:    human-readable name of the value being confirmed, used in the error message
#
# Exit 0, no stdout, on an exact (case-sensitive) match. Exit 1 with a named error on stderr
# otherwise (mismatch, empty <actual>, or a case difference).

set -e

EXPECTED="$1"
ACTUAL="$2"
LABEL="$3"

if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "Error: ${LABEL} must exactly equal '${EXPECTED}' to proceed. Got: '${ACTUAL}'." >&2
  exit 1
fi
