# Scoped database-broker tokens and automated Swarm deployment

Status: implemented in local component commits. See [usage and verification](database-broker-auth.md)
and [Swarm lifecycle](../infra/docs/broker-authentication.md). Images/commits have
not been published and no deployment has been performed. Disposable Swarm acceptance
and operator PKI provisioning remain release requirements.

The legacy-app integration uses `/broker-start` copied onto upstream image layers.
It performs authenticated discovery before exec with `--redis`, because the upstream
`--redis-from` paths can log bearer URLs and continue in memory after failure.

## Intended outcome

By default, require authentication and authorization for every broker API that
lists instances or returns credentials. In token mode, access to the internal
network alone must not grant access to any application's credentials or permit
arbitrary provisioning. Preserve tokenless operation through an explicitly
selected `none` mode for backward compatibility.

Keep `make deploy` as the operator's single command. It prepares configuration,
creates missing secrets, generates scoped tokens inside Swarm, and rolls out
the services. No manual registration request to a running broker is required.

The master key has no persistent copy outside Swarm. Only database-broker and a
temporary token-generation service receive it. Applications receive individual
derived tokens through their own Swarm secrets.

## 1. Declarative client policy

Add a non-secret YAML policy at `infra/broker-clients.yml`, mounted into
database-broker as a Swarm config. Use one YAML parser dependency in the shared
Go policy package so the server and token CLI apply identical validation.
For example:

```yaml
version: 1
deployment_id: razzie-cloud-production
key_id: k1
clients:
  razchess:
    generation: 1
    allow:
      - adapter: valkey
        instance: razchess
  access_gateway:
    generation: 1
    allow:
      - adapter: postgres
        instance: access_gateway
      - adapter: valkey
        instance: access_gateway
```

Include the complete initial policy:

| Client | Allowed adapter/instance pairs |
| --- | --- |
| `access_gateway` | `postgres/access_gateway`, `valkey/access_gateway` |
| `files` | `postgres/files` |
| `notes` | `postgres/notes` |
| `razchess` | `valkey/razchess` |
| `geoip_server` | `valkey/geoip_server` |

Use exact pairs, with no wildcard or implicit prefix permissions. A credential
grant includes the current get-or-create behavior for that exact instance.
Permission changes do not change the token; the broker always applies its
current policy. No initial application receives instance-listing privileges.
Keep listing denied unless an explicit, separately modeled enumeration grant is
introduced; never make it available merely because a client is authenticated.

Require a single YAML document and reject duplicate mapping keys and unknown
fields. Validate policy versions, identifier syntax, positive generations,
duplicate grants, and deployment identity. Define
adapter aliases and case normalization once and share those rules with broker
lookup so authorization cannot be bypassed through alternate spellings.

## 2. Deterministic token protocol

Create a shared Go package in database-broker for policy parsing, derivation,
token parsing, and verification. Both binaries use this package.

Generate a cryptographically random 32-byte master key. Define a precise,
versioned encoding, for example this fixed JSON array encoded without whitespace:

```text
["razcloud-broker", 1, deployment_id, key_id, client_id, generation]
```

Build this internal encoding from parsed policy values; YAML formatting,
comments, and mapping order must not affect token derivation.

Calculate the full HMAC-SHA-256 and encode it as unpadded base64url. Use a bounded
token envelope carrying protocol version, key ID, generation, and MAC:

```text
v1.k1.1.<base64url-mac>
```

The client ID remains a separate URL parameter. All envelope metadata is bound
into the HMAC input. Specify canonical numeric formatting and disallow delimiter
characters in key IDs. Never derive tokens with an ordinary concatenated hash.
Do not bind permissions into the HMAC; permission edits must not require token
redistribution. Changing a client's generation changes its token.

This is a reusable bearer credential, without an automatic expiry in the first
version. Revocation uses policy removal or generation changes. Receiving one
client's token does not permit derivation of another client's token.

Define optional accepted-key and accepted-generation lists for bounded rotation
overlap; absent those fields, accept only the configured active key and the
client's current generation. The generator issues only the current combination.

## 3. Broker enforcement

Add `AUTH_MODE` / `--auth-mode` with two supported values:

- `token` (default): require scoped tokens and valid policy/key configuration.
- `none`: preserve existing tokenless listing and get-or-create endpoints,
  including their current response formats. This mode needs no client policy,
  master key, or derived tokens and does not perform scoped authorization.

