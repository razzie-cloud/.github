# Development guide

## Repository boundaries and Git workflow

- This is the razcloud parent repository. `access-gateway/`, `database-broker/`,
  and `infra/` are Git submodules with separate histories and GitHub remotes
  under `razzie-cloud`. Use standard `git submodule` commands.
- Keep root documentation and coordination files in the parent. Change service
  code and deployment files in their owning submodule. Do not copy child source
  into the parent or replace a submodule with ordinary tracked files.
- Begin with `git status`, `git submodule status`, and
  `git submodule foreach 'git status --short --branch'`. Inspect existing diffs
  and untracked files before editing; they may be unfinished user work.
- Initialize missing components with `git submodule update --init --recursive`.
  This restores pinned commits, not the latest remote branch. Check for local
  changes first; avoid forced updates, resets, or cleanup of existing work.
- Submodules can be detached after checkout. Switch to an appropriate branch in
  the affected repository before making commits. Commit component work there,
  then stage that component's path in the parent to update its pinned commit.
  A parent commit does not include uncommitted child changes.
- Make referenced component commits available on their remotes before publishing
  parent pointer updates. Do not push or deploy unless the task authorizes it.
- A more specific `AGENTS.md` inside a component applies to that component.

## Architecture and source map

### access-gateway

- Go module `github.com/razzie-cloud/access-gateway`; entry point
  `cmd/access-gateway/main.go`.
- `internal/app/` owns HTTP handlers, WebAuthn, go-rel PostgreSQL persistence,
  bootstrap registration, and in-memory sessions. `internal/web/` embeds the
  browser UI directly into the binary; there is no frontend build pipeline.
- `internal/db/` embeds Goose SQL migrations from `migrations/`; they run during
  server initialization. Add new migration files for schema changes instead of
  rewriting migrations that may already have run.
- The entry point uses `internal/config.Load` for CLI flags and environment
  variables: `SERVICE_PORT` (default `8080`), `POSTGRES_URI` (required unless
  fetched from `POSTGRES_URI_FROM`), `POSTGRES_PASSWORD_FILE`, `ORIGIN`
  (`http://localhost:8080`), `RP_ID` (`localhost`), and `RP_NAME`
  (`Minimal WebAuthn`). Matching flags include `--port`, `--postgres-uri`,
  `--postgres-uri-from`, `--postgres-password-file`, `--origin`, `--rp-id`,
  and `--rp-name`. Origin and relying-party ID must agree with the deployment.
  Redis settings are parsed by the loader but sessions still use process memory.
- First-user bootstrap creates a token, stores its SHA-256 hash in PostgreSQL,
  and logs the raw token once. Treat that token as a credential. Sessions live
  in process memory and do not survive restarts or synchronize across replicas.

### database-broker

- Go module `github.com/razzie-cloud/database-broker`; entry point
  `cmd/database-broker/main.go`.
- `internal/config/` reads CLI flags and environment variables, including
  password files. `internal/router/` uses chi for HTTP routing;
  `internal/broker/` validates instance names and selects adapters.
- `internal/adapter/` defines shared interfaces and implements PostgreSQL and
  Dragonfly adapters. `redis` and `dragonfly` select the same Dragonfly adapter.
  PostgreSQL metadata migrations use go-rel/migration, separate from the
  gateway's Goose migrations.
- `GET /v1/instances/{adapter}` lists instances. The corresponding
  `/{instance}` and `/{instance}/uri` endpoints create missing instances and
  return credentials. These GET requests can mutate real databases; use local
  backends for development and keep the broker on the internal network.
- Configuration uses `SERVICE_PORT` (default `8080`), `POSTGRES_URI`,
  `POSTGRES_PASSWORD_FILE`, `DRAGONFLY_URI`, and `DRAGONFLY_PASSWORD_FILE`, with
  matching flags. Each backend is registered only when its URI is supplied.

### infra

