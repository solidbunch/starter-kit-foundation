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
  `variables:` block (`ENVIRONMENT_TYPE: dev`, `DEPLOY_SSH_HOST: develop.starter-kit.io`,
  `DEPLOY_PATH: /srv/develop.starter-kit.io`) and 3 concrete jobs (`build-composer`, `build-node`,
  `deploy-dev`) via plain `extends:` on the hidden templates — no `rules:` of its own, no
  interpolation. Only ever merged into a pipeline when the root `include:` rule matches `develop`.
- `.gitlab/ci/deploy-prod.gitlab-ci.yml` — the `workflow-deploy-production.yml` analog: same shape
  with prod values (`ENVIRONMENT_TYPE: prod`, `DEPLOY_SSH_HOST: starter-kit.io`,
  `DEPLOY_PATH: /srv/starter-kit.io`), jobs `build-composer`, `build-node`, `deploy-prod`. No
  `when: manual` — triggering is controlled entirely by the root file's `workflow: rules` (see
  "Trigger matrix" below). Pair with a **protected `production` environment**
  (Settings → CI/CD → Protected environments) to restrict *who* can run a prod release — see
  `README.MD`.

Domain/host values above (`starter-kit.io`, `develop.starter-kit.io`) are this repo's own
placeholder convention (same ones used in `config/environment/.env.type.dev` / `.env.type.prod`
and the GitHub Actions workflows) — replace them project-wide via `bootstrap-project`, not just
in these files.

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

build-composer  (image: $APP_COMPOSER_IMAGE, entrypoint:[""])  ─┐
build-node      (image: $APP_NODE_IMAGE,     entrypoint:[""])  ─┤ artifacts
                                                                 ▼
deploy-dev / deploy-prod  (image: alpine:3.20 + rsync/openssh)  needs:[build-composer, build-node]
```

Each build job runs **natively inside the toolkit image itself** (set as the job's `image:`)
instead of shelling out to the toolkit compose file — that pattern only works with a self-hosted
shell-executor runner sharing a filesystem with the Docker daemon, which GitLab.com shared runners
do not provide. `entrypoint: [""]` bypasses the toolkit images' custom `ENTRYPOINT` (host-UID
remap, `COMPOSER_AUTH` logging) so the job's own `script` runs directly. The two build jobs run
**in parallel** in the `build` stage — composer's install needs only `composer.*`, node's build
needs only the git-tracked theme source. The deploy job in the `deploy` stage `needs:` both and
receives their artifacts merged over a fresh clone, then rsyncs `./` to the target server and runs
the remote `make` sequence over SSH — that phase runs on the target server itself (which has
Docker), not on the runner. `resource_group: $ENVIRONMENT_TYPE` (one line in the shared `.deploy`
template) serializes concurrent deploys to the same server — relevant mainly for dev, which
auto-deploys on every push.

`.build-composer` also runs the same two conditional steps as GitHub Actions' `job-deploy.yml`,
for full parity: `composer run switch-theme-dev` when `ENVIRONMENT_TYPE == dev` (switches the
theme to its `dev-develop` Composer VCS branch — see `ci.md` and root `CLAUDE.md`'s "Intentional
Quirks"; becomes a harmless no-op if a project has detached its theme from that Composer package,
e.g. via `bootstrap-project`'s monorepo option), and the `IS_DEMO`-guarded
`solidbunch/monitoring-client`/`solidbunch/starter-kit-addon` dist update (skipped unless the
GitLab CI/CD variable `IS_DEMO` is `"true"`).

**`artifacts: paths:` on `.build-composer` is an explicit whitelist, not a whole-directory
carry-over — keep it in sync with what `composer install-*` actually produces.** GitHub Actions'
`job-deploy.yml` sidesteps this entirely by caching the whole working directory (`actions/cache/save`,
`path: .`), so anything Composer creates there — including `kit-modules/` (installer-path for
`solidbunch/basis`/`monitoring-client`/`monitoring-server`, see `infrastructure.md`) — rides along
automatically. GitLab's `artifacts:` has no equivalent here (deliberately not using
`paths: ['.']`, which would also carry `.git`, caches, and other build noise into the deploy
job) — the list must be maintained by hand: `vendor/`, `web/wp-core/`, `web/wp-content/plugins/`,
`web/wp-content/mu-plugins/`, the theme's `vendor/`, and `kit-modules/`. If a future Composer
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

`SSH_KEY`/`SSH_CONFIG` CI/CD variables are **environment-scoped** in the GitLab UI (same variable
name, scope `dev` vs `production`) rather than split into `_PROD`-suffixed variable names — keeps
the deploy job referencing plain `$SSH_KEY`/`$SSH_CONFIG` for both environments, resolved by
whichever `environment: name` (`dev` / `production`) the running job carries.

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

## Deploy job image

`alpine:3.20` + `apk add --no-cache openssh-client rsync` in `before_script` — no toolkit image
bundles both cleanly, and the deploy job only needs `rsync`/`ssh`, not the full source tree logic
(the heavy `make` work runs on the remote server). `git` is intentionally **not** installed —
GitLab's Docker executor performs the clone and artifact extraction in its helper image, not the
job image.

## Required CI/CD variables

- `SSH_KEY` (File, protected, environment-scoped `dev`/`production`) — private deploy key for
  that server.
- `SSH_CONFIG` (File, protected, environment-scoped `dev`/`production`) — SSH client config
  defining the host alias used by `DEPLOY_SSH_HOST`.
- `SSH_KNOWN_HOSTS` (File, optional) — only needed if host-key trust isn't already handled inside
  `SSH_CONFIG`.
- `COMPOSER_AUTH` (Variable, protected, scope `All`) — Composer auth JSON, needed to unlock
  licensed packages (see `infrastructure.md`).
- `APP_MULTI_INSTANCE` (Variable, optional, default absent, per-environment) — `1` enables the
  multi-instance (Traefik) deploy; see `infrastructure.md`.

See the "Deployment via GitLab CI" section of `README.MD` for the full variable table and setup
steps. Secrets are provided as GitLab CI/CD variables, never committed here.

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

## GitHub Actions side

For the GH workflows this pipeline parallels (unchanged, still active), see `ci.md`.
