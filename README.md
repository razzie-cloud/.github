# razcloud

Parent repository for the razzie.cloud services and infrastructure. The three
components are independent Git repositories, tracked here as Git submodules at
specific commits.

| Directory | Repository | Purpose |
| --- | --- | --- |
| `access-gateway/` | [access-gateway](https://github.com/razzie-cloud/access-gateway) | Passkey accounts, expiring device registration links, and admin user management |
| `database-broker/` | [database-broker](https://github.com/razzie-cloud/database-broker) | Go API that provisions PostgreSQL databases and Dragonfly/Redis namespaces |
| `infra/` | [infra](https://github.com/razzie-cloud/infra) | Docker Swarm stack, deployment script, NixOS configuration, and Hanko image |

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

The root [docker-compose.yml](docker-compose.yml) builds both Go services from
their submodules using host build networking, matching the gateway's standalone
Compose setup. The broker provisions the gateway's PostgreSQL database;
a separate Redis instance stores sessions with append-only persistence. Caddy
checks every whoami request, including the SSO callback, with the gateway's
`/forward_auth` endpoint before proxying it. Only Caddy publishes ports, bound
to loopback; the broker and data stores stay on an internal network. This setup
is for local development; the Swarm deployment remains under `infra/`.

PostgreSQL and Redis use named volumes, preserving accounts and sessions across
container recreation. Stop the stack with `docker compose down`. To deliberately
erase all local accounts and sessions and start bootstrap again, use
`docker compose down --volumes`.

Validate the configuration without starting containers:

```sh
docker compose config --quiet
```

### Run service checks

Both services declare Go 1.27. Run Go commands from the individual service
directory; this parent has no Go module or workspace.

```sh
(cd access-gateway && go build ./... && go test ./...)
(cd database-broker && go build ./... && go test ./internal/config ./internal/broker ./internal/router ./internal/util)
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

Updating a parent pointer does not build or deploy a service. The Swarm stack
uses published images; image releases and stack image references must be updated
separately when a component change needs deployment.
