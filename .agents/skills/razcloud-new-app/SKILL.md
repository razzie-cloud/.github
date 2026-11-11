---
name: razcloud-new-app
description: Bootstrap and integrate a new first-party app into Razzie Cloud, from its independent Go repository through gateway identity, broker discovery, embedded UI, Compose, Swarm, CI and contributor guidance. Use for a new platform app; a public third-party container may need only stack integration.
---

# Bootstrap a Razzie Cloud app

Begin with parent Git/submodule checks and current `AGENTS.md`. Establish the
app's purpose, name, public/protected/admin routes, authoritative storage and
repository location from the request/context. Clarify only decisions that
materially affect the product or need external authorization; continue independent
scaffolding while waiting. Deliver a useful slice of the requested app.

## Choose a matching example

Read the selected example's current guide/source; borrow conventions selectively.

| App needs | Starting example |
| --- | --- |
| Protected embedded UI, owner-scoped PostgreSQL settings and S3 | `files/` |
| Markdown, conditional S3 edits, derived search or background work | `notes/` |
| Small public page with runtime links and embedded assets | `landing/` |
| Internal provisioning API | `database-broker/` |

A new app does not need S3, crypt, River, WebAuthn, Redis or sharing because an
example has them. Gateway owns accounts/SSO; consuming apps verify its signed UUID rather than
building their own login or using usernames as owners.

For an S3 app, decide data authority before designing persistence. Files/Notes
use owner-configured connections and optional rclone crypt, not an operator-wide
bucket/master key. PostgreSQL settings, credentials and recovery records remain
durable. Own the app's settings; do not reuse another app's tables. If this storage
model is requested, preserve connection-time egress guards and use rclone APIs.

## Keep repository ownership correct

First-party services have independent repositories, normally
`github.com/razzie-cloud/<app>`, referenced as parent submodules. Check existing
directories, repositories and remotes first. Never put ordinary app source under
parent version control, copy Git metadata or replace a gitlink with a regular tree.

For an available authorized remote, use standard `git submodule add`/initialization
commands. If a remote is unavailable or publication is outside scope, prepare
the independent app repository locally and leave parent registration/pinning
pending with a concrete handoff. A separate temporary workspace can keep that
work outside the parent tree. Do not record a file:// submodule URL, invent a
reachable remote or publish an unpushed component pin. Remote creation/push
follows the user's actual authorization.

## Establish the service contract

Inspect current modules for the Go toolchain instead of copying a fixed version
from prose. The parent has no `go.mod`/`go.work`. Typical protected apps have
`cmd/<app>/main.go`, config, HTTP handlers, embedded web assets and persistence
as needed. Landing deliberately uses a smaller root-package structure.

Adopt conventions that apply:

- `SERVICE_PORT` / `--port`, conventionally 8080; matching flags/env for other
  settings, validated `ORIGIN` and optional `LANDING_ORIGIN`.
- Apps needing PostgreSQL support direct URI/password-file configuration and
  `POSTGRES_URI_FROM` broker discovery. Bound startup retries/discovery and keep
  credentials out of logs. Redis discovery is optional.
- Configure ACCESS_GATEWAY_URL / --access-gateway-url for protected apps. Follow
  Files/Notes internal/gatewayidentity: fetch public keys at startup, refresh
  expired sets/unknown keys with bounded requests, and fail closed after expiry.
  Verify v4.public issuer/audience/time, method/URI, matching UUID/name and signed
  admin policy where required. Keep the gateway assertion in server headers only.
- Verified gateway UUID identity, owner-scoped queries and authorization before
  mutations/storage access. Reject spoofed identity, bound request bodies and
  validate mutation origins. Preserve safe template/Markdown rendering.
- Interactive UIs embed local HTMX/PicoCSS with licenses, shared logo and distinct
  cloud-home/service links. Keep design mockups separate from live writes.
- Private GET/HEAD `/healthz` and cached `/readyz`, bounded background dependency
  checks and stale-result expiry. Inspect current implementations for timing.
  Probe required shared dependencies, not arbitrary user S3 endpoints or broker
  provisioning routes.
- JSON slog on stderr and validated `LOG_LEVEL`. Healthy/routine traffic stays
  quiet; classify failures with request IDs and static route patterns. Do not
  log raw backend errors, credentials or capability URLs.
- HTTP timeouts, bounded startup and graceful shutdown. When a schema is needed,
  use append-only migrations and replica-safe locks; inspect the chosen example's
  migration system instead of mixing libraries accidentally.

For a mockup-only request, stop at design artifacts and describe future backend
integration accurately. Do not turn a design request into a whole service build.

## Integrate and verify

Use [integration.md](references/integration.md) for the cross-repository matrix,
image workflow and acceptance checks. Implement relevant local/Swarm configuration
within the requested scope. Image selections stay operator configuration. Keep
parent docs and component contributor guidance consistent with the finished app.

Inside the new module, format Go, run build/vet/relevant tests and required race
checks; build the image when available. Validate Compose/Swarm without deploying.
Use disposable local backends. Report exact checks and external steps still
needed, including missing remotes or unpublished images. Source integration
alone does not establish a successful deployment.
