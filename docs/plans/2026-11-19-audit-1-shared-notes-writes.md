# Plan 1: coordinate shared Notes writes by their physical object

Status: implemented in Notes commit `95fdea0`. No deployment performed.

## Problem and evidence

With conditional writes disabled, two users can attach notebooks to one shared
connection, choose the same bucket/prefix, and edit the same S3 file. This is a
supported storage layout: `notes/internal/storage/shared_test.go` explicitly
checks that an unprefixed object is shared between users.

The protection currently follows the notebook rather than the file:

- `notes/internal/db/db.go:LockObject` hashes notebook ID and owner-prefixed
  logical key.
- `notes/internal/storage/managed.go:Managed.call` uses that lock, then reads the
  current notebook and connection policies through `Repository.Locked`.
- `notes/internal/storage/versions.go` passes mapping owner, notebook ID, and
  logical key to `ObserveVersion`, `ClaimVersion`, and `RecordVersion`.
- `notes/internal/db/migrations/00003_conditional_writes.sql` makes the version
  row unique by `(scope,key)` and binds it to the notebook/owner.
- `Mapped.physical` removes the logical owner, adds the effective notebook
  prefix, and applies rclone filename encryption. Different logical identities
  can therefore resolve to the same physical object.

The audit's temporary PostgreSQL/S3 reproduction used two owners' notebooks on
one unprefixed shared connection. Both edits reached unconditional S3 PUT and
both returned success. The latter upload overwrote the former. The reproduction
was run during the audit; this planning task does not rerun it or change tests.

The current architecture document explicitly limits coordination to a notebook.
This change extends the guarantee to mappings using the **same connection**. It
does not attempt to discover independent connections pointing at the same store.

## Selected design

Reuse the existing version table, compare-and-swap operations, and transaction
handling. Give compatibility-mode operations a canonical storage identity:

| Field | Value |
| --- | --- |
| Version `scope` | Authorized connection UUID, `c.ID` |
| Version `owner` | Connection creator UUID, `c.Owner` |
| Version `key` | Effective bucket, `/`, then the exact physical S3 key |
| Physical advisory-lock namespace | A fixed `notes-storage-object` domain plus the same scope/key |

Resolve the bucket with `Connection.BucketFor`, and obtain the physical key from
the same request-local `Mapped.physical` implementation that performs I/O. Do
not reconstruct crypt names or concatenate the mapping owner's UUID separately.
The key includes user-ID prefixing when enabled, the complete notebook prefix,
and rclone's encrypted filename when applicable. Valid bucket names contain no
slash, so `bucket + "/" + physicalKey` is unambiguous. Use a separate advisory
lock domain from the existing notebook locks; reuse `LockObject` with a fixed
domain prefix or a small purpose-specific sibling helper, not a new lock service.

Two authorized notebooks resolving to one object now share both its lock and
its revision row. Every successful compatibility-mode mutation advances that
single UUID revision, including an identical-content save. Changing only the
lock would leave another notebook's old revision valid when S3 returns the same
ETag, so both identities must change together.

Keep the existing `"notes-db-<UUID>"` validator format, `*` create-only marker,
opaque underlying S3 ETags, and HTTP conflict statuses. The table's `owner`
remains owner-scoped, but its owner is the connection creator rather than the
mapping owner. This row is coordination metadata, not an authorization grant.
Only freshly authorized managed storage may derive its identity. No handler
accepts a connection-owner UUID or physical key from the request.

Do not add a second version table, global storage registry, new dependency,
configuration switch, or public `Store` interface method. Do not forbid the
existing shared unprefixed layout or invalidate unrelated objects on each save.

## Lock and transaction order

Keep the current order and append the physical lock after policy resolution:

1. Begin or reuse the caller's `pgx.Tx`.
2. Acquire the existing notebook/logical-object advisory lock when there is an
   object key. `App.put`, `App.delete`, and `Engine.Index` already hold this lock;
   reacquisition inside the same transaction remains safe.
3. Call `Repository.Locked` to authorize the mapping and hold shared notebook
   and connection row locks. Check the current write policy for mutations.
4. Construct the current mapped handle. For a compatibility-mode object call,
   resolve its canonical identity and acquire the physical advisory lock on
   that **same transaction** before HEAD/GET/PUT/DELETE.
5. Perform S3 checks, version observation/claim, mutation, and version recording.
   Retain all locks until the transaction commits or rolls back.

Apply the physical lock to compatibility-mode `Head`, `Get`, `Put`, and `Delete`,
including calls made by indexing. Reads that issue or observe database
validators must serialize with writes too; otherwise a HEAD performed before
another write could overwrite coordination metadata afterward. Listings retain
their existing page transaction and policy checks, without an object lock.
Strict conditional-write mode keeps its existing path and does not need the
additional physical-lock query.

