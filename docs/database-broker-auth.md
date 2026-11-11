# Broker authentication across the stack

The broker defaults to scoped bearer tokens. A client token grants only exact
adapter/instance pairs in the current policy, including get-or-create for those
pairs. It cannot enumerate instances. Policy removal or generation changes revoke
a token after every broker replica converges; database credentials already issued
need separate rotation. See the broker's [protocol and CLI](../database-broker/docs/authentication.md).

## Local Compose

With Go 1.27 and Python 3, run `make local-auth` before `docker compose up --build`.
The broker CLI validates dev/broker-clients.yml, creates an independent random
32-byte master and writes derived app tokens into ignored .local/broker-auth.
Token files are read-only app mounts, including UID 10001 consumers; the master
is mounted only into the broker. Existing development keys are reused. Missing
keys with existing token state fail instead of being silently replaced.

Development policy uses a different deployment identity and key version from
production. Never copy production key/token material to a development machine.
HTTP discovery is limited to the private local network; production uses verified
HTTPS. Bearer tokens alone do not encrypt credentials or prevent traffic capture.

The explicit legacy configuration requires no policy, key or token files:

```
docker compose --env-file .env -f docker-compose.yml -f docker-compose.none.yml up --build -d
```

This override resets auth mounts and selects AUTH_MODE=none. There is no automatic
fallback when token configuration, token files or authentication fail. The standalone
broker stack has equivalent dev preparation and none-mode override in its repository.
Other standalone consumer stacks with direct database URIs need no broker resources.

## Swarm

`make deploy` delegates to infra's maintained lifecycle helper. It validates the
selected broker policy using the published broker image, prepares Swarm-only keys
and per-app secrets, rolls out policy before consumers, stages existing tokenless
migrations and verifies enforcement against each broker replica. Every Docker
command targets the selected context. No local Go/OpenSSL is needed for production
preparation; the helper uses Python 3's standard library and the broker image.

Production requires operator-issued broker TLS credentials/CA and published images
supporting this protocol, including the two thin legacy-app adapter images. Publish
component commits/images before publishing parent pins or deploying selected tags.
The current local commits do not change running services. See
[Swarm setup, rotation, recovery and verification](../infra/docs/broker-authentication.md).

## Implementation checks

Validation uses GOCACHE=/tmp/razcloud-go-cache because the sandbox's normal Go
cache is read-only. Local HTTP/S3/TLS fixture tests run with loopback socket access.

- In database-broker: go build ./...; go vet ./...; go test for internal/auth,
  config, broker, router, util, health, logging, discovery and cmd/...; race tests
  for auth, config, broker, router, discovery and cmd/....
- In access-gateway, Files and Notes: go build ./...; go vet ./...; go test ./...;
  go test -race ./.... PostgreSQL/Redis integration cases skip when disposable
  TEST_DATABASE_URL/TEST_REDIS_URL are absent. In-memory S3 fixtures run locally.
- Infra's 15 isolated fake-Docker tests cover preparation/reuse, additions,
  permission changes, failed/truncated/interrupted generation, partial resources,
  lost/replaced masters, custom SSH context targeting, rotation, revocation,
  staged migration, conflicts and explicit none mode. Secret stdin is consumed
  without saving it.
- Parent Compose token mode, storage-demo and explicit none mode; broker standalone
  token/none Compose; gateway/Files standalone Compose; infra rendered stack in
  token/none modes; shell/Python syntax and Git whitespace checks.

Adapter provisioning integration tests have not run: they need disposable local
PostgreSQL, Dragonfly and Valkey. No live Swarm deployment, image publication,
production probing or global Docker context change is part of this validation.
Disposable Swarm acceptance remains a release requirement, particularly worker
placement/health, migration, verified TLS renewal, all-replica revocation, cleanup
and secret absence from specs/logs. See the original [implementation plan](database-broker-auth-plan.md).
