---
paths:
  - "kit-modules/**"
  - "**/*.tf"
  - "**/*.tfvars"
---

# Infrastructure & kit-modules

`kit-modules/` holds Composer-installed sub-projects — each is its **own VCS repo**, git-ignored in
the foundation root. Never run `terraform` / `ansible` directly — always go through `make`.

Three modules: `basis` (IaC), `monitoring-client`, `monitoring-server`.

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
make ansible [env] [action] [static]      # ansible.sh
make basis                                # interactive shell in the IaC (`iac`) container
```

- Always `make tf [env] plan` and review the diff before `make tf [env] apply`.
- CI authenticates to AWS via **GitHub OIDC** (`basis/sh/oidc.sh`) — NEVER commit `.pem` keys,
  AWS access keys, or any credentials.
- Infrastructure changes ship through the `.github/workflows/` provision pipelines.

## monitoring — observability

- `kit-modules/monitoring-client/` — ships container logs from app servers to Loki via
  **fluent-bit** (`config/fluent-bit/`, own `docker-compose.yml`). Run with
  `make monitoring [mode]` (alias `make mon`).
- `kit-modules/monitoring-server/` — the **Grafana + Loki** server stack: its own
  `docker-compose.yml`, `config/` (grafana, loki, nginx, ssl, certbot), its own `iac/`
  (Terraform + Ansible) and `Makefile`. A standalone deployable — not part of the app environment.
