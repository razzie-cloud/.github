# Audit remediation designs — 19 November 2026

These four audit findings were implemented sequentially, with one subagent per
change and completed component commits before the next change began. The original
designs remain here; implementation belongs in the owning submodules.

| Audit item | Plan | Owning service | Implementation commit |
| --- | --- | --- | --- |
| 1 | [Shared Notes write coordination](2026-11-19-audit-1-shared-notes-writes.md) | Notes | `95fdea0` |
| 2 | [PostgreSQL instance-name limits](2026-11-19-audit-2-postgres-instance-names.md) | Database Broker | `e257f8e` |
| 3 | [Native form origins](2026-11-19-audit-3-native-form-origins.md) | Files and Access Gateway | Files `92c5a6c`, Gateway `9b1adb2` |
| 4 | [Account counting](2026-11-19-audit-4-account-counting.md) | Access Gateway | `19da5b3` |

Each plan records its selected design, affected code, implementation steps,
acceptance checks, compatibility, and limits. The validation below records checks
run during implementation; the plans' earlier audit evidence is separate.

## Validation

- In Notes, Database Broker, Files and Access Gateway: `go build ./...`,
  `go vet ./...`, `go test ./...`, and `go test -race ./...` passed. Gateway ran
  these checks again after item 4. Changed Go files were formatted and diff
  whitespace checks passed.
- Notes, Files and Gateway integration tests used explicitly configured
  disposable loopback PostgreSQL; Gateway also used disposable Valkey. Broker's
  complete adapter suites ran with local disposable PostgreSQL, Dragonfly and
  Valkey testcontainers. Owned fixtures were removed after verification.
- Files' native-form, panel-navigation and share-list Chromium tests passed as a
  regular batch. The new native-form test also passed under the race detector,
  observing real browser Origin headers, redirects, cookies and cross-origin
  referrer suppression. The share-list fixture now waits for the public HTMX
  processing event after history navigation without weakening its assertions.
- All 18 Gateway passkey bridge scenarios passed. A temporary native activity
  acceptance check used the real handler with PostgreSQL and Valkey, verified
  the browser-generated Origin, removed the unrelated session and retained the
  current session. Temporary acceptance files were removed.

An optional combined Files race/all-browser run hit the existing panel-navigation
execution-context timing failure at `navigation_browser_test.go:177`. Its regular
browser run passed, as did the full backend race suite and focused native browser
race test. No data race was reported; the broader browser timing limitation
remains separate from the completed production fixes.

## Release boundary

Notes requires stopping and draining all old HTTP processes and River workers
before migration, then starting only new replicas and reloading compatibility-mode
editors. Its plan and architecture guide describe rollback under the same
quiescence requirement. Independent connection records and external S3 writers
remain outside Notes' physical-object coordination.

Component commits and parent pointer updates are local. Nothing was pushed,
published or deployed; no live Swarm, host or real cloud storage acceptance ran.
