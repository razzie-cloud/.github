# Development guide

## Repository skills

Reusable project workflows live in the parent repository's `.agents/skills/`.
Read the relevant skill when the task matches; component `AGENTS.md` and current
source remain authoritative for service-specific details.

| Skill | Use for |
| --- | --- |
| [razcloud-frontend-mockups](.agents/skills/razcloud-frontend-mockups/SKILL.md) | Interactive sample-data designs, light/dark previews and screenshots |
| [razcloud-frontend-implementation](.agents/skills/razcloud-frontend-implementation/SKILL.md) | Embedded production UI changes and translating mockups into live templates |
| [razcloud-new-app](.agents/skills/razcloud-new-app/SKILL.md) | A new independent app and its platform integration |
| [razcloud-compose](.agents/skills/razcloud-compose/SKILL.md) | Parent local Compose stack, proxy routes and fixtures |
| [razcloud-swarm](.agents/skills/razcloud-swarm/SKILL.md) | Swarm configuration, image selection and deployment helper maintenance |

## Repository boundaries and Git workflow

- This is the Razzie Cloud parent repository. `access-gateway/`, `database-broker/`, `files/`,
  `notes/`, `chess/`, `sudoku/`, `landing/`, and `infra/` are Git submodules with separate histories and GitHub remotes
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
  registration links for them. Signed-in users can issue links for themselves. Admins can also select <new>
  to invite someone who chooses their own username; the regular user and first
  passkey are created atomically on enrollment, with no placeholder account.
  Links are single-use, expire after a selected 1–43200 minutes, and have locally
  generated QR codes. Enrollment consumes the link and stores the passkey in
  one PostgreSQL transaction.
  Existing-account links can alternatively sign in once without a passkey or
  device enrollment; enrollment remains the split button's default. Login and
  enrollment lock the same link row to prevent competing consumption. Redis
  link sessions follow normal TTL/SSO/revocation and are explicitly labeled;
  they do not block removal of unrelated devices. Invitations still require
  their first passkey. See gateway's guide for cross-store failure handling.
- First-user bootstrap creates a token, stores its SHA-256 hash in PostgreSQL,
  and logs the raw token once. Treat that token as a credential. Sessions live
  in Redis and survive gateway restarts. Replicas share sessions when configured
  with the same public ORIGIN and Redis backend/database.
  Goose migrations use a PostgreSQL session lock. Bootstrap initialization and
  enrollment share a transaction advisory lock; only the committed token's
  creator logs it, and startup cannot overwrite or recreate a consumed token.
- Administrators can disable other users from the Users table after confirming
  session revocation and blocked login. Disabled state is durable in PostgreSQL;
  passkey/link login, enrollment, gateway sessions, SSO and app authorization
  reject it. Ordered user-row locks coordinate revocation with login completion
  and prevent administrators from concurrently disabling each other. Redis
  cleanup failures retain disabled access; enabling requires successful cleanup
  and never restores deleted sessions. Accounts and passkeys are preserved.

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
- Files can rename files and move them within one root mapping, with a lazy
  folder picker and inline subfolder creation. Existing destinations are rejected;
  both physical paths use ordered locks on one database session with access and
  revision rechecks. S3 copy/delete is non-atomic; preserve both copies and report
  partial completion if source removal fails. Public shares remain path-bound.
- Identity is the auth proxy's `X-Auth-Request-User` UUID. Directory/share metadata queries
  are owner-scoped; connection reads also admit shared records. Public shares use random capability links on a separate
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
- Storage setup follows Files: personal or admin-managed shared S3 connections and bucket/prefix
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
- Compatibility-mode write locks and revisions use the connection UUID, bucket
  and physical S3 key, coordinating shared notebooks on that connection. Independent
  connections and external writers remain outside this protection. The physical
  revision migration requires stopping all Notes HTTP processes and River workers
  and reloading compatibility-mode editors; see `notes/docs/architecture.md`.
- River queues maintenance and indexing coordinate per-notebook scan/index work
  across replicas. Durable cursors, advisory locks and current S3 revalidation
  protect retries/duplicates. Only complete listings permit sweep; authoritative
  absence checks remove derived rows. Search uses PostgreSQL simple vectors.
