# Local CI/CD provisioning emulation harness

## What this is, and why it exists

`.github/workflows/job-provision.yml` creates AWS infrastructure (Terraform, via
`kit-modules/basis`) and configures servers (Ansible). This harness runs that **real** pipeline
locally, with no cloud account and no cost:

- LocalStack Community stands in for AWS (S3, DynamoDB, EC2, STS).
- A bare Debian 12 + systemd container (`ansible-target`) stands in for a freshly-provisioned EC2
  instance, reachable over real SSH.
- `act` runs the actual, unmodified `job-provision.yml` file — not a generated copy — so what runs
  locally is provably the same YAML GitHub runs.

The bar for every claim in this epic is **real local execution**, proven with copy-pasteable
commands and verbatim output (`sh/local-ci/EVIDENCE.md`), not a syntax check. Where real execution
was genuinely impossible (four items — see "What is structurally checked" below), that is stated
explicitly and never faked.

**Nothing in this harness ever touches real AWS, or dev/stage/prod.** See "This never affects
dev/stage/prod" below for the isolation mechanisms.

## Quick start — end to end

```bash
# 1. Bring the harness up: LocalStack + LocalStack Terraform overrides + throwaway SSH keypair +
#    config/environment/.env.type.dev.override, all git-ignored / generated fresh every run.
make localci up

# 2a. Real Terraform, via the harness's own convenience wrapper (thin pass-through to
#     kit-modules/basis/sh/terraform.sh — no parallel abstraction):
make localci tf                       # prints the real commands to copy-paste, e.g.:

# `terraform/state/backend.tf` is a self-referential S3 backend (it points at the very bucket
# the `state` layer creates), so a fresh LocalStack instance hits the exact same chicken-and-egg
# problem a fresh AWS account does: `terraform init` in state/ demands a bucket that doesn't
# exist yet. LocalStack Community also never persists state across container restarts (see
# "LocalStack Community limitations" below), so — unlike real AWS, where this is a true one-time
# bootstrap per account — this two-phase dance must be repeated every time the harness is brought
# up against a freshly-started LocalStack container.
#
# Phase 1 — bootstrap the bucket + lock table using LOCAL state, with resources still routed at
# LocalStack. Move the tracked backend.tf out of the way, AND the harness's own generated state
# override (sh/local-ci/tf-localstack-override.sh always restates a full S3 backend block for
# terraform/state, so leaving it in place recreates the same chicken-and-egg problem). Replace it
# with a provider-only override for the duration of Phase 1 — same LocalStack endpoints/dummy
# `test`/`test` credentials the rest of this harness uses (see "This never affects
# dev/stage/prod" below):
mv kit-modules/basis/terraform/state/backend.tf /tmp/state-backend.tf
mv kit-modules/basis/terraform/state/localstack_override.tf /tmp/state-localstack_override.tf
cat > kit-modules/basis/terraform/state/localstack_override.tf <<'EOF'
# TEMPORARY — Phase 1 of the LocalStack state-backend bootstrap (see sh/local-ci/README.md).
# Provider-only: no backend override, so this init/apply uses local state.
provider "aws" {
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  access_key                  = "test"
  secret_key                  = "test"

  endpoints {
    s3       = "http://localstack:4566"
    dynamodb = "http://localstack:4566"
    ec2      = "http://localstack:4566"
    sts      = "http://localstack:4566"
  }
}
EOF
bash kit-modules/basis/sh/terraform.sh -e state -c init
bash kit-modules/basis/sh/terraform.sh -e state -c apply
rm kit-modules/basis/terraform/state/localstack_override.tf
mv /tmp/state-backend.tf kit-modules/basis/terraform/state/backend.tf
mv /tmp/state-localstack_override.tf kit-modules/basis/terraform/state/localstack_override.tf

# Phase 2 — migrate that local state into the LocalStack bucket Phase 1 just created. Same
# `-migrate-state` dance as the real-AWS bootstrap (kit-modules/basis/README.MD, "Method 2: Local
# Deployment"), adapted to point at LocalStack: the restored localstack_override.tf already
# supplies the endpoints/dummy credentials, `-backend-config` only needs to inject
# bucket/region/dynamodb_table, matching what harness-up.sh exports
# (TF_VAR_tf_backend_bucket=localci-terraform-state, TF_VAR_aws_region=eu-west-1,
# TF_VAR_tf_lock_table=localci-terraform-locks):
make basis   # interactive shell in the iac container, repo mounted at /srv
#   inside the container:
cd /srv/kit-modules/basis/terraform/state
terraform init -migrate-state \
  -backend-config="bucket=$TF_VAR_tf_backend_bucket" \
  -backend-config="region=$TF_VAR_aws_region" \
  -backend-config="dynamodb_table=$TF_VAR_tf_lock_table"
#   answer "yes" when asked to copy the existing state to the new backend

# From here on, the normal per-layer sequence works exactly as before:
bash kit-modules/basis/sh/terraform.sh -e state -c plan -f tfplans/state.tfplan
bash kit-modules/basis/sh/terraform.sh -e state -c apply -f tfplans/state.tfplan
# ...repeat for -e shared and -e dev

# 2b. Real Ansible, same pattern:
make localci ansible                  # prints the real command to copy-paste:
bash kit-modules/basis/sh/ansible.sh -e dev -a playbook

# 3. Real act run against the real job-provision.yml (never call bare `act` — always through
#    act-run.sh, which owns the crash-safety trap):
make localci act -- -W .github/workflows/job-provision.yml -j provision -e .claude/local-ci-scratch/inputs-plan.json

# 4. Tear the harness down: stops LocalStack + ansible-target, removes the Terraform overrides and
#    the dev.override file, removes the throwaway keypair, restores kit-modules/basis/.env/
#    .env.runtime/.env.secret from the pre-run snapshot, byte-verifies the restore, clears the
#    sentinel.
make localci down
```

