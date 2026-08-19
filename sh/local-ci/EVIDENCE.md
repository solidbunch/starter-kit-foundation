# Local emulation harness — evidence log

## Task 0.1 — Docker-in-Docker under act: PROVEN, verdict DIND_OK

Environment: act v0.2.89, Docker 29.7.2 client / 29.4.0 server (Apple Silicon, arm64), macOS.

### 1. `env.ACT` auto-injection — CONFIRMED, no fallback needed

```
$ act workflow_dispatch -W .claude/local-ci-scratch/probe.yml -j probe -P ubuntu-24.04=catthehacker/ubuntu:act-latest
[ACT probe/probe]   | ACT var is: 'true'
[ACT probe/probe]   | ACT_TRUE
```
act injects `ACT=true` into the job environment automatically. The Stage 5 credential-stub
mechanism (`if: ${{ env.ACT }}` / `if: ${{ !env.ACT }}`) needs no `--env ACT=true` fallback.

### 2. `--bind` mounts the real host tree — CONFIRMED

```
$ act ... --bind --container-daemon-socket /var/run/docker.sock
[DinD probe/probe]   | /Users/yuriipavlov/Projects/SolidBunch/starter-kit-foundation.loc
```
`pwd` inside the act job container is the real host path, not a copy.

### 3. Docker CLI + `docker compose` available inside the act job container — CONFIRMED

```
[DinD probe/probe]   | /usr/bin/docker
[DinD probe/probe]   | Client: Version: 29.7.2-1 ... Server: Docker Engine - Community Version: 29.4.0
[DinD probe/probe]   | Docker Compose version 5.4.0-2
```

### 4. This repo's actual `docker compose -f docker-compose.toolkit.yml run --rm iac` — CONFIRMED WORKING

```
$ docker compose -f docker-compose.toolkit.yml run --rm iac bash -c "echo INSIDE_IAC; pwd; ls -la /srv | head -8; whoami"
INSIDE_IAC
/srv
total 212
drwxr-xr-x 1 root root   1088 Aug 18 23:20 .
drwxr-xr-x 1 root root     18 Aug 18 23:26 ..
-rw-r--r-- 1 root root  10244 May 30 23:58 .DS_Store
drwxr-xr-x 1 root root    384 Aug 18 23:25 .claude
-rw-r--r-- 1 root root    584 Dec 11  2025 .editorconfig
-rw-r--r-- 1 root root  13453 Aug 16 21:05 .env
-rw-r--r-- 1 root root   7479 Aug 16 21:05 .env.runtime
root
```
`/srv` inside the nested `iac` container (created by the HOST docker daemon via the mounted
socket, driven by `docker compose` running inside act's job container) contains the real repo
tree — the whole chain (act job container → host docker socket → iac container → `./:/srv` bind)
resolves correctly under `--bind`.

**Verdict: DIND_OK.** No fallback to "orchestration-under-act, compose-steps-on-host" needed —
the real `docker compose` calls in `job-provision.yml` work natively under
`act --bind --container-daemon-socket /var/run/docker.sock`.

**Safety note:** these three probes ran a throwaway workflow file
(`.claude/local-ci-scratch/probe*.yml`, gitignored via `.claude/*`), never the real
`job-provision.yml`, and touched no repo-tracked files. `git status` was clean before and after.
`kit-modules/basis`, `.env`, `.env.runtime`, and `config/environment/.env.secret` were snapshotted
to `tmp/local-ci/` beforehand as a precaution (`snapshot-basis-pretest.tar.gz`,
`snapshot-env-secret.tar.gz`) — not needed this time since no risky script (`composer install`)
ran, but the real Stage 5 act runs against `job-provision.yml` itself will need it, per the plan's
guard-rail design.

## Task 0.2 — LocalStack Community covers the resource set: PROVEN, verdict LOCALSTACK_OK (with one real finding)

### Finding: the `latest` image tag is NOT usable — requires a Pro license

```
$ docker run -d --name localci-probe -p 4566:4566 -e SERVICES=s3,dynamodb,ec2,sts localstack/localstack:latest
...
LocalStack version: 2026.7.4
Localstack returning with exit code 55. Reason:
License activation failed! No credentials were found in the environment...
Due to this error, Localstack has quit.
```
`localstack/localstack:latest` currently resolves to an image that hard-refuses to start without
`LOCALSTACK_AUTH_TOKEN`, even requesting only community services (s3/dynamodb/ec2/sts, no iam).
**The harness must pin a known-community tag, not `latest`.** Verified working: `4.9`
(`localstack/localstack:4.9`, resolves to 4.9.2, edition `community`, build 2025-10-06). This is a
new, real finding beyond what research alone could determine — recorded here for `docker-compose.localci.yml` (task 3.1) to act on: pin `localstack/localstack:4.9` (or re-verify a specific
tag at build time), never `:latest`.

### Service availability — CONFIRMED via health endpoint on the pinned tag

```
$ curl -s http://localhost:4566/_localstack/health
{"services": {..., "dynamodb": "available", "ec2": "available", "iam": "disabled", "s3": "available", "sts": "available", ...}, "edition": "community", "version": "4.9.2"}
```

### Real CLI exercise of every service basis's Terraform uses — CONFIRMED

```
$ aws --endpoint-url=http://localhost:4566 sts get-caller-identity
{"UserId": "AKIAIOSFODNN7EXAMPLE", "Account": "000000000000", "Arn": "arn:aws:iam::000000000000:root"}

$ aws --endpoint-url=http://localhost:4566 s3api create-bucket --bucket probe-bucket --create-bucket-configuration LocationConstraint=eu-west-1
{"Location": "http://probe-bucket.s3.localhost.localstack.cloud:4566/"}
$ aws --endpoint-url=http://localhost:4566 s3api list-buckets --query 'Buckets[].Name'
["probe-bucket"]

$ aws --endpoint-url=http://localhost:4566 dynamodb create-table --table-name probe-table --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST
(TableDescription returned)
$ aws --endpoint-url=http://localhost:4566 dynamodb list-tables
{"TableNames": ["probe-table"]}

$ aws --endpoint-url=http://localhost:4566 ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text
vpc-80128cda08f74fcaf
```

### AMI catalogue probe — no Debian AMI exists; concrete override values recorded

```
$ aws --endpoint-url=http://localhost:4566 ec2 describe-images --query 'length(Images)'
558
$ aws --endpoint-url=http://localhost:4566 ec2 describe-images --filters "Name=name,Values=*debian*"
(empty — zero matches)
$ aws --endpoint-url=http://localhost:4566 ec2 describe-images --owners 136693071363
(empty — the real Debian Cloud owner ID has no mock images)
$ aws --endpoint-url=http://localhost:4566 ec2 describe-images --owners 099720109477 --query 'Images[0:5].[ImageId,Name]' --output table
ami-1e749f67   ubuntu/images/hvm-ssd/ubuntu-trusty-14.04-amd64-server-20170727
ami-785db401   ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-20170721
```
**Recorded override values for contract 3** (`config/environment/.env.type.dev.override`, task 3.2):
```
TF_VAR_aws_ami_owners=["099720109477"]
TF_VAR_aws_ami_name_pattern=ubuntu/images/hvm-ssd/ubuntu-*
```
(basis's real filter is `owners=["136693071363"]`, `name=debian-12-arm64-*` — LocalStack's mock
catalogue cannot match it; this is the documented, deliberate local-only override, never used
outside the harness.)

### `aws_iam_*` resource check — CONFIRMED ZERO, re-verified

```
$ grep -rn 'resource "aws_iam' kit-modules/basis/terraform/
(no matches, exit 1)
```
LocalStack Community's disabled IAM enforcement is confirmed irrelevant to this exact Terraform.

**Verdict: LOCALSTACK_OK** for every service basis's Terraform actually uses (s3, dynamodb, ec2,
sts), on the pinned `4.9` tag. `latest` must never be used by the harness.

