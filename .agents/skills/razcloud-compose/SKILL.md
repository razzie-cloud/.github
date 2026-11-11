---
name: razcloud-compose
description: Maintain or troubleshoot Razzie Cloud's parent local Docker Compose stack, Caddyfile, example environment, storage-demo profile and app integration. Use for local development orchestration; production Swarm and deployment helpers belong to razcloud-swarm.
---

# Maintain the local Compose stack

Read parent `AGENTS.md`, `docs/development.md`, root `docker-compose.yml`,
`Caddyfile` and `.env.example`. Inspect status/diffs and relevant component guides.
Parent orchestration stays in parent; Dockerfiles and standalone service Compose
files stay in their submodules.

## Map a change across the stack

The parent stack builds first-party submodules. `backend` is internal; `web`
supplies proxy access and required egress. Only Caddy publishes the shared HTTP
port, bound to `127.0.0.1`. Individual service Compose files may expose dev ports;
do not accidentally copy those exposures into the parent stack.

Map the affected service's build/image, environment, networks, health/startup
dependencies, volumes, hostname, Caddy policy and gateway allowlist together:

- `LOCAL_PORT` drives Caddy listener/publication and all local origins, callbacks,
  homepage and share URLs. Keep gateway `RP_ID=auth.localhost`. Runtime config
  changes need recreation; source/embedded asset changes need image builds.
- Use distinct hostnames such as `files.localhost` and `notes.localhost`. Cookies
  are host-only but shared across ports; different ports do not isolate sessions.
  The homepage uses `localhost`.
- Gateway uses PostgreSQL and numbered Valkey discovery. Each database-using
  app has its own broker instance. Broker instance/URI GET endpoints provision
  data; use `/readyz` for health instead.
- Broker waits for PostgreSQL/Valkey health. Preserve app startup checks;
  `service_started` is not readiness. Notes/Files discover PostgreSQL and need
  no operator S3 credentials.

## Preserve proxy policy

Use Caddy `route` ordering: strip incoming identity, forward auth, copy verified
headers (UUID, name and X-Auth-Request-Token), then proxy. Configure
ACCESS_GATEWAY_URL=http://access-gateway:8080 for Files/Notes and wait for gateway
readiness before their startup key fetch. PASETO verification must fail closed
after key expiry; use the public app ORIGIN as audience. Never expose tokens in
the whoami echo. Protected management includes `/_auth/callback`. Exact app
origins belong in gateway `FORWARD_AUTH_ORIGINS`.

- Ordinary apps use `/forward_auth`. Dozzle uses `/forward_auth/admin` everywhere;
  also strip incoming `Remote-*`. Preserve UUID/name header mappings, private
  HTTP port and disabled actions/shell.
- Notes strips `X-Notes-Admin`, admin-authorizes `/v1/admin/*` and only then sets
  the marker. Other paths use ordinary auth; ordering must preserve this split.
- `shared-files.localhost` strips identity, permits `/s/*` and `/static/*` only
  and returns 404 elsewhere. It stays outside the gateway origin allowlist.
- Whoami removes upstream cookies from its header echo; identity verification
  must not reveal session credentials.

## Preserve local state

Do not overwrite ignored `.env`. Its example explains separate PostgreSQL/Valkey
passwords and URI-safe characters. Avoid printing expanded real Compose/env
configuration because it contains credentials.

Keep named PostgreSQL, Valkey AOF/ACL and Dozzle settings volumes. A password
setting does not rotate initialized database/ACL credentials. `down -v`, volume
removal and resets are separate destructive operations, not config repairs.

The optional `storage-demo` profile uses Files' in-memory S3 fixture, bucket
`files-demo` and separate `S3_DEV_PASSWORD`. Files/Notes allow only the exact
private HTTP demo endpoint `s3-demo:9000`; do not broaden that exception. Each app
owns user connections; no global S3 credentials or new secret volume is needed.
Demo objects disappear on fixture restart.

Landing builds the independent submodule and renders runtime domain/scheme/port
with an optional app-list mount. Keep app cards and `LANDING_ORIGIN` aligned.

## Validate and troubleshoot

Validate without starting containers or contacting a production daemon:

```sh
docker compose --env-file .env.example config --quiet
docker compose --env-file .env.example --profile storage-demo config --quiet
```

Validate changed standalone Compose files with their documented example settings.
Configuration validity does not establish Caddy/auth correctness: inspect route
ordering and use authorized local runtime acceptance when needed. Build changed
service images when required, after verifying a local/disposable target daemon.
Do not switch global Docker context as validation.

When startup/recreation is in scope, inspect the endpoint read-only and use an
explicit verified local context. Preserve volumes; limit recreation/builds to
what changed. Do not upgrade hosts or recreate everything for one service change.

For `.localhost` access, check the actual host browser's resolution and WSL/VM
forwarding. Linux curl success does not prove host access; `curl --resolve` can
test host routing without DNS changes. Passkey prerequisites can be checked with
`window.isSecureContext` and `PublicKeyCredential` in the host browser.

For intermittent timeouts, compare HAR timings/Caddy errors with direct backend
response times, then inspect network addresses. `docs/development.md` records a
duplicate-MAC incident; treat it as a diagnostic possibility, not an automatic
reason for upgrades or recreation.

For changed auth routes, check anonymous redirect/callback, signed-in access,
sign-out revocation, identity stripping, admin denial and share-path restrictions
as applicable. Report exact config/build/browser checks and environment limits.
