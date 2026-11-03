# razcloud

Parent repository for the razzie.cloud services and infrastructure. The four
components are independent Git repositories, tracked here as Git submodules at
specific commits.

| Directory | Repository | Purpose |
| --- | --- | --- |
| `access-gateway/` | [access-gateway](https://github.com/razzie-cloud/access-gateway) | Passkey accounts, expiring device registration links, and admin user management |
| `files/` | [files](https://github.com/razzie-cloud/files) | S3-backed directories, optional rclone crypt, public shares, and an HTMX/PicoCSS file manager |
| `database-broker/` | [database-broker](https://github.com/razzie-cloud/database-broker) | Go API that provisions PostgreSQL databases and Dragonfly/Redis namespaces |
| `infra/` | [infra](https://github.com/razzie-cloud/infra) | Docker Swarm stack, deployment script, and NixOS configuration |

The [files service plan](docs/files-service-plan.md) records its architecture and
acceptance criteria. See [files/README.md](files/README.md) for configuration and
secret-storage requirements.

The [casting design](docs/casting-design.md) describes MP4 casting,
browser-controlled photo slideshows, temporary shares, and device testing.

## Checkout

Clone this parent repository with `git clone --recurse-submodules <parent-url>`.
The parent URL is wherever this repository is eventually hosted. The submodules
use their existing GitHub SSH URLs, so cloning them requires GitHub SSH access.

For an existing checkout:

```sh
git submodule update --init --recursive
git submodule status
```

This checks out the commits recorded by the parent, usually with detached HEADs.
Before editing a component, switch to an appropriate branch within it. Preserve
any existing local work before switching branches or updating submodules.

## Development

### Run the complete local stack

With the submodules checked out and Docker Compose installed, run these commands
from the project root against your local Docker daemon:

```sh
cp .env.example .env
# Replace POSTGRES_PASSWORD in .env with a random value, e.g. openssl rand -hex 24.
docker compose up --build -d
docker compose logs access-gateway
```

Compose builds the gateway from the checked-out source and tags it as
`ghcr.io/razzie-cloud/access-gateway:dev`. Override `ACCESS_GATEWAY_IMAGE_TAG`
in `.env` to change the local build's tag.

Find `BOOTSTRAP TOKEN` in the gateway logs. Open <http://localhost:8080>, create
the first administrator using that token and a passkey, then sign in. The token
is logged only when first generated; keep the initial logs until setup is done.

Open <http://127.0.0.1:8081> for the protected `traefik/whoami` demo. It redirects
to the gateway for sign-in, then returns to whoami with a separate app session.
Whoami displays the verified `X-Auth-Request-User` and `X-Auth-Request-Name`
headers. Signing out at the gateway revokes access to the demo.

Use the exact hostnames above to keep their host-only cookies separate:
`localhost` for the gateway and `127.0.0.1` for whoami. Both are loopback HTTP origins,
so local passkeys work without certificates or hosts-file changes. `AUTH_PORT`
and `WHOAMI_PORT` in `.env` can override the default ports; use those ports in
your browser too. Keep them distinct and use URI-unreserved characters for
`POSTGRES_PASSWORD`, as documented in `.env.example`.

Open <http://files.localhost:8082> for the files UI (`FILES_PORT` overrides its
port). Use this exact hostname to isolate its app cookie from the gateway and
whoami: host-only cookies are shared across ports on the same host.
Opening `http://localhost:8082` or `http://127.0.0.1:8082` redirects to
`files.localhost`, preserving the requested path and query string.
Public share links use `http://shared-files.localhost:8082/s/<token>` on the same
`FILES_PORT`. Use **Share** beside an entry or **Sharing** in the directory toolbar
to create read-only file/folder links with an optional password. The sharing
hostname permits unauthenticated visitors and only exposes share/static routes;
the files management hostname keeps forward authentication on every path.

Open <http://localhost:8083> for Dozzle's container logs (`DOZZLE_PORT`
overrides the port; `DOZZLE_IMAGE_TAG` selects its image). It requires an
administrator account: every request, including `/_auth/callback`, goes through
the gateway's `/forward_auth/admin` endpoint. Regular users receive 403.
Opening `127.0.0.1` on this port redirects to `localhost`, preserving the path
and query string. Dozzle has no directly published port; Caddy
is its only host entry point. Container actions and shell access are disabled.

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

Host OS browser access has been an ongoing issue with the Files and Whoami
local routes when Docker runs inside WSL2 or a VM. A successful request inside
the development environment does not establish that a browser on the host OS
can reach the same URL. In particular, `.localhost` names such as
`files.localhost` and `dozzle.localhost` have not worked reliably in this setup;
publishing a loopback port alone does not fix host-side name resolution or
forwarding. Dozzle therefore uses plain `localhost` on its own port, `8083`,
without redirecting to a `.localhost` name. The Files and Whoami routes above
still use their existing hostnames and may need host-side troubleshooting.
All four Caddy ports are bound to `127.0.0.1`. Verify access in the actual host OS
browser; the Windows `\\wsl.localhost\Ubuntu` file-share path is unrelated to HTTP.

Cookies are shared across ports on the same hostname. Dozzle's app cookie and
the gateway's sign-in cookie have different names, so these two can use
`localhost` together. Moving additional protected apps to `localhost` also
requires addressing their shared `razcloud_app` cookie name.

After updating an existing checkout, run `docker compose up --build -d` to
rebuild the gateway and recreate the changed services and port binding. Existing
accounts and gateway sessions are preserved; open the new Files URL and sign in
if needed. For command-line clients that do not resolve `.localhost`, use
`curl --resolve files.localhost:8082:127.0.0.1 http://files.localhost:8082/`.

For an optional disposable S3 demo, set a fresh `S3_DEV_PASSWORD` in `.env` and
start `docker compose --profile storage-demo up --build -d`. The development
fixture creates an in-memory `files-demo` bucket. In Files, add a custom S3
connection with endpoint `http://s3-demo:9000`, region `us-east-1`, path-style
addressing, access key `files-dev`, and that development password. Choose Read-only
or Writable, then create a directory for `files-demo` with optional rclone crypt.
Demo objects disappear when the fixture restarts. The private HTTP exception is
limited to `s3-demo:9000`; normal vendor connections use public HTTPS. Only use
these credentials with the local demo.

The root [docker-compose.yml](docker-compose.yml) builds all three Go services from
their submodules using host build networking, matching the gateway's standalone
Compose setup. The broker provisions the gateway's and files' PostgreSQL databases;
a separate Redis instance stores sessions with append-only persistence. Caddy
checks every whoami/files request, including the SSO callback, with the gateway's
`/forward_auth` endpoint, and Dozzle requests with `/forward_auth/admin`, before
proxying them. Only Caddy publishes ports, bound to
loopback; the broker and data stores stay on an internal network. This setup
is for local development; the Swarm deployment remains under `infra/`.

PostgreSQL and Redis use named volumes, preserving state across
container recreation. Stop the stack with `docker compose down`. To deliberately
erase local accounts, sessions, files configuration, and crypt recovery secrets, use
`docker compose down --volumes`.

Validate the configuration without starting containers:

```sh
docker compose config --quiet
```

### Run service checks

All three services declare Go 1.27. Run Go commands from the individual service
directory; this parent has no Go module or workspace.

```sh
(cd access-gateway && go build ./... && go test ./...)
(cd database-broker && go build ./... && go test ./internal/config ./internal/broker ./internal/router ./internal/util)
(cd files && go build ./... && go vet ./... && go test ./...)
```

The broker's full `go test ./...` suite also starts PostgreSQL and Dragonfly
containers through testcontainers and needs a reachable local Docker daemon.
See [AGENTS.md](AGENTS.md) for architecture, configuration, checks, and current
integration limitations. See [database-broker/README.md](database-broker/README.md)
for its API, [access-gateway/README.md](access-gateway/README.md)
for passkey setup, device onboarding, and admin user management, and
[infra/nixos/README.md](infra/nixos/README.md) for host setup.

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
numeric stable release tag (`MAJOR.MINOR.PATCH`, with an optional `v` prefix),
fetches it into each service repository, and writes the image tags to ignored
`infra/.env`. It preserves other settings and leaves branches, checkouts, and
parent submodule pointers unchanged. Prereleases are excluded. Tag discovery
does not verify that image publishing has finished.

The file is initialized from `infra/.env.example` when absent. Review it before
deploying; edit it to pin older releases. `make config` and `make deploy` delegate
to infra's Makefile without fetching new tags. `make deploy-latest` selects
releases and then deploys. Use `INFRA_ENV_FILE=/absolute/path` to select another
file, or pass image tags, `DOCKER_CONTEXT`, and `STACK_NAME` as Make command-line
assignments. See [infra/README.md](infra/README.md) for standalone use.
