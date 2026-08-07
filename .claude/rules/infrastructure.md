---
paths:
  - "kit-modules/**"
  - "**/*.tf"
  - "**/*.tfvars"
---

# Infrastructure & kit-modules

`kit-modules/` holds Composer-installed sub-projects — each is its **own VCS repo**, git-ignored
in the foundation root. Never run `terraform` / `ansible` directly — always go through `make`.

Three modules: `basis` (IaC), `monitoring-client`, `monitoring-server` — plus opt-in `proxy`
(multi-instance reverse proxy, see below). A fourth licensed package, `starter-kit-addon`, follows
the same licensing mechanism but is a demo-only plugin, not part of normal project work — see the
one-line note at the end of this file instead of treating it as a fifth kit-module.

## How kit-modules are installed — licensing gates real code, not just presence

`composer.json` declares `basis`, `monitoring-client`, and `monitoring-server` as regular requires
(`solidbunch/basis`, `solidbunch/monitoring-client`, `solidbunch/monitoring-server`), resolved
from the private Composer repository `https://licensing.starter-kit.io/wp-json/skl/v1/`. `proxy`
is **not** a default require — it's opt-in, added manually with `composer require solidbunch/proxy`
on servers that need it (see below). Composer's `installer-paths` (`composer.json` →
`extra.installer-paths`) map packages of `type:kit-module` into `kit-modules/{$name}/`.

**With a valid SolidBunch license/auth token, `composer install`/`update` always resolves the
real module code** — the three required modules are not optional once licensed; they're a normal
part of the stack and should be present in `kit-modules/` whenever a license is configured.
**Without a valid license**, the licensing repo serves an empty `metapackage` stub instead — check
`composer.lock`: an unlicensed module shows `"type": "metapackage"` and `"description":
"Unavailable without a valid license. Module is skipped."`, with no `source`/`dist`.

So don't infer license state from directory presence alone — **always check `composer.lock`**,
because the two can disagree:

- A directory absent from `kit-modules/` can mean either "not installed yet" **or** "no valid
  license" — check `composer.lock`'s `type` field for that package before assuming.
- A directory can also be **present but stale**: if `composer update` runs later without
  `COMPOSER_AUTH` set (auth lost, token expired, ran outside the intended environment),
  `composer.lock` will show `metapackage` for a module whose directory on disk still holds real
  code from a previous licensed install. Composer does not clean up the stale directory by
  itself. Treat `composer.lock` as the source of truth for current license state, not what's
  sitting in `kit-modules/`.

Auth is supplied via the `COMPOSER_AUTH` env var (a serialized JSON credentials object — see
`sh/env/.env.secret.template`), consumed by the `composer` container's
`dockerfiles/composer/docker-entrypoint.d/30-composer-config.sh` and injected in CI from the
`COMPOSER_AUTH` GitHub secret (`job-deploy.yml`, `job-provision.yml`). Set it locally in
`config/environment/.env.secret` to unlock real module code.

## basis — Infrastructure as Code

`kit-modules/basis/` provisions AWS infrastructure (Terraform) and configures servers (Ansible).

### Terraform — `basis/terraform/`

```
envs/
  shared/   Shared infra (VPC, network, security groups) — apply FIRST
  dev/      Dev environment root config
  prod/     Prod environment root config
            each env: backend.tf, provider.tf, variables.tf, main.tf, outputs.tf
modules/    Reusable modules — called by the env root configs
  network/           vpc.tf, subnet.tf, route.tf, outputs.tf, variables.tf
  security_groups/   security_groups.tf, outputs.tf, variables.tf
  instances/         instances.tf, variables.tf  (EC2 instances)
state/      Bootstraps the S3 + DynamoDB state backend (bucket.tf) — run ONCE, before envs
public_keys/   SSH public keys for provisioned instances
```

- **New reusable module** → create `terraform/modules/<name>/` with its `*.tf` + `variables.tf` +
  `outputs.tf`; wire it into an environment with a `module "<name>" { source = "../../modules/<name>" }`
  block in `envs/<env>/main.tf`. Env root configs only compose modules + set variables.
- Environment-specific values come from `variables.tf` / `*.tfvars` — never hardcode account IDs,
  regions, AMIs, IPs.
- State is remote (S3 bucket + DynamoDB lock, configured in each `backend.tf`).
  NEVER commit `.tfstate` / `.tfstate.backup`.

### Ansible — `basis/ansible/`

```
inventory.yml   Target hosts
playbook.yml    Main playbook — includes the ordered partials
partials/       01-update-folders … 07-update-sshd-config — run in numeric order
config/sshd/    sshd_config.j2 template
```

