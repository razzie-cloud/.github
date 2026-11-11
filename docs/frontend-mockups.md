# Frontend design mockups

The separate [Razzie Cloud landing page](../infra/landing/README.md) introduces
the project at `razzie.cloud` and links to GitHub, Files, and the gateway.
Its [light](../infra/landing/previews/desktop-light.png) and
[dark](../infra/landing/previews/desktop-dark.png) screenshots show the public
homepage design. Both stacks now include a static landing service: locally at
`http://localhost:8080` and in Swarm at `https://razzie.cloud` after deployment.

Local, interactive concepts for the existing embedded PicoCSS and HTMX frontends.
Each service owns its mockups under `docs/mockups/`. The reviewed layout and
automatic light/dark palettes are now implemented in Files' and the gateway's embedded
templates and stylesheet. The mockups remain separate sample-data design artifacts.
Authentication and storage behavior are unchanged.

The shared direction uses a pale slate canvas, white panels, navy
actions and warm gold navigation accents, small line icons, and consistent spacing. Desktop layouts put navigation
on the left and contextual forms beside the main content. On smaller screens,
navigation wraps and the columns stack.

## Review without running the services

Open the screenshots directly:

- [Files: directory overview](../files/docs/mockups/index-desktop.png)
- [Files: nested file browser](../files/docs/mockups/browse-desktop.png)
- [Gateway: account management](../access-gateway/docs/mockups/index-desktop.png)
- [Gateway: passkey sign-in](../access-gateway/docs/mockups/login-desktop.png)
- [Notes: note library](../notes/docs/mockups/index-desktop.png)
- [Notes: Markdown editor](../notes/docs/mockups/edit-desktop.png)

Dark versions are also available:

- [Files: directory overview](../files/docs/mockups/dark/index-desktop.png)
- [Files: nested file browser](../files/docs/mockups/dark/browse-desktop.png)
- [Gateway: account management](../access-gateway/docs/mockups/dark/index-desktop.png)
- [Gateway: passkey sign-in](../access-gateway/docs/mockups/dark/login-desktop.png)
- [Notes: note library](../notes/docs/mockups/dark/index-desktop.png)
- [Notes: Markdown editor](../notes/docs/mockups/dark/edit-desktop.png)

Every mockup screen has a corresponding dark desktop image; the service screen
guides below link the complete sets. The preview bar switches between light and
dark versions of the current screen. Dark presentation is scoped to the mockups.

For clickable previews, run this from the **Razzie Cloud parent checkout**:

```sh
python3 -m http.server 8765 --bind 127.0.0.1
```

Then visit:

