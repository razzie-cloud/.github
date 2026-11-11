# New-app integration matrix

Paths are parent-relative. Read current parent and `infra/AGENTS.md` first.
Synchronize the actual app's names and HTTP paths across affected files.

| Concern | Owning files | Decision to preserve |
| --- | --- | --- |
| Independent repository | Component Git repo; parent `.gitmodules` and gitlink | Component owns code. Its commits must be remotely available before publishing parent pins. |
| Config/startup | App entry point/config | Flags/env match; discovery is bounded; secrets stay out of logs. |
| PostgreSQL | App migrations and both stack environments | Independent broker instance, e.g. `/v1/instances/postgres/<app>/uri`; follow the broker's instance-name validator. |
| Optional Valkey | App config and stack environment | Separate broker-managed `valkey` instance. Database 0 is metadata; app database capacity is finite. |
| Local service | Root `docker-compose.yml` | Build submodule, private backend port, networks as needed, broker-health dependency for discovery. |
| Local routing | Root `Caddyfile` and gateway origin allowlist | Exact `http://<app>.localhost:${LOCAL_PORT}` origin and distinct hostname for app cookies. |
| Swarm service | `infra/docker-stack.yml` | Published image, required tag variable, appropriate overlays, deployment labels/readiness; no `depends_on` assumption. |
| Swarm settings | `infra/.env.example`, `infra/Makefile` | Add/export `<APP>_IMAGE_TAG` and settings; actual selections live in ignored `.env`. |
| Release selection | Root `scripts/update-image-tags.sh` | Add first-party service/key in matching positions; retain all-or-nothing resolution and operator settings. |
| Homepage | Root/infra `landing-apps.json`; landing example as appropriate | Supported icon presets, runtime domains/ports; built-in sign-in and optional app cards have separate roles. |
| Documentation | App guide; parent README/AGENTS; infra guide as needed | Real data authority, routes, launch/check commands and new invariants; no current release selections in prose. |

## Authentication and routing

For a protected app, adapt the complete Files/Notes policy: strip incoming
`X-Auth-Request-User` / `X-Auth-Request-Name` / `X-Auth-Request-Token`,
call `/forward_auth`, copy verified
identity, then proxy. Protect every path including `/_auth/callback`; the gateway
redeems callbacks through forward auth. The app verifies the PASETO before using the UUID. Configure ACCESS_GATEWAY_URL
in both stacks (private http://access-gateway:8080 is supported), fetch
/.well-known/paseto-keys at startup and refresh expired key sets. Preserve
one-minute assertions, request binding, issuer/audience and UUID/name equality.
Never fall back to unsigned identity or expired keys after a fetch failure. See
access-gateway/docs/reference.md#signed-proxy-identity for the contract. Add its
exact origin to the gateway allowlist in both stacks. Align `ORIGIN`, gateway
origins, `LANDING_ORIGIN`, scheme and port with external browser URLs.

Admin routes use `/forward_auth/admin`. Strip/reissue any trusted app marker
only after authorization; the app must also require signed admin=true. Notes' `/v1/admin/*` shows mixed-policy ordering;
Dozzle shows whole-host admin policy. A general route must not shadow admin routes.

Public apps need no SSO unless the product calls for it. Public capabilities
need explicit scope: Files uses a separate host, only `/s/*` / `/static/*`,
stripped identity and 404 elsewhere. Do not expose management there or add that
share host to the app-origin allowlist.

## Images and CI

Use a multi-stage Dockerfile, embedded assets, unprivileged runtime user and
`/readyz` container probe on `SERVICE_PORT`. Choose replicas from actual state
and coordination needs; shared databases alone do not make in-memory work safe.

Inspect the closest service's `.github/workflows/checks.yml` and
`publish-image.yml`. CI format-checks/builds/vets/tests the module, provisions
disposable integration backends as needed and builds its Dockerfile. Current
publication workflows respond to new tags, validate Docker tag syntax and push
GHCR images under the exact Git tag, including `v`. Preserve required permissions
and supported platforms. Do not release to validate a workflow.

## Acceptance and release handoff

- Test ownership, denied routes, validation and persistence relevant to the app
  on disposable loopback backends. Include read-only/concurrency storage cases
  when applicable.
- Validate parent Compose and Swarm interpolation. Review routing, allowlists
  and config exports together. Record skipped runtime acceptance separately.
- In an authorized local environment, check redirect/sign-in/callback, verified
  UUID, sign-out revocation, admin denial and spoofed-identity rejection for the
  app's policies. Readiness remains private.
- Component commits, parent pins, Git tags, GHCR images and stack selections are
  separate artifacts. Publish only within task scope and in dependency order;
  verify image publication before deployment. Parent pins do not change running
  images.