Reject unknown or empty explicitly supplied mode values. Never infer `none` mode
from missing files, an empty policy, invalid tokens, or authentication failures.
The `none` mode does not load policy/key files; emit one startup warning identifying
the selected mode without secret values. If requests contain client/token query
parameters in `none` mode, ignore them as the old broker does; do not imply that
supplying a token provides scoped enforcement in that mode.

Add configuration for the policy file and versioned master-key file paths. There
is normally one active key; explicitly configured overlap supports rotation.
In token mode, require valid authentication configuration before listening or
initializing provisioning backends. Missing keys, malformed policy, or invalid
configuration must fail startup; do not silently start an unauthenticated API.

Preserve the existing credential endpoints and response formats. A request looks
like:

```text
GET /v1/instances/valkey/razchess/uri?client=razchess&token=v1.k1.1.<mac>
```

For each credential request in token mode:

1. Require exactly one client parameter and one token parameter, with bounded
   lengths; reject ambiguous or malformed authentication input.
2. Require an enabled client, an accepted key ID, and an accepted generation
   from the server's current policy.
3. Derive the expected MAC and compare it in constant time.
4. Authorize the normalized adapter/instance pair before any backend lookup or
   provisioning operation.
5. Return the existing JSON or URI response with `Cache-Control: no-store`.

Use a generic 401 for missing or invalid authentication, 403 for authenticated
but forbidden access, and bounded non-secret audit fields. Apply the same checks
to JSON and URI endpoints and deny instance enumeration by default in token
mode. Set `Cache-Control: no-store` on credential responses in either mode.
Health endpoints stay private, unauthenticated, and free of provisioning side
effects in both modes.

Never log raw URLs, query strings, tokens, master-key bytes, returned credentials,
or backend errors. Logging may identify the authenticated client and static
route template. An unauthenticated claimed client ID remains untrusted input.

## 4. Token CLI in the broker image

Build a second binary, `/broker-token`, into the existing database-broker image.
Keep `/database-broker` as the image's default entrypoint.

The CLI supports:

- `validate`: validate policy and public inputs without database access or a key.
- `generate`: read the mounted key and policy, select a declared client, and
  write exactly one token to stdout. Emit only sanitized diagnostics to stderr.
- `hold`: keep a temporary helper container alive for controlled `docker exec`
  invocations, with signal handling and a maximum lifetime.

It must not initialize PostgreSQL, Valkey, Dragonfly, the broker HTTP server, or
the service's normal health monitor. The selected published image supplies both
the server and generator, avoiding a local Go/OpenSSL dependency and divergent
implementations. Never accept the master-key value in an argument or environment
variable; accept a mounted file path.

## 5. One-command preparation inside Swarm

Extend `infra/deploy.sh` and its Makefile integration, preserving explicit Docker
context targeting and all existing database-secret behavior.

Expose `BROKER_AUTH_MODE` in infra's environment/Makefile and pass it to the
broker's `AUTH_MODE`, explicitly defaulting this stack to `token`. The sequence
below applies to token mode. An operator-selected `none` deployment omits
policy/key/token mounts and token generation and uses the existing tokenless
consumer configuration. Render and validate the appropriate stack references;
the `none` mode must not require nonexistent authentication secrets. Never switch
modes automatically to recover from a failed secure deployment.

1. Validate selected images, policy, stack interpolation, and the target manager
   before changing the Swarm. Serialize deployments for a given stack.
2. Ensure a stack-scoped, versioned master secret exists. On first deployment,
   stream fresh randomness directly into `docker secret create`; never save,
   print, or retain a local key file. After creation, never retrieve the key.
   If an existing installation has lost its master secret, stop for explicit
   recovery using a new key version; never silently replace an already-used key.
3. Install the policy as a content-addressed Swarm config. Reuse unchanged
   content; automatically select a new config name when its bytes change.
4. Identify missing client secrets from the policy, active key, and generations.
   If none are missing, skip token generation entirely.
5. Create one temporary helper service from the selected broker image. Pin it
   to the manager node reached by the selected Docker context so that subsequent
   container operations address the correct Docker Engine, including when the
   context uses SSH. Give it only the policy and needed master secret, disable
   the inherited HTTP health check and service logging, and grant no Docker
   socket, backend credentials, published ports, or application overlay access.
6. Wait with a deadline for its running task. Use `docker exec` without a TTY to
   run `/broker-token generate` for each missing token. Capture the successful
   output in process memory, validate its exact format, then pass it through
   stdin to `docker secret create`. Do not create a secret from a failed or
   truncated generator stream. Never use `docker service logs` to collect tokens.