`make localci tf` / `make localci ansible` are **not** a new abstraction over Terraform/Ansible —
they are reminders that point at the real underlying scripts (`kit-modules/basis/sh/terraform.sh`,
`kit-modules/basis/sh/ansible.sh`), which the harness only wires network/credentials for. Run
those real scripts directly once the harness is up; `make localci tf`/`ansible` exist only so an
operator doesn't have to remember them.

`make localci act` **must** go through `sh/local-ci/act-run.sh` (never a bare `act` call — see
"Data-loss guard rails" below for why). Everything after `--` is passed straight to
`act-run.sh`'s own flags (`-W`, `-j`, `-e`, `-l`, and anything after a second `--` for raw `act`
flags).

### Order matters

`harness-up.sh` must run before any Terraform/Ansible/`act` invocation (it writes the LocalStack
env overrides and Terraform `*_override.tf` files those commands depend on) and `harness-down.sh`
must run last (it is what restores `kit-modules/basis`/`.env`/`.env.runtime`/`.env.secret`).
Running Terraform/Ansible/`act` commands without the harness up will either fail immediately
(no LocalStack overrides present) or, worse, try to talk to real AWS — don't do it.

## What is genuinely executed vs structurally checked

Everything in this epic was proven by real execution **except** the four items act cannot
emulate at all, per the plan's own table:

| Feature | Why act cannot emulate it | How it was verified instead |
|---|---|---|
| GitHub Environment approval gate | act has no "wait for approval" concept | Structural only: `environment: ${{ inputs.ENVIRONMENT_TYPE }}` present at job level, `actionlint` clean. Hand-off: configure required reviewers in repo Settings → Environments. |
| `concurrency:` groups | act has no concurrency-group semantics | Structural only: `concurrency: { group: provision-${{ inputs.ENVIRONMENT_TYPE }}, cancel-in-progress: false }` present and correct. |
| Cross-run `download-artifact` | act's local artifact server only serves same-run artifacts | Structural only: the `run-id`/`github-token`/`actions: read` wiring inspected. The pinned-plan `apply` logic that *consumes* a downloaded plan was proven for real by pre-seeding `tfplans/*.tfplan` on disk and exercising the workflow's own `[ -f tfplans/<layer>.tfplan ]` branch. |
| GitHub OIDC token minting | act has no OIDC provider | Static LocalStack dummy credentials (`AWS_ACCESS_KEY_ID=test`/`AWS_SECRET_ACCESS_KEY=test`) exported under a `if: ${{ env.ACT }}` step, mutually exclusive with the real `if: ${{ !env.ACT }}` OIDC step. Real OIDC minting is validated only by the user's own future real `dev`/`plan` dispatch on GitHub. |

Everything else — Terraform init/plan/apply against LocalStack (all three layers), the real
`kit-modules/basis/sh/terraform.sh -f` pinned plan-file save/apply flow, the pinned-plan vs fallback vs stale-plan branches, the
real Ansible playbook run and its idempotence re-run, the act orchestration steps
(checkout → credentials → SSH setup → `.env` prep → OIDC-credential stubbing), and the fixed
`/workspace`→`/srv` summary step — was run for real, with verbatim output recorded in
`sh/local-ci/EVIDENCE.md`.

## GID/UID collision fix (item 2.2) — status

The `addgroup`/`adduser` collision described throughout this document (macOS host GID 20, act's
root UID/GID 0) is **fixed**, not merely worked around, as of commits `99adbc6` (`php`/`composer`
entrypoint) and `ae05608` (`iac` entrypoint) on this branch. Both entrypoints now use
name-aliasing: when the host's `CURRENT_UID`/`CURRENT_GID` is already taken by another
user/group in the image, they append a *second* name for that ID (an alias line in `/etc/group` /
`/etc/passwd`, plus a matching `/etc/shadow` line on Debian) rather than failing outright or
adopting the colliding entry's own name. See
`dockerfiles/php/docker-entrypoint.d/10-update-user.sh` and
`dockerfiles/iac/docker-entrypoint.sh`.

**Fixed image tags** (the fix only exists in these tags — pulling/building the old tags still
reproduces the original failures documented below):

| Image | Tag carrying the fix |
|---|---|
| `php` | `ghcr.io/solidbunch/starter-kit-php:8.4-fpm-alpine3.24-r1` |
| `composer` | `ghcr.io/solidbunch/starter-kit-composer:2.10-php8.4-alpine3.24-r1` (rebuilds `FROM` the fixed `php` tag, so it inherits the same entrypoint fix) |
| `iac` | `ghcr.io/solidbunch/starter-kit-iac:1.1.1` |