- [Files](http://127.0.0.1:8765/files/docs/mockups/index.html)
- [Gateway](http://127.0.0.1:8765/access-gateway/docs/mockups/index.html)
- [Gateway sign-in](http://127.0.0.1:8765/access-gateway/docs/mockups/login.html)
- [Notes](http://127.0.0.1:8765/notes/docs/mockups/index.html)

The preview banner links between services. Use HTTP rather than opening HTML as
`file://` so HTMX can fetch the sample fragments. Stop the server with Ctrl+C.

## Files

The directory overview gives each bucket/prefix mapping a compact card. The file
browser uses a stable directory sidebar, a breadcrumb above the title, a readable
table, and a contextual detail/upload column. Sharing and storage settings have
focused forms with guidance beside them. The recipient view has a simpler shell
and only read-only actions.

The original frontend used `aria-label="Breadcrumb"`, while Pico's vendored CSS
expects `aria-label="breadcrumb"`. The implementation uses the lowercase label and a slash divider,
following [Pico's breadcrumb documentation](https://picocss.com/docs/nav#breadcrumb).

See the [Files screen guide](../files/docs/mockups/README.md).

## Access Gateway

The account overview separates activity from enrollment and user creation. Devices
are compact rows with disclosure controls for renaming/removal; sessions and user
identifiers retain table layouts. The right column keeps enrollment available
without pushing activity far down the page. The sign-in and registration screens
use a two-column panel with one clear primary action.

See the [Gateway screen guide](../access-gateway/docs/mockups/README.md).

## Notes

Notes has its own submodule and self-contained design mockups.
Eight screens cover the library, reading, editing, creating a note, tag collections,
tag filtering, first use, and a proposed storage setup. Both themes follow the
existing service shell, controls, colors, logo, and spacing. The editor places
Markdown beside a fixed rendered example and keeps attachments below the draft.
Local downloads, sample search, attachment removal/upload fixtures, and save/failure
states make the concept reviewable without backend access. Changes are not saved.

See the [Notes screen guide](../notes/docs/mockups/README.md) and
[implemented architecture](../notes/docs/architecture.md). The live Go service
uses a separate PicoCSS/HTMX interface with user-managed connections, optional
rclone encryption, notebook selection, explicit conditional saves,
S3 authority, PostgreSQL search and River reconciliation. Compose and Swarm route
it through the gateway; the static mockups remain broader design references.

## Implementation boundaries

These are design artifacts with sample data. Forms fetch static HTML fragments
through the existing vendored HTMX; they never call service APIs. No passkey,
share, upload, account, or storage connection is created. No custom JavaScript,
external assets, frontend build step, or dependency installation is needed.
The CSP disables inline scripts/styles and HTMX evaluation/history snapshots.

The concepts show layout and interaction patterns rather than exhaustive forms:
bootstrap, advanced crypt compatibility, recovery, failure states, media preview,
and Cast. The production templates retain the existing forms and integration hooks
for those features; this change adds no recovery flow.
Directory descriptions are illustrative copy, not an existing persisted field.
Counters are sample record counts, not storage usage or quota estimates.

## Verification

The review used headless Chromium via Playwright against a loopback-only static
server. All 24 full pages (12 per theme) were checked at 1440×1050 and 390×844 for successful loads,
a single primary heading, and page-level horizontal overflow. Representative HTMX
forms and fragment swaps were exercised. Desktop screenshots were captured from
the rendered pages.

The dark pass captured all 12 desktop screens and refreshed the four existing
light screenshots. Theme switching, dark navigation between services, and HTMX
interactions were checked with no browser errors. Sampled visible dark-theme
text/control colors had contrast ratios of at least 6.68:1; this sampling is not
a full accessibility audit. No Go checks were repeated for the dark pass, since
it only changes mockup HTML/CSS, fixture links, documentation, and screenshots.

The initial mockup pass changed only design artifacts. The subsequent branding
pass also updates the embedded header/logo assets and relying-party display names.
See [the branding notes](brand/README.md) for the logo and naming policy.
Hardware passkey/Cast and production backends are not part of the mockup checks.
Nothing was pushed, published, or deployed during these checks.

## Production frontend implementation

The gateway now uses account-state navigation, a split activity/enrollment layout,
device management disclosures, and distinct login/bootstrap/enrollment panels.
Files uses a navigation shell, directory cards, breadcrumbs, contextual directory
information and upload/new-folder forms, focused settings/sharing forms, and a
separate public share shell. Both follow the browser's color-scheme preference
and keep HTMX/PicoCSS assets local, with CSP-compatible markup.

Validation for the implementation:

- `gofmt` on the new Go regression tests; `go build ./...`, `go vet ./...`, and
  `go test ./...` in both service modules, plus `go test -race ./...` in Files.
- Regression coverage for state transitions, protected activity actions,
  public/read-only UI boundaries, escaping, and navigation in HTMX fragments.
- Rendered production-template fixtures checked in Chromium: 18 page variants,
  two color schemes, and four widths (320, 390, 768, 1440 pixels), totaling 144
  layout checks. Checks included headings, overflow, and role-specific controls.
- Browser interaction checks for device controls, QR display, user creation
  retargeting, sign-out, crypt disclosure, media preview/Escape cleanup, folder
  creation, multipart upload, and validation-error rendering. Mutation responses
  used local template fixtures; the Cast SDK was stubbed.
- Git whitespace checks and comparison of the original/live form routes, field
  names, and upload/media/Cast hooks.

Go checks used a writable temporary build cache. PostgreSQL and Redis integration
variables were unset, so those integration tests skipped. Live database/auth
workflows, hardware WebAuthn, and Cast receiver acceptance were not exercised.
No changes were deployed.

The navigation follow-up aligns service headers with the centered application
frame (and the narrower public-share frame). Selected panels briefly outline
when a valid anchor targets them, including after HTMX loads the target; repeated
activation restarts the cue, and reduced motion uses a timed static outline.
Files has upload/new-folder shortcuts. The earlier default-panel fallback was
removed: bare URLs and unanchored updates do not trigger outlines. The workspace
also fills its grid column, removing the former 1400px inner cap and excess right
gutter while preserving equal horizontal padding.
Browser checks covered 72 light/dark layout cases at 390, 1440, 1920, and 2553
pixels, plus repeated/keyboard/async-fragment navigation, cleanup, reduced motion,
and registration-fragment handling under the existing CSP. Build, vet, and tests
passed for both modules, with Files race checks also passing. Database/Redis
integration variables remained unset; these browser checks used local fixtures.
