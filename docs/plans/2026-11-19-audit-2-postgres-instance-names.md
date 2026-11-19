# Audit item 2: bound new PostgreSQL instance names

Status: implemented in Database Broker commit `e257f8e`. No deployment performed.

## Problem and evidence

The broker accepts nonempty ASCII letters, digits and underscores and normalizes
names to lowercase in [broker.go](../../database-broker/internal/broker/broker.go).
The common syntax validator in
[names.go](../../database-broker/internal/names/names.go) has no length limit.
Token policies allow instance grants up to 128 bytes in
[policy.go](../../database-broker/internal/auth/policy.go).

For a new PostgreSQL instance,
[postgres.go](../../database-broker/internal/adapter/postgres/postgres.go) builds
`db_<instance>` and `user_<instance>_<suffix>`. The suffix is seven unpadded base32
characters from four random bytes, as implemented in
[rand.go](../../database-broker/internal/util/rand.go). PostgreSQL's ordinary
identifier limit is 63 bytes. Quoting an identifier does not prevent truncation.

The preceding audit reproduced the failure against disposable PostgreSQL:
provisioning `strings.Repeat("a", 58) + "a"` succeeds, while provisioning
`strings.Repeat("a", 58) + "b"` fails with SQLSTATE `42710`, role already exists.
Both generated roles truncate to `user_` followed by 58 `a` characters, removing
both the distinguishing final character and random suffix. `CREATE DATABASE`
already ran before that failure, so the unsuccessful request also leaves an
empty database outside its rolled-back transaction. This evidence comes from the
audit; no tests were rerun to prepare this plan.

## Selected behavior

Permit new PostgreSQL instance names of at most **50 ASCII bytes**:

```text
role length = len("user_") + 50 + len("_") + 7 = 63
database length = len("db_") + 50 = 53
```

The length rule applies only when PostgreSQL metadata is absent and provisioning
is about to begin. Existing long names must keep returning their saved database,
role, password and URI. Do not rename, rotate, rewrite or re-provision them.
Dragonfly and Valkey retain their existing behavior.

Keep the current ASCII syntax and canonicalization at the broker boundary.
Place this creation-only PostgreSQL rule inside the PostgreSQL adapter because
only that layer knows whether the request is a lookup or a new provision. This
also protects callers that invoke the adapter directly. Do not add a read-only
lookup method to the shared adapter interface just to move the guard upstream.

## Request and error flow

1. Keep the first PostgreSQL metadata lookup exactly as it is. Return existing
   records before applying the creation limit; preserve dependency errors.
2. Keep the per-instance session lock and the second metadata lookup on its
   pinned connection. A record created by a concurrent or older replica still
   wins and must be returned, even if its name is longer than 50 bytes.
3. After the locked lookup returns `rel.ErrNotFound`, set the fixed logging stage
   to `validate_instance_name` and reject `len(instanceName) > 50`.
4. Run the guard before generating credentials, constructing identifiers or
   calling `createDatabase`. An overlong request may read metadata and acquire
   the existing lock, but must create no database, role or metadata row.
5. Add one domain error sentinel, `adapter.ErrInstanceNameTooLong`, alongside the
   shared adapter contract in
   [interface.go](../../database-broker/internal/adapter/interface.go). Use a
   fixed, safe message such as `instance name is too long to provision`.
   Return it through the adapter's existing deferred `logging.Wrap`.
6. At the existing adapter call in `broker.GetOrCreateInstance`, use `errors.Is`
   to recognize that sentinel and return the existing broker `Error` with status
   422. Build its message from the fixed sentinel, never from arbitrary wrapped
   backend error text. Other errors and successful results pass through.
7. The current router can then serialize the direct broker `Error` through its
   existing `StatusCode()` handling. No new HTTP dependency belongs in the
   adapter, and no router implementation change is needed.

The error translation is necessary: the adapter wraps all failures, while
[controller.go](../../database-broker/internal/router/controller.go) currently
checks `StatusCode()` only on the outermost error. Merely adding that method to
an inner error would still produce HTTP 500.

Authentication remains first. An unauthenticated request still gets 401 and an
out-of-scope request still gets 403. Only an authorized creation attempt, or a
request in explicit legacy mode, reaches the 422 name rejection. Credential
responses retain `Cache-Control: no-store`.

## Policy decision

Leave policy parsing and the 128-byte grant limit unchanged. A policy authorizes
access to a named instance; it cannot determine whether that instance already
exists. Reducing its PostgreSQL grant limit to 50 would prevent startup with
valid grants for existing long instances. Policy validation and token generation
must remain independent of live database access.

Document the distinction explicitly: a PostgreSQL grant between 51 and 128 bytes
may address an existing record, but cannot create a new instance. No new policy
flag, protocol version or configuration setting is required.

## Implementation scope and order

