---
paths:
  - ".github/workflows/**"
---

# GitHub Actions CI/CD

Five workflow files in `.github/workflows/`, split into three reusable jobs (`job-deploy.yml`,
`job-provision.yml`, `job-bootstrap-state.yml`) plus two thin triggers
(`workflow-deploy-develop.yml`, `workflow-deploy-production.yml`).
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
  `sh/env/secret-gen.sh` + `sh/env/init.sh` (this part stays inline, see "Shared deploy scripts"
  below), then runs `sh/ci/composer-extras.sh` inside the toolkit `composer` container — it
  switches the theme to `dev-develop` only when `ENVIRONMENT_TYPE == dev`, and force-updates a
  fixed set of demo-only packages from `dist` (see "Shared deploy scripts" below for which ones)
  only when the `IS_DEMO` repo variable is `true` — then
  `sh/system/install.sh yes` (composer + npm), then `sh/ci/scrub-secrets.sh` removes the generated
  `.env`/`.env.runtime`/`.env.secret` before the whole workspace is cached (`Save Built job`).
  Deploy phase runs on `ubuntu-22.04`, pinned to the run's GitHub Environment
  (`environment: ${{ inputs.ENVIRONMENT_TYPE }}`). After restoring the cached build (`Use Built
  job`), `sh/ci/setup-ssh.sh` (`SSH_INPUT_MODE: literal`) writes `~/.ssh/id_rsa` +
  `~/.ssh/config` from the `SSH_KEY`/`SSH_CONFIG` secrets, then `sh/ci/deploy.sh
  '${{ inputs.ENVIRONMENT_TYPE }}'` does the rest: it sources `sh/ci/resolve-deploy-target.sh`,
  which greps `APP_DOMAIN` out of `config/environment/.env.type.$ENVIRONMENT_TYPE`, fails fast
  (naming the reason) if the file is missing or `APP_DOMAIN` is empty, and exports `APP_DOMAIN` +
  `DEPLOY_PATH=/srv/$APP_DOMAIN` — then `deploy.sh` `rsync`s the whole repo over SSH to
  `$DEPLOY_PATH` (excludes `.git*`, `node_modules`, `backups/`, `db-*/`, `logs/`, all `.env*`
  variants, `config/ssl/`, uploads/languages/cache — see the `--exclude` list before changing what
  ships), then over SSH on the target: `make secret`, `make APP_MULTI_INSTANCE=<var> proxy deploy
  '<env>'` (Stage C hook — writes the instance's Traefik/nginx wiring before `sh/env/init.sh`
  regenerates `.env`), `sh/env/init.sh`, `make ssl`, `make recreate`, `make monitoring off` →
  `make monitoring on`, DB health check, `make core-install`. See "Shared deploy scripts
  (`sh/ci/`)" below for the full script inventory and the constraints that shaped it.
- Required secrets: `SSH_KEY`, `SSH_CONFIG`, `COMPOSER_AUTH` (see `infrastructure.md` for what
  `COMPOSER_AUTH` unlocks) — that's it. **No CI/CD variable is required for the deploy target on
  either platform** — it's derived from `APP_DOMAIN`. Full GitHub-side configuration: the section
  below.

## Shared deploy scripts (`sh/ci/`)

The deploy-time logic that used to be duplicated inline in `job-deploy.yml` and
`.gitlab/ci/deploy.gitlab-ci.yml` now lives once, in `sh/ci/`, called identically from both
pipelines. See `gitlab-ci.md` for the GitLab-side call sites — this is the canonical description,
not repeated there.

- **`sh/ci/resolve-deploy-target.sh`** — sourced (`. ./sh/ci/resolve-deploy-target.sh`), never
  executed, by `sh/ci/deploy.sh` only. Reads `ENVIRONMENT_TYPE` from the environment, greps
  `APP_DOMAIN` out of `config/environment/.env.type.$ENVIRONMENT_TYPE`, and exports `APP_DOMAIN` +
  `DEPLOY_PATH=/srv/$APP_DOMAIN`.
