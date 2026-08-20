---
paths:
  - ".github/workflows/**"
---

# GitHub Actions CI/CD

Four workflow files in `.github/workflows/`, split into two reusable jobs plus two thin triggers.
Never edit deploy/provision logic ad hoc without checking both the trigger and the job file it calls.

## Deploy pipeline

- `workflow-deploy-develop.yml` — triggers on push to `develop` (+ manual `workflow_dispatch`),
  calls `job-deploy.yml` with `ENVIRONMENT_TYPE=dev`, host `develop.starter-kit.io`.
- `workflow-deploy-production.yml` — **manual only** (`workflow_dispatch`), calls `job-deploy.yml`
  with `ENVIRONMENT_TYPE=prod`, host `starter-kit.io`. There is no auto-deploy-on-push to prod.
- `job-deploy.yml` (`workflow_call`) — build phase runs on `ubuntu-24.04`, prepares `.env` via
  `sh/env/secret-gen.sh` + `sh/env/init.sh`, switches the theme to `dev-develop` only when
  `ENVIRONMENT_TYPE == dev`, force-updates `monitoring-client` (+ a demo-only addon plugin, not
  relevant outside showcase deploys — see `infrastructure.md`) from `dist` only when the `IS_DEMO`
  repo variable is `true`, then `sh/system/install.sh yes` (composer +
  npm). Deploy phase runs on `ubuntu-22.04`, restores the cached build, `rsync`s the whole repo
  over SSH to `DEPLOY_PATH_DESTINATION` (excludes `.git*`, `node_modules`, `backups/`, `db-*/`,
  `logs/`, all `.env*` variants, `config/ssl/`, uploads/languages/cache — see the `--exclude`
  list before changing what ships), then over SSH on the target: `make secret`,
  `make APP_MULTI_INSTANCE=<var> proxy deploy '<env>'` (Stage C hook — writes the instance's
  Traefik/nginx wiring before `sh/env/init.sh` regenerates `.env`), `sh/env/init.sh`, `make ssl`,
  `make recreate`, `make monitoring off` → `make monitoring on`, DB health check,
  `make core-install`.
- Required secrets: `SSH_KEY`, `SSH_CONFIG`, `COMPOSER_AUTH` (see `infrastructure.md` for what
  `COMPOSER_AUTH` unlocks). Full GitHub-side configuration: the section below.

## Provisioning pipeline

- `job-provision.yml` — **manual only** (`workflow_dispatch`), inputs: `ENVIRONMENT_TYPE`
  (dev/stage/prod), `ACTION_TYPE` (plan/apply/destroy), `SKIP_ANSIBLE` (bool). Auths to AWS via
  **GitHub OIDC** (`aws-actions/configure-aws-credentials`, `permissions: id-token: write`) — no
  static AWS keys in secrets.
- Force-updates `solidbunch/basis` from `dist` only when `IS_DEMO` is `true`, same pattern as the
  deploy job.
- Verifies `kit-modules/basis` actually exists (`has_basis` step output) before running any
  Terraform/Ansible step — if the license didn't resolve real code, the whole provisioning
  sequence short-circuits with a log message instead of failing hard. Don't assume a green run
  means infrastructure was actually touched; check this step's output.
- Terraform runs in a fixed order: `state` (backend bootstrap) → `shared` (network) →
  `${EFFECTIVE_ENV_TYPE}` (the target env) — each `init` then the chosen `ACTION_TYPE`. Mirrors
  the `envs/shared` → `envs/<env>` apply order described in `infrastructure.md`.
- Ansible (`inventory` then `playbook`) only runs when `ACTION_TYPE == apply` and
  `SKIP_ANSIBLE == false`.
- Cleans up the generated Ansible inventory (`generated.inventory.yml`) in an `if: always()` step
  — don't remove that cleanup when editing the job.
- `TFPLAN_PASSPHRASE` (secret, optional) drives the plan-then-apply flow: the Terraform plan is
  GPG-encrypted (AES256) into the `tfplan-<env>` run artifact, and an `apply` run given a
  `PLAN_RUN_ID` downloads and decrypts it instead of re-planning. Every step in that chain is
  gated on the `tfplan_secret` step output, so an unset secret degrades to plain plan-then-apply
  with a warning in the run summary — it never fails the run.

## GitHub configuration — environments, secrets, variables

Both jobs pin themselves to a **GitHub Environment** named after the run's environment type:
`environment: ${{ inputs.ENVIRONMENT_TYPE }}` (`job-provision.yml`, `job-deploy.yml`). So
`dev`, `stage`, and `prod` must exist under repo **Settings → Environments**, spelled exactly
that way — a missing environment is created implicitly and empty, carrying none of the variables
below. Environment protection rules (required reviewers, wait timer) are configured there too,
not in the workflow YAML; they gate **both** pipelines now that deploy is environment-pinned.
Environments with variables/secrets need a public repo, or GitHub Pro/Team/Enterprise for a
private one.

Secrets (**Settings → Secrets and variables → Actions → Secrets**):

| Secret | Required | Used by |
|---|---|---|
| `SSH_KEY` | yes | deploy + provision |
| `SSH_CONFIG` | yes | deploy + provision — host-key trust comes entirely from here |
| `COMPOSER_AUTH` | yes | deploy + provision, unlocks licensed modules (`infrastructure.md`) |
| `TFPLAN_PASSPHRASE` | no | provision only, plan encryption (see above) |
| `GITHUB_TOKEN` | — | auto-provided, nothing to configure |

Variables (**Variables** tab, or per environment):

| Variable | Level | Required | Meaning |
|---|---|---|---|
| `AWS_ROLE_TO_ASSUME` | repo | for provisioning | IAM role ARN assumed via OIDC |
| `IS_DEMO` | repo | no | demo/showcase mode, see below |
| `APP_MULTI_INSTANCE` | **environment** | no | `1` enables the multi-instance (Traefik) deploy on that environment's server; see `infrastructure.md`. Repo-level would apply it to prod too |

There is no `AWS_REGION` variable — the region is read out of `config/environment/.env.main`
(`TF_VAR_aws_region`) by the "Extract AWS region" step, and reaches containers through
`docker-compose.toolkit.yml`'s `AWS_DEFAULT_REGION`. Don't reintroduce a GitHub-side copy.

## Demo mode (`IS_DEMO`)

A GitHub Actions **repository variable**, not a secret. When `true`, both pipelines force
`composer update` (from `dist`, ignoring the lock file) on the licensed packages relevant to that
job before installing — used for the public demo/showcase deployment so it always runs the
latest licensed module code. Normal client deployments leave this unset/`false` and rely on
`composer.lock`.

## Local emulation

`job-provision.yml` can be run for real, locally, with no cloud account — Terraform against
LocalStack, Ansible against a real SSH target container, `job-provision.yml` itself under `act`.
See `sh/local-ci/README.md` for the full harness (what's genuinely executed vs structurally
checked, LocalStack Community limitations, every act/macOS gotcha found, and the data-loss guard
rails protecting `kit-modules/basis`). Entry points: `make localci [up|down|tf|ansible|act]`.

## GitLab CI alternative

A parallel GitLab CI/CD pipeline (for plain GitLab.com shared runners) is also available,
mirroring this deploy pipeline — see `gitlab-ci.md`. Independent of this one; both can coexist.
