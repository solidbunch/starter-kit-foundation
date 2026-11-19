# Changelog

Foundation releases are git tags on `main` (`X.Y.Z`, no `v` prefix). Downstream projects record the
release they are based on in `FOUNDATION_VERSION` and are updated with the `upgrade-foundation`
skill, which reads the sections of this file between the project's version and the target.

Each release lists only what a downstream project must **do or know**. Routine changes stay in
`git log`. Use these headings, in this order, omitting empty ones:

- **Action required** — manual steps: a MariaDB version change, new secret names, new CI/CD
  secrets or variables, renamed or removed files the project may reference
- **Changed** — behaviour or defaults that change without a manual step
- **Added**

Bump rule: patch = fixes only; minor = new behaviour, no manual steps; anything under
**Action required** is at least a minor bump and gets called out in the release notes.

## Unreleased

### Action required

- **MariaDB 11.5 → 11.8 LTS** (`APP_DATABASE_IMAGE`). The image refuses to start when its
  `major.minor` differs from the one in `db-data/mariadb_upgrade_info` (version guard; patch bumps
  within a series start normally). After `make recreate`, start once with `MARIADB_AUTO_UPGRADE=1`,
  then remove it. Back up first (`make export`). Details: `.claude/rules/docker.md`, "MariaDB
  version guard".
- **iac image: Ansible 12.3.0 → 15.0.0 (ansible-core 2.19 → 2.22) on Debian 12 → 13**
  (`APP_IAC_IMAGE` 1.2.0). ansible-core 2.22 needs Python ≥3.13, hence the Debian 13 base. Core 2.19+
  tightened templating and conditionals, so existing playbooks can fail at run time even when
  `--syntax-check` passes. Run `make ansible dev playbook` (or `make localci ansible`) against a
  non-production environment before provisioning stage/prod.

### Changed

Security updates to the Foundation images (new tags, already published — `make recreate` pulls them):

- nginx 1.29.8 → 1.30.7 (stable branch, Alpine 3.24; fixes the HTTP/2, HTTP/3, TLS 1.3 and
  `resolver` advisories published up to 1.30.7)
- PHP 8.4.27 → 8.4.28 (php-fpm, php-cgi, timezone and DOM fixes)
- Composer 2.10.3 → 2.11.2 (command execution via `composer.lock`, zip symlink extraction)
- Alpine 3.24.3 → 3.24.4 (cron, certbot, `APP_PASS_GEN_IMAGE`, GitLab CI jobs)
- iac image 1.1.4 → 1.2.0: Terraform 1.17.0 → 1.17.2, Terragrunt 1.2.0 → 1.2.2, AWS CLI 2.38.5 →
  2.41.1 (Ansible and Debian: see Action required)

### Added

- `upgrade-foundation` skill (`/upgrade-foundation`) for updating downstream projects.
- `FOUNDATION_VERSION` convention (see `upgrade-foundation`).