- **`sh/ci/deploy.sh`** — executed as `sh ./sh/ci/deploy.sh '<env>'`. Sources the script above,
  then runs the `ssh mkdir` + `rsync` + remote `make` chain against the target server. Called by
  GitHub's `Deploy via SSH` step and GitLab's `.deploy` `script:`.
- **`sh/ci/composer-extras.sh`** — executed as `sh ./sh/ci/composer-extras.sh '<env>' '<is_demo>'`.
  The theme-switch-to-`dev-develop` + demo-mode dist update of a fixed set of packages (see the
  script itself for the current list), both gated by its two positional args. Called from inside
  the toolkit `composer` container on GitHub (via `su -c`, hence positional args rather than an
  env var — `su`'s environment preservation isn't reliable) and natively from GitLab's
  `.build-composer`.
- **`sh/ci/setup-ssh.sh`** — executed as `sh ./sh/ci/setup-ssh.sh`, requires `SSH_INPUT_MODE`
  (`file` or `literal`) plus `SSH_KEY`/`SSH_CONFIG`. Writes `~/.ssh/id_rsa` (mode `400`) and
  `~/.ssh/config` (mode `600`). GitHub passes `SSH_INPUT_MODE: literal` (secrets are the key
  material itself); GitLab passes `SSH_INPUT_MODE=file` (its `SSH_KEY`/`SSH_CONFIG` are File-type
  CI/CD variables, i.e. paths). The mode is an explicit flag, never content-sniffed.
- **`sh/ci/scrub-secrets.sh`** — executed as `sh ./sh/ci/scrub-secrets.sh`, no args. Removes
  `.env`, `.env.runtime`, `config/environment/.env.secret` before GitHub caches the whole
  workspace (`actions/cache/save`, `path: .`). GitHub-only caller — GitLab's `.build-composer`
  `artifacts:` is an explicit allowlist that never includes these files, so there is nothing to
  scrub on that side.

These five are deploy-side. `sh/ci/` also holds three provisioning-side guard scripts, shared the
same way between `job-provision.yml`/`job-bootstrap-state.yml` on GitHub and
`provision.gitlab-ci.yml`/`bootstrap-state.gitlab-ci.yml` on GitLab (eight scripts total in the
directory) — see "Provisioning pipeline" and "State backend" below for the call sites:

- **`sh/ci/extract-aws-region.sh`** — reads `TF_VAR_aws_region` out of
  `config/environment/.env.main`. Called by both platforms' provisioning and bootstrap-state jobs
  wherever the AWS region is needed, and by bootstrap-state's `CONFIRM`-equals-region guard (see
  "State backend" below).
- **`sh/ci/confirm-match.sh`** — exact-string comparison used by the `CONFIRM`/`CONFIRM_DESTROY`
  guards, fails closed before any AWS/credential step runs.
- **`sh/ci/verify-basis.sh`** — checks that `kit-modules/basis` actually resolved to real code
  (licensed) before any Terraform/Ansible step runs; GitHub's `has_basis` step output and GitLab's
  `provision`/`bootstrap-state` jobs both call it the same way.

All eight are `#!/bin/sh`, POSIX-only (no `bash`isms, no `echo -e`) — the GitLab deploy job runs in
bare `alpine:3.20`, which has no bash and never installs one, so every script that could run there
has to work under busybox `ash`. GitHub's runner `/bin/sh` (dash) is POSIX too, so the same scripts
work unmodified on both platforms.

Two things deliberately stayed inline rather than being extracted here, because the two platforms'
implementations share no common command: **`.env` preparation** (`secret-gen.sh`/`init.sh` on
GitHub vs. native `pass_gen.sh`/`init.sh` on GitLab — they differ in Docker-availability, path, and
whether `COMPOSER_AUTH` gets appended to a file) and **dependency installation** (GitHub's single
`sh/system/install.sh yes` call vs. GitLab's two parallel native composer/node build jobs, because
GitLab.com shared runners have no Docker daemon).