Pass the derived canonical identity through the existing `Managed.call`
callbacks to the storage version helpers. Keep it request-local; do not put
current credentials or policies on the long-lived `Managed` handle. A small
internal value is acceptable if it avoids passing the same three strings
separately, but it must not introduce a new public abstraction.

Preserve `store.WithTransaction` reuse. No additional pool acquisition may occur
while an app write, object index job, or scan page owns a transaction. Keep
`App.queueAfterWrite` and its savepoint: a queue failure must not roll back a
successful S3 write's revision record. Existing handling of an ambiguous commit
after S3 success remains unchanged and documented.

## Migration and lifecycle

Add the next Goose migration, currently
`notes/internal/db/migrations/00006_physical_write_versions.sql`. Never edit
migration 00003.

The Up migration, in its ordinary Goose transaction, must:

1. Clear only `object_write_versions`, intentionally invalidating existing
   compatibility-mode editor tokens.
2. Drop `object_write_versions_scope_owner_fkey`, the current notebook foreign
   key. Verify the actual generated constraint name in the migration test.
3. Change `scope` from `text` to `uuid`. The new values are connection UUIDs;
   this matches `storage_connections.id` for PostgreSQL foreign-key types.
4. Add a composite `(scope,owner)` foreign key referencing
   `storage_connections(id,owner) ON DELETE CASCADE`. Keep the existing
   `(scope,key)` primary key and remaining fields.

Do not clear settings, secrets, recovery records, indexes, scan state, River
jobs, or any S3 content. Do not backfill notebook revisions: aliases may have
different old revisions and encrypted physical names require the real mapping
logic. Fresh UUIDs on the next authorized observation are safer and smaller.

Update `Repository.SaveConnection` mode-switch invalidation from the notebook
subquery to `DELETE FROM object_write_versions WHERE scope=$1`, using `c.ID`.
Its existing exclusive connection row lock orders this change against managed
operations' shared policy locks. Preserve invalidation when switching in either
direction, including switching back after an identical-content strict-mode save.
Also clear retained rows when saving a connection with no attached notebooks.
The existing `attached` check already runs under that exclusive connection lock;
using it avoids retaining old object tokens when a detached connection UUID is
reused for a different endpoint, credentials, or prefix policy. No current
notebook draft is valid in this detached state.

Notebook removal must no longer cascade shared physical revisions. Another
notebook can still use that object. Requests naming the deleted notebook still
fail ownership/existence checks before version lookup. Reattaching through the
same connection and physical path reuses its retained revision if nothing has
changed; a validator describes the object, not the mapping's lifetime. A write,
delete/recreate, or mode switch invalidates the old token. Deleting the
connection cascades its revisions; recreating a connection produces a new UUID
and new revisions.

The Down migration must clear only this coordination table, remove the
connection foreign key, return `scope` to `text`, and restore the notebook
foreign key. Both directions require stopped Notes processes. Do not claim that
rolling back the binary alone works against the changed schema.

## Files and callers to change

| Location | Planned change |
| --- | --- |
| `notes/internal/storage/managed.go` | Derive the authorized physical identity, append the compatibility physical lock, and pass the identity to object callbacks. |
| `notes/internal/storage/versions.go` | Use connection owner/ID and bucket/physical key for observation, claim, and recording; retain logical key for S3 calls. |
| `notes/internal/store/versions.go` | Retain existing SQL and UUID compare-and-swap behavior; rename parameters/comments to explain the connection scope. |
| `notes/internal/store/store.go:SaveConnection` | Invalidate by connection scope on mode switches or a detached connection save, under the existing exclusive policy lock. |
| `notes/internal/db/db.go` | Retain logical locks; add a domain-separated physical lock using the same transaction and existing PostgreSQL mechanism. |
| `notes/internal/db/migrations/00006_physical_write_versions.sql` | Change coordination ownership/type and deliberately expire old tokens. |
| `notes/internal/app/app.go:put/delete/queueAfterWrite` | Review callers and preserve lock/transaction/savepoint behavior; no route or response changes. |
| `notes/internal/index/index.go:Index/ScanPage` | Review existing transaction propagation and shared-object locking; no queue payload, scan, or index ownership changes. |
| `notes/internal/storage/versions_test.go`, `shared_test.go`, `managed_test.go` | Add cross-owner regression cases and update connection-scope assertions. |
| `notes/internal/app/versions_test.go` | Cover API/editor validators, conflict draft retention, and queue failures across aliases. |
| `notes/internal/index/index_integration_test.go` | Exercise indexing against another owner's write and retain the one-connection pool checks. |
| New migration integration test under `notes/internal/db/` | Test upgrade/downgrade with populated coordination metadata and preserved durable/content rows. |
| `notes/docs/architecture.md`, `notes/AGENTS.md` | Describe connection-owned physical coordination, lifecycle, the reload requirement, and its boundaries. |
| Parent `AGENTS.md` | Update its Notes coordination summary if it still describes notebook-only write safety. |

