---
name: bootstrap-project
description: Turns a freshly cloned starter-kit-foundation checkout into a named, running project - renames APP_NAME/APP_TITLE/APP_DOMAIN, optionally renames the theme via its own clone-theme CLI, optionally bundles the theme into this root repo instead of its own separate VCS repo (editing .gitignore/composer.json accordingly), sanity-checks the edits, runs make secret/env/install, rewrites the project's own README.md (local install + CI/CD summary), and refreshes CLAUDE.md/rules via project-brief. Triggers on "bootstrap this project", "start a new project from this template", "initialize new project". Not for editing an already-running project's config - that's config.md / infrastructure.md territory.
---

# Bootstrap Project — turn the template into *your* project

This runs once, right after `git clone` of `starter-kit-foundation`, before the user has followed
`https://starter-kit.io/docs/overview/` by hand. It automates the pre-project setup that
documentation describes, in the order the real Makefile/env pipeline expects. Do not skip steps
or reorder them — later steps (`make install`, theme rename) read the files earlier steps write.

## Step 0 — Collect the inputs Claude cannot guess

Ask once, via `AskUserQuestion` (batch what you can), whatever the user didn't already give you:

1. **Project slug** — lowercase, hyphen-safe (e.g. `acme-shop`). Becomes `APP_NAME`.
2. **Project title** — human-readable (e.g. `"Acme Shop"`). Becomes `APP_TITLE`.
3. **Local domain** (required) — default `<slug>.loc` if the user has no preference. Becomes
   `APP_DOMAIN` in `.env.type.local`.
   **Dev/stage/prod domains** (optional) — ask, but let the user decline/skip; if skipped, leave
   those environments untouched (not needed until actually provisioned).
4. **Theme repository mode** — keep the default: the theme stays in its own separate VCS repo,
   Composer VCS-installs it as `source` into `web/wp-content/themes/<slug>` (current behavior —
   supports independent theme releases/branching, e.g. the dev environment's `dev-develop` branch
   tracking). Or: bundle the theme directly into this root repo (monorepo) — no separate theme
   repo, the theme's files get tracked here instead, and Composer stops managing it. This drives
   Step 6 below (it runs after Step 5 if both are chosen — see that step for why).
5. **Theme name** — keep `starter-kit-theme` as-is (skip Step 5), or rename it: new theme slug
   (folder name), display name, and package label. This is a cosmetic rename only — the theme's
   internal PHP namespace, hook/settings prefixes, and REST API namespace stay unchanged unless
   the user explicitly asks for a deeper rename too (see Step 5).
6. **Project description** — one to three sentences on what this project actually is (for the
   README this skill writes in Step 7). Optional — if skipped, fall back to a generic line built
   from the title: `"<title> — a WordPress project built on SolidBunch StarterKit."`

Don't ask about anything you can default sensibly (e.g. domain slug) — ask only what's genuinely
ambiguous. This is meant to feel like one command, not a questionnaire.

## Step 1 — Rename the project (env sources, never generated files)

Edit only source files under `config/environment/` — never `.env` or `.env.runtime` (both
regenerated, see root `CLAUDE.md`):

- `config/environment/.env.main`: `APP_NAME=<slug>`, `APP_TITLE="<title>"`
- `config/environment/.env.type.local`: `APP_DOMAIN=<domain>` (repeat for `.env.type.dev`/
  `.env.type.stage`/`.env.type.prod` for any environment the user gave a domain for in Step 0)
- `config/environment/.env.main`: `GITHUB_ORG`/`GITHUB_REPO` — run `git remote get-url origin`; if
  it resolves to a `github.com` remote, parse `<org>`/`<repo>` out of it and set both. If no origin
  is set (or it isn't a GitHub URL), leave these two untouched and flag it in Step 9's report — they
  still hold StarterKit's own values (`solidbunch`/`starter-kit-foundation`) and must be set by hand
  before this project's CI/CD role/Terraform state work. `ROLE_NAME` and `TF_VAR_tf_lock_table`
  stay out of scope regardless — a real DynamoDB table the user controls can't be invented
  automatically; flag those in Step 9 too. `TF_VAR_tf_backend_bucket` is already handled — it
  derives from `${APP_NAME}` via `.env.main`'s existing default, same as `TF_VAR_sk_vpc_name`/
  `TF_VAR_sk_ssh_key_name`.
- The deploy target (SSH destination / destination path) needs **no configuration at all**, on
  either platform — there is no deploy-target CI/CD variable to set. Both pipelines derive it at
  runtime from the `APP_DOMAIN` value just edited above in this same step
  (`config/environment/.env.type.dev`/`.stage`/`.prod`), computing the deploy path as
  `/srv/$APP_DOMAIN` and using `$APP_DOMAIN` itself as the SSH destination alias. The only thing
  that must be true is that each environment's `SSH_CONFIG` secret/variable has a `Host` block
  named after that environment's `APP_DOMAIN` (e.g. `Host develop.<devDomain>`,
  `Host <prodDomain>`) — full contract: `.claude/rules/ci.md` (GitHub) and
  `.claude/rules/gitlab-ci.md` (GitLab). Step 7's generated README walks the user through setting
  up `SSH_CONFIG` with the correct `Host` names.