| File | Planned change |
| --- | --- |
| `database-broker/internal/adapter/interface.go` | Add the domain error sentinel; keep the interface methods unchanged. |
| `database-broker/internal/adapter/postgres/postgres.go` | Add a private 50-byte creation limit and the guard after the locked metadata miss. |
| `database-broker/internal/broker/broker.go` | Translate the wrapped domain error into the existing HTTP-422 broker error. |
| `database-broker/internal/adapter/postgres/postgres_test.go` | Add provisioning boundary, no-side-effect and existing-record compatibility tests. |
| `database-broker/internal/broker/broker_test.go` | Test error translation, including a wrapped sentinel, without changing other adapter behavior. |
| `database-broker/internal/router/router_test.go` | Exercise both JSON and URI endpoints through a real broker with a stub adapter that returns the wrapped sentinel. |
| `database-broker/internal/auth/auth_test.go` | Add a focused assertion that an existing-length PostgreSQL grant remains accepted, if current cases do not already cover it. |
| `database-broker/README.md`, `docs/reference.md`, `docs/authentication.md`, `AGENTS.md` | Describe the creation-only PostgreSQL limit, lookup compatibility and 422 result. |

Implement the guard and domain error first, then broker translation and tests.
Retain the existing session-lock protocol and same-connection provisioning
sequence. There is no schema migration, dependency addition, consumer change,
Compose change or Swarm configuration change.

## Acceptance tests

Use the existing disposable-backend fixtures, never production databases.

1. **Boundary succeeds:** provision a 50-byte ASCII name through the adapter;
   assert the saved role is exactly 63 bytes, its database is 53 bytes, and the
   returned URI authenticates. Two distinct 50-byte names with a long shared
   prefix must provision independently.
2. **Boundary rejects without writes:** request a new 51-byte name directly from
   the adapter. Assert `errors.Is(err, adapter.ErrInstanceNameTooLong)` survives
   logging wrappers. Compare `pg_database`, `pg_roles` and `instances` before and
   after; there must be no new objects or metadata. Include the two 59-byte audit
   inputs and a 128-byte input in the same rejection cases.
3. **Existing long record still resolves:** provision a short fixture normally,
   then change only its metadata lookup key to a valid 59-byte name in the test
   database. Both `GetInstance` and `GetOrCreateInstance` must return exactly the
   stored credentials and URI, with no provisioning and no 422. This deliberately
   tests metadata lookup compatibility without relying on truncated identifiers.
4. **Error mapping works end to end:** register a stub adapter in a real broker,
   returning `logging.Wrap("validate_instance_name", sentinel)`. Both credential
   endpoint forms return 422 JSON with the fixed message and `no-store`. Keep
   the existing test proving raw backend SQL/password errors remain generic 500.
5. **Other adapters and authorization remain intact:** a long valid name reaches
   a non-PostgreSQL stub unchanged; existing auth tests still enforce 401/403
   before adapter work. Policy parsing still accepts PostgreSQL grants of 51 and
   128 bytes and still rejects grants above its existing 128-byte bound.
6. **Existing concurrency remains intact:** the current concurrent provisioning,
   canceled lock acquisition and rollback/retry tests continue to pass. The new
   guard must not change successful short-name provisioning or lock cleanup.

Planned verification inside `database-broker/`: gofmt changed Go files,
`go build ./...`, `go vet ./...`, focused broker/router/auth tests, and
`go test -race ./...` against a verified local disposable Docker daemon or the
documented disposable loopback backends. No deployment is a validation step.

## Release and compatibility

Commit implementation and documentation in the broker submodule. Publish its
commit and image only when release is authorized; publishing the parent's pin
alone cannot update a deployed image. Update the parent pin only after the
component commit is available remotely.

No data migration or consumer rollout is needed. Existing names and credentials
remain valid. During a mixed-version rollout, an older replica can still attempt
new long-name provisioning. Pause creation of names above 50 bytes until every
broker replica is upgraded; ordinary lookups and short-name provisioning can
continue. A rollback restores the old unsafe creation behavior.

Do not automatically delete databases left by earlier failed attempts. The
current adapter intentionally accepts an existing database on retry and does
not assume that it is empty. Operators must inspect any old orphan separately
before deciding what to remove or recover.

## Non-goals and remaining risks

This fixes identifier truncation for new broker-managed PostgreSQL resources.
It does not redesign resource names, reconcile already colliding records, rotate
credentials, change the random suffix, add cleanup jobs or impose PostgreSQL's
limit on Redis-compatible adapters. Existing random role-name collisions remain
ordinary transactional failures, as they are today.

The 50-byte value is derived from the current prefix and seven-character suffix;
the boundary test must fail if that naming format changes. Nonstandard
PostgreSQL builds with a smaller identifier limit are outside the present
supported deployment assumptions. This plan was checked against source and the
prior audit reproduction; implementation and its new tests remain to be done.
