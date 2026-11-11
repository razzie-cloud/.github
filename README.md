# Razzie Cloud

<img src="docs/brand/razzie-cloud-logo.png" width="96" alt="Razzie Cloud logo">

A self-hosted platform with shared passkey sign-in, database provisioning, and an
S3 file manager. This parent repository brings the services together for local
use and tracks their independent repositories as Git submodules.

| Repository | What it does |
| --- | --- |
| [access-gateway](access-gateway/README.md) | Passkey accounts, device enrollment, user management, and shared sign-in for protected apps |
| [database-broker](database-broker/README.md) | Creates per-service PostgreSQL and Valkey databases and returns their connection URIs |
| [files](files/README.md) | Browse, upload, and share S3 files, with optional rclone encryption |
| [notes](notes/README.md) | Markdown notes with user-managed S3 connections, optional rclone encryption, and search |
| [landing](landing/README.md) | Public homepage with configurable domain, app cards, and bundled icon presets |
| [infra](infra/README.md) | Deploys the platform with Docker Swarm and Caddy; includes optional NixOS host configuration |

Caddy checks app access with the gateway. Services ask the broker for a database
connection, then connect directly to their data stores. File contents stay in S3.

## Try it locally

You need Git with GitHub SSH access and Docker with the Compose plugin, using a
local Docker daemon. Go is only needed when running services outside containers.

```sh
git clone --recurse-submodules git@github.com:razzie-cloud/.github.git razcloud
cd razcloud
cp .env.example .env
# Set POSTGRES_PASSWORD and VALKEY_PASSWORD to separate random hex values.
# Generate each with: openssl rand -hex 24
docker compose up --build -d
docker compose logs access-gateway
```

For an existing checkout, initialize missing components with
`git submodule update --init --recursive` after checking for local changes.

The stack uses HTTP on `*.localhost`. Modern browsers treat these as local
secure contexts, so passkeys work without certificates or trust installation.

Find the `bootstrap.token_created` log event and its `bootstrap_token` field.
Open the gateway, create your first administrator with that token and a passkey,
then sign in. The token is logged only once when generated.

| Local URL | Use |
| --- | --- |
| <http://localhost:8080> | Homepage: project links, configurable apps, and sign-in |
| <http://auth.localhost:8080> | Gateway: sign in, add users, and enroll devices |
| <http://whoami.localhost:8080> | Whoami: see the identity passed to a protected app |
| <http://files.localhost:8080> | Files: connect your S3 storage and add a directory |
| <http://logs.localhost:8080> | Dozzle: view container logs as an administrator |
| <http://shared-files.localhost:8080> | Public share host: open a link created in Files; the root returns 404 |

Use these exact hostnames: app cookies are shared across ports on the same host.
All services share port `8080`; `LOCAL_PORT` in `.env` changes it for every URL.
WSL2/VM host browsers need working loopback forwarding; see
[local troubleshooting](docs/development.md#host-browser-troubleshooting).

To try Files without cloud storage, follow the
[disposable S3 demo](docs/development.md#disposable-s3-demo). Stop the stack with
`docker compose down`; named volumes preserve accounts and configuration.

## Deploy or develop

For a server installation, start with the [infra guide](infra/README.md).
For local configuration, service checks, and component updates, see
[development and maintenance](docs/development.md). Architecture and contributor
rules live in [AGENTS.md](AGENTS.md).

Reusable workflows for frontend mockups, production UI, new apps, local Compose
and Swarm maintenance are listed in [repository skills](AGENTS.md#repository-skills).

See the [brand assets](docs/brand/README.md) and
[frontend design mockups](docs/frontend-mockups.md) for the visual identity.

Notes is available at `http://notes.localhost:8080` in local Compose and
`https://notes.<DOMAIN>` in Swarm. Start the local `storage-demo` profile with
`S3_DEV_PASSWORD` set, then add connections and optionally encrypted notebooks in
Notes’ Storage page, just as in Files. See the
[Notes service guide](notes/README.md) for conditional saves, search, and recovery.
