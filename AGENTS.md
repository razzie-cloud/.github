# Development guide

## Repository boundaries and Git workflow

- This is the Razzie Cloud parent repository. `access-gateway/`, `database-broker/`, `files/`,
  `notes/`, `landing/`, and `infra/` are Git submodules with separate histories and GitHub remotes
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
  bootstrap registration, and Redis-backed sessions. `internal/web/` embeds the
  browser UI directly into the binary; there is no frontend build pipeline.
  Frontend work must use HTMX + PicoCSS, served from embedded local assets.
  See `access-gateway/AGENTS.md` for enrollment and authorization invariants.
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
  `REDIS_URI` (or `REDIS_URI_FROM`) is required for shared session storage;
  `REDIS_PASSWORD_FILE` supplies Redis credentials. Payloads are cached locally
  with bounded TTLs, while authorization checks Redis key liveness on every hit.
- The first user is the admin and can create regular users and issue device
  registration links for them. Signed-in users can issue links for themselves.
  Links are single-use, expire after a selected 1–43200 minutes, and have locally
  generated QR codes. Enrollment consumes the link and stores the passkey in
  one PostgreSQL transaction.
- First-user bootstrap creates a token, stores its SHA-256 hash in PostgreSQL,
  and logs the raw token once. Treat that token as a credential. Sessions live
  in Redis and survive gateway restarts. Replicas share sessions when configured
  with the same public ORIGIN and Redis backend/database.
  Goose migrations use a PostgreSQL session lock. Bootstrap initialization and
  enrollment share a transaction advisory lock; only the committed token's
  creator logs it, and startup cannot overwrite or recreate a consumed token.

### database-broker

- Go module `github.com/razzie-cloud/database-broker`; entry point
  `cmd/database-broker/main.go`.
- `internal/config/` reads CLI flags and environment variables, including
  password files. `internal/router/` uses chi for HTTP routing;
  `internal/broker/` validates instance names and selects adapters.
- `internal/adapter/` defines shared interfaces and implements PostgreSQL,
  Dragonfly, and Valkey adapters. `redis` and `dragonfly` select the same
  Dragonfly adapter; `valkey` requires standalone Valkey 9.1.0+ with numbered
  database ACLs.
  PostgreSQL metadata migrations use go-rel/migration, separate from the
  gateway's Goose migrations.
- `GET /v1/instances/{adapter}` lists instances. The corresponding
  `/{instance}` and `/{instance}/uri` endpoints create missing instances and
  return credentials. These GET requests can mutate real databases; use local
  backends for development and keep the broker on the internal network.
- Configuration uses `SERVICE_PORT` (default `8080`), `POSTGRES_URI`,
  `POSTGRES_PASSWORD_FILE`, `DRAGONFLY_URI`, `DRAGONFLY_PASSWORD_FILE`, `VALKEY_URI`,
  and `VALKEY_PASSWORD_FILE`, with matching flags. Each backend is registered
  only when its URI is supplied.
- PostgreSQL migrations use an outer transaction advisory lock. Provisioning
  takes a per-instance session lock and uses the same pinned connection for
  CREATE DATABASE and the metadata/role transaction. Dragonfly atomically
  reserves canonical credentials at `instance-pending:<name>` before applying
  ACLs and publishing `instance:<name>`; retain reservations without expiry so
  concurrent requests and failed provisioning retries use the same password.
  Valkey atomically reserves database numbers and canonical credentials with
  WATCH/MULTI/EXEC, excludes the metadata database, and denies pub/sub commands
  and channels for every provisioned user. Retain its reservations and ownership
  registry indefinitely. With `aclfile` configured, save ACLs before publishing
  credentials; keep the ACL file with RDB/AOF backups. See `database-broker/AGENTS.md`.

### files

- Go module `github.com/razzie-cloud/files`; entry point `cmd/files/main.go`.
  Read `files/AGENTS.md` for invariants and verification commands.
