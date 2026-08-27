---
paths:
  - ".gitlab-ci.yml"
  - ".gitlab/ci/**"
---

# GitLab CI/CD — dev + prod deploy pipeline

GitLab analog of the GitHub Actions deploy pipelines (`workflow-deploy-develop.yml` +
`workflow-deploy-production.yml` → `job-deploy.yml`, see `ci.md`). GitHub Actions stay in the repo
untouched and keep working — this is an additional, independent pipeline, not a migration. Runs on
**plain GitLab.com shared runners** — no self-hosted runner, no shell executor, no
`docker`/`docker compose` call anywhere in the CI files.

## Structure — branch-gated `include:` + `extends:`, jobs defined once

- `.gitlab-ci.yml` (root) — `stages: [build, deploy]`, the only `variables:` block in the whole
  pipeline (`APP_COMPOSER_IMAGE`, `APP_NODE_IMAGE`, `WP_DEFAULT_THEME`, environment-agnostic), the
  `workflow: rules` that gate pipeline creation, and 3 `include:` entries: the shared template file
  (unconditional) plus the two environment files, each gated by its own `rules:` on
  `$CI_COMMIT_REF_NAME`.
- `.gitlab/ci/deploy.gitlab-ci.yml` — the `job-deploy.yml` analog: ONLY hidden (leading-dot) job
  templates (`.build-composer`, `.build-node`, `.deploy`), fully parameterized by variables, zero
  environment-specific values. Hidden jobs are never added to a pipeline on their own, so this file
  is safe to include unconditionally even though only one environment's concrete jobs will ever
  extend it in a given pipeline.
- `.gitlab/ci/deploy-dev.gitlab-ci.yml` — the `workflow-deploy-develop.yml` analog: a top-level
  `variables:` block holding only `ENVIRONMENT_TYPE: dev`, `environment: name: dev` (no `url:` —
  see "Deriving the deploy target" below for why), and 3 concrete jobs (`build-composer`,
  `build-node`, `deploy-dev`) via plain `extends:` on the hidden templates — no `rules:` of its
  own, no interpolation. Only ever merged into a pipeline when the root `include:` rule matches
  `develop`. Nothing in this file names the deploy target — it's derived at deploy time from
  `APP_DOMAIN`, inside the `.deploy` template.
- `.gitlab/ci/deploy-prod.gitlab-ci.yml` — the `workflow-deploy-production.yml` analog: same shape
  (`ENVIRONMENT_TYPE: prod` in `variables:`, `environment: name: prod`, no `url:`), jobs
  `build-composer`, `build-node`, `deploy-prod`. Same target derivation as dev, reading
  `.env.type.prod`. No `when: manual` — triggering is controlled entirely by the root file's
  `workflow: rules` (see "Trigger matrix" below). Pair with a **protected `prod` environment**
  (Settings → CI/CD → Protected environments) to restrict *who* can run a prod release.

The deploy target (SSH alias, destination path) is not a literal in any of these files and is not
a GitLab CI/CD variable either — it's derived at runtime by `.deploy`'s `script:` from `APP_DOMAIN`
in `config/environment/.env.type.$ENVIRONMENT_TYPE`, tracked in git. See "Deriving the deploy
target" and "Required CI/CD variables" below for the full contract. `bootstrap-project` no longer
edits these files for this purpose.

### Why the two environment files never collide

`deploy-dev.gitlab-ci.yml` and `deploy-prod.gitlab-ci.yml` both define a job named
`build-composer` / `build-node`, and both carry a top-level `variables:` block — normally exactly
the setup that causes GitLab to deep-merge two included files' globals into one namespace, last
include winning (see "The bug this design avoids" below). What makes it safe here is that **the
two files are never included in the same pipeline**: each is gated by its own `rules:` on the
`include:` entry in `.gitlab-ci.yml` (`$CI_COMMIT_REF_NAME == "develop"` /
`== "main"`), so only one of them is ever merged in for a given branch. Verified against
`docs.gitlab.com/ci/yaml/includes/` — "Use `rules` with `include`" is GA syntax (no
experimental/beta banner), and its own supported-variables list for `include:` explicitly names
`$CI_COMMIT_REF_NAME` (not `$CI_COMMIT_BRANCH`, which the docs use in an example on the same page
but omit from that list — `CI_COMMIT_REF_NAME` is the one actually documented as safe to use
there).

**This is the one thing to keep intact when editing these files**: if the `rules:` on either
`include:` entry is ever removed, both env files merge again and the collision returns — see "The
bug this design avoids" below for exactly what that looked like.

## Pipeline shape — 2 stages, one environment's jobs per pipeline

```
stages: [build, deploy]

build-composer  (image: $APP_COMPOSER_IMAGE, entrypoint:[""])
      │ artifacts (needs: [build-composer])
      ▼
build-node      (image: $APP_NODE_IMAGE,     entrypoint:[""])
      │
      ▼  artifacts
deploy-dev / deploy-prod  (image: alpine:3.20 + rsync/openssh)  needs:[build-composer, build-node]
```

Each build job runs **natively inside the toolkit image itself** (set as the job's `image:`)
instead of shelling out to the toolkit compose file — that pattern only works with a self-hosted
shell-executor runner sharing a filesystem with the Docker daemon, which GitLab.com shared runners
do not provide. `entrypoint: [""]` bypasses the toolkit images' custom `ENTRYPOINT` (host-UID
remap, `COMPOSER_AUTH` logging) so the job's own `script` runs directly.

**`build-node` runs after `build-composer`, not in parallel with it** (`needs: [build-composer]`
on `.build-node`) — a correction from an earlier version of this doc, which claimed the two build
jobs were independent because "node's build needs only the git-tracked theme source." That premise
is false: `web/wp-content/themes/${WP_DEFAULT_THEME}/` is entirely git-ignored in this repo (`git
ls-files` returns nothing under that path). The theme is a Composer VCS package
(`solidbunch/starter-kit-theme`, `preferred-install: source`), so the whole theme directory —
including `package.json`, which `npm run install-${APP_BUILD_MODE} --prefix
"web/wp-content/themes/${WP_DEFAULT_THEME}"` requires — only exists on disk after
`.build-composer`'s top-level `composer install-${APP_BUILD_MODE}` checks it out. On GitLab.com's
shared runners each job starts from its own fresh clone with no shared filesystem, so without
`needs:`, `build-node` could start (and fail with `npm error enoent Could not read package.json`)
before or in parallel with `build-composer`. `.build-composer`'s `artifacts: paths:` therefore also
carries the whole theme directory (`web/wp-content/themes/${WP_DEFAULT_THEME}/`, not just its
`vendor/` subdirectory) so `build-node` receives the checked-out theme source, not only its PHP
deps. The deploy job in the `deploy` stage still `needs:` both `build-composer` and `build-node`
and receives their artifacts merged over a fresh clone, then rsyncs `./` to the target server and
runs the remote `make` sequence over SSH — that phase runs on the target server itself (which has
Docker), not on the runner. `resource_group: $ENVIRONMENT_TYPE` (one line in the shared `.deploy`
template) serializes concurrent deploys to the same server — relevant mainly for dev, which
auto-deploys on every push.