- `docker-stack.yml` defines a Docker Swarm stack with PostgreSQL, Dragonfly,
  the broker, Caddy Docker Proxy, and a whoami demo. The `internal` overlay
  carries database traffic; `web` carries ingress traffic. Caddy uses service
  deployment labels and publishes ports 80/443.
- `deploy.sh` creates missing external Docker secrets and deploys the stack.
  Its defaults are Docker context `razcloud` and stack name `razzie-cloud`,
  overridable with `DOCKER_CONTEXT` and `STACK_NAME`. It resolves the stack
  file relative to the current directory, so deployment runs from `infra/`.
- `images/hanko/` contains a Hanko image, a configuration template, and an
  entrypoint that requests broker credentials and runs Hanko migrations. Its
  presence does not mean Hanko is included in the current stack.
- `nixos/configuration.nix` describes the host, SSH, Docker, firewall, upgrades,
  and reboot timer. `networking.nix` contains placeholder addresses.
  `hardware-configuration.nix` is host-provided and absent here. `harness.nix`
  configures a separate runner user/rootless Docker but is not imported by the
  main configuration. Preserve `system.stateVersion` unless migrating the host.

## Local development and verification

- Both Go modules declare Go 1.27. Run module commands inside the relevant
  submodule; the parent has no `go.mod` or `go.work`.
- Format changed Go files with `gofmt`. For service changes run `go build ./...`
  and `go vet ./...` in the affected module, plus relevant tests.
- Gateway: `cd access-gateway && go test ./...` includes configuration tests.
  Running the service also needs PostgreSQL and `POSTGRES_URI` (or
  `POSTGRES_URI_FROM`); use `go run ./cmd/access-gateway` with the variables above.
- Broker unit tests without Docker:
  `cd database-broker && go test ./internal/config ./internal/broker ./internal/router ./internal/util`.
- Broker full suite: `cd database-broker && go test ./...`. Adapter integration
  tests use testcontainers to start PostgreSQL and Dragonfly and pull images
  if necessary. They do not skip themselves when Docker is unavailable.
  Ensure the daemon is local/disposable, not the production Docker context.
- Each service has its own Dockerfile and Compose file. The local stacks both
  publish ports 5432 and 8080; run them separately or adjust host port mappings.
- Validate shell edits with `bash -n infra/deploy.sh` and
  `sh -n infra/images/hanko/entrypoint.sh`. With the Compose plugin installed,
  validate each service using `docker compose -f <service>/docker-compose.yml config --quiet`.
- Validate stack edits without deploying:
  `STACK_NAME=razzie-cloud docker stack config -c infra/docker-stack.yml >/dev/null`.
  Use a Nix-capable environment for Nix validation; complete host evaluation
  requires its hardware configuration and actual networking settings.
- Report exactly which checks ran and any environment limitations. Do not run
  `deploy.sh`, `docker stack deploy`, `nixos-rebuild switch`, or change Docker
  contexts as part of ordinary validation.

## Current integration gaps to check before extending the system

These reflect the inspected checkout; recheck the relevant source before relying
on them, and update this guide when they change.

- Gateway configuration supports broker URI discovery and PostgreSQL/Redis
  flags. `main.go` maps PostgreSQL, port, and WebAuthn settings into `app.Config`;
  Redis is not wired into session storage.
- The current stack's Caddy snippet points at `access-gateway:8080/forward_auth`,
  but the stack has no access-gateway service and the gateway has no implemented
  forward-auth handler. The `/` static-file route can catch unknown paths; a
  response from that URL does not demonstrate working forward authentication.
- Infra references a published broker image. Editing the local broker or
  updating its parent pointer does not change the deployed image. Coordinate
  image publication and stack tags when releasing cross-component changes.
- The existing local changes in infra predate parent setup. Keep unrelated fixes
  separate from those changes and do not commit them incidentally.

## Change discipline

Keep changes scoped to the task and owning repository. For cross-component work,
check HTTP paths, config names, secret names, database migrations, image tags, and
Caddy labels together. Keep credentials and local environment files out of Git.
Deployment and host changes affect a real server and require task authorization.