- Embedded PicoCSS/HTMX includes storage setup, notebook selection and explicit
  saves with preserved conflict drafts. Repeated multi-file selections build an
  in-memory queue, including for new notes. Save writes the note before uploading
  attachments with progress; retry skips acknowledged uploads. Attached-file
  removal preserves the draft and queue. Compose/Swarm keep every path behind SSO;
  /v1/admin/* requires the same verified signed admin role as shared connections;
  every Notes path uses ordinary /forward_auth, as Files does.
- Notes' notebook sidebar includes an attachment browser with All / Orphaned
  categories, search, downloads and confirmed orphan deletion. The index bounds
  listing pages; authoritative parent absence is checked in storage. Orphan
  deletion rechecks the parent, current attachment validator and read-only policy
  under object/settings locks. No automatic cleanup runs; removing a note retains
  its attachments. Sidebar browsing remains available on mobile.
- Run build/vet/tests/race inside notes/. PostgreSQL integration uses disposable
  loopback TEST_DATABASE_URL and random schemas; S3 fixtures start automatically.
  Tests include independent rclone filesystem compatibility and encrypted rebuild.

### chess

- Independent Go module `github.com/razzie-cloud/chess`, registered as the `chess/`
  submodule; entry `cmd/chess/main.go`. Remote/image publication remains pending.
  Publish component commits before publishing parent pins. Read `chess/AGENTS.md`,
  the [design plan](chess/docs/plans/2026-11-24-chess-design.md) and
  [implementation evidence](chess/docs/plans/2026-11-24-chess-implementation.md).
- Signed-in `chess` owns setup, Sessions/Archive, deletion and personal puzzles;
  `shared-chess` exposes only fragment-token guest exchange, guest play, viewing
  capabilities and static assets. Both proxy and app enforce the host boundary.
  Gateway owns SSO; Chess always verifies signed PASETO assertions on its app host.
- PostgreSQL owns matches, canonical moves, grants, guest sessions, receipts,
  viewer leases, immutable puzzle definitions and completion bitsets. Puzzle
  play has no server-side session: each move submits the complete history and
  boards for proof-based replay; only completion is persisted. No
  Chess Redis/Valkey or S3 backend is needed. Matches never expire; explicit
  owner deletion retains minimal creation tombstones. Back up the full database.
- Stockfish bot opponents use five fixed difficulty levels across all
  three match creators. Chess persists one pending bot job per match in PostgreSQL,
  dispatches it to the private bounded worker and accepts authenticated callbacks
  only on a separate private listener. Recheck revision, bot seat and legality
  under the match lock; bot matches have no guest playing grants. The local
  main Compose file and production Swarm stack cap the worker at
  1.25 CPU / 512 MiB, with one engine search and eight accepted jobs. Production
  deploy creates/reuses
  the `chess_bot_token` Swarm secret for both services, and the worker companion
  image follows `CHESS_IMAGE_TAG`. See `chess/docs/plans/2026-11-26-stockfish-bot.md`.
- Rules use malbrecht/chess with strict UCI/FEN and bounded PGN input. ECO data is
  normalized locally and embedded; preserve deepest-prefix labels after leaving
  book. Puzzle proof runs only in `cmd/puzzleprep`; published solutions must cover
  every defense with at most one fork and three complete lines at the calculated
  shortest mate length. The unreleased collection contains 206 mate-in-two puzzles
  with consecutive IDs; original source indices remain in provenance.
- Puzzles opens collections with numbered board previews and immediate play.
  Every defense line must reach mate before completion is saved; completed boards
  stay locked at their final positions. Sessions/Archive cards preview the latest
  match position. New-game choices live in the first navigation item, while match
  move and access controls live beside the board. Overview navigation replaces
  redundant page headings; puzzle collections use plain sections and dividers.
- Local Compose builds `./chess`, uses its dedicated PostgreSQL broker token,
  and exposes `chess.localhost` / `shared-chess.localhost`. Swarm requests two
  replicas with shared PostgreSQL and no affinity. The legacy extra RazChess
  definition is removed; cutover must explicitly stop the old running service,
  preserve its Valkey data/grant for rollback and prepare public-host DNS/TLS.
- Run build/vet/unit/race checks inside `chess/`; database tests require disposable
  loopback `TEST_DATABASE_URL`. See the service verification report for actual
  passes and remaining browser/live acceptance limits.

### sudoku

- Independent `github.com/razzie-cloud/sudoku` Go module, registered as the `sudoku/`
  submodule, with entry point
  `cmd/sudoku/main.go`. Read `sudoku/AGENTS.md` and its design document.
  Publish its repository and component commit before publishing the parent pin.
- Signed-in Sudoku has New game, Sessions, Archive and Puzzles in the Chess
  layout. The generator proves uniqueness and rates five technique levels.
  Five immutable collections hold 32 generated boards each, within the
  256-slot limit. Numbered tiles show completion and in-progress borders.
- PostgreSQL stores owner-scoped random games and puzzle attempts with pencil
  marks and revisions. Completed boards stay locked. Random games can be
  archived and resumed, and solved games move to Archive automatically.
  Archive and Sessions preview the latest saved board.
- Local Compose builds `./sudoku` and protects all paths on
  `sudoku.localhost`. Swarm runs two replicas with a scoped `postgres/sudoku`
  broker grant. The app verifies signed Gateway identity and needs
  PostgreSQL for private readiness.
- Run build, vet, tests and race checks inside `sudoku/`. Set a disposable
  loopback `TEST_DATABASE_URL` and Chromium path for persistence and browser
  coverage.

### landing

- Independent `github.com/razzie-cloud/landing` Go module and homepage image.
  Read `landing/AGENTS.md`. A Go HTTP service embeds its assets
  and pre-renders public HTML in memory at startup. PAGE_MODE=both serves the
  public apex and authenticated home.<DOMAIN> by original Host on one listener,
  rejecting other hosts except for private probes, without URI rewriting.
  Standalone public (default) and home modes remain available. Home requires
  signed gateway identity and renders personal welcomes and device/session
  links. Keep its independent PASETO verifier/tests
  synchronized with Files/Notes; personal responses are no-store. It listens on
  SERVICE_PORT (8080), serves only the page/assets for its mode, and exposes
  GET/HEAD /healthz and /readyz.
- `DOMAIN`, `SCHEME` and optional `PUBLIC_PORT` drive metadata and links. Public Sign in
  links to `home.<DOMAIN>` through existing gateway SSO; Home links to gateway
  account management. Gateway HOME_ORIGIN sends direct sign-ins Home while app
  SSO preserves its destination.
  Optional `APPS_CONFIG_FILE` JSON lists cards
  and navigation entries with bundled SVG presets; Files/Notes are examples.
- Gateway, Files and Notes use `LANDING_ORIGIN` / `--landing-origin` for their
  shared cloud-home link; the separate service-name link opens the app.
  Gateway sets LANDING_ORIGIN to the public landing and uses HOME_ORIGIN for
  signed-in logo links; account-state swaps restore the public link on sign-out.
- Run build/vet/race tests in `landing/`. Images and commits must be published
  before deploying parent pins or selecting image tags.

### infra

- `docker-stack.yml` defines a Docker Swarm stack with PostgreSQL, Valkey,
  the broker, access-gateway, files, Dozzle,
  Caddy Docker Proxy, Chess, Sudoku, a public landing page at `razzie.cloud`, and a whoami demo.
  Swarm's `DOMAIN` setting defaults to `razzie.cloud` and controls public hostnames,
  auth origins, and landing-page links and metadata.
  `landing/` is an independent submodule that packages the static page in `ghcr.io/razzie-cloud/landing`;
  build/publish it before selecting `LANDING_IMAGE_TAG` in infra's environment.
  The `internal` overlay carries database traffic; `web` carries ingress traffic. Caddy uses service
  deployment labels and publishes ports 80/443 in host mode to preserve visitor
  IPs for GeoIP. Public DNS targets the manager running Caddy.
  Public UUID/GeoIP/0x40hues definitions live individually in infra/extra/.
  Root/infra make config-extra and deploy-extra discover those YAMLs separately.
  Broker labels map Redis/PostgreSQL instances to deploy-time environment variables;
  the temporary fetcher reuses scoped tokens and verified TLS. GeoIP uses its own Valkey instance. The legacy RazChess grant/data remain
  only for the explicit rollback window; Chess uses a separate PostgreSQL instance. See
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

- All service Go modules and the infra helper module declare Go 1.27. Run module commands inside the relevant
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
- The parent `docker-compose.yml` builds the first-party services and runs a local auth
  demo with PostgreSQL, Valkey, Caddy, and traefik/whoami. Copy `.env.example`
  to `.env` and set separate local `POSTGRES_PASSWORD`, `VALKEY_PASSWORD` and
  `CHESS_BOT_TOKEN` values before starting (the bot token needs 32+ characters).
  Caddy publishes a single loopback HTTP port, `8080`,
  and routes by hostname: public homepage `http://localhost:8080`, gateway
  `http://auth.localhost:8080`, signed-in Home `http://home.localhost:8080`, whoami `http://whoami.localhost:8080`, Files
  `http://files.localhost:8080`, Notes `http://notes.localhost:8080`, Chess
  `http://chess.localhost:8080`, guest/view links `http://shared-chess.localhost:8080`, Sudoku
  `http://sudoku.localhost:8080`, and Dozzle `http://logs.localhost:8080`.
  `LOCAL_PORT` overrides the shared port. Compose builds `landing/` with
  runtime domain/port settings and an optional app-list JSON mount. The main
  stack includes the private Stockfish worker; it uses `chess/Dockerfile.bot`,
  without Air or a source mount. Chess and Stockfish share `CHESS_BOT_TOKEN`.
  The main Compose file uses Air-based automatic recompilation in all seven
  first-party services. Each component owns
  its `Dockerfile.dev` and `.air.toml`; read-only source mounts include embedded
  assets, while binaries/logs and named build caches stay outside the checkout.
  Reload browsers after successful builds; rebuild development images after
  dependency changes. See `docs/development.md#automatic-recompilation`.
  `docker-compose.none.yml` uses the same dev images, source mounts and caches,
  but disables broker token authentication and removes its auth mounts;
  gateway passkey sign-in and SSO remain enabled.
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
  First-party runtime images use Distroless static, retaining existing user IDs.
  Container probes run the service binary's `healthcheck` command against local
  `/readyz` on SERVICE_PORT (default 8080); a TLS-enabled broker instead uses
  its loopback HEALTH_PORT (default 8081). Keep Compose and generated Swarm
  overrides in exec form; no runtime shell or wget is available.
- All services use slog JSON logs on stderr. LOG_LEVEL selects DEBUG, INFO
  (default), WARN, or ERROR. Routine HTTP traffic, SQL, static assets, and health
  probes are quiet at INFO. Request failures use generated IDs, static route
  templates, and classified errors; never log raw backend errors or capability
  URLs. The gateway preserves its one-time bootstrap credential event even at
  ERROR so first-user setup remains possible.
- Gateway configuration supports broker URI discovery and PostgreSQL/Redis
  flags. `main.go` maps these into `app.Config`; Redis stores sessions, passkey
  ceremonies, and SSO handoffs. Local caches never bypass Redis liveness checks.
- Gateway usernames allow 1–64 ASCII letters, digits, `_`, `-` and `.`, preserve
  display capitalization and match case-insensitively. PostgreSQL enforces the
  format and unique lowercase names; migration refuses invalid names/collisions
  without merging accounts. Login ceremonies/decoys normalize case uniformly,
  while Redis completion accepts older mixed-case ceremonies atomically.
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
  Set `FORWARD_AUTH_ORIGINS` to allowed app origins or leading `*.` subdomain
  patterns (exact scheme/port, no apex match, gateway origin excluded); `ORIGIN`
  is the public gateway URL. The stack includes access-gateway at `https://auth.razzie.cloud`
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
  `infra/.env`; `.env.example` in infra lists the variables. UUID,
  GeoIP and 0x40hues use fixed extra YAML defaults with optional overrides and are excluded from
  tag discovery. Keep other current service versions out of stack files and all
  current versions out of README.md and AGENTS.md. Root `make latest-tags` selects
  the highest stable numeric release tags from the seven platform service remotes
  (gateway, broker, Files, Notes, Chess, Sudoku and landing)
  without changing source checkouts or parent pins. Root `make config` and `make deploy` delegate to
  infra's Makefile, which loads and exports the selected environment file.
  `make deploy-latest` combines tag selection and deployment; do not run it as
  validation. Releases need no parent or infra version-only commits. See
  `infra/README.md` and `infra/AGENTS.md` for deployment invariants.
- Root `make postgres-upgrade` delegates to infra using `INFRA_ENV_FILE`. It is
  explicit maintenance: Caddy/PostgreSQL downtime, a verified local cold volume
  archive and an in-place major upgrade, followed by a PostgreSQL-only service
  update. Keep the selected POSTGRES_IMAGE_TAG and POSTGRES_VOLUME_TARGET in
  the operator environment for future deployments. POSTGRES_UPGRADE_IMAGE can
  select a custom migration image; preserve binary version checks and digest
  pinning for overrides. Read the recovery procedure
  in `infra/docs/operations.md`; never run this target as validation.

## Change discipline

Keep changes scoped to the task and owning repository. For cross-component work,
check HTTP paths, config names, secret names, database migrations, image tags, and
Caddy labels together. Keep credentials and local environment files out of Git.
Deployment and host changes affect a real server and require task authorization.

For frontend work, pay particular attention to alignment. Visually check heading
counters, badges, text baselines, icons and neighboring controls in both themes
at mobile and desktop widths, including after HTMX swaps. Use explicit shared
alignment and spacing; inspect inherited Pico margins and line heights. Passing
overflow checks alone is insufficient: review close-up screenshots and verify
that elements look aligned, as well as checking their bounding boxes.

## Signed gateway identity

Authenticated service headers follow the [shared account-header contract](docs/brand/README.md#signed-in-account-header):
shield, username linked to the public gateway and an inline Administrator badge
only for admins, also on mobile. Keep the five local `account-header.css` copies
identical and use this pattern in future apps. Gateway owns sidebar sign-out;
public/anonymous shells omit account identity. Never use the private gateway
discovery URL as a browser destination or unsigned role headers for the badge.

Gateway forward-auth responses include X-Auth-Request-Token (PASETO v4.public)
beside UUID/name. Daily UTC signing keys are atomically reserved in the shared
Redis/Valkey namespace, prepublish the next public key and retain a two-minute
previous-key overlap. GET/HEAD /.well-known/paseto-keys exposes public keys only.
Files/Notes enable verification with ACCESS_GATEWAY_URL / --access-gateway-url;
both stacks set the private gateway origin. Fetch on startup and refresh on
expired/unknown-key use; never trust expired cached keys during an outage.
Verify issuer, public app ORIGIN audience, one-minute lifetime, exact method/URI,
and matching UUID/name. All app-owned admin actions, including Notes maintenance
APIs and Files/Notes shared connections, require `gatewayidentity.IsAdmin` and
propagate that verified role through `store.WithAdmin`. Empty URL retains legacy
proxy mode for ordinary access but never grants admin rights. Use /forward_auth
for every Files/Notes management path; do not rely on X-Notes-Admin or unsigned role headers.
Reserve /forward_auth/admin for proxy-authorized apps such as Dozzle that do not
verify gateway claims themselves. Strip/copy the token
with other identity headers, exclude public shares/health, and never echo tokens.
Keep the independent Files/Notes verifier copies and tests synchronized. The
full protocol is in access-gateway/docs/reference.md#signed-proxy-identity.

## Scoped broker authentication

Broker defaults to AUTH_MODE=token with strict YAML policy, deterministic scoped
HMAC tokens and explicit key/generation overlap. See
[broker authentication](docs/database-broker-auth.md) and broker docs/authentication.md.
AUTH_MODE=none is an explicit legacy opt-out; it never loads policy/key files.
All credential responses are no-store. Token-mode listing is denied.

First-party consumers use BROKER_TOKEN_FILE / --broker-token-file and optional
BROKER_CA_FILE / --broker-ca-file; public discovery URLs contain client IDs only.
Keep independent discovery implementations/tests synchronized, including broker's
legacy startup adapter. Never log URLs/raw HTTP errors or retry without auth.

Local Compose uses independent development policy and ignored .local credentials;
run make local-auth with Go before starting. docker-compose.none.yml resets
auth mounts explicitly and needs no token files. Production deploy.sh delegates to
Go for Swarm-only master generation, scoped client secrets, versioned policy,
verified TLS, staged migration and bounded convergence. Read infra's broker auth
guide and run its fake-Docker tests when changing lifecycle behavior. For a new
installation, make broker-pki automates an internal CA and broker TLS secret using
Go 1.27, preserves existing inputs and refuses implicit rotation. Keep
its CA key in ignored infra/pki/ and back it up securely. Do not deploy
or publish as ordinary validation; referenced local commits still require publication
before parent pointer updates or image references are published.

## Shared S3 connections

Files/Notes retain independent connection stores. Personal connections remain
owner-managed; shared connections require a verified signed gateway admin for
creation, editing and removal, even for their creator. No unsigned admin header
or legacy-proxy role grants this authority. Shared status is immutable in SQL.
Shared-only user-ID prefixing prepends the mapping owner's UUID before the logical
prefix and outside crypt; it locks while any user has a mapping attached. Keep
mapping/crypt ownership scoped, use the connection creator for Files S3 secrets,
and include effective physical prefixes in Notes crypt recovery. Database triggers
allow mapping references only to owned personal or shared connections. Notes shared
policy changes invalidate conditional-write revisions across all attached owners.

Personal/shared Files and Notes connections also support an optional fixed bucket.
Mappings resolve it server-side before storage access and under connection row
locks at save; SQL triggers reject overrides or restrictions incompatible with
existing mappings across users. New connections default path-style addressing
off; existing choices are preserved and the local S3 demo still needs it enabled.
