# Local development and maintenance

See the [README](../README.md) for the platform overview and first run.

## Development

### Run the complete local stack

Run the commands in this guide from the parent repository root.

With the submodules checked out and Docker Compose installed, run these commands
from the project root against your local Docker daemon:

```sh
cp .env.example .env
# Set POSTGRES_PASSWORD and VALKEY_PASSWORD to separate random hex values.
# Generate each with: openssl rand -hex 24
docker compose up --build -d
docker compose logs access-gateway
```

Compose builds the gateway from the checked-out source and tags it as
`ghcr.io/razzie-cloud/access-gateway:dev`. Override `ACCESS_GATEWAY_IMAGE_TAG`
in `.env` to change the local build's tag.

The public homepage is at <http://localhost:8080>. Compose builds the independent
`landing/` submodule. Its optional `LANDING_APPS_FILE` JSON mount defaults to the
Files/Notes example. Domain, scheme and `LOCAL_PORT` are rendered at container
startup. Recreate containers after port or config changes; rebuild the landing
image only after source or asset changes. Services receive `LANDING_ORIGIN` so
their cloud logo returns here while the service name opens the app.

Find the `bootstrap.token_created` event and its `bootstrap_token` field in the
gateway logs. Open <http://auth.localhost:8080>, create the first administrator
using that token and a passkey, then sign in. The token
is logged only when first generated; keep the initial logs until setup is done.

Open <http://whoami.localhost:8080> for the protected
`traefik/whoami` demo. It redirects to the gateway for sign-in, then returns to
whoami with a separate app session.
Whoami displays the verified `X-Auth-Request-User` and `X-Auth-Request-Name`
headers. Signing out at the gateway revokes access to the demo.

Use the exact hostnames above to keep their host-only cookies separate. Modern
browsers resolve `.localhost` names to loopback and treat HTTP on these hosts as
secure contexts, allowing passkeys without certificates. All local services use
port `8080`; `LOCAL_PORT` in `.env` changes that port for every hostname. Use the
same port in your browser and URI-unreserved characters for `POSTGRES_PASSWORD`
and `VALKEY_PASSWORD`, as documented in `.env.example`.

Open <http://files.localhost:8080> for the files UI. Use this exact hostname to
isolate its app cookie from the gateway and whoami: host-only cookies are shared
across ports on the same host. Public share links use
`http://shared-files.localhost:8080/s/<token>` on the same shared port.
Use **Share** beside an entry or **Sharing** in the directory toolbar
to create read-only file/folder links with an optional password. The sharing
hostname permits unauthenticated visitors and only exposes share/static routes;
the files management hostname keeps forward authentication on every path.

Open <http://logs.localhost:8080> for Dozzle's container logs
(`DOZZLE_IMAGE_TAG` selects its image). It requires an administrator account:
every request, including `/_auth/callback`, goes through the gateway's
`/forward_auth/admin` endpoint. Regular users receive 403.
Dozzle has no directly published port; Caddy is its only host entry point.
Container actions and shell access are disabled.

Dozzle's [forward-proxy authentication](https://dozzle.dev/guide/authentication/forward-proxy)
normally reads `Remote-User`, `Remote-Name`, and optional `Remote-Email`,
`Remote-Filter`, and `Remote-Roles`. We configure `DOZZLE_AUTH_HEADER_USER` as
`X-Auth-Request-User` (stable account UUID) and `DOZZLE_AUTH_HEADER_NAME` as
`X-Auth-Request-Name` (username). No email header is needed. Caddy strips supplied
identity and `Remote-*` headers before copying the gateway's verified identity.
Administrator authorization comes from the gateway's current database role.
Dozzle's settings persist in the `dozzle_data` volume. Its Docker socket mount
is read-only, but that does not restrict Docker API operations; only run this
setup against a trusted local daemon.

### Host browser troubleshooting

Caddy publishes one HTTP port, bound to `127.0.0.1`, and routes requests by their
`.localhost` hostname. Host-browser access to an HTTP server in WSL2 using
`app.localhost:8080` has been verified in this setup. With WSL2/VMs, check
loopback forwarding and hostname resolution in the actual host OS browser if
an app is unreachable; a successful request inside Linux alone does not verify
host browser access.

Keep the separate hostnames: app cookies are shared across ports on the same
host. Use HTTP and the shared `LOCAL_PORT`, rather than opening the IP address.
In the gateway page's browser console, `window.isSecureContext` should be `true`
and `typeof PublicKeyCredential` should be `"function"` for passkey support.

For command-line clients that do not resolve `.localhost`, use an explicit
loopback mapping:

```sh
curl --resolve files.localhost:8080:127.0.0.1 http://files.localhost:8080/
```