`kit-modules/basis` Terraform/Ansible internals and the rest of CI/CD wiring beyond the above are a
separate task the user can ask for by name later; `infrastructure.md`/`ci.md` cover that ground when
it comes up.

Do not touch `.env.secret` — untouched by rename, regenerated secrets aren't part of identity.

## Step 2 — Regenerate the derived env files

```bash
make secret        # no-op if .env.secret already exists
make env local      # rebuild .env / .env.runtime from the edited sources, no docker yet
```

Confirm the printed values match what was just edited before moving on.

## Step 3 — Sanity check (before install)

Before running `make install`, re-read `config/environment/.env.main`/`.env.type.local` (and any
other `.env.type.*` touched) and confirm they match what was requested in Step 0, nothing left
half-edited. This is just re-reading the small set of files this skill itself just wrote — no
agent needed.

## Step 4 — Install

Confirm with the user before running (it builds/starts Docker containers):

```bash
make install [local]
```

Then remind them: if `APP_DOMAIN` isn't a `.localhost` domain, add it to `/etc/hosts`
(`127.0.0.1 <domain>`). Admin credentials print in the terminal and land in
`config/environment/.env.secret`.

## Step 5 — Theme rename (only if the user chose this in Step 0)

The theme ships its own WP-CLI command for this: `wp clone-theme`. It copies the active theme's
folder to a new slug and search-replaces 7 identifiers throughout the copy (skipping images,
`node_modules`, `vendor`). It needs a running, installed WordPress with the current theme active —
that's why this step runs after Step 4, not before.

Read the theme's current values first (they may differ from the defaults below if this project was
already renamed once): `web/wp-content/themes/<current-slug>/config/common/main.php` → `themeName`,
`package`, `themeSlug`, `themeNamespace`, `hooksPrefix`, `settingsPrefix`, `restApiNamespace`.

Run it non-interactively — it's a plain sequence of stdin prompts, one value per line, in this
exact order. Reuse the current values from `config/common/main.php` for the last four lines to
keep this a **cosmetic-only rename** (only change theme name / package / slug), unless the user
explicitly asked for the internal PHP namespace and prefixes to change too:

```bash
docker compose exec -T --user www-data php wp clone-theme <<'EOF'
<new theme display name>
<new package label>
<new-theme-slug>
<themeNamespace — unchanged unless asked>
<hooksPrefix — unchanged unless asked>
<settingsPrefix — unchanged unless asked>
<restApiNamespace — unchanged unless asked>
EOF
```

Then:

1. Activate it: `docker compose exec -T --user www-data php wp theme activate <new-theme-slug>`

2. Update `config/environment/.env.main`: `WP_DEFAULT_THEME=<new-theme-slug>`, then `make env local`
   to regenerate `.env`/`.env.runtime` so build scripts target the new theme folder.

3. `wp clone-theme` skips `vendor`/`node_modules` when copying, so the new folder has neither —
   `.env`'s `WP_DEFAULT_THEME` now points at it (previous step), so just re-run the project's own
   build script, non-interactively:
   
   ```bash
   bash ./sh/system/install.sh yes
   ```
   
   This is the exact script `make install` calls — it re-runs root `composer install-<mode>`
   (harmless no-op, already correct) and, scoped to `$WP_DEFAULT_THEME`, `composer install-<mode>`
   
   + `npm run install-<mode>` for the **new** theme folder. Confirm `vendor/`, `node_modules/`, and
     compiled `assets/` now exist under the new theme folder before moving on.