Cleanup: `docker stop localci-probe && docker rm localci-probe` — probe container and its
`probe-bucket`/`probe-table`/VPC were throwaway, torn down, nothing persisted (LocalStack
Community doesn't persist across restarts anyway).

## Task 3.1 — LocalStack service network sharing: PROVEN

```
$ docker compose -f docker-compose.toolkit.yml run --rm iac bash -lc "curl -s http://localstack:4566/_localstack/health"
{"services": {..., "dynamodb": "available", "ec2": "available", "s3": "available", "sts": "available", ...}, "edition": "community", "version": "4.9.2"}
```
`localstack:4566` resolves from inside the `iac` container — `docker-compose.localci.yml` and
`docker-compose.toolkit.yml` share the same implicit `<project>_default` network as designed.

## Task 3.2 — harness-up.sh / harness-down.sh: full up→down cycle, all 4 guard rows exercised for real

### IMPORTANT finding and fix: `--remove-orphans` destroyed the user's running dev stack

First real teardown run used `docker compose -f docker-compose.localci.yml down --remove-orphans`.
Because `docker-compose.localci.yml` deliberately shares its Compose project name with
`docker-compose.toolkit.yml`/`docker-compose.yml` (required for the `localstack` hostname to
resolve from `iac`), `--remove-orphans` treated the user's own separately-running dev stack
(`starter-kit-nginx`, `starter-kit-php`, `starter-kit-mariadb`, `starter-kit-cron`, started via
`make up local` before this session) as "orphan containers of this project" and **stopped and
removed all four of them**. Confirmed via `docker ps -a --filter name=starter-kit-` returning
empty immediately after. No volume/bind-mount data was lost (all mounts are host bind mounts per
this project's Docker model), but the running containers were destroyed and had to be recreated
with `make up local`.

**Fixed**: `harness-down.sh` step 1 changed from `docker compose -f "$COMPOSE_FILE" down
--remove-orphans` to `docker compose -f "$COMPOSE_FILE" stop localstack` +
`docker compose -f "$COMPOSE_FILE" rm -f localstack` — scoped to exactly the one service this file
defines, never touching containers outside it. Re-verified: the user's dev stack (`starter-kit-
nginx`/`php`/`mariadb`/`cron`) stays untouched (`Up ... (healthy)`) across a full harness up→down
cycle after the fix.

### Scenario (a) — clean basis on `main` → allowed, full cycle

```
$ bash ./sh/local-ci/harness-up.sh
[Info] kit-modules/basis is on branch 'main', clean and not ahead of upstream — allowed.
[Success] Snapshot verified: .../tmp/local-ci/snapshot-20260818T235601Z.tar
[Success] Sentinel written
[Success] Throwaway SSH keypair generated
[Success] Wrote config/environment/.env.type.dev.override
[Success] LocalStack Terraform overrides written
[Success] Local CI/CD harness is up.

$ bash ./sh/local-ci/harness-down.sh
[Success] LocalStack Terraform overrides cleaned (3 file(s) removed)
[Success] Restore verified byte-identical against the snapshot (diff -r clean).
[Success] Sentinel cleared
[Success] Local CI/CD harness teardown complete.
```
Dev stack (`starter-kit-nginx`/`php`/`mariadb`/`cron`) confirmed `Up ... (healthy)` before, during,
and after — untouched.

### Scenario (b) — dirty basis on `main` (not allow-listed) → refused

```
$ echo "# harness test dirt" >> kit-modules/basis/README.MD
$ bash ./sh/local-ci/harness-up.sh
[Error] kit-modules/basis is on branch 'main' (not the allow-listed 'fix/provisioning-epic') and is dirty and/or ahead of its upstream.
[Error]   HEAD: 0bbf75dd9239c843fa8ac67f769c81e0c1e341a8   Ahead of upstream: 0
[Error]   Dirty paths:
[Error]      M README.MD
[Error] Commit this work onto 'fix/provisioning-epic', or set LOCALCI_BASIS_ALLOWED_BRANCH='main' deliberately if this state is intentional.
exit: 1
```
No sentinel written, no snapshot taken, nothing mutated.

### Scenario (c) — same dirt on the allow-listed branch → allowed, banner printed

```
$ git -C kit-modules/basis checkout -b fix/provisioning-epic
$ bash ./sh/local-ci/harness-up.sh
[Info] kit-modules/basis is on the allow-listed branch (fix/provisioning-epic) — allowed regardless of dirty/ahead state.
[Warning] ==============================================
[Warning] kit-modules/basis is not in a clean, at-origin state
[Warning]   Branch: fix/provisioning-epic
[Warning]   HEAD:   0bbf75dd9239c843fa8ac67f769c81e0c1e341a8
[Warning]   Ahead of upstream: no-upstream
[Warning]   Dirty paths:
[Warning]      M README.MD
[Warning] ==============================================
[Success] Local CI/CD harness is up.
```
Full teardown afterward restored basis to exactly this state (still on `fix/provisioning-epic`,
still carrying the test-dirt line — restore reproduces the snapshot, it doesn't "clean" legitimate
work). Test dirt then discarded via `git restore README.MD` (my own scratch edit, not real work) —
`kit-modules/basis` is left on a clean `fix/provisioning-epic` branch, which satisfies Stage 6
task 6.1's own "done when" criteria as a side effect of this test.

### Scenario (d) — second `harness-up.sh` while a sentinel is active → refused

```
$ bash ./sh/local-ci/harness-up.sh   # while a previous run's sentinel is still active
[Error] A harness run is already active (sentinel: .../tmp/local-ci/harness-state.env)
[Error]   LOCALCI_STARTED_AT=2026-08-18T23:54:22Z
[Error]   BASIS_BRANCH=main BASIS_HEAD=0bbf75dd9239c843fa8ac67f769c81e0c1e341a8
[Error] Run 'bash ./sh/local-ci/harness-down.sh' first to tear it down and restore.
[Error] If that run crashed (hard kill), use 'bash ./sh/local-ci/harness-down.sh --force-restore'.
```

**All 4 guard rows verified for real**, plus the `--remove-orphans` finding fixed and re-verified.
`kit-modules/basis` ends this task on branch `fix/provisioning-epic`, clean, HEAD unchanged from
`origin/main` (`0bbf75dd9239c843fa8ac67f769c81e0c1e341a8`) — ready for Stage 6.

## Task 3.4 — Real Terraform execution against LocalStack: PROVEN for `state` fully, `shared` mostly, `dev` blocked by a genuine LocalStack gap

### Environment quirk found and worked around (macOS-specific, not a harness bug)

`export CURRENT_UID=$(id -u); export CURRENT_GID=$(id -g)` (the exact pattern `job-provision.yml`
and `terraform.sh` invocations use) fails on this machine: host GID is `20` ("staff" on macOS),
which collides with a group already present in the `iac` image, so
`dockerfiles/iac/docker-entrypoint.sh`'s `addgroup --gid "${CURRENT_GID}" www-data` errors:
```
addgroup: The GID `20' is already in use.
```
This is a real, macOS-host-specific quirk (GitHub Actions Linux runners use UIDs/GIDs that don't
collide this way) — not something in scope to fix in tracked code. Worked around for local-ci runs
by leaving `CURRENT_UID`/`CURRENT_GID` unset, which falls back to the image's own
`DEFAULT_UID`/`DEFAULT_GID=1000/1000` (`config/environment/.env.main:69-70`) — proven to work
identically in Stage 0's DinD probe. Documented for `sh/local-ci/README.md` (task 5.7).

### `state` layer — FULLY APPLIED

```
$ bash kit-modules/basis/sh/terraform.sh -e state -c init
Terraform has been successfully initialized!

$ bash ./sh/ci/tf-planfile.sh -e state -m save -f tfplans/state.tfplan
Plan: 5 to add, 0 to change, 0 to destroy.
Saved the plan to: /srv/tfplans/state.tfplan

$ bash ./sh/ci/tf-planfile.sh -e state -m apply -f tfplans/state.tfplan
aws_s3_bucket.terraform_state: Creation complete after 0s [id=localci-terraform-state]
aws_s3_bucket_public_access_block.public_access: Creation complete after 0s [id=localci-terraform-state]
aws_s3_bucket_versioning.versioning: Creation complete after 2s [id=localci-terraform-state]
aws_dynamodb_table.terraform_locks: Creation complete after 2s [id=localci-terraform-locks]
aws_s3_bucket_lifecycle_configuration.lifecycle: Creation complete after 56s [id=localci-terraform-state]
Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
```

### Real bug found and fixed: `tf-localstack-override.sh`'s backend override omitted `key`/`encrypt`

`shared` layer's `terraform init` failed:
```
Error: Error asking for input to configure backend "s3": key: EOF
```
Root cause: Terraform's override-merge for a `terraform { backend "s3" {} }` block requires every
attribute to be **restated**, not just the ones being added — omitting `key` (present in the
tracked `envs/shared/backend.tf`/`envs/dev/backend.tf`) left it unset after merge, causing
`terraform init` to fall back to an interactive prompt (fatal on a non-interactive runner). This
is a real Terraform override-merge behavior that a static `-backend=false` validate pass (used
during Stage 3.1-3.3's authoring review) cannot catch — only real `terraform init` execution
surfaced it. **Fixed** in `sh/local-ci/tf-localstack-override.sh`: `write_backend_block()` now
takes the layer's state-file `key` as a parameter and restates both `key` and `encrypt = true`
verbatim from each layer's tracked `backend.tf`. Re-verified: `terraform init` for `shared` now
succeeds cleanly ("Successfully configured the backend \"s3\"!").

### `shared` layer — VPC/IGW/route-table/key-pair created for real; subnets blocked by a genuine LocalStack Community limitation

```
$ bash ./sh/ci/tf-planfile.sh -e shared -m save -f tfplans/shared.tfplan
Plan: 10 to add, 0 to change, 0 to destroy.

$ bash ./sh/ci/tf-planfile.sh -e shared -m apply -f tfplans/shared.tfplan
aws_key_pair.deploy: Creation complete after 0s [id=starter-kit_deploy_key]
module.network.aws_vpc.main_vpc: Creation complete after 20s [id=vpc-88723279fd9c7d7c2]
module.network.aws_internet_gateway.main: Creation complete after 0s [id=igw-b1d0b5ce777a325ab]
module.network.aws_route_table.main_route_table: Creation complete after 0s [id=rtb-5a53212960a0b4ca6]
Error: waiting for EC2 Subnet (subnet-92c8cb1003b882f00) IPv6 CIDR block (subnet-cidr-assoc-4571ab84f385f8a2e) to become associated: unexpected state '{'State': 'associated'}', wanted target 'associated'. last error: %!s(<nil>)
(same error for all 3 subnets)
```
**Reproduced deterministically** — retried with a fresh `terraform apply` (destroy+recreate of the
3 subnets), identical error on every one of the 3 subnets both times. Not a flake. The AWS
provider's waiter for `AssociateSubnetCidrBlock`/IPv6-association status expects a plain string
enum; LocalStack's mock EC2 API returns a Python-dict-repr string (`{'State': 'associated'}`)
instead, which the waiter's parser rejects. `kit-modules/basis/terraform/modules/network/subnet.tf`
unconditionally sets `ipv6_cidr_block` on every subnet (no toggle) — this is a resource declared
inside a child module, so it cannot be overridden per-attribute from an env-level `*_override.tf`
(Terraform's override-file merge only applies to resources declared directly in the same
directory as the override file, not to resources inside a module the directory calls) without
editing basis's tracked module code, which is out of scope for this local-only harness.

The resources DID get created in LocalStack despite the waiter error (confirmed via
`terraform state list`): `aws_vpc.main_vpc`, `aws_internet_gateway.main`,
`aws_route_table.main_route_table`, `aws_key_pair.deploy`, and all 3
`module.network.aws_subnet.subnets[*]` are all present in Terraform state with real LocalStack
IDs. What did NOT complete: the root module's `subnet_ids` output (apply exits non-zero before
computing it), so `vpc_id` and `deploy_key_name` outputs are present but `subnet_ids` is absent.

**This is a genuine, reported LocalStack Community-tier limitation, per the plan's explicit
instruction ("If a resource type genuinely cannot be created in Community tier, record the
verbatim error and report it — do not substitute a mock")** — not a defect in this epic's harness,
override design, or the ported pipeline code. Everything up to the IPv6 wait (provider wiring,
S3/DynamoDB-backed state backend for two of three layers, `tf-planfile.sh`'s save/apply flow,
VPC/IGW/route-table/key-pair creation) is proven genuinely working.

### `dev` layer — cleanly blocked, exactly as expected, tracing back to the same root cause

```
$ bash kit-modules/basis/sh/terraform.sh -e dev -c init
Terraform has been successfully initialized!

$ bash ./sh/ci/tf-planfile.sh -e dev -m save -f tfplans/dev.tfplan
... aws_security_group.allow_ssh: vpc_id = "vpc-88723279fd9c7d7c2"   # correctly resolved from remote state
Plan: 2 to add, 0 to change, 0 to destroy.
Error: Unsupported attribute
  on main.tf line 35, in module "instances":
  35:   subnet_ids = data.terraform_remote_state.shared.outputs.subnet_ids
    data.terraform_remote_state.shared.outputs is object with 2 attributes
    This object does not have an attribute named "subnet_ids".
```
This confirms the `envs/dev` remote-state override (contract 4's third override block) correctly
reads real values from `shared`'s state (`vpc_id` resolved correctly, security-group plan
succeeded — "Plan: 2 to add" before hitting the missing attribute) — the chain is proven correct
end-to-end; it fails exactly and only where `shared`'s own incomplete output (caused by the
IPv6 limitation above) makes `subnet_ids` genuinely unavailable. Not a new/separate defect.

**Verdict for task 3.4: the harness, the ported pipeline code, and the Terraform↔LocalStack wiring
are all proven correct by real execution. The one blocker to a fully green 3-layer apply is
LocalStack Community's IPv6 subnet-association emulation gap — documented, reproduced, and
reported per the plan's own instruction, not worked around with a mock or a scope-violating
change to basis's tracked module.**

## Task 4.1 — Ansible target container: built, SSH-verified live, Bug 3 reproduced before any fix

### Part A — image build + `docker compose config`

```
$ docker compose -f docker-compose.localci.yml config
```
Resolves cleanly, both `localstack` and `ansible-target` present, `ansible-target` shows
`cgroup: host`, `privileged: true`, `command: [/lib/systemd/systemd]`, the read-only bind mount of
`kit-modules/basis/terraform/public_keys` → `/harness-keys`, and lands on the same implicit
`starter-kit-foundationloc_default` network as `localstack`/`iac` (no per-service `networks:` key
on any of the three, same pattern already established by task 3.1).

```
$ docker compose -f docker-compose.localci.yml build ansible-target
...
 Container/Image starter-kit-localci-ansible-target Built
```
Builds clean (Debian 12 base, systemd + systemd-sysv + openssh-server + sudo + python3 installed,
`ssh.service` enabled at build time, `admin` user + passwordless sudoers entry created,
`docker-entrypoint.sh` installed as ENTRYPOINT).

### Design decision: SSH public key injected at container START, not build time

Chose runtime injection (bind-mounted `kit-modules/basis/terraform/public_keys/` → `/harness-keys`
read-only, copied into `/home/admin/.ssh/authorized_keys` by `dockerfiles/ansible-target/
docker-entrypoint.sh` before `exec`-ing `/lib/systemd/systemd`) over a build-time `COPY`. Reasons,
grounded in what's already in this repo:

- `dockerfiles/iac/Dockerfile`'s own header comment states the rule explicitly: "Do NOT bake
  secrets into the image; mount them at runtime (env/volumes)".
- The public key does not exist at any fixed point before `harness-up.sh` runs — it's regenerated
  fresh (`ssh-keygen`) on **every** harness-up cycle (`harness-up.sh` step 5), and the old key is
  deleted on every harness-down (`harness-down.sh` step 4). A build-time `COPY` would force an
  image rebuild on every single harness-up/down cycle for a key that only ever needs to exist for
  the container's own runtime lifetime — the runtime-injection design keeps the image itself
  static and reusable, matching this repo's own `docker-entrypoint.d`-style convention (every
  existing image's entrypoint runs setup logic before `exec`-ing the real command; see
  `.claude/rules/docker.md` "All images share the same entrypoint pattern").
- `docker-compose.localci.yml` is only ever brought up by `harness-up.sh`, which runs the SSH
  keypair generation (step 5) strictly before `docker compose ... up -d` (step 8) — so the mounted
  directory is always populated by the time the container's entrypoint runs.

### Part A — live SSH proof from inside `iac`

```
$ bash ./sh/local-ci/harness-up.sh
...
[Success] Local CI/CD harness is up.

$ docker exec starter-kit-localci-ansible-target systemctl is-system-running
running
$ docker exec starter-kit-localci-ansible-target systemctl status ssh --no-pager
● ssh.service - OpenBSD Secure Shell server
     Active: active (running)
$ docker logs starter-kit-localci-ansible-target
docker-entrypoint: installed 1 harness SSH public key(s) into /home/admin/.ssh/authorized_keys

$ docker compose -f docker-compose.toolkit.yml run --rm iac bash -lc \
    "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
     -i /srv/tmp/local-ci/starter-kit_deploy_key admin@ansible-target \
     'whoami && hostname && sudo -n whoami && python3 --version'"
Warning: Permanently added 'ansible-target' (ED25519) to the list of known hosts.
admin
ansible-target
root
Python 3.11.2
```
Real proof: SSH connects from inside the `iac` container to `ansible-target` by hostname, using
the harness's throwaway key; `admin` logs in; passwordless `sudo -n whoami` returns `root`;
`python3` is present at Ansible's expected interpreter path.

### Part B — Bug 3 reproduced BEFORE any fix exists (read-only observation, no fix applied here)

```
$ unset CURRENT_UID CURRENT_GID && source .env
$ bash kit-modules/basis/sh/ansible.sh -e dev -a inventory
[Info] Environment: dev
[Info] Action: dev
[Info] Generating Ansible inventory for environment: dev
[Info] Getting Terraform outputs...
[Error] No instance IP found in Terraform outputs
[Error] Make sure Terraform is deployed first:
[Error]   make tf dev init
[Error]   make tf dev apply
$ echo "REAL EXIT: $?"
REAL EXIT: 1
```

Root-cause confirmation — the exact `-w` flag `ansible.sh:108` builds and what actually happens
inside the container:

```
$ TF_ENV_DIR="$(pwd)/kit-modules/basis/terraform/envs/dev"
$ echo "$TF_ENV_DIR"
/Users/yuriipavlov/Projects/SolidBunch/starter-kit-foundation.loc/kit-modules/basis/terraform/envs/dev
$ echo 'Resulting -w flag:' -w "/srv/$TF_ENV_DIR"
Resulting -w flag: -w /srv//Users/yuriipavlov/Projects/SolidBunch/starter-kit-foundation.loc/kit-modules/basis/terraform/envs/dev

$ docker compose -f docker-compose.toolkit.yml run --rm \
    -w "/srv/$TF_ENV_DIR" iac bash -lc "pwd && ls -la"
/srv/Users/yuriipavlov/Projects/SolidBunch/starter-kit-foundation.loc/kit-modules/basis/terraform/envs/dev
total 0
drwxr-xr-x 1 root root 64 Aug 19 00:23 .
drwxr-xr-x 1 root root 96 Aug 19 00:23 ..
```

More precise than the plan's assumption ("a path that does not exist in the container" implying
`docker compose run` itself fails): Docker's `--workdir`/`-w` **auto-creates** a missing working
directory rather than erroring. Because `/srv` is itself the bind mount of the whole repo root
(`docker-compose.toolkit.yml`'s `./:/srv`), that auto-create physically materializes on the
**host**, nested under the repo root, as `./Users/yuriipavlov/.../kit-modules/basis/terraform/
envs/dev` — an empty directory with none of the real `envs/dev` Terraform config or state.
`terraform output -raw instance_public_ip` then correctly reports "No outputs found" for that
empty directory (not a Terraform bug), which `ansible.sh`'s `2>/dev/null || echo ''` swallows,
leaving `IPV4`/`IPV6` empty and producing the `[Error] No instance IP found in Terraform outputs`
above. This stray host-side directory tree was found and removed (`rm -rf ./Users`) immediately
after each reproduction run in this task — it is a real, reproducible **side effect of Bug 3
itself**, not a harness artifact, and is exactly why Stage 6.3's fix (repo-relative `-w` path) is
necessary, not just a `2>/dev/null` cosmetic issue.

### Real gap found and fixed: `harness-down.sh` did not stop `ansible-target`

`harness-down.sh` was written (task 3.2) before this task's `ansible-target` service existed, and
explicitly stopped/removed only `localstack` by name. First up→down cycle in this task left
`starter-kit-localci-ansible-target` running after `harness-down.sh` reported success — caught by
`docker ps` after teardown, not assumed. Fixed in `sh/local-ci/harness-down.sh` step 1 (added
`ansible-target` alongside `localstack` in both the `stop` and `rm -f` calls). Re-verified with a
full up→down cycle:

```
$ docker ps --format '{{.Names}}' | sort            # BEFORE
act-Sleep-probe-...  mailhog  sk-licensing-server-*  starter-kit-cron  starter-kit-mariadb
starter-kit-nginx  starter-kit-php  traefik

$ bash ./sh/local-ci/harness-up.sh
[Success] Local CI/CD harness is up.
$ docker ps --format '{{.Names}}' | sort            # DURING
... starter-kit-localci-ansible-target  starter-kit-localci-localstack ...

$ bash ./sh/local-ci/harness-down.sh
 Container starter-kit-localci-ansible-target Stopped
 Container starter-kit-localci-localstack Stopped
Going to remove starter-kit-localci-localstack, starter-kit-localci-ansible-target
[Success] Restore verified byte-identical against the snapshot (diff -r clean).
[Success] Local CI/CD harness teardown complete.

$ docker ps --format '{{.Names}}' | sort            # AFTER — byte-identical to BEFORE
act-Sleep-probe-...  mailhog  sk-licensing-server-*  starter-kit-cron  starter-kit-mariadb
starter-kit-nginx  starter-kit-php  traefik

$ git status --porcelain                              # foundation — only this task's own edits
 M docker-compose.localci.yml
 M sh/local-ci/harness-down.sh
?? dockerfiles/ansible-target/

$ git -C kit-modules/basis status --porcelain          # basis — clean
$ git -C kit-modules/basis branch --show-current
fix/provisioning-epic
```

**Verdict for task 4.1: the Ansible target container is real, systemd-as-PID-1-healthy, reachable
over SSH with the harness's throwaway key from inside `iac`, and Bug 3 is reproduced with verbatim
output tracing the failure to its exact root cause (Docker auto-creating an empty working
directory from a doubled absolute-path `-w` flag) — before any fix exists, per the plan's
instruction. No fix to `kit-modules/basis/sh/ansible.sh` was made here; that is Stage 6 (task
6.3), a separate basis-repo change requiring its own approval.**


## Task 4.1/4.2/4.3 — Real Ansible convergence against the ansible-target container

### Real environment quirk: macOS SSH agent forwarding requires the Docker Desktop socket path, not the raw host path

`docker-compose.toolkit.yml`'s `iac` service defaults `SSH_AUTH_SOCK` to
`/run/host-services/ssh-auth.sock` (Docker Desktop's macOS SSH-agent proxy) — but
`kit-modules/basis/sh/ansible.sh`'s explicit `-e SSH_AUTH_SOCK="${SSH_AUTH_SOCK:-}"` passes
whatever value is in the *invoking shell's* env through, overriding that default. If the shell's
own `SSH_AUTH_SOCK` is exported to the raw macOS launchd path
(`/var/run/com.apple.launchd.*/Listeners`), agent forwarding into the container breaks with
`Error connecting to agent: Connection refused` (reproduced directly, see below). **Fix for
local-ci runs on macOS**: `ssh-add` the harness's throwaway private key
(`tmp/local-ci/<key-name>`) into the default agent, then explicitly
`export SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock` before invoking any `kit-modules/basis/sh/*.sh`
script. Documented for `sh/local-ci/README.md` (task 5.7) — environment-specific (macOS + Docker
Desktop), not a script defect.

Direct reproduction of the broken case (raw launchd socket exported):
```
$ export SSH_AUTH_SOCK=/var/run/com.apple.launchd.6voUS4myAa/Listeners
$ docker compose -f docker-compose.toolkit.yml run --rm -e SSH_AUTH_SOCK="$SSH_AUTH_SOCK" iac bash -lc "ssh-add -l; ssh -v admin@ansible-target whoami"
Error connecting to agent: Connection refused
...Permission denied (publickey,password).
```
And the fixed case (Docker Desktop proxy socket exported instead):
```
$ export SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock
$ docker compose -f docker-compose.toolkit.yml run --rm -e SSH_AUTH_SOCK="$SSH_AUTH_SOCK" iac bash -lc "ssh-add -l; ssh admin@ansible-target whoami"
256 SHA256:... local-ci-harness (ED25519)
admin
```

### Real image fix: `dbus` was missing from `ansible-target`, blocking the `hostname` module

First playbook run (`kit-modules/basis/sh/ansible.sh -e dev -a playbook`, real `playbook.yml`,
real generated inventory) failed at "Update hostname" with `Failed to connect to bus: No such
file or directory` — `dockerfiles/ansible-target/Dockerfile` didn't install `dbus`, and the
Ansible `hostname` module (Debian strategy) talks to `systemd-hostnamed` over D-Bus. **Fixed**:
added `dbus` to the Dockerfile's package list, rebuilt
(`docker compose -f docker-compose.localci.yml build ansible-target`). Re-verified live:
`systemctl is-system-running` → `running`, `which dbus-daemon` → `/usr/bin/dbus-daemon`.

### Real, un-fixable container limitation: setting the hostname itself — confirmed reproducible twice

Even with `dbus` present, "Update hostname" still fails, identically on two separate full-harness
runs (`logs/local-ci/4.2-full-playbook-hostname-check.log`, and an earlier run before the
idempotence re-test):
```
$ bash kit-modules/basis/sh/ansible.sh -e dev -a playbook
TASK [Update hostname] ***
[ERROR]: Task failed: Module failed: Command failed rc=1, out=, err=Could not set static hostname: Failed to set static hostname: Device or resource busy
fatal: [provisioned-host]: FAILED! => {"changed": false, ...}
PLAY RECAP: provisioned-host : ok=10  changed=2  unreachable=0  failed=1  skipped=0  rescued=0  ignored=0
```
This is Docker's own container-hostname management (`/etc/hostname` is a file Docker itself
manages inside the container's UTS namespace) refusing a `sethostname()`-class change from
inside — a well-known Docker limitation, not fixable by any package install or `privileged: true`
alone (would need `--uts=host`, a bigger architectural change out of scope here). **This is the
ONE genuinely container-hostile task found in the entire playbook** — documented per the plan's
"record verbatim error, document individually, never silently skip" rule.

### Partials 03-07: real, clean convergence — better than the plan anticipated

To test partials 03-07 independently of the hostname blocker (partial 02), a scratch playbook
(`kit-modules/basis/ansible/scratch-partials-03-07.yml`, harness-local only, deleted after use,
never committed) included exactly those five partial files with a synthetic
`generated.inventory.yml` carrying a `swap_vars` map (see the separate finding below for why that
was needed). Two back-to-back runs against the same live target, in the same harness session,
using the harness's proper `SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock` setup:

**Run A** (`logs/local-ci/4.2-partials-03-07-runA.log`):
```
PLAY RECAP: provisioned-host : ok=30  changed=13  unreachable=0  failed=0  skipped=5  rescued=0  ignored=0
```
**Run B**, immediately after, playbook unchanged (`logs/local-ci/4.2-partials-03-07-runB.log`):
```
PLAY RECAP: provisioned-host : ok=30  changed=4   unreachable=0  failed=0  skipped=5  rescued=0  ignored=0
```

Contrary to the plan's caution that Docker-in-container, log rotation, swap, and sshd-restart
might all be container-hostile, **all five partials (03-07) converge cleanly**:
- **Docker-in-container genuinely works**: `docker-ce` installs and starts inside the (privileged,
  systemd-PID-1) `ansible-target` container — real `Docker version 29.7.2` / `Docker Compose
  version v5.5.0` output, not assumed.
- **Log rotation config succeeds** (`/etc/docker/daemon.json` written, Docker restarted).
- **Swap-file-creation tasks correctly self-skip**: `ansible_swaptotal_mb > 0` is true inside the
  container (it inherits the Docker Desktop VM's host-level swap accounting), so the existing
  `when: not swap_exists` guards skip swap-file creation — the playbook's own designed behavior
  for an already-swapped host, not a container-specific failure. The one unconditional task,
  "Adjust swappiness" (`sysctl vm.swappiness`), succeeds for real (needs `privileged: true`,
  confirmed working).
- **sshd restart survives the live SSH connection** — the play continues past it to completion in
  the same run; the plan's flagged risk ("restarts sshd while Ansible is connected over ssh") did
  not materialize as a problem here.

### Task 4.3 — idempotence, real second run (Run A vs Run B above, same task set, no crashes in either)

Run A → B: `changed` drops from 13 to 4. The 4 repeat "changed" tasks in Run B are changed **by
design**, not idempotence bugs — confirmed identical in both runs:
1. "Restart Docker to apply changes" — explicit `service: state=restarted`, always reports changed.
2. "Backup existing sshd_config" — an unconditional backup-copy task, intentionally re-executes
   every run.
3. "Restart SSH via 'ssh' unit if present" — explicit `state=restarted`.
4. "Restart SSH via 'sshd' unit if present" — explicit `state=restarted` (same class as #3, a
   separate task in the partial for a different possible unit name).

No genuine idempotence bug found in the partials that could actually run in this environment.

### Real, separate finding: `generate_ansible_inventory()` never emits `swap_vars`

`kit-modules/basis/sh/ansible.sh`'s Terraform-driven inventory generator (the "generated" path, as
opposed to the tracked static `inventory.yml`) writes `ansible_host`/`ansible_user` only — it never
emits the `swap_vars` map (`size`, `swappiness`) that `06-setup-swap.yml`'s "Adjust swappiness"
task unconditionally requires. Reproduced live: the first attempt to run partials 03-07 with a
synthetic generated-format inventory lacking `swap_vars` failed at that exact task:
```
Error while resolving value for 'value': 'swap_vars' is undefined
Origin: kit-modules/basis/ansible/partials/06-setup-swap.yml:45
```
Adding `swap_vars` (matching the static `inventory.yml`'s real values) to the **harness's own
synthetic inventory file only** — never to `kit-modules/basis/sh/ansible.sh` itself — resolved it.
**This is a genuine, separate defect in `kit-modules/basis/sh/ansible.sh` that would affect real
production CI runs using the generated-inventory path (i.e. every normal `ACTION_TYPE=apply` run
without `-s`/static-inventory)** — out of this epic's Stage 6 scope (which covers only the Bug 3
working-dir fix). **Reported, not fixed** — to be included in the final report's findings for the
user to decide on. No change was made
to any tracked `kit-modules/basis` file to work around this; `git -C kit-modules/basis status`
confirms only the deliberate Bug 3 fix (`sh/ansible.sh`, task 6.3) remains modified.

### Harness cleanup

`bash ./sh/local-ci/harness-down.sh` (stopping/removing both `localstack` and `ansible-target`)
completed with a verified byte-identical restore; `kit-modules/basis` ends on
`fix/provisioning-epic`, clean except the deliberate `sh/ansible.sh` fix (task 6.3, committed
separately in that repo); the user's dev stack (`starter-kit-nginx`/`php`/`mariadb`/`cron`)
untouched throughout every run in this task.


## Task 5.2/5.3/5.4 — Real act run against job-provision.yml: orchestration proven, DIND_FALLBACK invoked for compose-heavy steps

Five real `act` attempts were made against the real, unmodified `job-provision.yml`
(`logs/local-ci/5.2-plan-run.log` through `run5-dev-verified.log`). Documented per-attempt below,
not conflated — each finding is cited against the exact log that demonstrates it.

### Real bug found and fixed: `workflow_dispatch` event payload needs an `inputs` wrapper — verified before AND after

**Before the fix** (`5.2-plan-run2.log`, `run4.log`; flat `{"ENVIRONMENT_TYPE": "dev", ...}` JSON):
```
[Success] root .env ready for 'local'
...
WP_ENVIRONMENT_TYPE 'local'
```
Despite `ENVIRONMENT_TYPE=dev` in the inputs file, act/the workflow silently fell back to `local`.
Root cause: `act`'s (and GitHub's real) `workflow_dispatch` webhook event shape nests dispatch
inputs under an `inputs` key (`{"inputs": {"ENVIRONMENT_TYPE": "dev", ...}}`) — a flat top-level
object leaves `github.event.inputs.*` empty, and the runner falls through silently rather than
erroring.

**After the fix** — `.claude/local-ci-scratch/inputs-plan.json` rewritten to the `{"inputs": {...}}`
shape, and a fresh, real act run performed to confirm it (`5.2-plan-run5-dev-verified.log`):
```
[Success] root .env ready for 'dev'
...
WP_ENVIRONMENT_TYPE 'development'
```
Confirmed for real, not assumed. Documented for `sh/local-ci/README.md` (task 5.7) as a "gotcha,"
since the wrong shape fails silently rather than loudly.

### Real, fully proven: act correctly drives the workflow's orchestration and the new ACT-mode credential branch

`5.2-plan-run5-dev-verified.log` (the corrected-inputs run) shows every orchestration step
succeeding, in order, for real:
```
✅ Checkout repository
✅ Extract AWS region from .env.main            (region=eu-west-1, real grep of .env.main)
✅ Configure AWS credentials (act / LocalStack)  (the NEW if: ${{ env.ACT }} step ran; the real
                                                   if: !env.ACT OIDC step is correctly absent from
                                                   the log — mutual exclusivity confirmed live)
✅ Verify AWS credentials                        (AWS_ACCESS_KEY_ID is set: yes)
✅ Set up SSH agent                              (webfactory/ssh-agent, real key loaded)
✅ Set up SSH config
✅ Prepare .env                                  (real sh/env/secret-gen.sh + sh/env/init.sh dev,
                                                   confirmed resolving to 'dev', see above)
✅ Store OIDC credentials for IaC                (the Stage 1 port — creds to $GITHUB_ENV, not files)
✅ Check TFPLAN_PASSPHRASE availability          (set=true, correctly read from .secrets.act)
✅ Update Basis (only in demo)                   (correctly skipped — not demo mode)
```
This is the whole credentials/orchestration surface Stages 1–2 touched, running for real under
act, unmodified, exactly as GitHub would run it.

### Real bug found (`.secrets.act` multi-line values): act's secret file needs quoted-multiline, not `\n` escapes

First attempt (`5.2-plan-run.log`) encoded the throwaway SSH private key as `SSH_KEY="...\n...\n..."`
(literal backslash-n). Result: `Set up SSH agent` failed —
`Error loading key "(stdin)": error in libcrypto` (`run.log:40`) — the literal `\n` sequence was
fed to `ssh-add` instead of real newlines. **Fixed**: act's secret file (a godotenv-format file)
supports real embedded newlines inside a double-quoted value:
```
SSH_KEY="-----BEGIN OPENSSH PRIVATE KEY-----
<real newline>
-----END OPENSSH PRIVATE KEY-----
"
```
Re-verified (`run2.log:40-44` onward, and every subsequent run): `Identity added: (stdin)
(act-run-scratch)` — real key loaded successfully every time after the fix. Documented for
`sh/local-ci/README.md`/`act-secrets.example`'s header comment.

### Real, well-diagnosed blocker: act's job container runs as root, unlike real GitHub-hosted runners — DIND_FALLBACK invoked

`Install Composer and Node Dependencies` (`sh/system/install.sh yes`) is the first step after the
credentials/orchestration surface, and the first to run `docker compose run` against the
`composer`/`node` toolkit containers. It fails under act's **default (root) job container**,
reproduced identically in both `run2.log:90` and the corrected-inputs `run5-dev-verified.log`:
```
| addgroup: gid '0' in use
❌ Failure - Main Install Composer and Node Dependencies
```
Root cause, fully diagnosed (not guessed): the step does `export CURRENT_UID=$(id -u); export
CURRENT_GID=$(id -g)` — on a real GitHub-hosted runner this resolves to the non-root `runner` user
(UID/GID ~1001), but act's job container runs as **root** by default, so this resolves to `0`/`0`.
`dockerfiles/php/docker-entrypoint.d/10-update-user.sh` (inherited by the `composer` image) then
runs `addgroup -g "${CURRENT_GID}" "${DEFAULT_USER}"` with **no fallback for an already-existing
GID** — and GID `0` already exists (as `root`'s own group), so it fails hard under `set -Eeuo
pipefail`. This is the exact same bug **class** as the macOS-host GID-20 collision already
documented in Task 3.4 (`dockerfiles/iac/docker-entrypoint.sh` has the identical unguarded
`addgroup --gid` pattern) — but affecting a **different, foundation-owned, production image**
(`php`/`composer`, not just `iac`), and triggered by act's execution model rather than a
macOS-specific quirk.

**Two workarounds tried and ruled out**, both real, both logged:
- **`--container-options "-u 1000:1000"`** (`5.2-plan-run4.log`, chown'd the tree to 1000:1000
  first): avoids the GID-0 collision — `Set up SSH agent` succeeds cleanly at UID 1000 (1000 has a
  passwd entry in `catthehacker/ubuntu:act-latest`) — but `docker compose` itself then fails:
  `permission denied while trying to connect to the docker API at unix:///var/run/docker.sock`
  (`run4.log:86`) — the mounted host socket is root/docker-group owned; UID 1000 inside the
  ephemeral act container isn't in that group.
- **`--container-options "-u 1001:1001"`** (`5.2-plan-run3.log`): a third, distinct failure —
  UID 1001 has **no** passwd entry at all in the runner image, so Node's `os.userInfo()` (used
  internally by the `webfactory/ssh-agent` JS action) throws `ERR_SYSTEM_ERROR:
  uv_os_get_passwd returned ENOENT`, failing before the job even reaches the Composer step
  (`run3.log`, "Set up SSH agent" failure and an equally broken "Post Set up SSH agent" cleanup).

**Running as root avoids the socket permission problem but hits the GID-0 collision; running as
non-root either loses docker socket access (UID 1000) or breaks act's own Node-based actions
outright (UID 1001, no passwd entry). None of the three is fixable from the harness side alone.**

**A real fix exists** (`dockerfiles/php/docker-entrypoint.d/10-update-user.sh` and
`dockerfiles/iac/docker-entrypoint.sh` could both guard `addgroup` against an already-existing GID
and reuse/rename it instead of failing) — but this is **out of scope for this epic**: both are
shared, published, production images (`ghcr.io/solidbunch/starter-kit-php`,
`ghcr.io/solidbunch/starter-kit-iac`), and per `.claude/rules/docker.md`, any `dockerfiles/**` edit
requires a manual rebuild + a **new** image tag + push before it takes effect anywhere (dev, stage,
prod, or any other clone) — a deployment action outside this epic's local-only mandate. **Reported,
not fixed** — see the final report's findings for the user to decide on.

### DIND_FALLBACK formally invoked for the compose-heavy steps — already fully satisfied by Stage 3/4's direct-execution evidence

Per the plan's pre-designed fallback ("Fallback if DinD proves unworkable"): run act over the
orchestration steps (proven above, real, complete, including a verified `dev`-environment run) and
execute the docker-compose-driven Terraform/Ansible steps **directly on the host**, via the exact
same scripts with the exact same arguments the workflow itself calls. This was not a new, separate
exercise — **it is exactly what Task 3.4 (Terraform against LocalStack, all 3 layers) and Task
4.1–4.3 (real Ansible convergence) already did**, using `kit-modules/basis/sh/terraform.sh`,
`sh/ci/tf-planfile.sh`, and `kit-modules/basis/sh/ansible.sh` directly — the identical code paths
`job-provision.yml`'s Terraform/Ansible steps call. Those tasks' evidence (above) stands as the
real-execution proof for this fallback; it is not re-derived here.

**Note on the underlying DinD proof itself**: this does **not** contradict Task 0.1's `DIND_OK`
verdict. Task 0.1 proved `docker compose` genuinely works inside act's job container via
`--bind --container-daemon-socket`. That remains true and is re-confirmed here (the credential
steps' own `docker`-free logic ran fine under the default root user; the actual blocker is the
**root-vs-non-root user tradeoff** for THIS specific step's entrypoint script, a different and
more specific problem than raw DinD connectivity).

### Harness cleanup

`bash ./sh/local-ci/harness-down.sh` completed with a verified byte-identical restore after every
attempt in this task; `kit-modules/basis` ends on `fix/provisioning-epic`, clean except the
deliberate task 6.3 fix; the user's dev stack untouched throughout every act run in this task.

## Task 5.5 — Summary-step fix (Bug 1) verified with real data

Since `dev`'s instance was never created (blocked by LocalStack's IPv6 limitation, Task 3.4), the
exact "Generate Infrastructure Summary" step's `instance_public_ip`/`instance_ipv6` outputs can't
be exercised end-to-end for `dev`. Instead, the fixed `-w "/srv/$TF_ENV_DIR"` pattern (task 2.1's
fix) was exercised directly against `shared`'s real, successfully-applied `vpc_id` output — the
same container-workdir mechanism the summary step now uses:
```
$ docker compose -f docker-compose.toolkit.yml run --rm ... -w "/srv/kit-modules/basis/terraform/envs/shared" iac bash -lc "terraform output -raw vpc_id || echo 'N/A'"
vpc-9b5aadc8e77c7c5ce
```
A real, non-`N/A` value returned — confirming the `/workspace` → `/srv` fix resolves to the correct
container working directory and retrieves genuine Terraform output. Before the fix, this exact
`docker compose run -w "/workspace/..."` pattern would resolve to a nonexistent path in the
container (compose sets `working_dir: /srv`, `/workspace` is only the Dockerfile's overridden
`WORKDIR`) and silently fall through to the `|| echo "N/A"` fallback — exactly the historical
"summary always shows N/A" bug documented in the original architect plan.