### Slow pages and intermittent proxy timeouts

When even tiny static assets wait seconds before their first byte, compare HAR
request timings with Caddy's upstream errors. If the backend responds immediately
over its own loopback interface but Caddy logs `dial tcp ...:8080: i/o timeout`,
check the Docker bridge for duplicate MAC addresses:

```sh
docker --context default network inspect razcloud_web --format '{{range .Containers}}{{.Name}} {{.IPv4Address}} {{.MacAddress}}{{println}}{{end}}'
docker --context default network inspect razcloud_backend --format '{{range .Containers}}{{.Name}} {{.IPv4Address}} {{.MacAddress}}{{println}}{{end}}'
```

Each container interface on the same network needs a unique MAC. A duplicate
between the gateway and Notes can make authentication traffic and Notes traffic
switch the bridge's forwarding entry between their interfaces. TCP retransmissions
then produce long waits even though DNS, SQL and page rendering are fast.

Docker Engine 25.0.0 has a documented duplicate-MAC bug. Upgrade the engine to a
patched release, then **recreate** affected containers; restarting them alone can
retain the bad addresses. See the [Docker release note](https://docs.docker.com/engine/release-notes/25.0/#2503).
After the host upgrade, from the parent checkout:

```sh
docker --context default compose up -d --force-recreate --no-build --pull never
```

This uses existing images and preserves named database volumes. Recheck both
networks for duplicates and repeat the browser load. A host Docker upgrade is an
operator action, separate from service-source changes or ordinary validation.

### Disposable S3 demo

For an optional disposable S3 demo, set a fresh `S3_DEV_PASSWORD` in `.env` and
start `docker compose --profile storage-demo up --build -d`. The development
fixture creates an in-memory `files-demo` bucket. In Files, add a custom S3
connection with endpoint `http://s3-demo:9000`, region `us-east-1`, path-style
addressing, access key `files-dev`, and that development password. Choose Read-only
or Writable, then create a directory for `files-demo` with optional rclone crypt.
Demo objects disappear when the fixture restarts. The private HTTP exception is
limited to `s3-demo:9000`; normal vendor connections use public HTTPS. Only use
these credentials with the local demo.

### Notes

Open `http://notes.localhost:8080` after signing in. Notes starts with a storage
setup screen. Add an S3 connection under Storage (provider, endpoint, region,
path-style option, credentials and access policy), then attach a notebook to a
bucket/prefix. Optional encryption uses rclone crypt passwords and naming options,
including verification for existing encrypted data and downloadable recovery.

With `storage-demo` enabled, use endpoint `http://s3-demo:9000`, region `us-east-1`,
path-style addressing, access key `files-dev`, and `S3_DEV_PASSWORD`. Choose bucket
`files-demo` and a dedicated prefix, such as `my-notes`. This bucket is in-memory.
Durable provider credentials are entered in the same UI; no NOTES_S3_* credential
variables are needed. Notes owns its PostgreSQL settings and secrets rather than
sharing Files records. Back up these durable settings and crypt recovery passwords;
its content index and River scan progress can be rebuilt from S3.

Saves use underlying S3 ETags, including encrypted notes, and retain conflicting
drafts. Admin rebuild/status paths use /forward_auth/admin; normal storage and
content management use /forward_auth and owner-scoped lookups. See
[Notes configuration and recovery](../notes/README.md).

### Local stack internals and cleanup

The root [docker-compose.yml](../docker-compose.yml) builds all four Go services from
their submodules using host build networking, matching the gateway's standalone
Compose setup, plus the Go landing-page service image from `landing/`.
The homepage joins only the web network, is public, and has no database dependency.
The broker provisions the gateway's and files' PostgreSQL databases
and the gateway's numbered Valkey database. The gateway discovers
its credentials through `REDIS_URI_FROM` using `/v1/instances/valkey/access_gateway/uri`.
Valkey requires the local `VALKEY_PASSWORD`; `VALKEY_IMAGE_TAG` selects a 9.1.0+
image with database ACL support. Database 0 holds broker metadata; the other 15
databases are available to applications. The broker waits for both PostgreSQL
and Valkey health checks before starting. Caddy
checks every whoami/files request, including the SSO callback, with the gateway's
`/forward_auth` endpoint, and Dozzle requests with `/forward_auth/admin`, before
proxying them. Only Caddy publishes a port, bound to loopback; the broker and
data stores stay on an internal network. This setup
is for local development; the Swarm deployment remains under `infra/`.

PostgreSQL, Valkey, and Dozzle use named volumes, preserving accounts, files
configuration, sessions, broker credentials, and log viewer settings across
container recreation. Valkey uses AOF with an every-second fsync and a separate
ACL file; the broker saves ACLs before publishing new credentials. Keep both
together in backups. The initial admin password is hashed into the ACL file on
first start; changing `.env` alone does not rotate it in an existing volume.
Stop the stack with
`docker compose down`. To deliberately erase local accounts, sessions, broker credentials, files
configuration, and crypt recovery secrets, use `docker compose down --volumes`.

When updating an existing Dragonfly demo, rename `DRAGONFLY_PASSWORD` to
`VALKEY_PASSWORD` in `.env`, remove `DRAGONFLY_IMAGE_TAG`, and add
`VALKEY_IMAGE_TAG` from `.env.example`. Start the stack again and sign in again.
PostgreSQL accounts and passkeys remain; Dragonfly sessions are not migrated.
The old Dragonfly container can be removed explicitly after the switch is verified.

Validate the configuration without starting containers:

```sh
docker compose config --quiet
```

### Run service checks

All five Go modules, including the landing service, declare Go 1.27. Run Go
commands from the individual service directory; this parent has no Go module or workspace.

```sh
(cd access-gateway && go build ./... && go test ./...)
(cd database-broker && go build ./... && go test ./internal/config ./internal/broker ./internal/router ./internal/util)
(cd files && go build ./... && go vet ./... && go test ./...)
(cd notes && go build ./... && go vet ./... && go test ./...)
```

The broker's full `go test ./...` suite also starts PostgreSQL, Dragonfly, and Valkey
containers through testcontainers and needs a reachable local Docker daemon.
See [AGENTS.md](../AGENTS.md) for architecture, configuration, checks, and current
integration limitations. See [database-broker/README.md](../database-broker/README.md)
for its API, [access-gateway/README.md](../access-gateway/README.md)
for passkey setup, device onboarding, and admin user management, and
[infra/nixos/README.md](../infra/nixos/README.md) for host setup.

## Updating components

Commit component changes in that component's repository, publish the commit to
its remote, then record the new pointer in the parent:

```sh
git -C database-broker status
# Commit and push the component changes using your development workflow.
git add database-broker
git commit -m "Update database-broker"
```

Use the same process for the other components. The parent records only their
commit IDs: uncommitted and untracked component files are not included. Publish
component commits before publishing parent commits that reference them.

Parent pointers record source checkouts independently of deployment releases.
Service releases do not require version-only commits here or in infra.

To select the newest stable release tags from the service remotes:

```sh
make latest-tags
make config
# Once the tagged images have been published, deploy explicitly:
make deploy
```

`latest-tags` uses Bash, Git, awk, and GNU coreutils (`sort -V`). It selects the highest
numeric stable release tag (`MAJOR.MINOR.PATCH`, with an optional `v` prefix)
for the five platform services (gateway, broker, Files, Notes and landing),
fetches it into each service repository, and
writes those image tags to ignored `infra/.env`. RazChess, UUID, GeoIP and 0x40hues use
fixed stack defaults with optional overrides in `.env`; this command does not
query their remotes or change their overrides.
If an existing file lacks `DOZZLE_IMAGE_TAG`, it adds the default
from `infra/.env.example`; an existing operator-selected value is preserved.
It preserves other settings and leaves branches, checkouts, and parent submodule
pointers unchanged. Prereleases are excluded. Tag discovery does not verify
that image publishing has finished.

The file is initialized from `infra/.env.example` when absent. Review it before
deploying; edit it to pin older releases. `make config` and `make deploy` delegate
to infra's Makefile without fetching new tags. `make deploy-latest` selects
releases and then deploys. Use `INFRA_ENV_FILE=/absolute/path` to select another
file, or pass image tags, `DOCKER_CONTEXT`, and `STACK_NAME` as Make command-line
assignments. See [infra/README.md](../infra/README.md) for standalone use.

## Signed identity between services

Files and Notes in this stack set `ACCESS_GATEWAY_URL=http://access-gateway:8080`.
They fetch `/.well-known/paseto-keys` at startup and refresh expired public-key
sets on use. Caddy strips incoming `X-Auth-Request-Token` and copies the gateway's
PASETO beside UUID/name. Assertions bind the app origin, method, URI and identity;
Notes also verifies the signed admin authorization. Public shares and private
health probes keep their existing access rules. Keys rotate daily in shared
Redis/Valkey with overlapping public keys. Discovery outages cannot extend trust
past cached expiry. Upgrade/publish the gateway before enabling verification in
Files/Notes; select published images before rollout. See the gateway's
[signed identity contract](https://github.com/razzie-cloud/access-gateway/blob/master/docs/reference.md#signed-proxy-identity).
