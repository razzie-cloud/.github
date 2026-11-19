# Razzie Cloud identity

The display name is **Razzie Cloud**. Use that spelling in page titles, headers,
documentation, and passkey relying-party display names.

![Razzie Cloud logo](razzie-cloud-logo.png)

`razzie-cloud-logo.png` is the user-maintained full-size artwork.
`razzie-cloud-logo-small.png` is the supplied 256×196 image used for service
header logos. `razzie-cloud-logo-favicon.png` is the separate square 256×256 image
used only for favicons. Landing's large central artwork uses the full-size
`razzie-cloud-logo.png`. The current mark
combines the smiling gold cloud with navy detailing and an integrated R.
Preserve the supplied image and its aspect ratio when displaying it.

Exact copies of `razzie-cloud-logo-small.png` are kept at these paths in the parent checkout
(Gateway, Files and Notes retain the local filename `razzie-cloud-logo.png`):

- `access-gateway/internal/web/static/razzie-cloud-logo.png`
- `files/internal/web/static/razzie-cloud-logo.png`
- `notes/docs/mockups/assets/razzie-cloud-logo.png` (static mockups)
- `notes/internal/web/static/razzie-cloud-logo.png`
- `landing/assets/razzie-cloud-logo-small.png`

Landing also keeps an exact copy of the full-size artwork at
`landing/assets/razzie-cloud-logo.png` for its central logo and social preview.
Each directory listed above also keeps an exact copy of
`razzie-cloud-logo-favicon.png`; all production and mockup favicon links use it.
Existing logo boxes use `object-fit: contain` to preserve the artwork's aspect
ratio and the header's alignment.
Header logos and Landing's central artwork render at 80% scale within their
existing layout boxes, compensating for the supplied artwork's tighter crop.

The service headers, favicons, and HTML mockups use the service-local assets;
the landing page and Notes mockups use their own asset copies. Root and profile
documentation reference the full-size artwork directly. Refresh the corresponding
active copies and saved preview screenshots when a supplied image changes.

Mockup buttons use navy; warm gold distinguishes the active navigation item.
Green badges continue to represent statuses such as writable access.

Existing machine identifiers retain their current spelling: repository URLs,
module imports, cookie/session namespaces, database names, Docker context/project
names, bucket names, and hostnames. Changing those would require separate
compatibility and infrastructure migrations.

## Files and Notes terminology

Call saved S3 provider settings a **connection** in navigation, forms, help,
errors and documentation. A connection holds the provider, endpoint, credentials
and access policy; directories in Files and notebooks in Notes use it to select
a bucket and prefix. Use **storage** for the data, provider or physical location,
rather than as another name for a connection.

## Signed-in account header

Access Gateway, Files, Notes, authenticated Home and future authenticated Razzie Cloud services use
the same upper-right account control: the existing 20px shield/check line icon,
the bold username linking to Access Gateway's public account page, then a green
**Administrator** badge on the same line only for administrators. Regular users
have no role badge. Keep the shield and username visible on mobile; truncate
long usernames within the available space rather than widening the page.
Use the shared spacing, sizes, colors and focus treatment from
[`account-header.css`](../../access-gateway/internal/web/static/account-header.css).
The Files/Notes/Landing copies must remain identical. Use the existing local SVG, PicoCSS
and escaped Go templates; keep each independently deployable service's assets local.

The identity markup is `.identity` containing the shield and `.identity-copy`;
the latter contains `.account-link > strong` and the optional `.badge.green`.
The username link has `title="Manage your account"`, with the full username as
the strong element's title. The identity container has `aria-label="Signed-in account"`.
Settings links belong in app navigation. Sign out belongs in Gateway's sidebar,
with the note that connected apps are also signed out. Do not add app-local
sign-out controls or duplicate the identity in a full-width account card.

Gateway uses its configured public `ORIGIN` for the account link. Files/Notes
use the public issuer pinned by gateway key discovery, never the private
`ACCESS_GATEWAY_URL` or incoming Host/forwarded headers. Their independent
`gatewayidentity.AccountURL` helpers remain synchronized. Legacy proxy mode
uses `auth.<LANDING_ORIGIN host>` with the same scheme/port; invalid or IP-only
cloud-home settings fall back to `https://auth.razzie.cloud/`.
The administrator badge uses the current database role in Gateway and the
verified signed admin claim in consuming apps; unsigned role headers grant none.
Public share and anonymous shells omit the signed-in identity. Gateway account
state fragments refresh the header with an HTMX out-of-band swap on sign-in,
sign-out and account-state updates; full pages have only one header target.

## Verification

The current logo refresh passed:

- Byte comparison of all five small-image copies against
  `razzie-cloud-logo-small.png`, all five favicon copies against
  `razzie-cloud-logo-favicon.png`, and Landing's large copy against the full-size
  `razzie-cloud-logo.png`. All 72 relative mockup favicon links resolve.
- Chromium checks of rendered Gateway, Files, Notes, public Landing and Home
  templates in light/dark at 320, 390, 768 and 1440 pixels (40 cases). Header
  logos loaded at 256×196, separate favicons at 256×256 and Landing's central
  artwork at 1200×850, with no stretching, horizontal overflow or browser errors.
  Representative temporary screenshots were visually inspected.
- The 80% scale passed those 40 production layouts, including image replacement,
  plus 12 light/dark mobile/desktop mockup layouts. Existing layout boxes and
  Landing's artwork rotation are preserved.
- `go build ./...` and `go vet ./...` in all four UI modules, `go test ./...`
  in Gateway/Files/Notes, and `go test -race ./...` in all four.
- Git whitespace checks in the parent and all submodules.

Checks ran outside the sandbox to allow the Go cache and local fixture sockets.
Browser checks used temporary production-template fixtures, without live SSO or
storage. Historical mockup screenshots were not regenerated. Docker builds were
not run because daemon access was unavailable. Nothing was deployed.