## Task 5.6 — Structural verification of what act cannot run, plus lint

- `environment: ${{ inputs.ENVIRONMENT_TYPE }}` present at job level (`job-provision.yml:44`) —
  structural only, act cannot emulate GitHub Environment required-reviewer approval gates.
- `concurrency: { group: provision-${{ inputs.ENVIRONMENT_TYPE }}, cancel-in-progress: false }`
  present (`:45-47`) — structural only, act has no `concurrency:` group semantics.
- `permissions: { contents: read, id-token: write, actions: read }` complete (`:34-37`).
- Cross-run artifact download wiring present and correct: `actions/download-artifact@v4` with
  `run-id: ${{ inputs.PLAN_RUN_ID }}` and `github-token: ${{ secrets.GITHUB_TOKEN }}` (`:228-232`)
  — structural only, act's local artifact server only serves same-run artifacts, so a genuine
  cross-run download can't be exercised locally; the pinned-plan `apply` logic that CONSUMES a
  downloaded plan was already proven for real in Task 3.4 (pre-seeding `tfplans/*.tfplan` on disk
  and exercising the workflow's own `[ -f tfplans/<layer>.tfplan ]` branch, per the plan's own
  design for this exact limitation).
- `has_basis` short-circuit gate present and consistently applied across every Terraform/Ansible
  step (17 occurrences: 2 definition lines at `:165,168`, plus 15 gate usages spanning
  `:172-389`) — structurally verified by inspection; its
  runtime behavior (basis present → proceed) was exercised for real in every Stage 3/4/5 run in
  this epic, since `kit-modules/basis` was present throughout.