Two intentional behaviour deltas came out of the extraction, both harmless-tightening rather than
functional changes: the "env file not found" error text is now the same unified string on both
platforms (`Error: $ENV_FILE not found (build cache/artifact restore may have failed)` — GitHub
previously said "build cache", GitLab said nothing about the cause at all), and `~/.ssh/config` is
now `chmod 600` on **both** platforms (GitLab already did this; GitHub previously left it at the
runner's default `644`).

`sh/ci/` is not the same thing as the pre-existing `sh/local-ci/` (see "Local emulation" below):
`sh/ci/` is shared logic actually invoked by the two real CI pipelines (GitHub Actions and
GitLab CI), while `sh/local-ci/` is a local `act`+LocalStack test harness for running
`job-provision.yml` on a laptop with no cloud account — different purpose, different callers,
never call one from the other.

## Provisioning pipeline

A GitLab analog of this pipeline now exists — see `gitlab-ci.md`'s "Provisioning pipeline"
section. It is not a line-for-line port; three deliberate structural deltas:

- **Single job vs. build+provision split.** `job-provision.yml` is one big job end to end. GitLab
  splits the same sequence across separate jobs — `validate-provision-inputs` (guard checks only),
  `build-basis` (produces the `kit-modules/` artifact other jobs consume), and `provision` (the
  actual Terraform/Ansible run) — because GitLab.com shared runners have no Docker daemon, the same
  constraint that splits the deploy pipeline's dependency installation (see "Shared deploy scripts"
  above).
- **Step summary vs. summary-artifact file.** This job writes its run summary via GitHub's
  step-summary mechanism (`$GITHUB_STEP_SUMMARY`). GitLab has no equivalent job-summary API on
  every tier, so its `provision`/`bootstrap-state` jobs instead build a plain Markdown file
  (`provision-summary.md` / `bootstrap-state-summary.md`) and upload it as a job artifact.
- **`PLAN_RUN_ID` vs. `PLAN_JOB_ID`.** Same concept — pin an earlier plan run instead of
  re-planning — different granularity: GitHub pins a workflow *run*, GitLab pins a *job* (GitLab
  has no cross-run artifact download on Free tier). See gitlab-ci.md's "`PLAN_JOB_ID` vs GitHub's
  `PLAN_RUN_ID`" section for the full reasoning.

- `job-provision.yml` — **manual only** (`workflow_dispatch`), inputs: `ENVIRONMENT_TYPE`
  (dev/stage/prod), `ACTION_TYPE` (plan/apply/destroy), `SKIP_ANSIBLE` (bool). Auths to AWS via
  **GitHub OIDC** (`aws-actions/configure-aws-credentials`, `permissions: id-token: write`) — no
  static AWS keys in secrets.
- **Four jobs, not one.** `provision` (Terraform `shared`→`<env>`), `ansible` and `dns` (both
  `needs: provision`, both gated on `needs.provision.outputs.has_basis == 'true' &&
  inputs.ACTION_TYPE == 'apply'` — `ansible` additionally on `SKIP_ANSIBLE == 'false'`), and
  `summary` (`needs: [provision, ansible, dns]`, `if: always()`). `ansible` and `dns` run as
  genuinely separate, concurrent jobs in the run's graph — `dns` invokes
  `kit-modules/basis/sh/dns.sh` (see `kit-modules/basis/CLAUDE.md`/`README.MD` for the script's
  own CLI/provider contract, not repeated here) and appends its own `### DNS records` section to
  its own `$GITHUB_STEP_SUMMARY`. `provision`, `ansible`, and `dns` each carry
  `environment: ${{ inputs.ENVIRONMENT_TYPE }}` and repeat the full credentialed preamble via a
  shared composite action, `.github/actions/provision-setup/action.yml` (checkout's job-to-job
  credentials don't persist on GitHub, so each job re-runs region extraction, OIDC auth, SSH
  setup, `.env` prep including the `CLOUDFLARE_API_TOKEN` secret-clobber-trap append — see the
  DNS-provider plan's Architecture notes §10 — Composer install, and `verify-basis.sh`; it takes
  every credential as an explicit `inputs:` value since a composite action cannot read the
  `secrets` context, and exposes `has_basis` as an `outputs:`). `summary` carries **no**
  `environment:` and uses no composite action — it needs no credentials, only
  `needs.provision.outputs.ipv4/.ipv6` (real value or empty — never the `N/A`/`ERROR` sentinel,
  see below) plus `needs.ansible.result`/`needs.dns.result`, and renders the
  `success`/`failure`/`cancelled`/`skipped` outcome of each honestly rather than assuming success.