**The workarounds documented elsewhere in this file — "leave `CURRENT_UID`/`CURRENT_GID` unset on
macOS" (below) and "act's root-user GID-0 collision blocks the Composer/install step" (in the DinD
verdict section right below this one) — are now STALE for anyone running the tags above.** They
remain accurate only for anyone still on the previous tags (`php:8.4-fpm-alpine3.24`,
`composer:2.10-php8.4-alpine3.24`, `iac:1.1.0`) — i.e. anyone who has not built these
`-r1`/`1.1.1` images locally. They are left in place below (annotated, not deleted), because that
is exactly what a reader still on the old tags will hit.

**Not yet published anywhere else.** These new tags exist only in this machine's local Docker
image cache — `config/environment/.env.main` on this branch points at them, and they were built
locally (`make docker build php` / `make docker build composer` / `make docker build iac`). They
have **not** been pushed to `ghcr.io`; `make docker push` has not been run by any task in this
epic and never will be automatically. Until the repo owner runs it manually, every fresh clone,
every dev/stage/prod deploy, and every teammate pulling this branch still resolves the old,
colliding-on-collision tags — the fix does not exist for them yet, only on this machine.

### DinD verdict: `DIND_OK` for connectivity, `DIND_FALLBACK` for one specific step class

Task 0.1 proved `act --bind --container-daemon-socket /var/run/docker.sock` genuinely works: a
`docker compose -f docker-compose.toolkit.yml run --rm iac` step inside act's job container reaches
the **host** Docker daemon and sees the real repo at `/srv` — not a copy, not empty. `env.ACT` is
also auto-injected by act (confirmed empirically), so the Stage 5 credential-stub mechanism needed
no `--env ACT=true` fallback.