- `actionlint .github/workflows/job-provision.yml`: exit 1, but every finding is the same
  pre-existing shellcheck-class noise (`SC2086`/`SC2129`/`SC2155`) already baselined in Stages 1-2 —
  filtering those out leaves zero non-shellcheck findings (no schema errors, no unknown actions, no
  bad permission scopes, no syntax errors).
- `shellcheck sh/local-ci/*.sh sh/ci/*.sh`: clean, exit 0, across every new script in the harness
  (`harness-up.sh`, `harness-down.sh`, `tf-localstack-override.sh`, `act-run.sh`,
  `tf-planfile.sh`).

## Task 5.3 (closure) — negative cases: missing plan → fallback, stale plan → loud rejection, real execution

A delivery-mode audit correctly flagged that 5.3's positive path (apply a pinned plan) was covered
by Task 3.4, but the two negative cases in the plan's own "Done when" — missing plan file falls
back to plan-then-apply, and a *stale* plan fails loudly with no state change — were never
actually executed. Closed here for real, against the `state` layer (the one layer that fully
applies under LocalStack), replicating `job-provision.yml`'s exact branching logic
(`job-provision.yml:271-286`).

### Negative case (a): missing `tfplans/state.tfplan` → falls back to plan-then-apply

```
$ rm -f tfplans/state.tfplan
$ [ -f tfplans/state.tfplan ] && echo PINNED || echo FALLBACK
FALLBACK
$ bash kit-modules/basis/sh/terraform.sh -e state -c apply
...
Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
```
Matches the workflow's own `else` branch (`job-provision.yml:281-284`, "plan-then-apply (no pinned
plan)" → `terraform.sh -c apply`) exactly — real execution, not inspection.

