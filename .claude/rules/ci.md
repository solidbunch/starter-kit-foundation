---
paths:
  - ".github/workflows/**"
---

# GitHub Actions CI/CD

Four workflow files in `.github/workflows/`, split into two reusable jobs plus two thin triggers.
Never edit deploy/provision logic ad hoc without checking both the trigger and the job file it calls.

## Deploy pipeline

- `workflow-deploy-develop.yml` — triggers on push to `develop` (+ manual `workflow_dispatch`),
  calls `job-deploy.yml` with `ENVIRONMENT_TYPE=dev`. The deploy target is not an input at all —
  it's derived at runtime by the `deploy` job from `APP_DOMAIN` (see "GitHub configuration"
  below).
- `workflow-deploy-production.yml` — **manual only** (`workflow_dispatch`), calls `job-deploy.yml`
  with `ENVIRONMENT_TYPE=prod`. Same deploy-target derivation as above, reading `prod`'s
  `.env.type.prod`. There is no auto-deploy-on-push to prod.
- `job-deploy.yml` (`workflow_call`) — build phase runs on `ubuntu-24.04`, prepares `.env` via
  `sh/env/secret-gen.sh` + `sh/env/init.sh`, switches the theme to `dev-develop` only when
  `ENVIRONMENT_TYPE == dev`, force-updates `monitoring-client` (+ a demo-only addon plugin, not
  relevant outside showcase deploys — see `infrastructure.md`) from `dist` only when the `IS_DEMO`
  repo variable is `true`, then `sh/system/install.sh yes` (composer +
  npm). Deploy phase runs on `ubuntu-22.04`, pinned to the run's GitHub Environment
  (`environment: ${{ inputs.ENVIRONMENT_TYPE }}`). Immediately after restoring the cached build
  (`Use Built job`), a `Resolve deploy target from APP_DOMAIN` step greps `APP_DOMAIN` out of
  `config/environment/.env.type.$ENVIRONMENT_TYPE`, fails fast (naming the reason) if the file is
  missing or `APP_DOMAIN` is empty, and exports `APP_DOMAIN` + `DEPLOY_PATH=/srv/$APP_DOMAIN` via
  `$GITHUB_ENV` (see "GitHub configuration" below) — before `rsync`ing the whole repo over SSH to
  `$DEPLOY_PATH` (excludes `.git*`, `node_modules`, `backups/`, `db-*/`, `logs/`, all `.env*`
  variants, `config/ssl/`, uploads/languages/cache — see the `--exclude` list before changing what
  ships), then over SSH on the target: `make secret`, `make APP_MULTI_INSTANCE=<var> proxy deploy
  '<env>'` (Stage C hook — writes the instance's Traefik/nginx wiring before `sh/env/init.sh`
  regenerates `.env`), `sh/env/init.sh`, `make ssl`, `make recreate`, `make monitoring off` →
  `make monitoring on`, DB health check, `make core-install`.
- Required secrets: `SSH_KEY`, `SSH_CONFIG`, `COMPOSER_AUTH` (see `infrastructure.md` for what
  `COMPOSER_AUTH` unlocks) — that's it. **No CI/CD variable is required for the deploy target on
  either platform** — it's derived from `APP_DOMAIN`. Full GitHub-side configuration: the section
  below.

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
- Terraform runs `shared` (network) → `${EFFECTIVE_ENV_TYPE}` (the target env) — the `state`
  (backend bootstrap) layer is no longer run by CI; see below — each `init` then the chosen
  `ACTION_TYPE`. Mirrors the `envs/shared` → `envs/<env>` apply order described in
  `infrastructure.md`.
- Ansible (`inventory` then `playbook`) only runs when `ACTION_TYPE == apply` and
  `SKIP_ANSIBLE == false`.
- Cleans up the generated Ansible inventory (`generated.inventory.yml`) in an `if: always()` step
  — don't remove that cleanup when editing the job.