- Named per-user web directories map directly to S3 buckets/prefixes. Embedded
  rclone S3 and optional crypt APIs handle storage; there is no rclone subprocess,
  local sync, RC API, or custom encryption. UI assets use embedded HTMX/PicoCSS.
- File previews cover bounded UTF-8 text, safely formatted Markdown, native PDFs,
  images, audio, and video on personal and public-share download routes. Text and
  Markdown have a 2 MiB limit; media byte ranges preserve encrypted streaming.
  Browser codec support varies. Keep document sandboxing and share scope checks.
- Identity is the auth proxy's `X-Auth-Request-User` UUID. Management metadata queries
  are owner-scoped. Public shares use random capability links on a separate
  `SHARE_ORIGIN` hostname (`shared-files`), with read-only file/folder access and
  optional password sessions. Shares bind to directory IDs and cascade on deletion.
  Only capability discovery is unscoped; subsequent metadata uses the share owner.
  Share/storage snapshots cache for 30 seconds per replica; management changes
  invalidate locally and revocation propagates within that TTL. Connection read-only access takes precedence over directory policy.
- `POSTGRES_URI_FROM` normally provisions `/v1/instances/postgres/files/uri`.
  Configuration, credentials, and crypt passwords use owner-scoped PostgreSQL
  records. No files-specific secret volume or encryption key is required.
  IMPORT_SECRETS_DIR is a one-time option to import a legacy secrets volume.
