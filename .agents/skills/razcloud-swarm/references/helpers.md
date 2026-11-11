# Swarm helper contracts

Re-read executable implementation before editing. Paths are parent-relative.

## Commands and side effects

| Command | Current behavior |
| --- | --- |
| Root `make config` | Delegates to infra with absolute `INFRA_ENV_FILE`; validates without deploying. |
| Root `make latest-tags` | Queries/fetches first-party tags and updates the selected ignored env file. Does not change app checkouts/pins, publish images or deploy. |
| Root `make deploy` | Delegates to infra; creates missing secrets and deploys. |
| Root `make deploy-latest` | Tag selection followed by deployment; never use as validation. |
| Infra `make config` | Loads `ENV_FILE`, exports settings and runs quiet Compose config validation. |
| Infra `make deploy` | Loads settings and invokes `deploy.sh` from infra. |

Root `INFRA_ENV_FILE` defaults to `infra/.env`; infra `ENV_FILE` defaults to
`.env`. Make command-line assignments take precedence. Keep root absolute-path
resolution and infra exports aligned, including optional app settings. Preserve
the established Make assignment format; it is not arbitrary shell dotenv syntax.

## Tag selection

`scripts/update-image-tags.sh` resolves database-broker, access-gateway, Files,
Notes and landing releases from each submodule origin.

- Accept stable numeric `MAJOR.MINOR.PATCH` with optional `v`, no leading numeric
  zeros, prereleases or floating tags. Compare numerically; keep exact spelling.
- Resolve **all** services before fetching tags or changing the env file. Failed
  discovery/fetch must leave env selection unchanged. Fetch selected tags without
  checkout changes or submodule recursion. Never force-rewrite conflicting tags.
- Keep `services` and `keys` aligned. Inactive public apps stay outside discovery;
  preserve their optional overrides.
- Preserve settings/comments and existing Dozzle selection. Seed missing env from
  `infra/.env.example`; fill absent Dozzle from the example, not a remote query.
  Retain the script's normalization of duplicate targeted assignments.
- Write beside the destination then rename into place, preserve existing mode
  and clean temporary files on failure. Do not print secret settings. Tag
  selection does not establish image publication.

## Deployment

`infra/deploy.sh` defaults to context `razcloud` / stack `razzie-cloud`, overridable
with `DOCKER_CONTEXT` / `STACK_NAME`. Stack path is relative to the current
directory; normal entry is infra's Makefile.

Validate config before secret creation. Preserve existing external
`postgres_password` and `valkey_password`; generate only missing values with
bounded randomness through stdin, without printing them. Retain pipefail safety
and explicit context targeting. Deployment uses `--with-registry-auth` for node
access to selected private images. Do not incidentally switch global context,
rotate/remove secrets, prune services or delete volumes.

## Meaningful isolated checks for script changes

Use a temporary workspace with fake `git`/`docker` commands recording arguments
and returning authored results. Execute copied scripts/Makefiles there; do not
use production or the operator's `.env` for behavior tests.

- Feed mixed tag prefixes, numeric gaps, prereleases, malformed versions and no
  stable release. Verify selection and unchanged env after discovery/fetch failure.
- Use env fixtures with comments, custom paths, overrides, duplicates and absent
  keys. Verify unrelated values and file modes survive.
- Simulate invalid deploy config: no secret/deploy mutation follows. Cover
  existing/missing secrets and custom context/stack; verify order/arguments.
  Consume random secret stdin without recording it.
- Exercise parent Make with a custom env path and CLI overrides; verify child
  values/exports.

Run these when behavior changes. Avoid tests that only match script wording,
or live tag discovery/deployment for documentation-only edits.