`.build-composer` calls the same shared script as GitHub Actions' `job-deploy.yml` for full
parity — `sh ./sh/ci/composer-extras.sh "$ENVIRONMENT_TYPE" "$IS_DEMO"`, after the two composer
installs — which runs `composer run switch-theme-dev` when `ENVIRONMENT_TYPE == dev` (switches the
theme to its `dev-develop` Composer VCS branch — see `ci.md` and root `CLAUDE.md`'s "Intentional
Quirks"; becomes a harmless no-op if a project has detached its theme from that Composer package,
e.g. via `bootstrap-project`'s monorepo option), and the `IS_DEMO`-guarded dist update of a fixed
set of demo-only packages (skipped unless the GitLab CI/CD variable `IS_DEMO` is `"true"`). See
`ci.md`'s "Shared deploy scripts (`sh/ci/`)" for which packages and the full script inventory —
this file does not repeat it.

**`artifacts: paths:` on `.build-composer` is an explicit whitelist, not a whole-directory
carry-over — keep it in sync with what `composer install-*` actually produces.** GitHub Actions'
`job-deploy.yml` sidesteps this entirely by caching the whole working directory (`actions/cache/save`,
`path: .`), so anything Composer creates there — including `kit-modules/` (installer-path for
`solidbunch/basis`/`monitoring-client`/`monitoring-server`, see `infrastructure.md`) — rides along
automatically. GitLab's `artifacts:` has no equivalent here (deliberately not using
`paths: ['.']`, which would also carry `.git`, caches, and other build noise into the deploy
job) — the list must be maintained by hand: `vendor/`, `web/wp-core/`, `web/wp-content/plugins/`,
`web/wp-content/mu-plugins/`, the whole `web/wp-content/themes/${WP_DEFAULT_THEME}/` directory
(not just its `vendor/` subdirectory — `build-node` also consumes this artifact for the theme's
git-ignored source, see "Pipeline shape" above), and `kit-modules/`. If a future Composer
installer path is added and this list isn't updated, that path silently never reaches the deploy
job or the server — rsync can't sync what was never copied into the deploy job's working directory
in the first place.

## The bug this design avoids

An earlier design held six concrete jobs — `build-composer`, `build-composer-prod`, etc. — split
across the two environment files, both included **unconditionally**, each setting its own
top-level `variables:` (`ENVIRONMENT_TYPE`, `DEPLOY_BRANCH`, `DEPLOY_SSH_HOST`, `DEPLOY_PATH`).
GitLab merges the global `variables:` of all included files into one namespace, later includes
winning — so every pipeline, regardless of which branch triggered it, resolved to whichever
environment file was listed last in `.gitlab-ci.yml`'s `include:`. A push to `develop` could
silently deploy with prod's `DEPLOY_PATH`.

A follow-up design tried `spec:inputs` (GitLab's typed-parameter mechanism for templates shared
*across projects*) to route around the shared namespace, which worked but required interpolated
job names (`"deploy-$[[ inputs.environment_type ]]"`) and a `spec:` header with several mandatory
inputs — solving a self-inflicted problem with more machinery than the actual GitLab-recommended
answer for a single repo's branch-only split: gate the `include:` itself (see "Why the two
environment files never collide" above), which removes the shared-namespace problem at the root
and lets both environments use plain, unsuffixed job names.

## Trigger matrix

`.gitlab-ci.yml`'s `workflow: rules` decides whether a pipeline is created at all; the `include:`
`rules:` then decides which environment's jobs are merged into it. No `when: manual` anywhere.

| Event | Pipeline created? | Jobs that run |
|---|---|---|
| push to `develop` | yes | 3 dev jobs, automatic |
| "Run pipeline" (web) on `develop` | yes | 3 dev jobs, automatic |
| push to `main` | **no** | — |
| "Run pipeline" (web) on `main` | yes | 3 prod jobs, automatic |
| push or web on any other branch | **no** | — |
| merge request / tag | **no** | — |

A prod release is started from CI/CD → Pipelines → "Run pipeline" with ref `main` — this is the
GitLab equivalent of GH's `workflow_dispatch: {}` on the prod workflow, not a push-triggered
pipeline with a manual play button. Both are "a trigger restricted to main, requiring a human
action"; this is the GH-parity reading. The branch literals appear twice — once in `workflow:
rules` (`$CI_COMMIT_BRANCH`), once in the `include: rules` (`$CI_COMMIT_REF_NAME`) — because
`include:` is evaluated before jobs/variables and cannot read this file's own `variables:` block,
so the two can't be factored into one shared value. Both occurrences live in the same file now
(`.gitlab-ci.yml`), in adjacent blocks — update both on a branch rename.

`SSH_KEY`/`SSH_CONFIG` don't need per-environment scoping unless dev and prod actually use
different values — define one `SSH_KEY`/`SSH_CONFIG` pair with scope `All` by default. Only add a
`dev`- or `prod`-scoped override (same variable name, GitLab UI) if that environment needs a
different key/config than the other; GitLab resolves the most specific matching scope, so an
override coexists with the `All` default without touching the pipeline YAML — the deploy job
always references plain `$SSH_KEY`/`$SSH_CONFIG`.

## Native secret generation — `pass_gen.sh`

`sh/env/secret-gen.sh` normally runs `pass_gen.sh` inside a throwaway `docker run alpine`
container purely to get a POSIX shell on any host OS, bind-mounting `./sh` at `/shell`.
`pass_gen.sh` resolves its template path relative to its own location (`dirname "$0"`), not a
hardcoded absolute string — so it needs no adaptation for either caller: under the local Docker
mount `$0` is `/shell/env/pass_gen.sh` (unchanged behavior); in CI, build jobs invoke it at its
real repo path, no mount/copy required:

```
(cd config/environment && sh "$CI_PROJECT_DIR/sh/env/pass_gen.sh")
```

`cd`-ing into `config/environment` first makes the script's relative `output_file=".env.secret"`
land directly in the right place — same trick `docker run`'s (unset) working dir + `docker cp`
achieves locally. The generated secret values are throwaway — never shipped (the rsync
`--exclude` list drops all `.env*` variants and the deploy server regenerates its own via
`make secret`) — the build only needs `init.sh` to have a `.env.secret` to concatenate into `.env`.

`COMPOSER_AUTH` is read **natively** by Composer (its own env-var support) in `build-composer` —
no `.env.secret` append needed, since the job runs Composer directly rather than through a
container fed by `.env`.

## Image-reference variables — config-time constraint

`image:` is resolved at pipeline-config time, before any `script` runs, so `APP_COMPOSER_IMAGE` /
`APP_NODE_IMAGE` cannot be sourced from `.env.main` dynamically — they are committed as plain
GitLab CI `variables:` in the root `.gitlab-ci.yml`, with a comment to keep them in sync with
`config/environment/.env.main`. A tag bump in `.env.main` must be mirrored there by hand.

The same constraint applies to `WP_DEFAULT_THEME`: it's interpolated into the `artifacts:
paths` / `artifacts: exclude` entries in `deploy.gitlab-ci.yml`'s `build-composer` and
`build-node` jobs (e.g. `web/wp-content/themes/${WP_DEFAULT_THEME}/vendor/`), which are also
resolved at pipeline-config time like `image:`. It's committed as a static `variables:` entry in
the root `.gitlab-ci.yml` for the same reason — sourcing it from `.env.main` at runtime would be
too late for `artifacts:` to pick it up, silently producing "no files to upload" for every theme
path. Keep it in sync with `config/environment/.env.main` by hand — including after a theme rename
via `bootstrap-project`.

`WP_DEFAULT_THEME` (and, if ever needed, `APP_COMPOSER_IMAGE`/`APP_NODE_IMAGE`) can also be
overridden without editing `.gitlab-ci.yml` at all: GitLab's CI/CD variable precedence puts a
project-level UI variable ahead of a file's top-level `variables:` block, so setting a same-named
project variable in **Settings → CI/CD → Variables** wins over the committed YAML default with
zero pipeline-YAML edits — the committed value is effectively just an overridable default, not a
hard requirement to edit in place.

## Deploy job image

`alpine:3.20` + `apk add --no-cache openssh-client rsync` in `before_script` — no toolkit image
bundles both cleanly, and the deploy job only needs `rsync`/`ssh`, not the full source tree logic
(the heavy `make` work runs on the remote server). `git` is intentionally **not** installed —
GitLab's Docker executor performs the clone and artifact extraction in its helper image, not the
job image.

## Deriving the deploy target — `script:`, not `before_script:`

`.deploy`'s `script:` is a single entry, `sh ./sh/ci/deploy.sh "$ENVIRONMENT_TYPE"` — the same
shared script GitHub Actions calls (see `ci.md`'s "Shared deploy scripts (`sh/ci/`)"). `deploy.sh`
sources `sh/ci/resolve-deploy-target.sh`, which resolves `ENV_FILE` to
`./config/environment/.env.type.${ENVIRONMENT_TYPE}`, fails the job immediately (`echo "Error:
…"; exit 1`) if that file doesn't exist or `APP_DOMAIN` greps out empty, and otherwise `export`s
`APP_DOMAIN` and `DEPLOY_PATH="/srv/$APP_DOMAIN"` for the rest of `deploy.sh`'s shell. Every later
`ssh`/`rsync` call in `deploy.sh` uses `"$APP_DOMAIN"` as the SSH destination alias and
`"$DEPLOY_PATH"` as the remote path — no CI/CD variable involved at any point.