- **Behaviour change: more approval prompts on a protected environment.** If the target
  environment (`dev`/`stage`/`prod`) has required reviewers configured (see "GitHub configuration"
  below), an `apply` run now prompts for approval **once per credentialed job** — three times
  (`provision`, `ansible`, `dns`), not once — because all three carry their own `environment:` key
  (verified against the current `job-provision.yml`: `environment:` appears on exactly those three
  jobs, never on `summary`). This is a real, stated behaviour change from the single-job design,
  not an implementation detail to silently absorb. If three prompts per run is unacceptable,
  create an unprotected sibling environment for the two follow-up jobs (`ansible`/`dns`) — not
  done by default.
- Force-updates `solidbunch/basis` from `dist` only when `IS_DEMO` is `true`, same pattern as the
  deploy job.
- Verifies `kit-modules/basis` actually exists (`has_basis` step output, computed once in
  `provision` and threaded to `ansible`/`dns` via `needs.provision.outputs.has_basis`) before
  running any Terraform/Ansible/DNS step — if the license didn't resolve real code, the whole
  provisioning sequence short-circuits with a log message instead of failing hard, and `summary`
  still runs (`if: always()`) and reports `skipped` for `ansible`/`dns` rather than erroring on
  missing outputs. Don't assume a green run means infrastructure was actually touched; check the
  `has_basis` output.
- Terraform runs `shared` (network) → `${EFFECTIVE_ENV_TYPE}` (the target env) — the `state`
  (backend bootstrap) layer is no longer run by CI; see below — each `init` then the chosen
  `ACTION_TYPE`. Mirrors the `envs/shared` → `envs/<env>` apply order described in
  `infrastructure.md`. This is also the job whose `tf_outputs` step is the **single** Terragrunt
  read in the whole workflow — it reads `instance_public_ip`/`instance_ipv6` once and publishes
  them as job `outputs:` for `ansible`/`dns`/`summary` to consume, so no downstream job re-`init`s
  Terragrunt. That step normalizes the `N/A` (output not configured) and `ERROR` (terragrunt
  command itself failed) sentinels to an actually-empty string before they become `ipv4`/`ipv6`
  job outputs — a non-empty sentinel string reaching `dns.sh`'s `-4`/`-6` flags would be treated as
  an explicit (invalid) override and abort the whole `dns` job before writing any record, even the
  still-valid other-address-family one. The raw sentinel is preserved separately as
  `ipv4_display`/`ipv6_display`, consumed only by `summary`'s human-readable report — never fed
  into `dns.sh`.
- Ansible (`inventory` then `playbook`) runs in its own `ansible` job, only when
  `ACTION_TYPE == apply` and `SKIP_ANSIBLE == false`.
- Cleans up the generated Ansible inventory (`generated.inventory.yml`) in the `ansible` job's own
  `if: always()` step — don't remove that cleanup when editing the job.