4. The new folder is a **plain local copy — not Composer-managed**. The old
   `web/wp-content/themes/<old-slug>/` directory is untouched on disk, and root `composer.json`'s
   `require.solidbunch/starter-kit-theme` still points at it. Don't silently delete the old folder
   or edit that `composer.json` entry — flag both as a manual decision for the user in Step 9
   (removing/repointing it affects `composer.lock` state).

5. Grep the new theme's own guides for leftover references to the old slug/package name and fix
   any hits directly (plain find-and-replace) — it's a normal file edit in this working copy, the
   theme having its own git remote doesn't change that:
   `grep -rn <old-slug> web/wp-content/themes/<new-slug>/CLAUDE.md
   web/wp-content/themes/<new-slug>/blocks/CLAUDE.md web/wp-content/themes/<new-slug>/.claude/`.
   List these edits separately in the Step 9 report since they land in a different repo's working
   tree than the rest of the bootstrap changes.

## Step 6 — Theme repository mode (only if the user chose "monorepo" in Step 0)

Skip entirely if the user kept the default (separate theme repo) — no files to touch. Runs after
Step 5 (not before) when the user also chose to rename the theme: it must operate on the **final**
theme slug, not the intermediate default one. Converting `starter-kit-theme` to monorepo mode and
then renaming it afterwards would detach/un-ignore the wrong (soon-to-be-orphaned) folder while
the actually-active renamed theme stays Composer-managed and git-ignored — always resolve the
final `<slug>` from Step 0/Step 5 before starting this step.

1. Detach the theme from its own git history — it landed on disk as a full VCS-source checkout
   (its own `.git`), which would otherwise become a forgotten repo-inside-a-repo:
   
   ```bash
   rm -rf web/wp-content/themes/<slug>/.git
   ```

