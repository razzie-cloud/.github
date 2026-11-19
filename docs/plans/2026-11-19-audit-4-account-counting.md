# Design: count gateway accounts in PostgreSQL

Status: implemented in Gateway commit `19da5b3`. No deployment performed.

## Problem and evidence

[`countUsers`](../../access-gateway/internal/app/store.go) calls
`s.repo.FindAll(ctx, &users)` and returns the slice length. Every invocation
transfers all user columns and allocates a `User` for every account, even when its
caller only needs to know whether the count is zero. This is a small efficiency
improvement at the installation's expected load, not an authentication defect.

The installed `github.com/go-rel/rel` v0.43.0 already provides
`Count(ctx, collection, ...Querier) (int, error)`. Its implementation uses the
current repository/context adapter and a `count(*)` aggregate. No dependency or
direct SQL helper is needed. The current `User` model has no soft-delete field;
an unfiltered count of `users` preserves the existing set of accounts.

## Selected change

Replace only the body of `countUsers` in
[`internal/app/store.go`](../../access-gateway/internal/app/store.go):

```go
func (s *Server) countUsers(ctx context.Context) (int, error) {
    return s.repo.Count(ctx, "users")
}
```

Keep the function signature and all callers. Count every persisted account,
including disabled users and users without passkeys. Pending invitations and
registration ceremonies still contribute nothing until their user insertion
commits. Return the repository's error unchanged; callers must continue to deny
bootstrap or report an error when counting fails.

This returns one aggregate value instead of all user records. PostgreSQL still
has to compute an exact count; the design does not promise constant database
work as the account table grows.

## Scope and affected paths

Only `internal/app/store.go` needs an implementation change. Review these callers
to confirm that their existing zero/nonzero checks and error responses remain:

| Source | Caller and behavior |
| --- | --- |
| [`internal/app/http.go`](../../access-gateway/internal/app/http.go) | `handleBootstrap` reports `needsRegistration`; `handleRegisterBegin` rejects new bootstrap registration when users exist. |
| [`internal/app/ui.go`](../../access-gateway/internal/app/ui.go) | `state` sets the UI registration flag; `handleStateAfterLogout` renders that flag after sign-out. |

The real bootstrap safety checks remain separate and unchanged:
[`bootstrap.go`](../../access-gateway/internal/app/bootstrap.go) uses `EXISTS`
inside the bootstrap advisory-lock transaction, and
[`registration.go`](../../access-gateway/internal/app/registration.go) rechecks
the user count inside the enrollment transaction before committing the first
administrator. Do not replace those checks with this request-level helper or
change their locks, transactions, or Redis operations.

No schema, configuration, route, template, public documentation, or parent
submodule pointer change is needed for the optimization itself.

## Implementation steps

1. Check the gateway worktree and use its appropriate working branch, preserving
   existing work. Confirm the installed `rel.Repository.Count` signature.
2. Make the one-line body replacement and run `gofmt` on `store.go`.
3. Review the diff: no filters, joins, `LIMIT`, cache, new transaction, or changed
   caller/error handling should appear.
4. Run the gateway checks below. Keep this optimization in its own component
   commit; the native-form plan can touch the same repository independently.

## Verification and acceptance

Reuse the existing integration tests rather than add a test that merely checks
which repository method the implementation calls:

- [`TestPostgresNewUserInvitation`](../../access-gateway/internal/app/invitations_test.go)
  counts two existing users with different roles and no required enrollment. It
  confirms that issuing or beginning an invitation does not create another user.
- `TestPostgresCompetingInvitations` in the same file verifies the final count
  after competing enrollments.
- [`TestPostgresBootstrapRetryAndRace`](../../access-gateway/internal/app/registration_test.go)
  verifies zero users after bootstrap begin and one winning bootstrap enrollment.
- [`bootstrap_test.go`](../../access-gateway/internal/app/bootstrap_test.go)
  covers the separate locked initialization/enrollment behavior that must remain
  intact. The full suite also exercises disabled-account and HTTP behavior.

From `access-gateway/`, run `go build ./...`, `go vet ./...`, and `go test ./...`.
Run the integration suite with disposable loopback `TEST_DATABASE_URL` and
`TEST_REDIS_URL` set; without both, PostgreSQL tests skip and do not establish the
counting acceptance criteria. Run `go test -race ./...` with those same disposable
backends as required by the gateway verification workflow. Do not use production
backends.

Acceptance means the existing assertions still pass, the count has no account
status or passkey filter, and `countUsers` no longer loads a slice of users. No
benchmark harness or new mock repository is justified for this change.

## Compatibility, rollout, and limits

There is no migration or API change. Old and new gateway replicas can coexist;
they read the same rows and use the same bootstrap/enrollment coordination.
Normal component release and image publication rules apply if this is later
shipped; publishing or deployment is outside this planning task. Rollback is a
normal binary rollback with no data conversion.

Do not expand this work into an `EXISTS` API, a cached account count, account-table
index changes, unrelated helper deletion, or an ORM refactor. The material risk
would be accidentally filtering disabled or unenrolled accounts and reopening
bootstrap; the selected unfiltered aggregate avoids that behavior.

This plan was checked against the current callers, model, dependency API, and
tests. No service tests were run for this documentation-only task.