- **Concurrency is workflow-level, not job-level — this is required for safety, not a style
  choice.** `job-provision.yml` is `workflow_dispatch`-only (never `workflow_call`, unlike
  `job-deploy.yml`, which must keep its group at job level), so a top-level `concurrency:` block
  (`group: provision-${{ inputs.ENVIRONMENT_TYPE }}`, `cancel-in-progress: false`) covers the
  **entire run** — `provision`, `ansible`, `dns`, and `summary` together — from start to finish.
  No job in the file carries its own `concurrency:` key (grep-checkable:
  `grep -n "concurrency:" .github/workflows/job-provision.yml` returns exactly one hit, at top
  level). An earlier design considered one distinct group per job kind
  (`provision-<env>`/`-ansible`/`-dns`) — **that was rejected**: per-kind groups only serialize
  each kind against itself, so a second dispatch's `provision` job would become eligible the
  moment the first dispatch's `provision` job ends, while the first dispatch's `ansible`/`dns` are
  still working against the instance it just created — a live-infrastructure safety regression,
  not a cosmetic bug. A workflow-level group avoids that: there is only ever one lock holder, the
  run itself, and jobs *within* one run are still free to run concurrently against each other.
  **One-pending-slot behaviour, unchanged from the old job-level arrangement:** with
  `cancel-in-progress: false` there is at most one running and one pending run per group — a third
  dispatch queued behind an already-running-plus-pending pair silently cancels the pending one.
  GitHub's `queue: max` (a real deeper queue) is a documented opt-in **deliberately not adopted
  here** — it's gated behind a rollout whose availability can't be verified from inside this repo,
  and is a bigger behaviour change than this feature needs; note it here as a future option, not a
  todo.
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

### State backend — bootstrapped via a dedicated workflow, never inline in provisioning

A GitLab analog of `job-bootstrap-state.yml` also exists — see `gitlab-ci.md`'s "State-backend
bootstrap" section (`.gitlab/ci/bootstrap-state.gitlab-ci.yml`, dispatched via
`PIPELINE_KIND=bootstrap-state` rather than a separate workflow file, since GitLab shares one root
`.gitlab-ci.yml` across all three pipeline kinds — see "`PIPELINE_KIND` gating" there). Same
single-job-vs-split, step-summary-vs-artifact deltas as the provisioning pipeline above apply here
too.

CI's everyday provisioning role **assumes the S3 Terraform state backend already exists** —
`job-provision.yml` never runs the `state` layer. The everyday CI-facing IAM role
(`AWS_ROLE_TO_ASSUME`, generated by `kit-modules/basis/sh/aws/oidc.sh`) deliberately has **no**
`s3:CreateBucket` permission. Do not add it — this is intentional, not an oversight, since
`job-provision.yml` never calls `terraform apply` on `state` and granting `Create*` to that role
would be permanently-unused privilege.

`oidc.sh` lives under a per-cloud-provider subdirectory (`sh/<provider>/oidc.sh`, currently
`sh/aws/oidc.sh`) rather than flat in `sh/` — multi-provider support is planned, and this gives
each future provider's OIDC (and other provider-specific) scripts a natural home in their own
folder.

The backend has to be bootstrapped exactly once — per AWS account, or once for a brand-new
downstream project cloning this template. This is done by dispatching the **Bootstrap Terraform
State Backend** workflow (`job-bootstrap-state.yml`, `workflow_dispatch` only, under the Actions
tab) — never by hand-running Terraform locally. Before the first dispatch against a new account:

1. Run `sh/aws/oidc.sh -m gen` once — it prints the complete AWS Console setup for **both** IAM
   roles in a single run: the everyday provisioning role (`AWS_ROLE_TO_ASSUME`) and the narrower
   bootstrap role (`AWS_BOOTSTRAP_ROLE_TO_ASSUME`, repo-level variable — see the variables table
   below). Only the bootstrap role gets `s3:CreateBucket`; the everyday role never does.
2. Set `AWS_BOOTSTRAP_ROLE_TO_ASSUME` as a repo-level GitHub Actions variable from that output.
3. Dispatch **Bootstrap Terraform State Backend** from the Actions tab. Its only input is
   `CONFIRM`, which must exactly match the AWS region read from `TF_VAR_aws_region` in
   `config/environment/.env.main` — the workflow fails closed before touching AWS credentials if
   it doesn't match.

After this runs once, `make tf state [init|plan|apply|destroy]` works normally through the
`terraform.sh` wrapper forever after — nothing in `terraform.sh` changes, and `state` is never
removed or renamed as a `make tf` target; it's simply never invoked by `job-provision.yml`.

