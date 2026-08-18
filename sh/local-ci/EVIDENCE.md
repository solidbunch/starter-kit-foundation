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