- `TFPLAN_PASSPHRASE` (secret, optional) drives the plan-then-apply flow: the Terraform plan is
  GPG-encrypted (AES256) into the `tfplan-<env>` run artifact, and an `apply` run given a
  `PLAN_RUN_ID` downloads and decrypts it instead of re-planning. Every step in that chain is
  gated on the `tfplan_secret` step output, so an unset secret degrades to plain plan-then-apply
  with a warning in the run summary — it never fails the run.
- The plan/apply artifact tarball no longer contains a `state.tfplan` — only `shared.tfplan` and
  the target env's plan file (`tfplans/${EFFECTIVE_ENV_TYPE}.tfplan`), matching the two layers CI
  actually runs.
- **SSH key rotation.** Rotating the `SSH_KEY` secret only replaces `aws_key_pair.deploy` on the
  *next* Terraform apply — instances that are already running keep the OLD key in
  `authorized_keys` until they're re-provisioned. A rotated key does not take effect on existing
  servers by itself; it needs an explicit re-provision/Ansible run against them afterward.

### State backend — bootstrapped once, locally, never by CI

CI **assumes the S3/DynamoDB Terraform state backend already exists** — it never runs the `state`
layer. The CI-facing IAM role (generated by `kit-modules/basis/sh/aws/oidc.sh`) deliberately has **no**
`s3:CreateBucket` / `dynamodb:CreateTable` permission. Do not add it — this is intentional, not an
oversight, since CI never calls `terraform apply` on `state` anymore and granting `Create*` would
be permanently-unused privilege.

`oidc.sh` lives under a per-cloud-provider subdirectory (`sh/<provider>/oidc.sh`, currently
`sh/aws/oidc.sh`) rather than flat in `sh/` — multi-provider support is planned, and this gives
each future provider's OIDC (and other provider-specific) scripts a natural home in their own
folder.

The backend has to be bootstrapped exactly once — per AWS account, or once for a brand-new
downstream project cloning this template — with a one-time, two-phase local procedure. Run this
before the first `Provision Infrastructure` dispatch against a new account:

```bash
# Phase 1 — local state, creates the bucket + lock table
mv kit-modules/basis/terraform/state/backend.tf /tmp/state-backend.tf
make tf state init
make tf state apply
mv /tmp/state-backend.tf kit-modules/basis/terraform/state/backend.tf

# Phase 2 — migrate that local state into the bucket it just created
make basis   # interactive shell in the iac container, repo mounted at /srv
#   inside the container:
cd /srv/kit-modules/basis/terraform/state
terraform init -migrate-state \
  -backend-config="bucket=$TF_VAR_tf_backend_bucket" \
  -backend-config="region=$TF_VAR_aws_region" \
  -backend-config="dynamodb_table=$TF_VAR_tf_lock_table"
#   answer "yes" when asked to copy the existing state to the new backend
```

After this runs once, `make tf state [init|plan|apply|destroy]` works normally through the
`terraform.sh` wrapper forever after — nothing in `terraform.sh` changes, and `state` is never
removed or renamed as a `make tf` target; it's simply never invoked by the CI workflow.

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
| `SSH_CONFIG` | yes | deploy + provision — sets `StrictHostKeyChecking accept-new` (trust-on-first-use): accepts an unseen host key automatically on first connect, then refuses to connect if that host's key later changes, closing the MITM/key-swap gap a bare `no` would leave open |
| `COMPOSER_AUTH` | yes | deploy + provision, unlocks licensed modules (`infrastructure.md`) |
| `TFPLAN_PASSPHRASE` | no | provision only, plan encryption (see above) |
| `GITHUB_TOKEN` | — | auto-provided, nothing to configure |

Variables (**Variables** tab, or per environment):