State locking is S3-native (`use_lockfile`) for every layer, including `state` itself — no
DynamoDB table exists anywhere in this module. See `kit-modules/basis/CLAUDE.md`'s "State locking"
section for the full detail; there is nothing GitHub-specific about it.

## GitHub configuration — environments, secrets, variables

Both jobs pin themselves to a **GitHub Environment** named after the run's environment type:
`environment: ${{ inputs.ENVIRONMENT_TYPE }}` (`job-provision.yml`, `job-deploy.yml`). So
`dev`, `stage`, and `prod` must exist under repo **Settings → Environments**, spelled exactly
that way — a missing environment is created implicitly and empty, carrying none of the variables
below. Environment protection rules (required reviewers, wait timer) are configured there too,
not in the workflow YAML; they gate **both** pipelines now that deploy is environment-pinned.
That approval-prompt behavior only actually happens if the `dev`/`stage`/`prod` environments have
required-reviewer/wait-timer rules configured in Settings → Environments — declaring
`environment:` in the workflow YAML alone provides deployment tracking only, with zero prompts;
don't assume protection exists just because the environment name is referenced there.
Environments with variables/secrets need a public repo, or GitHub Pro/Team/Enterprise for a
private one.

Secrets (**Settings → Secrets and variables → Actions → Secrets**):

| Secret | Required | Used by |
|---|---|---|
| `SSH_KEY` | yes | deploy + provision |
| `SSH_CONFIG` | yes | deploy + provision — sets `StrictHostKeyChecking accept-new` (trust-on-first-use): accepts an unseen host key automatically on first connect, then refuses to connect if that host's key later changes, closing the MITM/key-swap gap a bare `no` would leave open |
| `COMPOSER_AUTH` | yes | deploy + provision, unlocks licensed modules (`infrastructure.md`) |
| `TFPLAN_PASSPHRASE` | no | provision only, plan encryption (see above) |
| `CLOUDFLARE_API_TOKEN` | no | provision only, required when `DNS_PROVIDER=cloudflare` — needs both `Zone:DNS:Edit` and `Zone:Zone:Read` (Zone Resources: "All zones") for the token to pass zone discovery *and* write the record; `Zone:DNS:Edit` alone is only sufficient when `CLOUDFLARE_ZONE_ID` is also set (skips discovery). Can be repo- or environment-scoped — all three jobs that read it (`provision`, `ansible`, `dns`) carry `environment:` |
| `GITHUB_TOKEN` | — | auto-provided, nothing to configure |

Variables (**Variables** tab, or per environment):

| Variable | Level | Required | Meaning |
|---|---|---|---|
| `AWS_ROLE_TO_ASSUME` | environment | for provisioning | Everyday provisioning role's ARN, assumed via OIDC. Same shared role's ARN is stored per environment (`dev`/`stage`/`prod`) rather than at repo level — see `infrastructure.md` / `kit-modules/basis/CLAUDE.md` for why the role itself is deliberately not split per environment |
| `AWS_BOOTSTRAP_ROLE_TO_ASSUME` | repo | for the *Bootstrap Terraform State Backend* workflow only | State-backend bootstrap role's ARN, assumed via OIDC. Deliberately a different, narrower role from `AWS_ROLE_TO_ASSUME` — it can create the S3 bucket the everyday role cannot |
| `IS_DEMO` | repo | no | demo/showcase mode, see below |
| `APP_MULTI_INSTANCE` | **environment** | no | `1` enables the multi-instance (Traefik) deploy on that environment's server; see `infrastructure.md`. Repo-level would apply it to prod too |

There is **no deploy-target variable** in this table — no `SSH_HOST_ALIAS`, no
`DEPLOY_PATH_DESTINATION`, on either the repo or environment level. The deploy target is derived
at runtime by `sh/ci/resolve-deploy-target.sh` (sourced from `sh/ci/deploy.sh`, see "Shared deploy
scripts" below), which greps
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