- **New provisioning step** → add a numbered file in `partials/` and include it in `playbook.yml`
  at the correct position; keep the numeric ordering meaningful.

### Commands (wrappers in `basis/sh/`)

```bash
make tf [env] [init|plan|apply|destroy]   # terraform.sh — e.g. make tf dev plan
make ansible [env] [inventory|playbook]   # ansible.sh
make basis                                # interactive shell in the IaC (`iac`) container
```

- Always `make tf [env] plan` and review the diff before `make tf [env] apply`.
- CI authenticates to AWS via **GitHub OIDC** (`.github/workflows/job-provision.yml`, no static
  AWS keys) — NEVER commit `.pem` keys, AWS access keys, or any credentials.
- `job-provision.yml` short-circuits (skips Terraform/Ansible) if `kit-modules/basis` isn't
  installed — check the `has_basis` step output before assuming provisioning ran.
- Infrastructure changes ship through the `.github/workflows/job-provision.yml` workflow
  (`workflow_dispatch`, env + action type chosen at run time).

## monitoring — observability

- `kit-modules/monitoring-client/` — ships container logs from app servers to Loki via
  **fluent-bit**, its own `docker-compose.yml`. Run with `make monitoring [on|off]`
  (alias `make mon`).
- `kit-modules/monitoring-server/` — the **Grafana + Loki** server stack: its own
  `docker-compose.yml`, `config/` (grafana, loki, nginx, ssl, certbot), its own `iac/`
  (Terraform + Ansible) and `Makefile`. A standalone deployable — not part of the app environment.
- `monitoring-client` is only force-updated from `dist` in CI when the `IS_DEMO` repo variable is
  `true` (`job-deploy.yml` step "Update Monitoring & Addon" — see the trailing note below for why
  that step's name mentions an addon); normal deploys keep the locked version.

## proxy — optional multi-instance reverse proxy

`kit-modules/proxy/` (package `solidbunch/proxy`) is a **Traefik v3** reverse proxy for running
several StarterKit instances on one server. Unlike the other three modules, it's **not** in
`composer.json`'s `require` — install it manually only when needed:

```bash
composer require solidbunch/proxy
```

- Default setup (one instance per server) needs none of this — nginx binds 80/443 directly.
- With the module installed, each instance opts in via `APP_MULTI_INSTANCE=1` in `.env.main`;
  the foundation kit then merges the module's `docker-compose.instance.yml` into the instance
  stack (drops nginx's host port bindings, joins the shared `proxy` Docker network, adds Traefik
  labels for autodiscovery + ACME).
- Traefik itself runs as its own Compose project (`-p proxy`, `kit-modules/proxy/docker-compose.yml`),
  independent of any single instance's lifecycle — `make down` on one instance doesn't touch it
  or other instances.
- TLS certs live in the named volume `proxy_certs`; Traefik issues/renews them itself.
- Config: `kit-modules/proxy/config/traefik.yml` (static — entrypoints, ACME resolver; set the
  real `certificatesResolvers.le.acme.email` before going live) and
  `config/dynamic/middlewares.yml` (security headers, optional rate-limit middleware, hot-reloaded).
- `APP_MULTI_INSTANCE` defaults to `0` in `config/environment/.env.main`. The Makefile exposes a
  single `make proxy` target — `make proxy start|stop|logs`, and `make proxy deploy <env>` (used
  by CI) — that delegates to `kit-modules/proxy/bin/proxy.sh`; if the module isn't installed it
  prints a skip message (or fails loudly for `deploy`, since that path is CI-driven).
- All actual proxy behaviour — which compose files to merge, starting/stopping Traefik,
  deploy-time wiring, and apex-vs-subdomain routing — lives entirely in `kit-modules/proxy`; the
  foundation implements none of it.
- When `APP_MULTI_INSTANCE=1`, `sh/system/certbot.sh` and the cron SSL-renewal job both skip
  themselves — Traefik owns TLS in multi-instance mode.
- Full step-by-step workflows: `kit-modules/proxy/README.md`.

## `starter-kit-addon` — not relevant to normal project work

A fifth licensed package, installed as a plugin (`web/wp-content/plugins/starter-kit-addon/`) via
the same licensing mechanism as the kit-modules above. It exists purely for SolidBunch's own demo/
showcase deployments — it is not something end clients use, so don't spend attention on it unless
a task specifically touches demo/showcase deploys or `IS_DEMO`-gated CI steps.