The derivation runs as part of the **`script:` invocation**, not `before_script:`. GitLab
concatenates `before_script` and `script` into one shell context, so an `export` from a
`before_script:`-invoked script would in practice survive into `script:` — but relying on that
undocumented-for-this-purpose behavior is one fewer platform assumption to make in a file nobody
here can authoritatively lint. Keeping the call in `script:` costs ~10s (the `apk add` and
`setup-ssh.sh` call in `before_script:` still run first) and keeps the derivation unconditionally
in the scope that consumes it. `after_script` needs neither value (it only deletes `~/.ssh/*`), so
it's unaffected either way.

**Zero CI/CD variables are required for the deploy target on either platform.** The only
GitLab-side configuration this pipeline needs is what already existed before this design:
`SSH_KEY`, `SSH_CONFIG`, `COMPOSER_AUTH`, and the optional `APP_MULTI_INSTANCE` — see "Required
CI/CD variables" below. `stage` needs no deploy-target configuration either: `.env.type.stage`
already carries its own `APP_DOMAIN`, so `.deploy` would resolve a stage target for free the
moment a stage environment file/pipeline exists — see `kit-modules/basis/CLAUDE.md` for the rest
of the stage gap this does not close.

**Contract: `SSH_CONFIG`'s `Host` block name must equal that environment's `APP_DOMAIN`.** This is
now a requirement, not a coincidence — every existing install already satisfies it (its `Host`
alias already equals the environment's domain), but a project using an unrelated alias name (e.g.
`prod-server-1`) would now break with `Could not resolve hostname`.

`environment: url:` is gone from both `deploy-dev` and `deploy-prod` — nothing replaces it.
Deriving `https://$APP_DOMAIN` was considered and rejected: `environment:url` is expanded by
GitLab at job level, so a value computed in `script:` can only reach it through a `report: dotenv`
artifact, which is more machinery for a cosmetic link. The environment now simply shows no "View
deployment" link, same as any project that never configured one. One thing worth knowing: because
GitLab re-evaluates `environment:url` on every deployment, the first deploy after this change
**clears** whatever URL an environment currently shows in the GitLab UI — expected, not a bug.

### Migrating off the earlier `DEPLOY_SSH_HOST` / `DEPLOY_PATH` / `DEPLOY_ENV_URL` design