- Google Cast uses the Default Media Receiver: direct MP4 and browser-timed
  JPEG/PNG slideshows. `CAST_SHARE_TTL` defaults to 6h, capped at 24h. Owner casts
  create ordinary expiring shares; public password shares use scoped stateless
  HMAC tickets. Media requests preserve guarded storage and byte ranges. Local
  embedded controller assets load the external SDK only on casting pages;
  hardware/CSP/CORS acceptance remains pending. See the
  [Files Cast reference](files/docs/reference.md#google-cast).
- S3 clients use a guarded loopback egress proxy for connection-time destination
  checks. Private/HTTP endpoints require exact operator-managed exceptions.
- PostgreSQL integration tests require a disposable loopback `TEST_DATABASE_URL`;
  other storage tests start an in-memory S3 HTTP server automatically.

### notes

- Go module `github.com/razzie-cloud/notes`; entry `cmd/notes/main.go`.
  Read `notes/AGENTS.md`, its plan correction and architecture document.
- Storage setup follows Files: owner-managed S3 connections and bucket/prefix
  notebooks with optional rclone crypt. Notes owns its settings, credentials and
  recovery records; no Files database tables or saved connections are shared.
- S3 is authoritative for Markdown/front matter and attachments. PostgreSQL
  storage settings/secrets are durable and need backups; only index/scan/River
  tables are disposable. No deployment-wide S3 bucket, credentials, master key,
  provider Docker secrets or Notes-specific volume is required.
- rclone crypt handles compatible name/content encryption; the AWS SDK retains
  conditional writes and paginated listing. Preserve connection-time egress
  checks, owner/notebook query scoping and current read-only policy checks.
  Storage checks share the caller's object/page transaction to avoid nested
  pool acquisition. Removing mappings retains S3 objects and crypt recovery.
- River queues maintenance and indexing coordinate per-notebook scan/index work
  across replicas. Durable cursors, advisory locks and current S3 revalidation
  protect retries/duplicates. Only complete listings permit sweep; authoritative
  absence checks remove derived rows. Search uses PostgreSQL simple vectors.
- Embedded PicoCSS/HTMX includes storage setup, notebook selection and explicit
  saves with preserved conflict drafts. Compose/Swarm keep every path behind SSO;
  /v1/admin/* also requires the gateway admin policy and trusted marker.
- Run build/vet/tests/race inside notes/. PostgreSQL integration uses disposable
  loopback TEST_DATABASE_URL and random schemas; S3 fixtures start automatically.
  Tests include independent rclone filesystem compatibility and encrypted rebuild.

### landing

- Independent `github.com/razzie-cloud/landing` Go module and homepage image.
  Read `landing/AGENTS.md`. A standard-library Go HTTP service embeds its assets
  and pre-renders HTML in memory at startup. It listens on SERVICE_PORT (8080),
  serves only the public page/assets, and exposes GET/HEAD /healthz and /readyz.
- `DOMAIN`, `SCHEME` and optional `PUBLIC_PORT` drive metadata and links. Sign in
  always links to `auth.<DOMAIN>`. Optional `APPS_CONFIG_FILE` JSON lists cards
  and navigation entries with bundled SVG presets; Files/Notes are examples.
- Gateway, Files and Notes use `LANDING_ORIGIN` / `--landing-origin` for their
  shared cloud-home link; the separate service-name link opens the app.
- Run build/vet/race tests in `landing/`. Images and commits must be published
  before deploying parent pins or selecting image tags.

### infra

- `docker-stack.yml` defines a Docker Swarm stack with PostgreSQL, Valkey,
  the broker, access-gateway, files, public RazChess/UUID/GeoIP/0x40hues apps, Dozzle,
  Caddy Docker Proxy, a public landing page at `razzie.cloud`, and a whoami demo.
  Swarm's `DOMAIN` setting defaults to `razzie.cloud` and controls public hostnames,
  auth origins, and landing-page links and metadata.
  `landing/` is an independent submodule that packages the static page in `ghcr.io/razzie-cloud/landing`;
  build/publish it before selecting `LANDING_IMAGE_TAG` in infra's environment.
  The `internal` overlay carries database traffic; `web` carries ingress traffic. Caddy uses service
  deployment labels and publishes ports 80/443 in host mode to preserve visitor
  IPs for GeoIP. Public DNS targets the manager running Caddy.
  RazChess and GeoIP use `--redis-from` with separate Valkey instances. Their
  startup wrappers wait for broker readiness; RazChess stays at one replica.
  Its default session loader uses `SCAN`, compatible with broker ACLs. See
  `infra/docs/operations.md`.
- `deploy.sh` creates missing external Docker secrets and deploys the stack.
  Its defaults are Docker context `razcloud` and stack name `razzie-cloud`,
  overridable with `DOCKER_CONTEXT` and `STACK_NAME`. It resolves the stack
  file relative to the current directory, so deployment runs from `infra/`.
- `nixos/configuration.nix` describes the host, SSH, Docker, firewall, upgrades,
  and reboot timer. `networking.nix` contains placeholder addresses.
  `hardware-configuration.nix` is host-provided and absent here. `harness.nix`
  configures a separate runner user/rootless Docker but is not imported by the
  main configuration. Preserve `system.stateVersion` unless migrating the host.

## Local development and verification

- All five Go modules declare Go 1.27. Run module commands inside the relevant
  submodule; the parent has no `go.mod` or `go.work`.
- Format changed Go files with `gofmt`. For service changes run `go build ./...`
  and `go vet ./...` in the affected module, plus relevant tests.
- Gateway: `cd access-gateway && go test ./...` includes configuration tests.
  Integration tests require disposable local `TEST_DATABASE_URL` and
  `TEST_REDIS_URL` backends (Redis-only tests need only the latter). Running the
  service needs PostgreSQL and Redis via `POSTGRES_URI`/`REDIS_URI` or their
  `_FROM` discovery options; use `go run ./cmd/access-gateway` with these set.
- Broker unit tests without Docker:
  `cd database-broker && go test ./internal/config ./internal/broker ./internal/router ./internal/util`.
- Broker full suite: `cd database-broker && go test ./...`. Adapter integration
  tests use testcontainers to start PostgreSQL, Dragonfly, and Valkey and pull images
  if necessary. They do not skip themselves when Docker is unavailable.
  Ensure the daemon is local/disposable, not the production Docker context.
  Alternatively set disposable loopback `TEST_DATABASE_URL`, `TEST_DRAGONFLY_URL`,
  and `TEST_VALKEY_URL` for native backends. PostgreSQL tests create/drop databases
  and roles; Dragonfly requires an empty broker registry and cleans up metadata,
  reservations, and ACL users. See `database-broker/AGENTS.md`.
  Valkey tests require an empty dedicated server with only the default admin and
  clean up all test data/users; its container fallback uses Valkey 9.1.0.
- Each service has its own Dockerfile and Compose file. The gateway/broker stacks both
  publish ports 5432 and 8080; run them separately or adjust host port mappings.
- The parent `docker-compose.yml` builds all four services and runs a local auth
  demo with PostgreSQL, Valkey, Caddy, and traefik/whoami. Copy `.env.example`
  to `.env` and set separate local `POSTGRES_PASSWORD` and `VALKEY_PASSWORD`
  values before starting. Caddy publishes a single loopback HTTP port, `8080`,
  and routes by hostname: public homepage `http://localhost:8080`, gateway
  `http://auth.localhost:8080`, whoami `http://whoami.localhost:8080`, Files
  `http://files.localhost:8080`, Notes `http://notes.localhost:8080`, and Dozzle `http://logs.localhost:8080`.
  `LOCAL_PORT` overrides the shared port. Compose builds `landing/` with
  runtime domain/port settings and an optional app-list JSON mount; rebuild only after source or asset changes.
  The broker provisions the gateway's
  and files' PostgreSQL databases and the gateway's numbered Valkey database;
  the gateway uses `REDIS_URI_FROM` with the `valkey` adapter path for credentials.
  Valkey is private to the backend network and uses `VALKEY_IMAGE_TAG` (9.1.0+).
  Database 0 stores broker metadata; 15 other databases are available to apps.
  The broker waits for both backend health checks. Both stacks persist Valkey
  AOF data and ACLs in `valkey_data`; the broker saves configured ACL files before
  publishing credentials. Initial admin credentials are hashed into the ACL file;
  environment/secret changes alone do not rotate an existing volume's password.
  Files stores its configuration and secret records in its broker database.
  The optional `storage-demo` profile adds a disposable in-memory S3 fixture
  with bucket `files-demo`; set S3_DEV_PASSWORD. Modern browsers resolve
  `.localhost` to loopback and permit passkeys over HTTP without certificates.
  Gateway `RP_ID` is `auth.localhost`.
  Host-browser HTTP access through `.localhost` in WSL2 has been verified;
  forwarding and resolution must still work on the browser's host. See
  [host browser troubleshooting](docs/development.md#host-browser-troubleshooting).
  Cookies span ports; apps must use separate hostnames to avoid sharing
  their common `razcloud_app` cookie. Every Dozzle path uses `/forward_auth/admin`; Caddy
  strips incoming identity and `Remote-*` headers. Dozzle maps the gateway's UUID
  and username headers via `DOZZLE_AUTH_HEADER_USER`/`DOZZLE_AUTH_HEADER_NAME`.
  Root `Caddyfile` protects every whoami/files management path, including the SSO
  callback. Public share links use `http://shared-files.localhost:8080/s/<token>`
  on the same shared port. Validate with
  `docker compose --env-file .env.example config --quiet`.
- Validate shell edits with `bash -n infra/deploy.sh`. With the Compose plugin installed,
  validate each service using `docker compose -f <service>/docker-compose.yml config --quiet`.
- Validate stack edits without deploying:
  `make config` with service tags selected in ignored `infra/.env`. Alternatively,
  `docker compose --env-file infra/.env -f infra/docker-stack.yml config --quiet`.
  Use a Nix-capable environment for Nix validation; complete host evaluation
  requires its hardware configuration and actual networking settings.
- Report exactly which checks ran and any environment limitations. Do not run
  `deploy.sh`, `docker stack deploy`, `nixos-rebuild switch`, or change Docker
  contexts as part of ordinary validation.

## Current integration gaps to check before extending the system

These reflect the inspected checkout; recheck the relevant source before relying
on them, and update this guide when they change.

- All services expose private GET/HEAD `/healthz` (liveness) and `/readyz`
  (cached readiness). Background checks have two-second dependency deadlines,
  repeat ten seconds after each cycle, and expire results after thirty seconds.
  Gateway checks PostgreSQL/Redis; broker checks each configured backend once
  (no backends means not ready); files checks PostgreSQL, not user S3 endpoints.
  Successful probes are quiet; background checks log dependency failure and
  recovery transitions with fixed dependency names, without backend errors.
  Container probes use `/readyz` on SERVICE_PORT.
- All services use slog JSON logs on stderr. LOG_LEVEL selects DEBUG, INFO
  (default), WARN, or ERROR. Routine HTTP traffic, SQL, static assets, and health
  probes are quiet at INFO. Request failures use generated IDs, static route
  templates, and classified errors; never log raw backend errors or capability
  URLs. The gateway preserves its one-time bootstrap credential event even at
  ERROR so first-user setup remains possible.
- Gateway configuration supports broker URI discovery and PostgreSQL/Redis
  flags. `main.go` maps these into `app.Config`; Redis stores sessions, passkey
  ceremonies, and SSO handoffs. Local caches never bypass Redis liveness checks.
- Gateway login asks for a username and filters passkeys by that account. Unknown
  users receive deterministic decoys; every list is padded to a common credential
  count/ID-length profile. PostgreSQL app_states persists the shared decoy secret.
  Log attempts and failures with bounded, quoted claimed_username, including
  canceled prompts; no explicit account-existence response is exposed.
  Credential-ID privacy limitations remain. Existing username-less ceremonies
  must restart on upgrade.
- The gateway implements `/forward_auth` and `/auth/authorize` with host-only
  app cookies and a single-use callback at the app's `/_auth/callback` path.
  `/forward_auth/admin` reuses this flow and requires the current PostgreSQL
  admin role on each app request; regular users receive 403 without a redirect.
  Set `FORWARD_AUTH_ORIGINS` to exact allowed app origins; `ORIGIN` is the public
  gateway URL. The stack includes access-gateway at `https://auth.razzie.cloud`
  and protects files and whoami with forward auth and verified identity headers.
  Dozzle uses `https://logs.razzie.cloud` and `/forward_auth/admin` on every path,
  including its callback. It runs globally in Swarm mode with a per-node settings
  volume, private HTTP port, and container actions/shell disabled. Its image tag
  is operator-selected via `DOZZLE_IMAGE_TAG` in `infra/.env`.
  The files route strips incoming identity headers before authentication.
  All management paths, including callbacks, are protected. The separate
  `shared-files.razzie.cloud` host exposes public `/s/*` and `/static/*` only,
  strips identity headers, and returns 404 elsewhere. It uses files SHARE_ORIGIN
  and is not in gateway FORWARD_AUTH_ORIGINS.
- Infra references a published broker image. Editing the local broker or
  updating its parent pointer does not change the deployed image. Coordinate
  image publication and stack tags when releasing cross-component changes.
- The existing local changes in infra predate parent setup. Keep unrelated fixes
  separate from those changes and do not commit them incidentally.
- The stack requires platform and third-party image tags from ignored
  `infra/.env`; `.env.example` in infra lists the variables. RazChess, UUID,
  GeoIP and 0x40hues use fixed stack defaults with optional overrides and are excluded from
  tag discovery. Keep other current service versions out of stack files and all
  current versions out of README.md and AGENTS.md. Root `make latest-tags` selects
  the highest stable numeric release tags from the four platform service remotes
  without changing source checkouts or parent pins. Root `make config` and `make deploy` delegate to
  infra's Makefile, which loads and exports the selected environment file.
  `make deploy-latest` combines tag selection and deployment; do not run it as
  validation. Releases need no parent or infra version-only commits. See
  `infra/README.md` and `infra/AGENTS.md` for deployment invariants.

## Change discipline

Keep changes scoped to the task and owning repository. For cross-component work,
check HTTP paths, config names, secret names, database migrations, image tags, and
Caddy labels together. Keep credentials and local environment files out of Git.
Deployment and host changes affect a real server and require task authorization.