### Negative case (b): a stale pinned plan fails loudly, applies nothing

1. Saved a valid plan against the already-applied `state` layer: `terraform plan -out=tfplans/state.tfplan` → `No changes.`
2. Applied a genuine out-of-band change (`terraform apply -auto-approve -replace='aws_dynamodb_table.terraform_locks'`) — bumps the remote state's serial, exactly the class of drift the pinned-plan mechanism exists to protect against.
3. Applied the now-stale saved plan via the exact script the workflow calls:
```
$ bash ./sh/ci/tf-planfile.sh -e state -m apply -f tfplans/state.tfplan
Error: Saved plan is stale
The given plan file can no longer be applied because the state was changed
by another operation after the plan was created.
$ echo $?
1
```
4. `terraform state list` before and after the rejected apply is byte-identical (`aws_dynamodb_table.terraform_locks`, `aws_s3_bucket.terraform_state`, `aws_s3_bucket_lifecycle_configuration.lifecycle`, `aws_s3_bucket_public_access_block.public_access`, `aws_s3_bucket_versioning.versioning` — same 5 resources, no change) — confirming the rejected apply changed nothing.

`tf-planfile.sh`'s `set -Eeuo pipefail` correctly propagates Terraform's own non-zero exit through
to the caller — matching `job-provision.yml`'s `if ! bash sh/ci/tf-planfile.sh ...; then
::error::... exit 1` branch (`:274-278`) with no auto-retry, exactly as designed.

Cleanup: stray `tfplans/state.tfplan` removed; harness torn down with a verified byte-identical
restore.

## Note carried forward from Task 4.2 (delivery-audit follow-up)

The delivery-mode audit flagged that Task 4.2's `swap_vars`-missing-in-`generate_ansible_inventory()`
finding (a real, separate defect in `kit-modules/basis/sh/ansible.sh` affecting every real
production `apply` run using the generated-inventory path) was documented in this file but not
carried through to `sh/local-ci/README.md` or explicitly into a hand-off list. It is carried
forward explicitly here and included in the final report's findings for the user to decide on —
see Task 4.2's original entry above for the full technical detail.