An earlier revision of this pipeline read the deploy target from three environment-scoped GitLab
CI/CD variables. None of them are read anywhere anymore — if a repo still has them set (scope
`dev`/`prod`), delete them; they are dead configuration that looks load-bearing but isn't.
On GitLab specifically, a leftover `DEPLOY_PATH` UI variable is harmless even if left in place: the
`script:`-level `export DEPLOY_PATH=...` overwrites it before first use, so a stale UI value can't
win — but it should still be removed so the UI doesn't accumulate configuration that looks
load-bearing. This migration is not disruptive to deploys themselves: the derived values equal
what those variables held for every existing install (the old alias values were already exactly
the environment's domain), so no server-side change is needed.

## Required CI/CD variables

- `SSH_KEY` (File, protected, scope `All`; scope `dev`/`prod` only to override) — private deploy
  key for the target server(s).
- `SSH_CONFIG` (File, protected, scope `All`; scope `dev`/`prod` only to override) — SSH client
  config; must define a `Host` block whose name is that environment's `APP_DOMAIN` (see "Deriving
  the deploy target" above).
- `COMPOSER_AUTH` (Variable, protected, scope `All`) — Composer auth JSON, needed to unlock
  licensed packages (see `infrastructure.md`).
- `IS_DEMO` (Variable, optional, scope `All`) — demo/showcase mode — forces a `composer update` of
  demo-only packages from `dist`; normal deployments leave this unset.
- `APP_MULTI_INSTANCE` (Variable, optional, default absent, per-environment) — `1` enables the
  multi-instance (Traefik) deploy; see `infrastructure.md`.

That's the complete list — no deploy-target variable belongs here. Secrets/variables are provided
as GitLab CI/CD variables, never committed here.

## Linting / validating changes to these files

Nothing available in an AI coding assistant's sandbox can fully validate this pipeline — say so
plainly instead of implying otherwise. There is exactly one authoritative check and one useful
local pre-check; neither replaces the other, and the authoritative one requires a human with
project access.

### The only authoritative check: GitLab's own CI Lint, against the real project — human-only

`include: rules:`, `workflow: rules`, and `extends:` resolution can only be fully verified by
GitLab's own server-side Lint API. This requires an authenticated session against the actual
GitLab project — something an AI assistant cannot obtain on its own (no personal token exists to
hand it, and it shouldn't be asked to hold one). **This step is always run by a human, not
Claude.**

- **GitLab UI** — Build → Pipeline editor → pick the branch → **Validate** ("Full configuration"
  view shows the fully merged/expanded YAML with every included file resolved). No install, no
  auth beyond the normal GitLab login.
- **`glab ci lint`** (GitLab CLI) — same Lint API from the terminal, and with `--dry-run` it
  simulates actual pipeline creation for a given ref — including `workflow: rules`, which
  `gitlab-ci-local` below cannot check. Exact commands, run from the repo root, once per machine
  / once per branch respectively:

  ```bash
  # 1. Install (once)
  brew install glab

  # 2. Authenticate with your own GitLab account (once) — interactive, opens a browser/prompts
  #    for your own personal access token. Never paste a token into a chat with Claude for this.
  glab auth login

  # 3. Validate each branch that matters — run both, they resolve to different configs
  glab ci lint --dry-run --ref develop --include-jobs
  glab ci lint --dry-run --ref main --include-jobs
  ```

  `--dry-run` is what makes this authoritative rather than a syntax check: it asks GitLab to
  actually simulate creating a pipeline for `--ref`, so unlike a plain `glab ci lint` (which only
  checks syntax) it also evaluates `workflow: rules` and `include: rules` against that ref.
  `--include-jobs` prints the resulting job list so you can eyeball it against the "Trigger
  matrix" table above (`develop` → `build-composer`, `build-node`, `deploy-dev`; `main` →
  the `-prod` equivalents; anything else → an explicit "pipeline would not be created" style
  result, not a 0-jobs error).

### Local pre-check Claude can actually run: `gitlab-ci-local --list-all`

```
npx --yes gitlab-ci-local --list-all \
  --ignore-predefined-vars CI_COMMIT_REF_NAME,CI_COMMIT_BRANCH,CI_PIPELINE_SOURCE \
  --variable CI_COMMIT_REF_NAME=<branch> --variable CI_COMMIT_BRANCH=<branch> \
  [--variable CI_PIPELINE_SOURCE=web]
```

Downloaded on demand via `npx` (nothing installed globally), resolves `include:`,
`include: rules:` and `extends:` locally without touching the real GitLab project or needing any
credentials, and prints the resulting job list for a given branch. This is the check to run after
any edit to these files, before asking a human to do the authoritative check above. Expected
result against this repo's config: `develop` → exactly `build-composer`, `build-node`,
`deploy-dev`; `main` (with `CI_PIPELINE_SOURCE=web`) → exactly `build-composer`, `build-node`,
`deploy-prod`; any other branch → zero jobs.

**Real, confirmed limitation (read from its source, `node_modules/gitlab-ci-local/src` — it has no
`workflow:` handling anywhere): it does not implement the top-level `workflow:` key.** It will
list jobs for a ref/source combination that the real `workflow: rules` would have blocked entirely
(e.g. a plain `git push` to `main`, which `workflow:` restricts to web-triggered runs only). A
clean `gitlab-ci-local` run proves the `include:`/`extends:` dev-vs-prod job split is intact; it
proves nothing about whether a pipeline gets created in the first place. Only the authoritative
check above can confirm that.

Creates a `.gitlab-ci-local/` state directory as a side effect — gitignored, delete it
(`rm -rf .gitlab-ci-local/`) if it appears in `git status`, never commit it.

### What NOT to treat as a lint result

- A clean `yaml.safe_load()` / generic YAML linter run — necessary, not sufficient. It cannot
  catch a wrong `$CI_COMMIT_REF_NAME` vs `$CI_COMMIT_BRANCH`, a missing `include: rules:`, a job
  name that stopped matching `needs:`, or a `workflow:` gate mismatch — all of those are valid
  YAML that resolves to the wrong pipeline.
- A pipeline row that shows **"Failed" / "yaml invalid" / "jobs config should contain at least
  one visible job"** after clicking **"Run pipeline"** on a branch that isn't `develop` or
  `main` — this is the *expected* result of this design (see "Trigger matrix" above:
  branch-gated `include:` deliberately produces zero jobs on any other branch) presented through
  GitLab's manual-trigger error path, not a config defect. A plain `git push` to that same branch
  produces no pipeline row at all, because `workflow: rules` blocks it before the "0 jobs" case is
  ever reached — the manual "Run pipeline" button surfaces the error instead of silently doing
  nothing. Confirm by checking `develop` / `main` instead, not by reading this as a bug.

## Provisioning pipeline

GitLab analog of `.github/workflows/job-provision.yml` (Terraform `shared`→`<env>` + Ansible + DNS).
Lives in the same root `.gitlab-ci.yml` as the deploy pipeline described above — see "How the
provisioning pipeline coexists with the existing deploy pipeline" (`PIPELINE_KIND` gating) below
for why it's one shared file rather than a separate entry point.

### Job split — `provision` / `provision-ansible` / `provision-dns`

`.gitlab/ci/provision.gitlab-ci.yml` splits the sequence GitHub keeps as one job into three real
jobs plus a hidden base: `validate-provision-inputs` and `build-basis` (unchanged, see "Pipeline
shape" above for the equivalent build-split reasoning), then:

- **`.provision-base`** (hidden) holds everything the three real jobs share — `image`,
  `variables`, `id_tokens`, `resource_group`, `environment`, and the entire `before_script` guard
  chain (stage/env guard, region, destroy confirmation, `.env` prep including the
  `CLOUDFLARE_API_TOKEN` secret-clobber-trap append — the CI/CD variable must be appended to
  `config/environment/.env.secret` **before** `sh/env/init.sh` runs, or `init.sh`'s `.env.secret`
  merge silently overwrites it with the empty placeholder `sh/env/.env.secret.template` registers
  — same pattern GitHub's composite action uses, see `ci.md`, and the same one `build-basis`
  already applies for `COMPOSER_AUTH`), `has_basis` check, `TFPLAN_PASSPHRASE`/pinned-plan
  retrieval, the OIDC/STS exchange, SSH setup, SSH pubkey extraction, and the state-backend bucket
  guard. `extends:` merges `variables:`/`id_tokens:` key-by-key; `before_script:`/`script:`/
  `after_script:`/`artifacts:` are **not** merged — each real job below redeclares its own
  `script:`/`after_script:`/`artifacts:` in full rather than relying on inheritance for those keys.
  Duplicating the whole preamble per job (rather than trying to share state across jobs) is
  deliberate: GitLab job-to-job state never persists outside declared artifacts, the same
  constraint that forced GitHub's composite-action extraction.
- **`provision`** (stage `provision`, `needs: [build-basis]`) runs Terraform only
  (`shared`→`<env>`) and is the **single Terragrunt-output read** in this file: on `apply` it
  reads `instance_public_ip`/`instance_ipv6` once (same `N/A`/`ERROR` sentinel-normalization as
  GitHub's `tf_outputs` step — see `ci.md` — a real terragrunt error is never silently treated as
  "output not configured") and writes them as an `artifacts: reports: dotenv` file, `dns.env`
  (`INSTANCE_IPV4=`/`INSTANCE_IPV6=`, both keys always present, empty when the corresponding
  Terraform output is unset). This is the dotenv IP hand-off: any job that lists `provision` under
  its own `needs:` gets `INSTANCE_IPV4`/`INSTANCE_IPV6` auto-injected as ordinary job-level CI/CD
  variables — no second Terragrunt read anywhere in the file.
- **`provision-ansible`** and **`provision-dns`** (both stage `provision-follow`, a new stage
  added after `provision` specifically so they run *after* it rather than in parallel with it —
  same-stage jobs in GitLab run in parallel, and a same-stage `needs:` would work but make the
  graph unreadable — both `needs: [build-basis, provision]`) carry the Ansible block and the
  `dns.sh` call respectively. `provision-dns` reads `INSTANCE_IPV4`/`INSTANCE_IPV6` from the dotenv
  hand-off above and calls `bash kit-modules/basis/sh/dns.sh -e "$ENVIRONMENT_TYPE" -4
  "${INSTANCE_IPV4:-}" -6 "${INSTANCE_IPV6:-}" -y` (see `kit-modules/basis/CLAUDE.md`/`README.MD`
  for `dns.sh`'s own CLI/provider contract — not repeated here). `provision-ansible` alone moves
  the `generated.inventory.yml` cleanup into its own `after_script`, since it's the only job that
  creates that file.
- **No aggregating `summary` job on GitLab**, unlike GitHub. GitLab has no `$GITHUB_STEP_SUMMARY`
  equivalent; each of the three real jobs instead writes and `cat`s its **own**
  `provision-summary.md` section covering only its own work — a fourth job would need
  `when: always` plus cross-job artifact plumbing for no user-visible gain beyond another log blob.
  This is a deliberate, recorded asymmetry between the two platforms, not an oversight.

### Shared `resource_group` + `oldest_first` process mode — a required human action, not a suggestion

All three real jobs (`provision`, `provision-ansible`, `provision-dns`) share **one**
`resource_group: provision-$ENVIRONMENT_TYPE` (inherited from `.provision-base`, the same string
this pipeline always used — deliberately **not** split per job kind: a per-kind split would only
serialize each kind against itself, letting a second dispatch's `provision` start while the first
dispatch's `provision-ansible`/`provision-dns` are still running against the same instance — a
live-infrastructure safety regression, not a style choice). GitLab has no pipeline-level
equivalent of GitHub's workflow-level `concurrency:` (see `ci.md`) — `resource_group:` is strictly
per job — so the property "a second dispatch's Terraform cannot start until the first dispatch's
entire chain has drained" depends on this group's **process mode** being `oldest_first` rather
than the default `unordered`. `oldest_first` picks the oldest queued pipeline's job first
(ascending pipeline ID) whenever the lock frees up, so pipeline A's `provision-ansible`/
`provision-dns` are guaranteed to drain before pipeline B's `provision` ever gets the lock, even
though the resource group is shared across all three job kinds.

**There is no `.gitlab-ci.yml` or UI surface for process mode — it is set only via the GitLab API,
once per environment, after the resource group first exists (created on that environment's first
pipeline run):** concretely, the `PUT` below 404s until `provision-<env>` has been created by that
environment's first `provision` pipeline actually running — this is necessarily a **post-first-run**
step, it cannot be issued before an environment has ever been provisioned. It is also **per
environment**, not global: `provision-dev`, `provision-stage`, and `provision-prod` are three
independent resource groups, each needing its own `PUT`. Adding a new environment later
silently reintroduces the unsafe `unordered` default for that new environment's resource group
until this same API call is repeated against it — the earlier `PUT`s against the other
environments do nothing for it.

```
PUT /projects/:id/resource_groups/provision-<env>
    { "process_mode": "oldest_first" }

GET /projects/:id/resource_groups/provision-<env>    # verify it took
```

**Until that `PUT` is issued for a given environment (`provision-dev`, `provision-stage`,
`provision-prod`), the resource group runs in GitLab's default `unordered` mode and the
whole-chain mutual-exclusion guarantee described above does NOT hold** — a second dispatch's
`provision` can win the freed lock ahead of a still-queued `provision-dns` from an earlier
dispatch. This is a real operational gap, not a theoretical one: a fresh clone of this project, or
a newly added environment, starts in `unordered` mode and stays there silently until a human
issues the API call. It cannot be asserted from any in-repo test or CI Lint run. Treat this as a
required manual step for every environment this pipeline provisions, not an optional hardening
step — see the file header comment in `provision.gitlab-ci.yml` for the same warning inline.

One documented GitLab caveat worth knowing when debugging under `oldest_first`: a job sitting in
`created`/`Waiting for resource` is expected behaviour, not a stuck pipeline — but an **older
pipeline blocked on something ahead of it in the queue holds the resource**, and the documented
remedy is to cancel or re-dispatch that older pipeline, not to remove/reconfigure the resource
group.

### `spec:inputs` — the 7 pipeline inputs

Declared in the root `.gitlab-ci.yml`'s `spec:` document (`.gitlab-ci.yml:1-31`), the only place
GitLab allows pipeline inputs to be declared — "Inputs for pipelines must be defined in the
`spec:inputs` header of the main `.gitlab-ci.yml` file"
(https://docs.gitlab.com/ci/inputs/#define-input-parameters-with-specinputs). The `spec:` block is
its own YAML document, separated from the rest of the file by `---` (`.gitlab-ci.yml:1,31`).

| Input | Type | Default | Options / notes |
|---|---|---|---|
| `PIPELINE_KIND` | string | `deploy` | `options: [deploy, provision, bootstrap-state]` — see "`PIPELINE_KIND` gating" below |
| `ENVIRONMENT_TYPE` | string | `dev` | `options: [dev, stage, prod]` — provisioning only; `stage` is rejected by both `validate-provision-inputs` and `provision`'s own guard (`.gitlab/ci/provision.gitlab-ci.yml:59-66,152-159`) since no `kit-modules/basis/terraform/envs/stage/` exists (`kit-modules/basis/CLAUDE.md`'s documented `stage` gap) |
| `ACTION_TYPE` | string | `plan` | `options: [plan, apply, destroy]` |
| `SKIP_ANSIBLE` | boolean | `false` | |
| `PLAN_JOB_ID` | string | `''` | a GitLab **job** ID — see "`PLAN_JOB_ID` vs GitHub's `PLAN_RUN_ID`" below |
| `CONFIRM_DESTROY` | string | `''` | must equal `ENVIRONMENT_TYPE` when `ACTION_TYPE=destroy`; checked twice — once in `validate-provision-inputs` (`.gitlab/ci/provision.gitlab-ci.yml:72-75`), once again inside `provision`'s own `before_script` (`.gitlab/ci/provision.gitlab-ci.yml:164-168`), because a job-level retry skips `validate-provision-inputs` entirely |
| `CONFIRM` | string | `''` | `bootstrap-state` pipeline only; must equal the AWS region extracted from `.env.main`, not an environment name — see "State-backend bootstrap" below |

Every input carries a `default:` — not stylistic. The root file also serves the push-triggered
dev/prod deploy pipelines, which supply no pipeline inputs at all; an input without a default would
break automatic dev deploy-on-push (`.gitlab-ci.yml:1-6`'s own header comment states this). Max 20
inputs per pipeline (https://docs.gitlab.com/ci/inputs/) — this uses 7.

### Minimum GitLab version — 18.1, and the pre-18.1 fallback

Pipeline-level `spec:inputs` is GA only from GitLab **18.1** (behind the `ci_inputs_for_pipelines`
feature flag, default-on, in 17.11) — https://docs.gitlab.com/ci/inputs/. On a self-managed
instance older than 17.11, or with the flag disabled between 17.11 and 18.1, the root file's
`spec:` header will not work as designed: the New pipeline page will not render the typed
input form at all.

**Fallback for a pre-18.1 target**, not implemented here: prefilled pipeline `variables:` with
`description:`, which GitLab has supported since well before `spec:inputs` existed and which does
render a form field on the New pipeline page —
https://docs.gitlab.com/ci/variables/#prefill-variables-in-manual-pipelines. It has no `type:` or
`options:` enforcement (`PIPELINE_KIND=bogus` would not be rejected at pipeline-creation time the
way `options:` rejects it today) and no equivalent of `$[[ inputs.x ]]` config-time interpolation,
so `PIPELINE_KIND` would have to be read as a plain job-level `$PIPELINE_KIND` CI variable
everywhere it's used today — the same pattern already used for the other 6 inputs inside
`provision.gitlab-ci.yml`/`bootstrap-state.gitlab-ci.yml` (see their own header comments on why
those 6 are deliberately *not* mapped in root's top-level `variables:`). If this project ever needs
to target an older GitLab instance, that is the mechanical change required; nothing else in this
pipeline's design depends on 18.1 specifically.

### `PIPELINE_KIND` gating — why one root file needs it

The root `.gitlab-ci.yml` is shared by the deploy pipeline (this file's top section) and the
provisioning/bootstrap-state pipelines. A web-triggered pipeline on `main` currently produces the
three prod deploy jobs; without a gate, adding provisioning jobs to the same pipeline would make
one "Run pipeline" click run both deploy and provisioning simultaneously. `PIPELINE_KIND` is
interpolated once, at the root file's top-level `variables:`
(`PIPELINE_KIND: $[[ inputs.PIPELINE_KIND ]]`, `.gitlab-ci.yml:71`), and every deploy/provision/
bootstrap-state job carries a `rules:` on the resulting `$PIPELINE_KIND` CI variable (e.g.
`.gitlab/ci/provision.gitlab-ci.yml:48-49`, `:86-88`, `:141-142`;
`.gitlab/ci/bootstrap-state.gitlab-ci.yml:24-25`). Using a plain CI variable in each job's `rules:`
rather than repeating `$[[ inputs.PIPELINE_KIND ]]` in every file keeps the config-time
interpolation to one, auditable place — `.gitlab-ci.yml:56-71`'s own comment records why the other
6 inputs are deliberately *not* mapped the same way (root-level mapping of `ENVIRONMENT_TYPE`
previously collided with `deploy-dev`/`deploy-prod`'s own top-level `ENVIRONMENT_TYPE` and silently
broke prod deploys — confirmed by live `gitlab-ci-local` testing during this work).

The provisioning/bootstrap-state files are included **unconditionally**
(`.gitlab-ci.yml:98-101`) — unlike `deploy-dev.gitlab-ci.yml`/`deploy-prod.gitlab-ci.yml`, which
are branch-gated on `include: rules:` — and, by design, carry **no top-level `variables:` block**
of their own (both files' own header comments state this explicitly). Top-level `variables:` from
multiple included files deep-merge into one namespace, last include winning; that is exactly the
bug described in "The bug this design avoids" above. Since the provisioning files have no
top-level `variables:` at all, that collision surface doesn't exist for them — every one of their
6 non-`PIPELINE_KIND` inputs is instead mapped in the individual job's own `variables:` block
(e.g. `.gitlab/ci/provision.gitlab-ci.yml:50-53`, `:124-135`;
`.gitlab/ci/bootstrap-state.gitlab-ci.yml:33-36`).

### Required CI/CD variables

**Not GitLab CI/CD variables — `config/environment/.env.main` config, edited in the repo** (tracked
in git, not secret — `config/environment/.env.main:86-101`). These are read locally by
`kit-modules/basis/sh/aws/oidc.sh -p gitlab` when it *generates* the trust/permission policies
below — the pipeline itself never reads them at runtime (confirmed: none of these six names appear
anywhere in `.gitlab-ci.yml` or `.gitlab/ci/*.yml`; the `id_tokens:` block in both `provision.gitlab-ci.yml`
and `bootstrap-state.gitlab-ci.yml` hardcodes `aud: sts.amazonaws.com` directly, it does not
interpolate any of these). **Do not create matching GitLab CI/CD variables for these** — editing
`.env.main` (once per project, before running `oidc.sh -p gitlab -m gen`) is the only place they
belong:

- `GITLAB_ROLE_NAME` (default `gitlab-ci-role`) — everyday provisioning IAM role name.
- `GITLAB_BOOTSTRAP_ROLE_NAME` (default `gitlab-ci-bootstrap-role`) — narrower bootstrap-only role name.
- `GITLAB_HOST` (default `gitlab.com`) — OIDC issuer host; override for self-managed/Dedicated GitLab.
- `GITLAB_PROJECT_PATH` (placeholder `group/project`) — used in the OIDC `sub` claim.
- `GITLAB_PROJECT_ID` (placeholder `00000000`) — numeric project ID, pinned in the trust policy only when `GITLAB_HOST` is exactly `gitlab.com`.
- `GITLAB_PROVISION_BRANCHES` (default `"main develop"`) — space-separated branches allowed to assume the everyday role.

**Actual GitLab CI/CD variables** (Settings → CI/CD → Variables) — the operator sets these directly
from `kit-modules/basis/sh/aws/oidc.sh -p gitlab -m gen`'s printed output
(`kit-modules/basis/sh/aws/oidc.sh:101-128` for `-h` usage; the `-p gitlab` provider seams are at
`kit-modules/basis/sh/aws/oidc.sh:50,153-156,171-172,194-219`) — this is the only step of the setup
that actually touches the GitLab UI's Variables page:

- `AWS_ROLE_TO_ASSUME` — everyday role ARN, referenced by `provision`
  (`.gitlab/ci/provision.gitlab-ci.yml:269`). Never referenced by `bootstrap-state`.
- `AWS_BOOTSTRAP_ROLE_TO_ASSUME` — bootstrap role ARN, referenced by `bootstrap-state`
  (`.gitlab/ci/bootstrap-state.gitlab-ci.yml:89`). Never referenced by `provision`.
- `TFPLAN_PASSPHRASE` (optional) — GPG symmetric passphrase gating the pinned-plan
  encrypt/decrypt (`provision.gitlab-ci.yml:198-207`) and the pre-destroy state-backup encryption
  (`:367-384`). Unset ⇒ loud warning, never a hard failure; plaintext plans/state are never
  uploaded as artifacts either way.
- `PLAN_ARTIFACT_TOKEN` (optional) — a project access token, used as a `PRIVATE-TOKEN` fallback
  when the `JOB-TOKEN: $CI_JOB_TOKEN` fetch of a pinned plan artifact fails
  (`provision.gitlab-ci.yml:217-225`) — see the tier-ambiguity note below.
- `CLOUDFLARE_API_TOKEN` (Variable, optional, protected, environment-scoped — scope `*` or scope
  exactly `dev`/`stage`/`prod` to match `.provision-base`'s `environment: name: $ENVIRONMENT_TYPE`;
  a scope that doesn't match the running `ENVIRONMENT_TYPE` means the variable is never injected)
  — only needed when `DNS_PROVIDER=cloudflare` in `config/environment/.env.main`; read by
  `provision-dns`'s `dns.sh` call via `.provision-base`'s `before_script` append into
  `config/environment/.env.secret` (see "Job split" above for why the append must happen before
  `sh/env/init.sh`). Unset when `DNS_PROVIDER` is empty/`none`/`route53` — `dns.sh` skips or uses
  AWS credentials instead. **"protected" here is GitLab's branch-restriction flag, a separate axis
  from environment scope** — `provision.gitlab-ci.yml` gates its jobs solely on
  `$PIPELINE_KIND == "provision"` with no branch/ref restriction of its own, so if this variable
  is marked protected it is only injected when the pipeline runs on a protected branch/tag (repo
  Settings → Repository → Protected branches); an unprotected-branch dispatch of a `provision`
  pipeline would see it come through empty and `dns.sh` would skip/fail accordingly — mark it
  protected only if every branch that can dispatch `PIPELINE_KIND=provision` is itself protected,
  otherwise leave it unprotected. The Cloudflare token itself needs both `Zone:DNS:Edit` and
  `Zone:Zone:Read` (Zone Resources: "All zones") to pass zone discovery and write the record;
  `Zone:DNS:Edit` alone is sufficient only when `CLOUDFLARE_ZONE_ID` is also set (skips discovery).
  See `kit-modules/basis/README.MD`/`CLAUDE.md` for the full DNS provider configuration surface —
  not repeated here.

### `PLAN_JOB_ID` vs GitHub's `PLAN_RUN_ID` — a genuine semantic difference

GitHub's equivalent workflow pins an exact earlier *run* (`PLAN_RUN_ID` +
`actions/download-artifact`). GitLab has no Free-tier equivalent of that cross-run download:
`needs:artifacts` only resolves within the *same* pipeline; `needs:pipeline:job` is restricted to
the same parent-child pipeline hierarchy and explicitly rejects `$CI_PIPELINE_ID`; `needs:project`
is Premium+ and only ever yields the *latest successful* job, not a pinned one
(`.gitlab/ci/provision.gitlab-ci.yml:24-36`'s header comment records this reasoning). The only
mechanism that pins an exact earlier run on GitLab is the Job Artifacts API by **job ID**:
`GET $CI_API_V4_URL/projects/$CI_PROJECT_ID/jobs/<id>/artifacts`
(`provision.gitlab-ci.yml:212-214`). So the input is `PLAN_JOB_ID` — a GitLab **job** ID, found in
the job's own URL/log after a `plan` run — not a run/pipeline ID. An explicit `PLAN_JOB_ID` that
cannot be retrieved, unzipped, or decrypted **fails the job loudly**
(`provision.gitlab-ci.yml:226-251`); it never silently falls back to a fresh plan-then-apply — that
fallback only happens when `PLAN_JOB_ID` is empty to begin with.

`CI_JOB_TOKEN`'s access to the Job Artifacts API download endpoint is tier-ambiguous in GitLab's own
docs (listed as allowed on the job-token permissions page, while every `job_token` attribute on the
Job Artifacts API reference page is annotated Premium/Ultimate) — this could not be resolved from
docs alone. `PLAN_ARTIFACT_TOKEN` exists specifically as a fallback for this ambiguity, and the
pinned-plan failure path stays loud either way, so a 401/403 can never degrade into applying an
unreviewed plan.

### Tier notes

- **`spec:inputs`** — Free tier (https://docs.gitlab.com/ci/inputs/).
- **`id_tokens`/OIDC role assumption** — Free tier (https://docs.gitlab.com/ci/secrets/id_token_authentication/).
- **`resource_group:`** (used for `provision-$ENVIRONMENT_TYPE` and `bootstrap-state` serialization) — Free tier.
- **`environment: name:`** — Free tier. **Deployment approvals / required approvers on a protected
  environment are Premium+** (https://docs.gitlab.com/ci/environments/deployment_approvals/) — not
  shipped as a guard here; the hand-rolled `CONFIRM_DESTROY`/`CONFIRM` exact-match checks are the
  actual security boundary on every tier, run before any credential step
  (`validate-provision-inputs`: `.gitlab/ci/provision.gitlab-ci.yml:72-75`; repeated inside
  `provision`: `:164-168`; `bootstrap-state`: `.gitlab/ci/bootstrap-state.gitlab-ci.yml:54`).
- **`needs:project`** (cross-project/pinned-plan alternative considered and rejected) — Premium+,
  and only ever the latest successful job regardless of tier, so it wouldn't have solved the
  pinned-plan requirement even on a paid tier.

## State-backend bootstrap

GitLab analog of `.github/workflows/job-bootstrap-state.yml` — one-time S3 Terraform
backend bootstrap, under a separate, narrower IAM role. Implemented as its own file,
`.gitlab/ci/bootstrap-state.gitlab-ci.yml`, included unconditionally
(`.gitlab-ci.yml:101`) and gated on `PIPELINE_KIND == "bootstrap-state"`
(`.gitlab/ci/bootstrap-state.gitlab-ci.yml:24-25`) — see "`PIPELINE_KIND` gating" above.

- **`CONFIRM`-equals-region guard first.** `CONFIRM` here is the AWS region (e.g. `eu-west-1`), not
  an environment name — a different semantic from `provision`'s `CONFIRM_DESTROY`, which confirms
  `ENVIRONMENT_TYPE`. The guard runs before any AWS/credential step
  (`bootstrap-state.gitlab-ci.yml:49-54`): the region is extracted fresh from `.env.main`
  (`sh/ci/extract-aws-region.sh`), then compared against `$CONFIRM` via `sh/ci/confirm-match.sh`,
  so a wrong `CONFIRM` fails before any `sts`/`aws` line appears in the log.
- **Separate `AWS_BOOTSTRAP_ROLE_TO_ASSUME` role.** This job exchanges its OIDC token for the
  bootstrap role only (`bootstrap-state.gitlab-ci.yml:89`), never `AWS_ROLE_TO_ASSUME` — the
  bootstrap role is the only one with `s3:CreateBucket`
  (`kit-modules/basis/sh/aws/oidc.sh`'s two-role design, `oidc.sh:149-178,215-245`). The everyday
  `provision` job never references `AWS_BOOTSTRAP_ROLE_TO_ASSUME` either
  (`provision.gitlab-ci.yml:269` only uses `AWS_ROLE_TO_ASSUME`) — CloudTrail's principal alone
  tells you which pipeline touched AWS.
- **`resource_group: bootstrap-state`** serializes concurrent dispatches against the same AWS
  account, so two runs never race to create the same S3 bucket
  (`bootstrap-state.gitlab-ci.yml:37-39`).
- Needs `build-basis`'s `kit-modules/` artifact (`bootstrap-state.gitlab-ci.yml:26-32`), same
  mechanism `provision` relies on — `kit-modules/basis` is git-ignored, so a real GitLab.com shared
  runner's tracked-files-only clone never has it otherwise.

### Operator runbook — ONE-TIME MANUAL SETUP, real AWS account (not CI, not an agent)

**No agent has AWS credentials in this environment and must never attempt any step below.**
Everything here — the AWS Console clicks, the `aws iam` CLI calls, the `oidc.sh` invocations
against a real account, the GitLab CI/CD Variables page, the "Run pipeline" dispatches — is
100% a human-run procedure, same framing as `ci.md`'s "Lock-table rename" runbook. The agent's
job stopped at writing this file down; it does not execute any line in it.

This is the full one-time setup a real operator needs before GitLab provisioning can talk to a
real AWS account. Do it once per AWS account, in order.

```bash
# 0. Prerequisites: real AWS credentials in the shell (aws configure / an assumable admin role),
#    a GitLab project with Maintainer+ access to Settings → CI/CD → Variables, and — if this
#    project's group/project path, self-managed host, or provisioning branches differ from the
#    defaults — GITLAB_ROLE_NAME/GITLAB_BOOTSTRAP_ROLE_NAME/GITLAB_HOST/GITLAB_PROJECT_PATH/
#    GITLAB_PROJECT_ID/GITLAB_PROVISION_BRANCHES edited in config/environment/.env.main FIRST (they
#    are repo config, read locally by oidc.sh below — never set these as GitLab CI/CD variables,
#    see "Required CI/CD variables" above for why).

# 1. Identity provider — IAM → Identity providers → Add provider (skip if one already exists for
#    this issuer host; oidc.sh -m gen prints the exact ARN it expects to find):
#      Provider type: OpenID Connect
#      Provider URL:  https://gitlab.com          (or your GITLAB_HOST, self-managed/Dedicated)
#      Audience:      sts.amazonaws.com
#    Equivalent CLI (get the thumbprint the AWS docs way — the console derives it automatically,
#    the CLI requires it explicit):
aws iam create-open-id-connect-provider \
  --url "https://gitlab.com" \
  --client-id-list "sts.amazonaws.com" \
  --thumbprint-list "$(openssl s_client -servername gitlab.com -showcerts -connect gitlab.com:443 </dev/null 2>/dev/null \
    | openssl x509 -fingerprint -sha1 -noout | cut -d= -f2 | tr -d ':' | tr 'A-F' 'a-f')"
#    Confirm the provider ARN is arn:aws:iam::<ACCOUNT_ID>:oidc-provider/gitlab.com — oidc.sh
#    checks against exactly this ARN shape (ISSUER_HOST = $GITLAB_HOST, no scheme prefix in the
#    ARN itself).

# 2. Generate both IAM roles' trust/permission policies (run from the foundation repo root, with
#    kit-modules/basis installed and .env built — make env dev first if it isn't):
bash kit-modules/basis/sh/aws/oidc.sh -p gitlab -m gen -e dev
#    Follow its printed STEP 0 / STEP 1 / STEP 2 output exactly:
#      STEP 0 — confirms/creates the identity provider (already done in step 1 above)
#      STEP 1 — everyday provisioning role ($GITLAB_ROLE_NAME, default gitlab-ci-role):
#               IAM → Roles → Create role → Web identity → paste the printed trust policy
#               (STEP 1b) and permission policy (STEP 1c) exactly as printed — they already
#               interpolate this account's TF_VAR_tf_backend_bucket/TF_VAR_aws_region/
#               GITLAB_PROVISION_BRANCHES, nothing to fill in by hand.
#      STEP 2 — state-backend bootstrap role ($GITLAB_BOOTSTRAP_ROLE_NAME, default
#               gitlab-ci-bootstrap-role): same mechanism, narrower permissions
#               (s3:CreateBucket, everyday role never gets it).
#    Copy each role's ARN from `aws iam get-role --role-name <name> --query Role.Arn --output text`
#    after creating it — you need both in step 3.

# 3. GitLab CI/CD variables — Settings → CI/CD → Variables → Add variable, for THIS project.
#    Only these four are ever GitLab CI/CD variables — the pipeline reads nothing else this way
#    (GITLAB_ROLE_NAME/GITLAB_BOOTSTRAP_ROLE_NAME/GITLAB_HOST/GITLAB_PROJECT_PATH/GITLAB_PROJECT_ID/
#    GITLAB_PROVISION_BRANCHES are .env.main config, already set in step 0 below — do NOT also add
#    them here as CI/CD variables, the pipeline never reads them at runtime, only oidc.sh does,
#    locally, when it generated the policies you pasted in step 2):
#      AWS_ROLE_TO_ASSUME             = <everyday role ARN from step 2>
#                                        Environment scope: dev (repeat per environment if the
#                                        same role's ARN is reused across dev/stage/prod, or set
#                                        per-environment ARNs if you split the role later)
#      AWS_BOOTSTRAP_ROLE_TO_ASSUME   = <bootstrap role ARN from step 2>
#                                        Environment scope: All (default) — do NOT scope to dev/
#                                        stage/prod, this role is not environment-specific
#    Optional, only if used:
#      TFPLAN_PASSPHRASE              = <GPG symmetric passphrase>  (plan encryption)
#      PLAN_ARTIFACT_TOKEN            = <project access token>      (PRIVATE-TOKEN fallback for
#                                                                     cross-job plan artifact fetch)
#    See "Required CI/CD variables" above for what each one gates.

# 4. Verify the identity provider + both roles are actually wired correctly, before dispatching
#    anything that spends real AWS credentials:
bash kit-modules/basis/sh/aws/oidc.sh -p gitlab -m test -e dev
#    Expect: [Success] on both roles' "IAM Role found", "Trust policy configured correctly", and
#    "sub" scoping classified [Success] (not [Warning]/[Error]) for the branches you expect. Exit
#    code non-zero if either role failed any check — fix the flagged item and re-run before
#    proceeding; do not dispatch a pipeline against a role -m test has already flagged.

# 5. Dispatch the one-time state-backend bootstrap pipeline:
#    GitLab UI → CI/CD → Pipelines → Run pipeline. On the "Run pipeline" form:
#      Branch: main
#      PIPELINE_KIND   = bootstrap-state
#      CONFIRM         = <the exact AWS region from .env.main's TF_VAR_aws_region, e.g. eu-west-1>
#                         (NOT an environment name — see "CONFIRM-equals-region guard" above; a
#                         mismatch fails before any AWS call is made)
#    Leave every other input at its default. Click "Run pipeline", then watch the bootstrap-state
#    job's log to confirm the S3 bucket was created (or already existed).

# 6. Dispatch a provisioning plan run to confirm the everyday role works end to end:
#    GitLab UI → CI/CD → Pipelines → Run pipeline.
#      Branch: main (or develop, whichever GITLAB_PROVISION_BRANCHES allows)
#      PIPELINE_KIND    = provision
#      ENVIRONMENT_TYPE = dev
#      ACTION_TYPE      = plan
#    Leave SKIP_ANSIBLE/PLAN_JOB_ID/CONFIRM_DESTROY/CONFIRM at their defaults for a plain plan.
#    A clean run through Terraform plan output (no apply, nothing destroyed) confirms the whole
#    chain: OIDC token → STS exchange → AWS_ROLE_TO_ASSUME → Terraform against the real backend.
```

**Rollback — if a step fails partway:**

- **Step 1 (identity provider) created but step 2/3 abandoned:** safe to leave in place — an
  unused identity provider does nothing on its own. To remove it anyway:
  `aws iam delete-open-id-connect-provider --open-id-connect-provider-arn arn:aws:iam::<ACCOUNT_ID>:oidc-provider/gitlab.com`
  (only if no role's trust policy still references it — check with
  `aws iam list-open-id-connect-providers` first).
- **Step 2 (a role half-created — e.g. trust policy pasted but permission policy not attached, or
  vice versa):** don't try to patch a partial role by hand. Delete it and re-run `-m gen` fresh:
  `aws iam list-attached-role-policies --role-name gitlab-ci-role` to see what's attached, detach
  each with `aws iam detach-role-policy --role-name gitlab-ci-role --policy-arn <arn>`, then
  `aws iam delete-role --role-name gitlab-ci-role`. Repeat for the bootstrap role
  (`gitlab-ci-bootstrap-role`) if it was also touched. Re-run step 2 from scratch — `-m gen`'s
  output is idempotent to re-paste.
- **Step 3 (variables set wrong):** just correct the value in Settings → CI/CD → Variables and
  re-run step 4 (`-m test`) before dispatching anything.
- **Step 5/6 (pipeline dispatched, failed):** no AWS resource is created by a failed OIDC/STS
  exchange — nothing to roll back on the AWS side. Fix whatever `-m test` or the job log flagged,
  then re-dispatch the same pipeline. A **partially-applied** `bootstrap-state` run is safe to just
  re-dispatch — `sh/bootstrap-state.sh` is idempotent and skips the bucket if it already exists
  (see `kit-modules/basis/CLAUDE.md`); it does not partially tear down what step 5 already created.

**What a failed STS exchange looks like** — the exact error text both `provision.gitlab-ci.yml`
and `bootstrap-state.gitlab-ci.yml` print when `aws sts assume-role-with-web-identity` fails
(before/regardless of any AWS-side error text `aws` itself writes to `sts.stderr`, which is also
echoed immediately after this line):

```
Error: OIDC token unavailable or STS denied the web-identity exchange (aws sts assume-role-with-web-identity failed). Verify AWS_ROLE_TO_ASSUME is a valid role ARN, the GitLab OIDC identity provider exists in this AWS account, and the role's trust policy matches this project (see kit-modules/basis/sh/aws/oidc.sh -p gitlab -m test).
```

(`bootstrap-state.gitlab-ci.yml`'s equivalent names `AWS_BOOTSTRAP_ROLE_TO_ASSUME` instead.) The
underlying `aws` CLI error appended right after that line is typically AWS's own
`An error occurred (AccessDenied) when calling the AssumeRoleWithWebIdentity operation: Not
authorized to perform sts:AssumeRoleWithWebIdentity` — which almost always means one of: the role
ARN in the CI/CD variable is wrong/typo'd, the trust policy's `sub` condition doesn't match this
project's path/branch (re-run `-m test`, check the "sub" scoping line), or the identity provider
ARN embedded in the trust policy's `Principal.Federated` doesn't match what actually exists in
this AWS account (stale account ID, wrong issuer host after a `GITLAB_HOST` change). `-m test`
(step 4 above) is the tool that catches all three before a pipeline dispatch ever reaches this
error.

## `gitlab-ci-local` verification recipe

Two distinct uses, not interchangeable:

1. **`--list-all`** (job-graph resolution only, no real execution) — see "Local pre-check Claude
   can actually run" above. Safe to run freely; touches no real working-directory state beyond the
   gitignored `.gitlab-ci-local/` directory.
2. **A real (non-`--list-all`) execution of a job** — actually runs the job's `script:`/
   `before_script:`/`after_script:` in a container. Required by this plan's Architecture notes §E
   for every task producing or changing `.gitlab-ci.yml`/`.gitlab/ci/*.yml`: with no real AWS
   credentials and no GitLab-minted `id_tokens` JWT, `provision`/`bootstrap-state` are expected to
   fail precisely at the `aws sts assume-role-with-web-identity` call
   (`provision.gitlab-ci.yml:265-280`; `bootstrap-state.gitlab-ci.yml:85-100`), having already
   passed the confirm guard, region extraction and `has_basis` classification. Reaching that wall
   is the pass criterion; failing earlier is a defect.

### Hard requirement — snapshot `kit-modules/basis` before any real execution

**`gitlab-ci-local` executes against the real working directory — it is not sandboxed like `act`.**
This already caused a `kit-modules/basis` data-loss incident during this work (recorded in the
plan's Architecture notes §E and Risks section). Any real (non-`--list-all`) `gitlab-ci-local` run
of a job that touches `kit-modules/basis`, `tfplans/`, `.env`, or Terraform state — in practice,
every real run of `build-basis`, `provision`, or `bootstrap-state` — **must** begin with:

```bash
SNAP="$SCRATCHPAD/basis-snapshot-$(date +%F-%H%M%S)"
mkdir -p "$SNAP"
cp -a kit-modules/basis "$SNAP/"
git -C kit-modules/basis status --porcelain > "$SNAP/basis-git-status-before.txt"
```

and end with:

```bash
git -C kit-modules/basis status --porcelain > "$SNAP/basis-git-status-after.txt"
diff "$SNAP/basis-git-status-before.txt" "$SNAP/basis-git-status-after.txt"
```

On any unexpected difference, restore from `$SNAP` (`rm -rf kit-modules/basis && cp -a
"$SNAP/basis" kit-modules/basis`) before doing anything else. A warning comment in the pipeline
YAML is not sufficient — this snapshot/diff pair is a Done-when criterion, not advice, on every
Stage 4 task in the plan (each task's own Done-when cell repeats it).

Also delete the `.gitlab-ci-local/` state directory afterward (`rm -rf .gitlab-ci-local/`) — it is
gitignored, and must never be committed, same as the `--list-all` case above.

### `--input` limitation — `$[[ inputs.x ]]` does not propagate into included files' job-level `variables:`

Discovered during this work, not previously documented here: `gitlab-ci-local`'s `--input` flag
only resolves `$[[ inputs.x ]]` interpolation inside the **document that declares `spec:`** — the
root `.gitlab-ci.yml`. It does **not** propagate into included files' job-level `variables:` blocks
(e.g. `ENVIRONMENT_TYPE: $[[ inputs.ENVIRONMENT_TYPE ]]` in
`.gitlab/ci/provision.gitlab-ci.yml:51,99,131` or `CONFIRM: $[[ inputs.CONFIRM ]]` in
`.gitlab/ci/bootstrap-state.gitlab-ci.yml:36`), even though real GitLab resolves `$[[ inputs.x
]]` anywhere in the merged configuration
(https://docs.gitlab.com/ci/inputs/#use-inputs-in-included-templates confirms this is valid on
real GitLab). Real local testing of anything downstream of one of these 6 job-level inputs must use
`--variable` overrides directly on the job-level variable **names** instead (e.g. `--variable
ENVIRONMENT_TYPE=dev --variable CONFIRM_DESTROY=dev`), not `--input`. This sits alongside the
already-documented `workflow:` blind spot above ("Real, confirmed limitation…") as a second, separate
`gitlab-ci-local` gap — `workflow:` is invisible to it entirely, while `--input` is visible but
scoped to the wrong document for this repo's job-level-mapping design (see "`PIPELINE_KIND`
gating" above for why that design was chosen).

## GitHub Actions side

For the GH workflows this pipeline parallels (unchanged, still active), see `ci.md`.