The guide refers to `notes/docs/plan.md`, which is absent in this checkout;
`notes/docs/architecture.md` and current source were used for the design.

## Implementation order and acceptance

1. Convert the audit reproduction into a permanent two-owner regression before
   changing behavior. Keep fixtures disposable and local. Use controlled
   provider gates and final success/conflict counts; do not retain the old
   reproduction's requirement that both PUTs reach the provider, because that
   would deadlock when the fix correctly blocks the second writer.
2. Add migration tests and the migration. Test upgrade from a populated version
   5 schema, the new foreign-key type/ownership, both cascades, and Down under
   quiescence. Verify S3/settings/secrets/index content are untouched.
3. Derive the canonical identity once, add the physical lock, and route existing
   version operations through it. Change mode-switch invalidation in the same
   implementation change.
4. Extend existing integration tests and update documentation. In
   `shared_test.go`, two unprefixed, crypt-compatible mappings of one object
   should yield **one** version row; prefixed or physically different objects
   should retain separate rows.
5. Run `gofmt` on changed Go files, then `go build ./...`, `go vet ./...`,
   `go test ./...`, and `go test -race ./...` inside `notes/`, with a disposable
   loopback `TEST_DATABASE_URL`. Existing in-memory S3 fixtures provide storage.

Required regression outcomes:

- Two owners, two registries representing replicas, one unprefixed shared
  connection, one existing object: exactly one stale-base concurrent update
  succeeds and the other returns `storage.ErrConflict` / HTTP 412.
- The same test with identical content still has one winner; a completed
  identical-content save invalidates another owner's old validator even on a
  provider returning the same ETag and no distinct version ID.
- Concurrent creates have one winner. Update/delete and delete/recreate races
  cannot accept an old token. Attachments have the same protection as notes.
- Plain and rclone-encrypted mappings work, including compatible shared crypt
  settings and filename encryption off. Use actual `Mapped.physical` output.
- Distinct buckets, user-ID prefixes, physical paths, and crypt names remain
  independent. Legal long physical keys up to the current 1024-byte limit work;
  over-limit encrypted/prefixed keys are rejected before S3 and before creating
  coordination rows.
- Unauthorized notebook IDs, foreign personal connections, and read-only
  mappings/connections still fail before storage or coordination access.
- Mode switches invalidate tokens for every owner on that connection without
  changing other connections. Removing/recreating mappings and connections
  follows the lifecycle above. Saving a detached connection and reattaching the
  same bucket/key after a location change must yield a fresh validator even if
  the new provider returns identical metadata.
- Failed S3 mutations roll back revision claims. Queue insertion failure keeps
  the successful revision. Index rebuilds do not reset coordination metadata.
- Indexing and writes through aliases serialize; PostgreSQL pool size one still
  supports an indexing transaction and scan page without nested acquisition.

## Release and rollback

This is a coordinated Notes release, not a safe mixed-version rolling upgrade.
Old replicas use notebook identities and cannot participate in the new physical
protocol. Do not try to support both protocols with dual writes.

Publish the supporting Notes image before selecting it in infra. Back up Notes
PostgreSQL settings and preserve unsaved editor drafts. In an authorized release
window, stop and drain **all** Notes HTTP processes and River workers, migrate
once with the new release, and start only new replicas. Confirm the service is
ready and reload compatibility-mode editors; old tokens must get a conflict
rather than be translated or silently accepted. A brief Notes outage is the
chosen cost of a smaller, verifiable migration. Gateway, Files, and S3 need no
data changes.

Rollback also stops/drains all Notes processes first, runs the tested Down
migration, and restarts the old release. Reload editors again. Rollback restores
the old notebook-only safety limit, so avoid concurrent compatibility-mode edits
through shared aliases until the fixed release is restored. No deployment is
authorized or performed by this plan.

## Boundaries and risks

Independent connection records, separate Notes databases/installations, Files,
and external S3 clients still do not share this coordination. Compatibility mode
still has a HEAD-to-unconditional-write race with those writers. Provider
versioning/backups remain the recovery mechanism for those cases; this work does
not enable them or add cross-service coordination.

The additional physical lock intentionally serializes access to one physical
object within a compatibility-mode connection. It does not serialize unrelated
objects or whole connections. Preserve lock ordering and cancellation cleanup to
avoid deadlocks or pool exhaustion. A database failure after an S3 success remains
non-atomic and can require a reload, as documented today.

No open product decision is needed for implementation. The operational
requirement is an explicitly authorized quiesced Notes rollout and editor reload.
This document was checked against current source and existing tests; no service
checks, migration, or deployment were run for this planning task.
