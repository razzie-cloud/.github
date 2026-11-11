---
name: razcloud-swarm
description: Maintain Razzie Cloud's Swarm stack, infra environment/Makefile/deploy.sh, parent image-tag selection helper and release configuration. Use for stack/helper changes or an explicitly requested deployment; local Compose and NixOS host changes have separate workflows.
---

# Maintain the Swarm stack and helpers

Read parent `AGENTS.md`, `infra/AGENTS.md`, `infra/README.md` and relevant sections
of `infra/docs/operations.md`. Inspect parent/infra status and diffs. Infra owns
its stack/deploy script/Makefile; parent owns its Makefile and
`scripts/update-image-tags.sh`. Service source/Dockerfiles/workflows stay in
their submodules.

Determine whether the task is source/config maintenance, release selection or
deployment. Implement and validate authorized edits first. Maintenance does not
imply rollout. If deployment is already authorized, do not ask again; verify
the concrete target and selected images before executing it.

## Keep configuration coupled

Inspect `infra/docker-stack.yml`, `infra/.env.example`, `infra/Makefile`,
`infra/deploy.sh`, root `Makefile` and `scripts/update-image-tags.sh` for affected
names. Read [helpers.md](references/helpers.md) before changing helpers for their
side effects, invariants and meaningful isolated checks.

Swarm consumes published images, not local checkouts. Required tag variables and
operator settings must be exported by infra's Makefile and described in its
example environment. Release selections belong in ignored `infra/.env`. Keep
current versions out of README/AGENTS and stack files except the existing optional
defaults for inactive public apps. Preserve exact tag spelling, including `v`.
A Git tag does not prove GHCR publication; parent pins do not update running images.

`DOMAIN` drives hostname labels, gateway origins/RP, exact app-origin allowlists,
Files share origin and landing metadata/links. Change them together with DNS/TLS
considerations. `LANDING_ORIGIN` links apps home; sign-in targets `auth.<DOMAIN>`.

## Preserve runtime invariants

- Databases/broker stay on private `internal`. Apps join `web`/`internal` as needed.
  Only Caddy publishes ingress; 80/443 use host mode to preserve visitor IPs. DNS
  must reach the manager running Caddy, not an assumed routing-mesh endpoint.
- Caddy Docker Proxy uses **service deployment labels**. Keep ordered identity
  stripping, gateway auth, verified-header copying (including X-Auth-Request-Token)
  and proxying. Files/Notes use ACCESS_GATEWAY_URL=http://access-gateway:8080
  to fetch public keys at startup and require PASETO verification. Publish a
  gateway supporting /.well-known/paseto-keys before enabling consumers; startup
  errors restart under Swarm policy, and expired keys never permit fallback.
  Keep public ORIGIN as the audience; signed admin=true supplements app markers.
  Callbacks stay
  protected. Notes admin paths and all Dozzle paths use `/forward_auth/admin`;
  trusted markers are stripped/reissued after auth. Files' separate public share
  host allows only `/s/*` / `/static/*`, strips identity and returns 404 elsewhere.
  That host stays outside the app-origin allowlist.
- Swarm ignores `depends_on`. Retain bounded discovery, restart policies and
  `/readyz` probes on `SERVICE_PORT`. Provisioning routes are not probes. Existing
  public app wrappers wait for broker readiness before discovery.
- Replica counts follow coordination behavior. Gateway/broker share backends
  and migration/bootstrap/provisioning locks; Notes coordinates River jobs.
  RazChess stays at one replica for in-memory active sessions. Consult operations
  docs before changing counts/upgrade assumptions. Do not impose distinct-node
  placement on a single-node installation.
- Valkey is standalone with numbered-database ACL support. Database 0 is broker
  metadata. Preserve AOF and ACL files together in `valkey_data`. Initial admin
  initialization is not password rotation. Retain separate app instances and
  restricted ACLs; do not grant broad commands for an older KEYS-based loader.
- Files/Notes PostgreSQL settings, credentials and crypt recovery are durable.
  S3 content and Notes' derived index/jobs have different backup needs. Do not
  add provider secrets/volumes or remove old storage incidentally. Legacy Files
  migration is a separate explicit procedure in its reference.
- Dozzle is global with local Docker sockets/per-node settings. Keep HTTP private,
  mappings correct and shell/actions disabled. A read-only socket mount does not
  constrain Docker API operations.
- Landing JSON is a Docker config from `LANDING_APPS_FILE`. Updating contents in
  an existing deployment needs a new config name in both declaration and service
  reference. Keep the homepage public and source/config private.

## Validate without deployment

From parent with an existing selected environment:

```sh
make config
bash -n infra/deploy.sh
bash -n scripts/update-image-tags.sh
```

Do not overwrite the operator environment to make validation pass. Example-only
validation can supply placeholder first-party image tags through the environment:

```sh
DATABASE_BROKER_IMAGE_TAG=validation ACCESS_GATEWAY_IMAGE_TAG=validation \
FILES_IMAGE_TAG=validation NOTES_IMAGE_TAG=validation LANDING_IMAGE_TAG=validation \
docker compose --env-file infra/.env.example -f infra/docker-stack.yml config --quiet
```

Placeholders establish interpolation validity only; do not deploy them. Quiet
output avoids revealing real environment values. Test helper semantics in an
isolated fixture when behavior changes; syntax alone does not prove selection,
quoting or idempotency. NixOS evaluation is separate and needs host hardware and
actual network configuration.

For authorized deployment, verify published images and explicit context/stack,
validate final config and use the maintained Make/deploy entrypoint from its
expected directory. Inspect rollout status/readiness and relevant auth acceptance.
Stop on failure and report it instead of retrying releases/cleanup indefinitely.
Preserve secrets/volumes. Report checks, target and remaining external steps.
