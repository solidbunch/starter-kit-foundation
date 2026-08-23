#!/bin/sh
# Executed, not sourced. Three-state has_basis classifier — shared by job-provision.yml and
# job-bootstrap-state.yml (and their GitLab CI counterparts). Run from the repo root; requires
# jq and a composer.lock in the current directory.
#
# composer.lock's recorded package `type` for solidbunch/basis (licensed `kit-module` vs
# unlicensed `metapackage` stub) is cross-checked against whether kit-modules/basis actually
# landed on disk. Directory presence alone is not trustworthy — see
# .claude/plans/architect-plan-pipeline-audit-fixes.md item 4.
#
# stdout: exactly one line, `has_basis=true` or `has_basis=false`.
# stderr: the human-readable classification message (wording preserved verbatim from
#         job-provision.yml, minus the ::error::/::warning:: GitHub Actions annotation prefixes).
# exit:   0 for the three proceedable states, 1 when solidbunch/basis is recorded as licensed
#         (kit-module) in composer.lock but kit-modules/basis is missing on disk (install
#         genuinely broken).
#
# Usage: HAS_BASIS="$(sh ./sh/ci/verify-basis.sh)"; HAS_BASIS="${HAS_BASIS#has_basis=}"

set -e

LOCK_TYPE=$(jq -r '.packages[] | select(.name=="solidbunch/basis") | .type' composer.lock)
if [ -z "$LOCK_TYPE" ]; then
  LOCK_TYPE="metapackage"
fi

if [ -d "kit-modules/basis" ]; then
  DIR_PRESENT=true
else
  DIR_PRESENT=false
fi

if [ "$LOCK_TYPE" = "metapackage" ] && [ "$DIR_PRESENT" = "false" ]; then
  echo "composer.lock records solidbunch/basis as unlicensed (metapackage) and kit-modules/basis is absent — genuinely unlicensed. Skipping provisioning." >&2
  echo "has_basis=false"
elif [ "$LOCK_TYPE" = "kit-module" ] && [ "$DIR_PRESENT" = "false" ]; then
  echo "composer.lock records solidbunch/basis as licensed (kit-module) but kit-modules/basis is missing on disk — install failed or the license expired. Failing the job." >&2
  exit 1
elif [ "$LOCK_TYPE" = "metapackage" ] && [ "$DIR_PRESENT" = "true" ]; then
  echo "composer.lock records solidbunch/basis as unlicensed (metapackage) but kit-modules/basis is present on disk — ambiguous, likely a stale or local install. Proceeding anyway." >&2
  echo "has_basis=true"
else
  echo "Basis module found and composer.lock confirms it is licensed (kit-module)." >&2
  echo "has_basis=true"
fi
