# Razzie Cloud identity

The display name is **Razzie Cloud**. Use that spelling in page titles, headers,
documentation, and passkey relying-party display names.

![Razzie Cloud logo](razzie-cloud-logo.png)

`razzie-cloud-logo.png` is the user-maintained source of truth. The current mark
combines the smiling gold cloud with navy detailing and an integrated R.
Preserve the supplied image and its aspect ratio when displaying it.

Exact copies are kept at these paths in the parent checkout:

- `access-gateway/internal/web/static/razzie-cloud-logo.png`
- `files/internal/web/static/razzie-cloud-logo.png`
- `notes/docs/mockups/assets/razzie-cloud-logo.png` (static mockups)
- `notes/internal/web/static/razzie-cloud-logo.png`
- `landing/assets/razzie-cloud-logo.png`

The service headers, favicons, and HTML mockups use the service-local assets;
the landing page and Notes mockups use their own asset copies. Root and profile documentation reference
the master directly. Refresh all active copies and saved preview screenshots when
the master changes. The old image is retained separately as
`razzie-cloud-logo-old.png`; it is not an active application asset.

Mockup buttons use navy; warm gold distinguishes the active navigation item.
Green badges continue to represent statuses such as writable access.

Existing machine identifiers retain their current spelling: repository URLs,
module imports, cookie/session namespaces, database names, Docker context/project
names, bucket names, and hostnames. Changing those would require separate
compatibility and infrastructure migrations.

## Verification

The current logo refresh passed:

- SHA-256 comparison of all three active copies against the master; the old backup
  remains unchanged.
- Browser checks of 24 service mockup pages and four landing-page theme/viewport
  combinations, verifying the new image loads and retains its aspect ratio.
- Refresh of all 20 saved mockup and landing-page screenshots, with no browser errors.
- `go build ./...`, `go vet ./...`, and `go test ./...` in both service modules,
  plus `go test -race ./...` in Files.
- Removal of the obsolete prompt and its references, and Git whitespace checks.

Go used a temporary writable build cache. PostgreSQL/Redis integration variables
were unset, so those integration tests skipped. Nothing was deployed.