7. Name secrets using stack/deployment identity, protocol version, master-key
   version, client, and generation; use labels to validate ownership and detect
   conflicting preexisting objects, including a changed master secret's Swarm ID.
   Mount them under stable filenames in apps, with ownership/mode compatible
   with unprivileged Files and Notes processes. Reuse matching existing secrets
   without reading their values.
8. Remove the temporary helper on success, failure, or interruption; bound its
   lifetime for abandoned deployments. Clean up only resources owned by this
   run, and leave reusable secrets/configs intact after a partial failure.
9. Render the final non-secret stack references, validate them again, perform
   the appropriate rollout, and wait for bounded readiness/convergence checks.

The master key is available only in Swarm-managed secret mounts after creation.
Derived tokens briefly pass through the trusted deployment process and are
persisted only as Swarm secrets. Disable shell tracing and never export token
values into stack interpolation, labels, environment files, or command lines.
Docker control-plane administrators remain trusted: this design does not prevent
an administrator from scheduling a task with access to a secret.

## 6. Application integration

For access-gateway, Files, and Notes, add a shared configuration convention such
as `BROKER_TOKEN_FILE` / `--broker-token-file`. Their existing `*_URI_FROM`
settings contain the non-secret URL and client ID. When fetching a URI, read the
token file and add its value with proper URL encoding. The gateway uses its one
client token for both its authorized backends. Prevent duplicate authentication
parameters and reject conflicting token sources.

Keep the token-file option optional for compatibility with a tokenless broker:
when absent, preserve existing discovery behavior. When supplied, an unreadable
or invalid token file fails startup rather than retrying without authentication.
Select the corresponding third-party wrapper path explicitly from deployment
mode; never fall back to a tokenless request after an authentication failure.

Harden gateway discovery while changing this path: bounded response bodies,
timeouts/retries, status checks, redirect refusal, and errors that never include
the discovery URL or raw HTTP errors containing it. Preserve the equivalent
safeguards already present in Files and Notes.

For RazChess and GeoIP, retain upstream images and extend their existing startup
wrappers. Read the app token from `/run/secrets/`, construct the authenticated
URL at runtime, and pass it through the existing `--redis-from` flag. Preserve
other arguments and `exec` behavior. The stored Swarm service command contains
only non-secret configuration and secret paths; the token-bearing URL necessarily
exists in the application's runtime arguments. Audit upstream error logging and
verify that discovery/authentication failures do not silently start the app with
an unintended in-memory backend. If necessary, perform bounded, authorized
credential discovery as part of startup before invoking the app; keep health
checks limited to `/readyz`.

An application with a configurable discovery URL needs no source changes. An app
accepting only a database URI needs a startup adapter. A hardcoded client with no
configuration requires a patch or an adapter isolated to that app; do not add an
unauthenticated proxy on the shared network.

Supply an independent development key/policy and secret files for local Compose,
with token mode enabled by default there too. Also document an explicit `none`
Compose configuration that requires no token infrastructure. Production master
keys are never exported to local development. Update service and parent Compose
fixtures, examples, and validation for both supported modes.

## 7. Transport and secret exposure

Keep the broker private and add verified TLS for production credential discovery.
Plan broker certificate/key file support and consumer CA trust as a coupled
workstream; certificate issuance and renewal use the operator's PKI and remain
separate from the token master key. Account for CA trust in third-party images.
Do not disable certificate verification or treat bearer-token authentication as
encryption. Complete this transport setup before accepting the deployment against
a threat model that includes traffic capture or an impersonated broker.

Audit server, startup, HTTP-client, and operator tooling logs for full URLs. Do
not store tokens or authenticated URLs in Swarm configs, Git, `.env`, generated
stack files, diagnostics, or test failure output. Scoped tokens still permit
replay within their grants if stolen. Revoking a token does not revoke database
credentials already issued; database credential rotation is a separate operation.

## 8. Rollout and lifecycle

Publish supporting broker and first-party consumer images before deploying their
references. Parent submodule pins do not publish images or change running code.

On a fresh Swarm, prepare secrets/configs first, then deploy secured services;
consumer retries account for Swarm startup ordering.

For an existing installation, automate a staged migration inside `make deploy`:

1. Prepare keys, policy, and app secrets.
2. Upgrade consumers to send authenticated requests while retaining the currently
   deployed broker image, or using the new broker with explicit `AUTH_MODE=none`.
   Both accept the added query parameters without enforcing them. This temporary
   tokenless stage is permitted only when migrating an already-tokenless deployment;
   never downgrade an installation that already enforces tokens.
