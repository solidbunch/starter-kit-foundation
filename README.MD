# StarterKit

### [Website](https://starter-kit.io) | [Documentation](https://starter-kit.io/docs/overview/)

## Overview

StarterKit is a baseline WordPress environment template built for rapid project initiation.
It provides a preconfigured Docker-based infrastructure and a custom starter WordPress theme designed for modern development workflow. The kit simplifies the handling of sensitive data, and supports flexible configuration across multiple environments.

- Docker-based environment
- Infrastructure as Code with Terraform
- Server provisioning with Ansible
- CI/CD pipelines via GitHub Actions
- Custom WordPress theme with FSE, SCSS, Composer and PSR-12
- Secure, scalable, and production-ready setup by default

StarterKit follows Infrastructure-as-Product principles:
you get local, staging, and production environments configured, provisioned, and deployed consistently across all stages.

[Watch the introduction video](https://youtu.be/uCQcxhVUsdc) to see how it works.

## Getting Started

See the [StarterKit installation guide](https://starter-kit.io/docs/installation/).

## Deployment via GitLab CI

Alongside the GitHub Actions pipelines, this repo also ships a GitLab CI/CD pipeline that deploys
to the **dev** server on every push to `develop`, and to the **production** server when a release
is started via **CI/CD → Pipelines → "Run pipeline"** with ref `master` (not a push-triggered
manual play button). Runs on plain GitLab.com shared runners — no self-hosted runner needed. See
`.claude/rules/gitlab-ci.md` for the full design.

To make it work, in the GitLab project set:

1. **Settings → CI/CD → Variables** — add, each scoped to its environment
   (`dev` / `production`) via the variable's "Environment scope" field so the same variable name
   can hold different dev/prod values without any extra `_PROD` naming in the YAML:

   | Variable | Type | Protected | Env scope | Notes |
   |---|---|---|---|---|
   | `SSH_KEY` | File | yes | `dev` | Private deploy key for the dev server. |
   | `SSH_KEY` | File | yes | `production` | Private deploy key for the prod server. |
   | `SSH_CONFIG` | File | yes | `dev` | SSH client config defining the host alias used by `DEPLOY_SSH_HOST`. |
   | `SSH_CONFIG` | File | yes | `production` | SSH client config defining the host alias used by `DEPLOY_SSH_HOST`. |
   | `COMPOSER_AUTH` | Variable | yes | `All` | Composer auth JSON — needed to unlock licensed packages, see `infrastructure.md`. |

   Host-key trust for each server comes entirely from its `SSH_CONFIG` (same as the GitHub Actions
   pipeline) — no separate known_hosts variable needed, unless you'd rather manage it via the
   optional `SSH_KNOWN_HOSTS` file variable.

2. **`develop` and `master` branches** — dev deploys trigger on push to `develop`; prod deploys
   trigger only from a web-triggered "Run pipeline" on `master`. The branch is configured in two
   adjacent blocks of `.gitlab-ci.yml`: the `workflow: rules` (gates whether a pipeline is created
   at all) and the `include: rules` (gates which environment's jobs are loaded). Both must be
   updated together if these branch names ever change.

3. (Optional, recommended for prod) **Settings → CI/CD → Protected environments** — protect the
   `production` environment to restrict who can trigger a prod release.

No self-hosted runner setup is required — this pipeline targets GitLab.com's shared runners out of
the box.

## Stay Connected

- Participate on [GitHub Discussions](https://github.com/solidbunch/starter-kit-foundation/discussions)
- Connect via [LinkedIn](https://www.linkedin.com/company/solidbunch)
