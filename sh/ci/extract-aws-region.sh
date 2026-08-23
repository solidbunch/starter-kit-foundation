#!/bin/sh
# Executed, not sourced. Extracts TF_VAR_aws_region from ./config/environment/.env.main and
# prints it to stdout (no trailing text) — replaces the inline "Extract AWS region" step
# duplicated in job-provision.yml and job-bootstrap-state.yml.
#
# Usage: REGION="$(sh ./sh/ci/extract-aws-region.sh)"

set -e

REGION=$(grep '^TF_VAR_aws_region=' ./config/environment/.env.main | cut -d '=' -f2)

if [ -z "$REGION" ]; then
  echo "Error: TF_VAR_aws_region is not set in ./config/environment/.env.main" >&2
  exit 1
fi

echo "$REGION"