3. Verify all consumers have rolled out, then deploy the new broker in explicit
   `AUTH_MODE=token` and verify convergence of every broker replica.
4. Confirm tokenless and cross-client access are rejected. Do not revert to an
   unauthenticated broker as an automatic recovery action.

Handle failures by stopping the rollout with a clear stage report. The single
command may perform several controlled phases; Swarm updates are not atomic.
The new tokens provide access control only after broker enforcement is active.
Record that the transition retains the old exposure until final cutover.

For normal additions or permission expansions, roll out the broker policy before
starting consumers that need the new grants. For removals, ensure every broker
replica has stopped accepting the removed client. Rollbacks must not accidentally
restore revoked policy or secrets.

Provide explicit rotation workflows:

- Client token: issue a new generation, temporarily accept both generations,
  deploy the new app secret, verify convergence, then drop the old generation.
  Immediate compromise response can remove the old generation first and accept
  a controlled interruption.
- Master key: create a new versioned Swarm secret, temporarily configure both
  keys, derive/distribute new app tokens, then remove acceptance of the old key.
  Normally only one master key is active; two are mounted only during rotation.
- Policy: update content-addressed config references without rotating tokens.

Do not automatically delete old secrets/configs needed by running services or
an intentional rollback. Garbage collection is separate and reference-aware.
Document Swarm state backup/recovery: losing the master requires a new key and
token redistribution, not recreating application databases.

## 9. Implementation ownership and verification

Implement in this order:

1. `database-broker/`: shared policy/HMAC package, CLI, authorization middleware,
   server configuration, Dockerfile, documentation, and tests.
2. `access-gateway/`, `files/`, `notes/`: token-file discovery configuration,
   bounded fetch behavior, logging fixes, and configuration tests.
3. `infra/`: client policy, versioned secrets/configs, secure generator lifecycle,
   wrappers, staged deployment helper, environment examples, and operations docs.
4. Parent repository: authenticated Compose setup, fixtures, cross-component
   documentation, and submodule pointers after component commits are published.

Required checks include:

- Mode/configuration tests: token mode is the default; invalid or incomplete
  token-mode configuration fails startup; explicit `none` mode starts without
  policy/key files and preserves all original endpoint behavior; invalid mode
  values fail; no configuration or request error causes automatic downgrade.
- Fixed token vectors and changes to client/deployment/key/generation inputs;
  malformed tokens, unknown clients, duplicate parameters, alias/case handling,
  constant-time MAC comparison, and generation/key overlap.
- Router tests proving rejected requests never call backend provisioning, and
  covering both credential formats, listing denial, health exceptions, and
  `no-store` headers.
- CLI and client tests proving secret-free diagnostics, no redirects, rejected
  non-2xx responses, bounded bodies, and correct URL construction.
- Isolated deployment-helper tests with fake Docker commands: first deployment,
  unchanged redeploy, added client, permission-only edit, failed generation,
  partial state, lost/replaced master secret, interrupted helper, custom/remote
  context targeting, rotation, staged upgrade ordering, and explicit `none`
  deployment without token resources. Consume secret stdin without recording it.
- `gofmt`, build, vet, and relevant tests inside each affected Go module; service
  and parent Compose validation; stack config validation; `bash -n` for helpers.
- An explicitly authorized disposable Swarm test: fresh bootstrap and existing
  stack migration, repeated deploys, scoped discovery, denial without backend
  side effects, all-replica revocation, verified TLS, and helper cleanup. Confirm
  tokens are absent from service specs and logs and master mounts are confined
  to the broker and the temporary generator.

Routine validation must not deploy to production, change Docker contexts, or
probe provisioning endpoints on a live system. Report the exact checks run and
any environmental limitations during implementation.

## References

- [RFC 2104: HMAC](https://www.rfc-editor.org/rfc/rfc2104)
- [Docker Swarm secrets](https://docs.docker.com/engine/swarm/secrets/)
- [Docker Swarm configs](https://docs.docker.com/engine/swarm/configs/)
- [Creating services and placement constraints](https://docs.docker.com/reference/cli/docker/service/create/)
- [Executing commands in running containers](https://docs.docker.com/reference/cli/docker/container/exec/)
- [Creating secrets from stdin](https://docs.docker.com/reference/cli/docker/secret/create/)