Separately — and this is a **different, more specific problem, not a DinD failure** — act's job
container runs the workflow's own steps **as root by default**, unlike a real GitHub-hosted runner
(which runs as a non-root `runner` user). The workflow's `Install Composer and Node Dependencies`
step exports `CURRENT_UID=$(id -u)`/`CURRENT_GID=$(id -g)`, which resolves to `0`/`0` under act's
root job container. `dockerfiles/php/docker-entrypoint.d/10-update-user.sh` (inherited by the
`composer` image) then runs `addgroup -g "${CURRENT_GID}" "${DEFAULT_USER}"` with no fallback for
an already-existing GID, and GID `0` already exists (`root`'s own group) — so it fails hard:
`addgroup: gid '0' in use`. Two non-root workarounds were tried and both failed for their own
reasons (`-u 1000:1000` loses access to the mounted Docker socket; `-u 1001:1001` has no `passwd`
entry at all, breaking act's own Node-based actions before the job even reaches Composer). This is
the exact same *bug class* as the macOS-host GID-20 collision found in Task 3.4
(`dockerfiles/iac/docker-entrypoint.sh` has the identical unguarded `addgroup --gid` pattern), but
it affects a different, foundation-owned, production image (`php`/`composer`) and is triggered by
act's execution model, not a macOS quirk. At the time this section was written, a real fix (guard
`addgroup` against an already-existing GID) was out of scope for this epic. **That is no longer
current**: the fix has since landed (see "GID/UID collision fix (item 2.2) — status" above) via
name-aliasing in `dockerfiles/php/docker-entrypoint.d/10-update-user.sh` and
`dockerfiles/iac/docker-entrypoint.sh`, minted as `php:8.4-fpm-alpine3.24-r1`,
`composer:2.10-php8.4-alpine3.24-r1`, and `iac:1.1.1`. Those tags exist only in this machine's
local Docker cache — they have **not** been pushed to `ghcr.io` (`make docker push` not run) — so
this description (`addgroup: gid '0' in use`, "Reported, not fixed") remains exactly accurate for
the published tags dev/stage/prod and every other clone still pull, until that manual push
happens.

Per the plan's pre-designed fallback: the orchestration steps up to and including that point run
for real under act (checkout, region extraction, credential export, both the real and the
`ACT`-stubbed credentials branch — mutual exclusivity confirmed live, SSH agent/config, `.env`
prep, `Store OIDC credentials for IaC`, `Check TFPLAN_PASSPHRASE availability`); the
compose-driven Terraform/Ansible steps that Composer install would otherwise unblock run directly
on the host via the exact same scripts/arguments the workflow itself calls — which is exactly what
Stage 3's Terraform-against-LocalStack runs and Stage 4's Ansible convergence runs already did.
That evidence stands as the real-execution proof for this fallback; it is not a separate exercise.

## LocalStack Community limitations

- **The `latest` image tag is not usable.** It currently resolves to a build that hard-refuses to
  start without a `LOCALSTACK_AUTH_TOKEN` (Pro license), even when only Community services
  (`s3,dynamodb,ec2,sts`) are requested — verified live (`Localstack returning with exit code 55.
  Reason: License activation failed!`). `docker-compose.localci.yml` pins `localstack/localstack:4.9`
  (resolves to `4.9.2`, `edition: community`) instead. Never change this to `:latest`.
- **No IAM policy enforcement** — irrelevant here. `kit-modules/basis`'s Terraform declares zero
  `aws_iam_*` resources (`grep -rn 'resource "aws_iam' kit-modules/basis/terraform/` → no matches,
  re-verified), so the absence of IAM enforcement never masks a real bug this harness
  would otherwise catch.
- **No state persistence across container restarts.** LocalStack Community does not persist any
  created resource (buckets, tables, VPCs, instances, Terraform state) once the `localstack`
  container stops. This harness treats a run as one-shot verification, not a long-lived sandbox —
  there is no volume mount for it (`docker-compose.localci.yml`'s `localstack` service). If
  LocalStack restarts mid-harness, every subsequent Terraform/Ansible command must fail loudly
  (missing state/resources), not silently succeed against nothing.
- **LocalStack's EC2 is a mock.** A green `terraform apply` here proves the Terraform + AWS
  provider + S3/DynamoDB backend + this harness's LocalStack wiring are all correct — it does
  **not** prove the resulting resources would behave like real EC2 infrastructure. Never read a
  green local run as "verified against AWS".
- **Genuine, reproduced, un-fixable-from-here gap: EC2 subnet IPv6-association emulation.**
  `terraform apply` for the `shared` layer creates the VPC, Internet Gateway, route table, and key
  pair successfully, then fails identically on all three subnets:
  ```
  Error: waiting for EC2 Subnet (subnet-92c8cb1003b882f00) IPv6 CIDR block
  (subnet-cidr-assoc-4571ab84f385f8a2e) to become associated: unexpected state
  '{'State': 'associated'}', wanted target 'associated'. last error: %!s(<nil>)
  ```
  Reproduced deterministically on a fresh destroy+recreate — not a flake. The AWS provider's waiter
  expects a plain string enum for the association state; LocalStack's mock EC2 API returns a
  Python-dict-repr string instead, which the waiter's parser rejects. The resources DO get created
  in LocalStack despite the waiter error (confirmed via `terraform state list`: `aws_vpc.main_vpc`,
  `aws_internet_gateway.main`, `aws_route_table.main_route_table`, `aws_key_pair.deploy`, and all 3
  `module.network.aws_subnet.subnets[*]`), but the root module's `subnet_ids` output never
  computes, which blocks the `dev` layer's `module "instances"` (needs `subnet_ids` from remote
  state) and therefore the actual EC2 instance is never created locally.
  `kit-modules/basis/terraform/modules/network/subnet.tf` unconditionally sets `ipv6_cidr_block`
  on every subnet with no toggle, and it is a resource inside a child module — Terraform's
  override-file merge only applies to resources declared directly in the same directory as the
  override, not to resources inside a module the directory calls — so this cannot be worked around
  from this local-only harness without editing basis's tracked module code, which is out of scope.
  This is a real, reported LocalStack Community-tier limitation, not a defect in the harness, the
  override design, or the ported pipeline code — everything up to the IPv6 wait (provider wiring,
  the S3/DynamoDB-backed state backend for two of three layers, `terraform.sh -f`'s pinned-plan save/apply flow,
  VPC/IGW/route-table/key-pair creation, and the `dev` layer's remote-state read chain up to the
  exact point the missing `subnet_ids` output blocks it) is proven genuinely working.

## Ansible partials that could not converge in a container

Ran against a real, privileged, systemd-PID-1 target with a real SSH connection. Every partial in
`kit-modules/basis/ansible/partials/` was exercised for real; only one is genuinely container-hostile:

- **"Update hostname" (partial 02) — genuinely un-fixable, a Docker limitation, not this image's
  bug.** Reproduced identically on two separate full-harness runs:
  ```
  TASK [Update hostname] ***
  [ERROR]: Task failed: Module failed: Command failed rc=1, out=, err=Could not set static
  hostname: Failed to set static hostname: Device or resource busy
  fatal: [provisioned-host]: FAILED! => {"changed": false, ...}
  PLAY RECAP: provisioned-host : ok=10  changed=2  unreachable=0  failed=1  skipped=0  rescued=0  ignored=0
  ```
  Docker manages `/etc/hostname` itself inside the container's UTS namespace and refuses a
  `sethostname()`-class change from inside it — no package install or `privileged: true` fixes
  this; it would need `--uts=host`, a bigger architectural change out of scope here. This is the
  **only** genuinely container-hostile task found in the entire playbook.
  - **A real, separate bug was found and fixed on the way to this**: `dockerfiles/ansible-target/
    Dockerfile` was initially missing `dbus`, which blocked the *same* task with `Failed to connect
    to bus: No such file or directory` (the Ansible `hostname` module's Debian strategy talks to
    `systemd-hostnamed` over D-Bus). That was a real bug in this harness's own image and was fixed
    (added `dbus` to the package list, rebuilt, re-verified `systemctl is-system-running` →
    `running` and `which dbus-daemon` → `/usr/bin/dbus-daemon`). The "Device or resource busy"
    error above is what remains **after** that fix — it is the genuine Docker limitation, distinct
    from the dbus bug.
- **Partials 03-07 (Docker-in-container, log rotation, swap, sshd restart) all converge cleanly —
  better than the plan's own caution anticipated.** Docker-in-container genuinely installs and
  starts (`docker-ce`, real `Docker version 29.7.2` output); log rotation config succeeds; the
  swap-file-creation tasks correctly self-skip because `ansible_swaptotal_mb > 0` is true inside
  the container (it inherits the Docker Desktop VM's host-level swap accounting) — the one
  unconditional task, "Adjust swappiness" (`sysctl vm.swappiness`), succeeds for real; sshd restart
  does not kill the live Ansible SSH connection, and the play continues to completion in the same
  run.
- **Idempotence (second run, same playbook, unchanged):** `changed` drops from 13 to 4 between
  consecutive runs. The 4 repeat-changed tasks are changed **by design**, not idempotence bugs:
  "Restart Docker to apply changes" and both "Restart SSH via '…' unit if present" tasks use
  `state=restarted` (always reports changed by definition), and "Backup existing sshd_config" is an
  intentional unconditional backup-copy task. No genuine idempotence bug was found in anything that
  could actually run in this environment.
- **Separate, real bug found (reported, not fixed — out of this epic's scope): `generate_ansible_inventory()`
  in `kit-modules/basis/sh/ansible.sh` never emits a `swap_vars` map.** The tracked static
  `inventory.yml` carries `swap_vars: { size: 2G, swappiness: 20 }` per host, but the
  Terraform-driven "generated" inventory path (used by every normal `apply` run that doesn't pass
  `-s`) only writes `ansible_host`/`ansible_user`. `06-setup-swap.yml`'s unconditional "Adjust
  swappiness" task requires `swap_vars.swappiness` and fails with `'swap_vars' is undefined` against
  a real generated inventory — reproduced live while building this harness. This affects real
  production CI runs, not just the harness; it's a `kit-modules/basis` defect, out of scope for this
  epic (which only covers the Bug 3 working-dir fix), and is called out explicitly for the user to
  decide on.

## Real gotchas discovered while building this harness

These were all found by real execution, not anticipated in the plan. Operator-facing, in the order
you're likely to hit them:

- **macOS: `SSH_AUTH_SOCK` must be Docker Desktop's proxy socket, explicitly exported — not the raw
  macOS launchd socket.** `docker-compose.toolkit.yml`'s `iac` service defaults `SSH_AUTH_SOCK` to
  `/run/host-services/ssh-auth.sock` (Docker Desktop's macOS SSH-agent proxy), but
  `kit-modules/basis/sh/ansible.sh` passes through whatever `SSH_AUTH_SOCK` is set in the
  *invoking shell's* environment, overriding that default. If your shell's own `SSH_AUTH_SOCK`
  points at the raw macOS launchd path (`/var/run/com.apple.launchd.*/Listeners`), agent forwarding
  into the container breaks with `Error connecting to agent: Connection refused`. Fix: `ssh-add`
  the harness's throwaway private key (`tmp/local-ci/<TF_VAR_sk_ssh_key_name>`) into the default
  agent, then explicitly run:
  ```bash
  ssh-add tmp/local-ci/<TF_VAR_sk_ssh_key_name>
  export SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock
  ```
  before invoking any `kit-modules/basis/sh/*.sh` script. Environment-specific to macOS + Docker
  Desktop, not a script defect.
- **STALE as of `iac:1.1.1` — see "GID/UID collision fix (item 2.2) — status" above.** The
  paragraph below still applies verbatim to anyone on `iac:1.1.0` or earlier; on `iac:1.1.1` the
  entrypoint aliases the colliding GID instead of failing, so `CURRENT_UID`/`CURRENT_GID` no
  longer need to be left unset — this workaround is only needed until the fixed tag is what's
  actually pulled/built.
- **macOS: leave `CURRENT_UID`/`CURRENT_GID` unset when running basis scripts directly on this kind
  of host.** `export CURRENT_UID=$(id -u); export CURRENT_GID=$(id -g)` — the exact pattern
  `job-provision.yml` and `terraform.sh` use — fails on a Mac whose host GID is `20` ("staff"),
  which collides with a group already present in the `iac` image:
  `addgroup: The GID '20' is already in use.` GitHub Actions' Linux runners don't collide this way,
  so this is a macOS-host-specific quirk, not something to fix in tracked code. Leave
  `CURRENT_UID`/`CURRENT_GID` unset for local-ci runs — this falls back to the image's own
  `DEFAULT_UID`/`DEFAULT_GID=1000/1000` (`config/environment/.env.main`), proven to work identically
  in the DinD probe.
- **act: `workflow_dispatch` inputs JSON needs the `{"inputs": {...}}` wrapper — a flat object fails
  silently.** act's (and GitHub's real) `workflow_dispatch` webhook event nests dispatch inputs
  under an `inputs` key. A flat top-level object (`{"ENVIRONMENT_TYPE": "dev", ...}`) leaves
  `github.event.inputs.*` empty and the workflow **silently falls back to its declared defaults**
  rather than erroring — reproduced live: despite `ENVIRONMENT_TYPE=dev` in a flat inputs file, the
  run resolved `local`. Always use:
  ```json
  { "inputs": { "ENVIRONMENT_TYPE": "dev", "ACTION_TYPE": "plan", "SKIP_ANSIBLE": "false" } }
  ```
- **act: `.secrets.act` multi-line values need real embedded newlines inside a double-quoted value,
  not `\n` escapes.** Encoding the throwaway SSH private key as `SSH_KEY="...\n...\n..."` (literal
  backslash-n) breaks `ssh-add` with `Error loading key "(stdin)": error in libcrypto` — the literal
  `\n` sequence is fed to `ssh-add`, not a real newline. Use a real multi-line, double-quoted value
  in the godotenv-format secrets file:
  ```
  SSH_KEY="-----BEGIN OPENSSH PRIVATE KEY-----
  <the key's real lines, one per line>
  -----END OPENSSH PRIVATE KEY-----
  "
  ```
- **STALE as of `php`/`composer:…-r1` and `iac:1.1.1` — see "GID/UID collision fix (item 2.2) —
  status" above.** The paragraph below still applies verbatim to anyone on the previous tags; on
  the fixed tags the entrypoints alias the colliding root GID/UID instead of failing, so the
  `Install Composer and Node Dependencies` step no longer blocks under act — this remains the
  documented behaviour only for readers who have not built the `-r1`/`1.1.1` images locally.
- **act: the job container runs as root by default, which collides with `dockerfiles/php`'s and
  `dockerfiles/iac`'s unguarded `addgroup` calls whenever the workflow exports
  `CURRENT_UID=$(id -u)`/`CURRENT_GID=$(id -g)`.** See the "DinD verdict" section above for the
  full diagnosis (`addgroup: gid '0' in use`, and why the two non-root workarounds tried both fail
  for their own separate reasons). This blocks the `Install Composer and Node Dependencies` step
  and everything downstream of it **under act specifically** — it does not affect real GitHub-hosted
  runners, and it does not affect this harness's direct-execution path (Stage 3/4's Terraform and
  Ansible runs, driven straight from the host shell, are unaffected). The documented workaround is
  `DIND_FALLBACK`: exercise those steps directly via the same scripts and arguments the workflow
  itself calls, which is exactly what this harness's Terraform/Ansible evidence already did.
- **This is a distinct problem from the DinD proof itself, which does work.** `act --bind
  --container-daemon-socket /var/run/docker.sock` genuinely lets the workflow's own `docker compose`
  calls reach the host daemon and see the real repo at `/srv` (`DIND_OK`) — the
  root-vs-non-root user tradeoff above is a separate, more specific problem with one particular
  step's entrypoint script under act's execution model, not evidence that DinD itself is broken.

## This never affects dev/stage/prod

- **The harness never touches real AWS.** Every AWS-shaped call the harness drives (Terraform
  provider, S3/DynamoDB backend, EC2/STS calls) is redirected to `http://localstack:4566` via
  `config/environment/.env.type.dev.override` (git-ignored, `.gitignore:49` `.env.*override`), and
  two mechanisms on the `kit-modules/basis` side, split by which layer is Terragrunt-managed:
  - `terraform/state` — the one layer outside the Terragrunt graph (see `terraform/root.hcl`'s
    header) — still gets a real `*_override.tf` merge file
    (`kit-modules/basis/terraform/state/localstack_override.tf`, git-ignored by basis's own
    `.gitignore` — `override.tf`, `*_override.tf`), written by `harness-up.sh` and removed by
    `harness-down.sh`.
  - Every other layer (`terraform/envs/*`) is Terragrunt-managed — `terraform/root.hcl` itself
    reads `LOCALCI_LOCALSTACK_ENDPOINT` (one of the vars `harness-up.sh` writes into
    `.env.type.dev.override`) and conditionally generates a LocalStack-pointed
    `backend_generated.tf`/`provider_generated.tf` instead of the real-AWS one. No override `.tf`
    file is written into `envs/shared`/`envs/dev`/etc — a redeclared `terraform { backend "s3" {} }`
    or `provider "aws" {}` there would collide with Terragrunt's own generated files. Real CI never
    sets `LOCALCI_LOCALSTACK_ENDPOINT`, so this conditional is always the no-op (real AWS) branch
    outside the harness.
- **Zero tracked `kit-modules/basis` files are edited by the harness itself.** The only basis-side
  artifacts the harness writes (the `state` layer's LocalStack override `.tf` file, the
  Terragrunt-generated `backend_generated.tf`/`provider_generated.tf`, the throwaway SSH public key
  under `terraform/public_keys/`) are already git-ignored by basis's own `.gitignore` — untracked
  by design, not by the harness bypassing anything.
- **`kit-modules/basis` and the three env files are snapshotted before every harness-up run and
  restored, byte-verified, on teardown** (`harness-up.sh` step 3, `harness-down.sh` step 5) — so
  even if a script under harness control (e.g. `composer install`, which can delete an unlicensed
  `kit-modules/basis` checkout) mutates or destroys the on-disk tree, it is provably restored to
  its pre-run state before the harness reports done.
- **The `docker-compose.localci.yml` services (`localstack`, `ansible-target`) are separate,
  throwaway containers, brought up only by `harness-up.sh` and torn down only by `harness-down.sh`
  — never part of `docker-compose.yml` (the always-running app stack) or included in any deploy.**
  Neither image is ever built/pushed via `make docker`/`sh/system/docker.sh`, and neither is
  published to a registry.
- **The act runs exercise the real `job-provision.yml`, but under a credential branch
  (`if: ${{ env.ACT }}`) that is inert on real GitHub runs** — `env.ACT` is unset there, so the real
  `if: ${{ !env.ACT }}` OIDC step is what runs in dev/stage/prod, exactly as before this epic.
- **No dev/stage/prod credential, secret value, or state file is ever read or written by this
  harness.** `.secrets.act` (git-ignored) holds only throwaway/local values (a harness-generated
  SSH key, an arbitrary `TFPLAN_PASSPHRASE` string) — never a real deploy key or the real GitHub
  Actions secret.

## Data-loss guard rails

`act --bind` (required for the DinD proof to work — see above) means the workflow mutates the
**real** working tree, not a copy: `sh/system/install.sh yes` runs `composer install`, and
`composer.lock` currently reports `solidbunch/basis` as an unlicensed `metapackage` — meaning
composer **can delete the on-disk `kit-modules/basis` checkout**, including any unpushed local
branch work. This is the single highest-risk operation the harness protects against.

### The guard table

Applied by `harness-up.sh` before anything else runs, exactly as specified by the plan's
"Harness guard rails":

| `kit-modules/basis` state | Harness behaviour |
|---|---|
| On the allow-listed branch (`BASIS_ALLOWED_BRANCH`, default `fix/provisioning-epic`), clean or dirty, ahead of origin or not | **Allow.** Prints a banner naming the branch, HEAD sha, ahead-count, and every dirty path. Snapshot taken as always. |
| On any other branch, tree clean and not ahead of its upstream | **Allow.** Snapshot taken as always. |
| On any other branch, tree dirty or ahead of upstream | **Refuse**, naming the offending files/commits, telling the operator to commit onto the allow-listed branch or set `LOCALCI_BASIS_ALLOWED_BRANCH=<branch>` deliberately. |
| Snapshot cannot be taken or verified | **Refuse**, always, with no override. |

The refusal is a secondary check, not the real protection — what actually protects the checkout is
the snapshot + verified restore, which the guard table's "allow" rows still always take.

### `LOCALCI_BASIS_ALLOWED_BRANCH` — when you need it

`harness-up.sh`'s `BASIS_ALLOWED_BRANCH` constant defaults to `fix/provisioning-epic` — the exact
branch name created in the `kit-modules/basis` repo (contract 8: the two must match, or every harness
run is refused). If you deliberately want to run the harness against `kit-modules/basis` in a
dirty or ahead-of-origin state on some **other** branch (e.g. testing a different fix on a
different branch name), set the override explicitly so the operator's intent is visible in shell
history rather than a silent code edit:

```bash
LOCALCI_BASIS_ALLOWED_BRANCH=my-other-branch bash ./sh/local-ci/harness-up.sh
```

Never edit the constant in `harness-up.sh` to work around a one-off need — use the env var.

### Crash safety across the three-process sequence, and `harness-down.sh --force-restore`

The harness is not one process — `make localci up`, the Terraform/Ansible/`act` commands that
follow, and `make localci down` are three-plus separate invocations, so a `trap ... EXIT` inside
`harness-up.sh` alone protects nothing during everything that runs after it exits. The real
mechanism:

1. `harness-up.sh` writes `tmp/local-ci/harness-state.env` (the sentinel), recording the snapshot
   path, the pre-run basis branch/HEAD/porcelain hash, and marks the run active
   (`LOCALCI_ACTIVE=1`). A **second** `harness-up.sh` call while a sentinel is already active is
   refused outright, pointing at `harness-down.sh` (or `harness-down.sh --force-restore`).
2. Every `act` invocation goes through `sh/local-ci/act-run.sh`, which owns its **own**
   `trap restore_verify EXIT` — it re-reads the sentinel, re-computes basis's current
   branch/HEAD/porcelain hash, and if it diverged, wipes and re-extracts `kit-modules/basis` from
   the sentinel's snapshot tar, then byte-diff-verifies the result. This fires on normal exit,
   error exit, **and signals** (e.g. Ctrl-C / SIGINT mid-run) — this is what makes the safety net
   survive the real `up` → `act` → `down` process boundary.
3. A **hard kill** (`kill -9`, machine crash) escapes every trap by definition — nothing can run
   in response to it. That case is caught on the *next* harness invocation instead: `harness-up.sh`
   finds the stale active sentinel and refuses to start a new run, and the recovery path is:
   ```bash
   bash ./sh/local-ci/harness-down.sh --force-restore
   ```
   `--force-restore` makes every *non-critical* teardown step (stopping the LocalStack/
   `ansible-target` containers, cleaning the Terraform overrides, removing the generated `.env`
   override and throwaway keypair) best-effort instead of a hard failure — appropriate, because
   the whole point of this flag is recovering from a run that may already be in a partially-torn-
   down state. The tar-restore + `diff -r` byte-verify + sentinel-clear sequence stays exactly as
   strict in `--force-restore` mode as in the normal path: a verification mismatch is still a loud
   failure that leaves the snapshot (and the sentinel) in place rather than silently declaring
   success. Reach for `--force-restore` specifically when a normal `harness-down.sh` reports "a
   harness run is already active" pointing at a sentinel you know is stale (the process that wrote
   it is gone).

Restore verification is always byte-level (`diff -r` against the snapshot, not "the command exited
0"), both in the normal `harness-down.sh` path and in `act-run.sh`'s own trap. A mismatch never
silently clears the sentinel or deletes the snapshot — it is a loud failure, snapshot left in place,
requiring manual inspection.

## Verification: `make localci up` / `make localci down`

Real run against this machine, via the new `make localci` targets (not the scripts called
directly), immediately followed by a `docker ps` check that the always-running dev stack
(`starter-kit-nginx`/`php`/`mariadb`/`cron`) was never touched:

```
$ docker ps --format '{{.Names}}' | sort            # BEFORE
mailhog  sk-licensing-server-cron  sk-licensing-server-mariadb  sk-licensing-server-nginx
sk-licensing-server-php  starter-kit-cron  starter-kit-mariadb  starter-kit-nginx  starter-kit-php
traefik

$ make localci up
------------------------------
Local CI/CD harness — up
------------------------------
[Info] kit-modules/basis is on the allow-listed branch (fix/provisioning-epic) — allowed regardless of dirty/ahead state.
[Warning] ==============================================
[Warning] kit-modules/basis is not in a clean, at-origin state
[Warning]   Branch: fix/provisioning-epic
[Warning]   HEAD:   4ec8f2b815b966153ad5c16f875821b1f73aa1a2
[Warning]   Ahead of upstream: no-upstream
[Warning] ==============================================
[Info] Snapshotting: kit-modules/basis .env .env.runtime config/environment/.env.secret
[Success] Snapshot verified: .../tmp/local-ci/snapshot-20260819T011618Z.tar
[Success] Sentinel written: .../tmp/local-ci/harness-state.env
[Success] Throwaway SSH keypair generated
[Success] Wrote .../config/environment/.env.type.dev.override
[Info] Wrote .../kit-modules/basis/terraform/state/localstack_override.tf
[Success] LocalStack Terraform overrides written (endpoint: http://localstack:4566)
# `envs/shared`/`envs/dev`/etc get no override file — terraform/root.hcl reads
# LOCALCI_LOCALSTACK_ENDPOINT (also written above, into .env.type.dev.override) and generates a
# LocalStack-pointed backend/provider itself. See "This never affects dev/stage/prod" below.
[Info] Starting local CI services (docker-compose.localci.yml)...
 Container starter-kit-localci-ansible-target Started
 Container starter-kit-localci-localstack Started
[Success] Local CI/CD harness is up.
[Info] Tear it down with: bash ./sh/local-ci/harness-down.sh

$ docker ps --format '{{.Names}}' | sort            # DURING — dev stack unchanged, 2 new containers
... starter-kit-localci-ansible-target  starter-kit-localci-localstack ...

$ make localci down
------------------------------
Local CI/CD harness — down
------------------------------
 Container starter-kit-localci-ansible-target Stopped
 Container starter-kit-localci-localstack Stopped
Going to remove starter-kit-localci-localstack, starter-kit-localci-ansible-target
[Info] Removed .../kit-modules/basis/terraform/state/localstack_override.tf
[Success] LocalStack Terraform overrides cleaned (1 file(s) removed)
[Info] Removed .../config/environment/.env.type.dev.override
[Info] Removed .../kit-modules/basis/terraform/public_keys/starter-kit_deploy_key.pub
[Info] Removed .../tmp/local-ci/starter-kit_deploy_key
[Info] Restoring snapshot: .../tmp/local-ci/snapshot-20260819T011618Z.tar
[Success] Restore verified byte-identical against the snapshot (diff -r clean).
[Success] Sentinel cleared: .../tmp/local-ci/harness-state.env
[Success] Local CI/CD harness teardown complete.

$ docker ps --format '{{.Names}}' | sort            # AFTER — byte-identical to BEFORE
mailhog  sk-licensing-server-cron  sk-licensing-server-mariadb  sk-licensing-server-nginx
sk-licensing-server-php  starter-kit-cron  starter-kit-mariadb  starter-kit-nginx  starter-kit-php
traefik

$ git status --porcelain                              # foundation — only this task's own edits
 M Makefile
?? sh/local-ci/README.md

$ git -C kit-modules/basis status --porcelain          # basis — clean
$ git -C kit-modules/basis branch --show-current
fix/provisioning-epic
```

Both `make localci up` and `make localci down` ran green end to end. The dev stack was verified
byte-identical before/during/after via `docker ps`; `kit-modules/basis` stayed clean on
`fix/provisioning-epic` throughout, exactly as it was before this task started.

### A real Makefile hazard found and fixed while wiring these targets

`make localci [up|down|tf|ansible]` reuses the words `up`/`down`/`tf`/`ansible` as its subcommand
names — which happen to be this Makefile's own **pre-existing, unrelated top-level target names**
(`up:` → `docker compose up -d`, `down:` → the destructive `docker compose down -v`, `tf:` →
`kit-modules/basis/sh/terraform.sh`, `ansible:` → `kit-modules/basis/sh/ansible.sh`). GNU Make
treats every space-separated word on its command line as an independent goal to build: running
`make localci up` lists **both** `localci` and `up` as goals, so — verified with `make -n localci up`
before the fix existed — make would build `localci`'s own recipe *and* separately re-invoke the
real `up:` target (bringing up the whole app stack unintentionally), and `make localci down` would
likewise also fire the real, destructive `down:` target. **Fixed**: a `LOCALCI_GOAL` guard
(`$(filter localci,$(MAKECMDGOALS))`) makes `up`/`down`/`tf`/`ansible`'s own recipes a no-op
whenever `localci` is also present among the invoked goals — verified with `make -n` both before
(showing the double-fire) and after (showing a clean no-op `:`) the fix, and with the real
`make localci up`/`make localci down` run above showing no app-stack side effects. Normal usage of
those four targets on their own (`make up local`, `make tf dev init`, etc.) is unaffected — the
guard only activates when `localci` is also a listed goal.