2. Stop Composer from managing it — edit root `composer.json`:
   
   - Remove the `solidbunch/starter-kit-theme` entry from `repositories` (the `type: vcs` block
     pointing at `github.com/solidbunch/starter-kit-theme.git`)
   - Remove the `"solidbunch/starter-kit-theme": "dev-..."` line from `require`
   - Remove the `"solidbunch/starter-kit-theme": "source"` line from `config.preferred-install`
   - Remove the `switch-theme-dev` script — dev-branch tracking via Composer no longer applies
     (see the caveat below)
   
   Then run `composer update --no-install`. This resolves and rewrites `composer.lock` to drop the
   package (since it's no longer in `require`) **without** touching files on disk — the theme
   folder is already there and now tracked by git directly, so it must not be reinstalled/removed
   by Composer. Do not use `composer update --lock`: that only refreshes the lock's content-hash
   and does not actually remove the package from `packages`, leaving `composer.lock` inconsistent
   with `composer.json` and liable to reinstall the theme on the next `composer install`.

3. Un-ignore the theme folder in root `.gitignore`. Right now the whole content directory is
   ignored wholesale as Composer/runtime-managed (`/web/wp-content/*`, under "Content Files").
   Add, directly after that line:
   
   ```gitignore
   !/web/wp-content/themes/
   /web/wp-content/themes/*
   !/web/wp-content/themes/<slug>/
   ```
   
   This un-ignores only the active theme's folder — `plugins/`, `uploads/`, `upgrade/`, and any
   other theme folders stay ignored.

4. `git add web/wp-content/themes/<slug>` and confirm with `git status` that its files show as new
   and trackable, not still ignored.

**Caveat — flag this in Step 9's report, don't silently patch around it:** the dev environment
normally tracks the theme's `dev-develop` branch via the CI-only `composer run switch-theme-dev`
script (see root `CLAUDE.md`'s "Intentional Quirks" and `.claude/rules/ci.md`). In monorepo mode
there's no separate theme repo/branch left to track, so that mechanism no longer applies. Updating
the CI dev-deploy pipeline for this is out of scope for this skill — tell the user it needs a
manual look before their next dev deploy.

## Step 7 — Generate the project's own README

The template's `README.md` is StarterKit's own marketing/product page — links to
`starter-kit.io`, generic feature list, no mention of what *this* project is or how to run it.
Put the project itself first (description, local install, CI/CD). The template's own marketing
content (overview blurb, feature bullet list, video link, Stay Connected socials) must **not**
survive into the generated README as if it were this project's own data — a developer reading
`acme-shop`'s README should never see an "Overview" section describing "StarterKit" or a
"Stay Connected" block linking to SolidBunch's own GitHub Discussions/LinkedIn. Replace all of it
with a single short attribution line/paragraph at the bottom crediting the boilerplate, not a
relocated copy of it. Keep the new top section short — this is a landing page for a developer
opening the repo for the first time, not a manual; link out to `starter-kit.io/docs` and this
repo's own `.claude/rules/` files for depth instead of inlining it.

Write `README.md` at the repo root with this structure:

```markdown
# <APP_TITLE>

<Project description from Step 0 item 6, 1-3 sentences>

## Local installation

**Prerequisites:** Docker Engine v24+ (includes Compose v2), GNU Make, Git.

\`\`\`bash
git clone <this repo's URL>
cd <APP_NAME>
make install local
\`\`\`

Add `<APP_DOMAIN>` to `/etc/hosts` if it isn't a `.localhost` domain: `127.0.0.1 <APP_DOMAIN>`.
Admin credentials print at install time and are saved to `config/environment/.env.secret`.

## CI/CD setup

One-time setup in GitHub, then two workflows to run by hand for infra/prod:

**1. Create the deployment environments**: GitHub repo → **Settings** → **Environments** →
**New environment**, one per environment type: `dev`, `stage`, `prod`. The names must match
exactly — both pipelines pin themselves to the environment named after the run's
`ENVIRONMENT_TYPE`, and an environment that doesn't exist carries no variables. Protection rules
(required reviewers, wait timer) are optional; add them to `prod` if you want prod runs gated.

**2. Add repo secrets**: GitHub repo → **Settings** → **Secrets and variables** → **Actions** →
**Secrets** tab → **New repository secret**, one at a time:

- `SSH_KEY`: the raw private key, e.g.:
  \`\`\`
  -----BEGIN OPENSSH PRIVATE KEY-----
  b3BlbnNzaC1rZXktdjEAAAAABG5vbmU...
  -----END OPENSSH PRIVATE KEY-----
  \`\`\`

- `SSH_CONFIG`: an SSH client config, one `Host` block per environment:

  \`\`\`
  # SSH_CONFIG
  # Example for CI/CD deployment via SSH
  ####################################
  Host *
      IdentitiesOnly yes
      StrictHostKeyChecking no

  Host <dev APP_DOMAIN>
    HostName <dev server IP or hostname>
    User admin
    Port 22
    IdentityFile ~/.ssh/id_rsa

  Host <stage APP_DOMAIN>
    HostName <stage server IP or hostname>
    User admin
    Port 22
    IdentityFile ~/.ssh/id_rsa

  Host <prod APP_DOMAIN>
    HostName <prod server IP or hostname>
    User admin
    Port 22
    IdentityFile ~/.ssh/id_rsa
  \`\`\`

  The `Host` name in each block **must** equal that environment's `APP_DOMAIN` exactly — both
  pipelines use `APP_DOMAIN` directly as the SSH destination alias, so a mismatch fails the deploy
  with `Could not resolve hostname`, not a silent misdeploy.

- `COMPOSER_AUTH`: a GitHub personal access token in Composer's `github-oauth` JSON shape, quotes
  escaped (see `sh/env/.env.secret.template` and the
  [StarterKit CI/CD docs](https://starter-kit.io/docs/ci-cd-deployments/)):
  \`\`\`
  {\"github-oauth\":{\"github.com\":\"<GITHUB_PERSONAL_ACCESS_TOKEN>\"}}
  \`\`\`
  If you have paid `kit-modules` licenses, add an `http-basic` entry for
  `licensing.starter-kit.io` to the same JSON object:
  \`\`\`
  {\"github-oauth\":{\"github.com\":\"<GITHUB_PERSONAL_ACCESS_TOKEN>\"},\"http-basic\":{\"licensing.starter-kit.io\":{\"username\":\"<your email>\",\"password\":\"<your license password>\"}}}
  \`\`\`

- `TFPLAN_PASSPHRASE` (optional): any strong passphrase. Enables the provisioning pipeline's
  plan-then-apply flow — the Terraform plan is GPG-encrypted into a run artifact so an `apply`
  can replay a reviewed plan instead of re-planning. Without it those steps skip themselves and
  the run summary says so.

**3. Add variables**: same page, **Variables** tab.

Repository level (**New repository variable**):

| Name | Required | Value |
|---|---|---|
| `AWS_ROLE_TO_ASSUME` | for provisioning | ARN of the IAM role GitHub OIDC assumes for Terraform/Ansible, see step 4 |
| `IS_DEMO` | no | `true` only for SolidBunch demo/showcase stands — forces licensed modules to update from `dist` |

Environment level (**Settings** → **Environments** → pick one → **Add variable**):

| Name | Required | Value |
|---|---|---|
| `APP_MULTI_INSTANCE` | no | `1` on an environment whose server co-hosts several instances behind the Traefik proxy. Leave unset everywhere else — an unset variable means "off". Set it per environment, not repo-wide, or it applies to prod too |

There is no deploy-target variable to add here — nothing else to set at this level. The deploy
target is derived automatically from `APP_DOMAIN` (already set in
`config/environment/.env.type.dev`/`.stage`/`.prod` back in Step 1); the only requirement is the
`SSH_CONFIG` secret's `Host` block naming, shown above.

For the GitLab pipeline, the CI/CD setup is even smaller: just `SSH_KEY`, `SSH_CONFIG`, and
`COMPOSER_AUTH` as CI/CD variables (**Settings** → **CI/CD** → **Variables**), all scope `All` by
default — same `SSH_CONFIG` `Host`-name contract as above. Only add a `dev`- or `prod`-scoped
override for `SSH_KEY`/`SSH_CONFIG` if that environment needs a different key/config than the
other. No further variable is needed for the deploy target or path; both are derived the same way
from `APP_DOMAIN`, and there is no "View deployment" URL to configure.

Do **not** add an `AWS_REGION` variable — the region comes from `TF_VAR_aws_region` in
`config/environment/.env.main`, which the pipeline reads directly. The same reasoning applies to
the deploy target itself: it comes from `APP_DOMAIN` in tracked config, not a platform variable.

**4. Create the AWS IAM role** (one-time, needed before any provisioning run). Runs on your host,
not in a container, needs the AWS CLI installed locally with credentials that can read IAM:

\`\`\`bash
bash ./kit-modules/basis/sh/oidc.sh -m gen -e dev
\`\`\`

This prints the exact AWS Console clicks (IAM → Identity providers → Add provider → OpenID
Connect; IAM → Roles → Create role → Web identity) plus a ready-to-paste IAM policy JSON. Follow
it verbatim, then copy the created role's ARN into `AWS_ROLE_TO_ASSUME` from step 3.

**5. Bootstrap the Terraform state backend** (one-time, local, before the first provisioning run).
CI does not create this backend automatically — skipping this step means the first *Provision
Infrastructure* dispatch fails with "bucket does not exist":

\`\`\`bash
# Phase 1 — local state, creates the bucket + lock table
mv kit-modules/basis/terraform/state/backend.tf /tmp/state-backend.tf
make tf state init
make tf state apply
mv /tmp/state-backend.tf kit-modules/basis/terraform/state/backend.tf

# Phase 2 — migrate that local state into the bucket it just created
make basis   # interactive shell in the iac container, repo mounted at /srv
#   inside the container:
cd /srv/kit-modules/basis/terraform/state
terraform init -migrate-state \
  -backend-config="bucket=$TF_VAR_tf_backend_bucket" \
  -backend-config="region=$TF_VAR_aws_region" \
  -backend-config="dynamodb_table=$TF_VAR_tf_lock_table"
#   answer "yes" when asked to copy the existing state to the new backend
\`\`\`

**6. Run provisioning** (creates/updates AWS infrastructure via Terraform + Ansible): repo →
**Actions** tab → *Provision Infrastructure* in the left sidebar → **Run workflow** button (top
right of the run list) → set:
- `ENVIRONMENT_TYPE`: `dev`, `stage`, or `prod`
- `ACTION_TYPE`: `plan` (preview only, always run this first), `apply` (creates/changes
  infrastructure), or `destroy` (tears it down, only on purpose)
- `SKIP_ANSIBLE`: leave unchecked unless you specifically want Terraform-only

then click **Run workflow** again to confirm.

**7. Deploy to dev**: automatic, every push to `develop` deploys. To force a re-deploy without a
new commit: Actions → *Deploy to Develop* → **Run workflow**.

**8. Deploy to production**: never automatic. Actions → *Deploy to Production* → **Run workflow**
is the only way anything reaches prod.

Full reference: `.claude/rules/ci.md` (workflow internals) and `.claude/rules/infrastructure.md`
(Terraform/Ansible/licensing) in this repo.

---

Built on [SolidBunch StarterKit](https://starter-kit.io), a Docker + Terraform + Ansible + CI/CD
WordPress boilerplate. See its [documentation](https://starter-kit.io/docs/overview/) for details
on the underlying platform this project is built with.
```

The attribution line below the `---` divider is fixed text — write it as shown, don't copy the
template's own `README.md` content (its "Overview"/"Getting Started"/"Stay Connected" sections
describe StarterKit itself, not this project, and must not appear as if they were this project's
own data). Fill in the placeholders above the divider from what earlier steps already collected
(`APP_TITLE`/`APP_NAME` from Step 1, `APP_DOMAIN` from Step 1, the repo URL from
`git remote get-url origin` if set, else omit that line rather than guessing). Fill in
`<dev APP_DOMAIN>`/`<prod APP_DOMAIN>` from the actual `APP_DOMAIN` values Step 1 wrote into
`config/environment/.env.type.dev`/`.prod` (these are the exact `Host` names both pipelines
require — not a free-form alias). Write these as plain literal text — never write the placeholder
brackets or any commentary about whether/why they were renamed into the generated `README.md`.

If the project has a stage environment (user provided a stage domain in Step 0), include the
`Host <stage APP_DOMAIN>` block in the SSH_CONFIG and fill `<stage APP_DOMAIN>` from the
`APP_DOMAIN` Step 1 wrote into `config/environment/.env.type.stage`. If stage was skipped, **omit
the stage Host block entirely** from the generated SSH_CONFIG.

If Step 0 skipped
the description, use the fallback line defined there. If the user chose to rename the theme
(Step 5) or go monorepo (Step 6), the CI/CD section above still applies as-is — neither changes
what's required in GitHub secrets/vars.

Use `make install local` alone, not `make secret`/`make env` as separate preceding lines — Step 2
of this skill runs those separately for its own staged verification, but `make install` already
runs secret generation, `.env` build, Composer/npm, Docker, and the WP core install in one pass
(see `Makefile`). That reasoning belongs here, in the skill's own instructions — never write it
into the generated `README.md` itself, which must contain nothing but the literal, final steps
a developer follows.

## Step 8 — Refresh AI guidelines

Invoke the `project-brief` skill to re-scan the now-renamed project and update root `CLAUDE.md` /
`.claude/rules/` — project name/title, domain, and (if changed) the theme's identity need to be
reflected so future sessions don't describe the old template identity.

## Step 9 — Report

List every changed file with its full path. Separate clearly:

- **Done automatically**: env rename, regenerated `.env`, install,
  `GITHUB_ORG`/`GITHUB_REPO` rename (if `git remote get-url origin` resolved
  to a GitHub URL), theme repository mode change (if Step 6 ran — `.gitignore`/`composer.json`
  edits, detached `.git`), theme rename (if it ran), project README rewrite, guideline refresh
- **Left for the user**: `/etc/hosts` edit; `GITHUB_ORG`/`GITHUB_REPO` in
  `config/environment/.env.main`
  **only if** no GitHub origin was set for Step 1 to read (still StarterKit's own template values in
  that case); `ROLE_NAME`/`TF_VAR_tf_lock_table` in the same file (always
  left for the user — a real DynamoDB table can't be invented automatically), followed by
  `make env local` after any of the above are edited; GitHub repo/CI secrets setup; `kit-modules`
  licensing (see `infrastructure.md`); the orphaned old theme folder + `composer.json` entry (if
  Step 5 ran); the dev-deploy `switch-theme-dev` CI gap (if Step 6 ran monorepo mode — see its
  caveat) — anything this skill couldn't do without an external-system action or a destructive
  decision

Also mention: the theme ships as FSE (Full Site Editing) by default. If the user wants classic
PHP templates instead (Gutenberg blocks retained, only the page-assembly mechanism changes), point
them at `web/wp-content/themes/<WP_DEFAULT_THEME>/.claude/skills/convert-to-classic-theme/SKILL.md`
— runnable any time now that the theme exists on disk, not something this skill needs to gate on.

Never commit anything in this flow — leave the diff for the user to review and commit themselves.