| Variable | Level | Required | Meaning |
|---|---|---|---|
| `AWS_ROLE_TO_ASSUME` | repo | for provisioning | IAM role ARN assumed via OIDC |
| `IS_DEMO` | repo | no | demo/showcase mode, see below |
| `APP_MULTI_INSTANCE` | **environment** | no | `1` enables the multi-instance (Traefik) deploy on that environment's server; see `infrastructure.md`. Repo-level would apply it to prod too |

There is **no deploy-target variable** in this table — no `SSH_HOST_ALIAS`, no
`DEPLOY_PATH_DESTINATION`, on either the repo or environment level. The deploy target is derived
at runtime by the `deploy` job's `Resolve deploy target from APP_DOMAIN` step, which greps
`APP_DOMAIN` out of `config/environment/.env.type.$ENVIRONMENT_TYPE` (already tracked in git,
already customized per-project when `bootstrap-project` renames a project) and computes
`DEPLOY_PATH=/srv/$APP_DOMAIN` — the same pattern already used for `TF_VAR_aws_region` (see
below), just applied to a second value. It fails the run immediately, naming the reason, if
`.env.type.$ENVIRONMENT_TYPE` is missing (which also catches a failed build-cache restore, a
failure mode the job previously had no guard against at all) or if `APP_DOMAIN` is empty in that
file — a repo with a broken/missing env file gets a clear error instead of an `rsync` to `""`.
`APP_DOMAIN` doubles as the SSH destination alias: `ssh "$APP_DOMAIN"` /
`rsync … "$APP_DOMAIN:$DEPLOY_PATH"`.

**Contract: `SSH_CONFIG`'s `Host` block name must equal that environment's `APP_DOMAIN`.** This
is now a requirement, not a coincidence — every existing install already satisfies it (its
`Host` alias already equals the environment's domain), but a project using an unrelated alias
name (e.g. `prod-server-1`) would now break with `Could not resolve hostname`.

**Optional hardening: pinned host keys.** `accept-new` is the shipped default (zero-setup, trust-
on-first-use). Operators who want stronger verification can instead populate `SSH_CONFIG`'s
`known_hosts` with keys collected via `ssh-keyscan` for each target host, and drop
`StrictHostKeyChecking` back to its secure default (`ask`/unset, since the keys are now pre-
trusted) — this rejects a connection to a host whose key isn't already pinned, not just one that
changed. This is **not** the default because Terraform recreates EC2 instances on every
provisioning run (`kit-modules/basis`), and a re-created instance gets a brand-new host key each
time — a pinned `known_hosts` would need to be re-collected after every rebuild, or every
subsequent deploy hard-fails until it is. Treat this as an opt-in upgrade for operators who control
their own rebuild cadence, not something to enable by default.

`stage` needs no deploy-target configuration either — `.env.type.stage` already carries its own
`APP_DOMAIN`, so `job-deploy.yml` resolves a stage target for free the moment a stage trigger
workflow exists; only the trigger is still missing (see `kit-modules/basis/CLAUDE.md` and
`gitlab-ci.md` for the rest of the stage gap).

### Migrating off the earlier `SSH_HOST_ALIAS` / `DEPLOY_PATH_DESTINATION` design

An earlier revision of this pipeline read the deploy target from two GitHub Environment variables,
`SSH_HOST_ALIAS` and `DEPLOY_PATH_DESTINATION`. Neither is read anywhere anymore — if a repo still
has them set on its `dev`/`stage`/`prod` Environments, delete them; they are dead configuration
that looks load-bearing but isn't. This migration is **not disruptive to deploys themselves**: the
derived values equal what those variables held for every existing install (the old alias values
were already exactly the environment's domain), so no server-side change is needed — only the UI
variables become stale and worth cleaning up.

There is no `AWS_REGION` variable — the region is read out of `config/environment/.env.main`
(`TF_VAR_aws_region`) by the "Extract AWS region" step, and reaches containers through
`docker-compose.toolkit.yml`'s `AWS_DEFAULT_REGION`. Don't reintroduce a GitHub-side copy — the
same reasoning now applies to the deploy target derived from `APP_DOMAIN` above.

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
