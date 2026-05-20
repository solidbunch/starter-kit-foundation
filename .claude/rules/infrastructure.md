---
paths:
  - "kit-modules/basis/**"
  - "**/*.tf"
  - "**/*.tfvars"
---

# Infrastructure (Terraform + Ansible)

IaC lives in the `basis` kit-module (`kit-modules/basis/`) — installed via Composer, git-ignored in
the foundation root. It provisions AWS infrastructure (Terraform) and configures servers (Ansible).

## Commands — never run terraform/ansible directly, use make

```bash
make tf [env] [init|plan|apply]          # Terraform — e.g. make tf dev plan
make ansible [env] [playbook|inventory]  # Ansible — e.g. make ansible dev playbook
make basis                               # Open an interactive shell in the IaC container
```

These run inside the `basis` IaC container via `kit-modules/basis/sh/`.

## Rules

- Terraform state lives in a remote backend (S3 + DynamoDB) — NEVER commit `.tfstate` / `.tfstate.backup`.
- NEVER commit `.pem` / private keys or AWS credentials. CI authenticates to AWS via GitHub OIDC.
- Environment-specific values come from `.env` / `*.tfvars` — never hardcode account IDs, regions, IPs.
- Always run `make tf [env] plan` and review the diff before `make tf [env] apply`.
- Infrastructure changes are deployed through the `.github/workflows/` provision pipelines.
