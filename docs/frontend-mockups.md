# Frontend design mockups

## Gateway account identity proposal

The updated [light overview](../access-gateway/docs/mockups/index.html) and
[dark overview](../access-gateway/docs/mockups/dark/index.html) show the signed-in
username beside Files' shield icon in the upper-right header, with the
**Administrator** badge on the same line. Regular users omit the role badge.
The full-width account strip is
removed; **Sign out** sits below the sidebar navigation and remains visible on
mobile. Devices and enrollment begin on the same row, with consistent panel
spacing and aligned header/workspace frames.

Review the [dark desktop screenshot](../access-gateway/docs/mockups/dark/index-desktop.png)
or [dark mobile screenshot](../access-gateway/docs/mockups/dark/index-mobile.png).
The [gateway screen guide](../access-gateway/docs/mockups/README.md#account-identity-and-alignment-proposal)
links both themes and records verification. Chromium passed 10 layout cases
across both themes and 320/390/768/1440/1920 pixels, plus simulated HTMX actions,
keyboard focus, navigation, theme switching and sign-out destinations. No browser,
CSP or network errors occurred; screenshots were visually reviewed. This is a
record of the mockup checks; production implementation is described below.
The shield/inline-badge follow-up repeated the checks and refreshed screenshots,
also checking unbadged regular-user and long-username header variants in-browser.

Gateway, Files and Notes now implement the
[shared account header](brand/README.md#signed-in-account-header): the same shield,
gateway-linked username and inline administrator-only badge, using identical
local `account-header.css` copies. The frontend and new-app skills and parent
AGENTS.md preserve the pattern for future authenticated services. Files/Notes
resolve the browser destination from the public discovery issuer, with the
documented cloud-home convention in legacy proxy mode. No new runtime setting is
needed. Gateway moves sign-out into its sidebar, removes the old account card,
aligns devices with enrollment and places Refresh in the devices heading.
State fragments update the header through HTMX out-of-band swaps.

Implementation checks passed `go build ./...`, `go vet ./...`, `go test ./...`
and `go test -race ./...` in all three modules. PostgreSQL/Redis integration
tests skipped because TEST_DATABASE_URL/TEST_REDIS_URL were unset; local fixture
and signed-identity tests ran. Regression coverage includes escaped usernames,
signed-role badges, forged legacy-role headers, public account destinations,
expired verification keys and full-page/fragment header ownership.
Chromium checked 130 production-template layouts: both themes at
320/390/768/1440/1920 pixels, all three services with admin/member/long-username
identities, Gateway login/bootstrap/enrollment and Files public shares. Computed
account styles matched across services. Real anchor navigation, keyboard focus,
Gateway sign-out/sign-in, role changes and user-creation retargeting passed with
locally authored responses and production security headers. No page/console/CSP
errors occurred. Desktop/mobile screenshots were inspected visually. The updated
mockups passed another 10 layout cases and their simulated interactions.
The temporary browser harnesses were removed. Skill validation, synchronized
asset/helper comparisons and whitespace checks passed. No live passkey, storage,
publication or deployment acceptance was performed.

## Files rename and move concept

The [light file-actions preview](../files/docs/mockups/file-actions.html) and
[dark counterpart](../files/docs/mockups/dark/file-actions.html) explore icon
actions with hover/focus tooltips, file renaming, and a native Move dialog with
a collapsible folder hierarchy. The picker offers only the active root and its
descendants, prevents a move into the current folder, and supports inline
subfolder creation under the selected destination. Moving between roots is
unsupported. Conflict fixtures retain drafts; a read-only variant hides writes.

Review the [browser](../files/docs/mockups/file-actions-desktop.png),
[move picker](../files/docs/mockups/file-move-desktop.png),
[subfolder creation](../files/docs/mockups/file-move-create-desktop.png), and
[rename dialog](../files/docs/mockups/file-rename-desktop.png).
See the [Files screen guide](../files/docs/mockups/README.md#file-actions-rename-and-move)
for interactions and mobile/dark screenshots. The concept continues to use
browser-only sample changes and local HTMX fragments.

Chromium checked both themes, writable/read-only variants and 320/390/768/1440
pixel widths, including rename/move, folder creation, conflicts, invalid and
duplicate names, keyboard tooltips, focus, cancellation and theme navigation.
Screenshots were visually reviewed. Local-reference and whitespace checks passed;
no unexpected requests or browser/CSP errors were observed. No service Go checks,
live storage/auth/Cast acceptance, publication or deployment ran for this concept.

Files now implements the reviewed icon actions and file Rename/Move dialogs,
including lazy root-scoped folder branches and inline subfolder creation. Real
operations use the mapped rclone S3/crypt handle, reject existing destinations,
and lock both physical paths on one PostgreSQL session before rechecking current
access and revisions. Copy completes before source removal; partial completion
is reported. Read-only and public-share write restrictions remain enforced.
The [Files reference](../files/docs/reference.md#renaming-and-moving-files)
documents routes, path-bound shares and copy/delete limitations.

Implementation verification passed Files `go build ./...`, `go vet ./...`,
`go test ./...` and `go test -race ./...`, with disposable loopback PostgreSQL
and in-memory S3 fixtures. Chromium exercised real handlers/storage for plain and
encrypted directories in light/dark at 320, 390, 768 and 1440 pixels: 32 writable/
read-only layout cases plus two public-share checks. Rename conflicts, retained
drafts, simulated network-error feedback, lazy trees, duplicate-folder feedback,
folder creation, moves, confirmation dialogs, focus, tooltips and desktop/mobile
input sizing passed. Rendered screenshots were visually reviewed; no unexpected
browser/CSP errors occurred. The maintained audio and Cast browser runners also
passed; Cast used SDK stubs. The temporary acceptance harness was removed before
the complete test/race runs. Parent/component whitespace checks passed. No live
gateway session, production storage, Cast hardware, publication or deployment
was used.

The Share/Cast icon refinement uses a symmetric three-node Share symbol and a
Cast screen with a cutout around its broadcast waves. Production and all Files
mockup copies match, and affected screenshots were refreshed. Chromium covered
24 mockup and 24 production layout cases across light/dark and four widths,
including tooltip checks. Build, vet, full tests and race tests passed; database
integration skipped for this icon-only pass with `TEST_DATABASE_URL` unset.

## Shared S3 connections

The new [Files admin preview](../files/docs/mockups/shared-connections-admin.html)
and [Notes admin preview](../notes/docs/mockups/shared-connections-admin.html)
explore shared connections alongside the implemented forms. Each has a regular-user
counterpart, a matching dark page and interactive native dialogs. Serve this
checkout over loopback HTTP as described below. Preview links switch roles,
themes and services while preserving the current concept.

Admins get a **Shared** switch only at creation, initially off; edits display
its fixed state. Shared connections reveal a separate **Add user ID as a prefix**
switch. Cards and mapping previews show both path modes. Admins manage shared
connections; users can use them without seeing credentials and continue to
manage their own personal connections. Files and Notes records remain separate.

The implemented path order is bucket, optional gateway UUID, then the user's mapping
prefix. The prefix option is admin-editable only while no user has an attached mapping;
existing S3 objects are not moved. Sharing the connection does not share mapping
settings, although prefix-off mappings to the same location access the same objects.
These pages use static sample fragments and do not change production behavior.

Review screenshots: [Files list](../files/docs/mockups/shared-connections-admin-desktop.png),
[Files add](../files/docs/mockups/shared-connection-add-desktop.png),
[Notes list](../notes/docs/mockups/shared-connections-admin-desktop.png),
[Notes user view](../notes/docs/mockups/shared-connections-member-desktop.png),
[Notes dark add](../notes/docs/mockups/dark/shared-connection-add-desktop.png).

Verification: Chromium covered 32 combinations across both services, themes and
roles at 320, 390, 768 and 1440 pixels. Each case exercised Add/Edit, the default
and immutable sharing states, conditional prefix controls, both mapping paths,
error-draft retention, blank stored credentials, Cancel/Close/Escape, focus return,
simulated saves and theme round trips. No browser errors, failed responses,
external requests, writes or transmitted draft values were observed. Static
checks covered all 52 pages/fragments, relative links, matching theme fixtures
and matching shared scripts/styles. Desktop/mobile screenshots were captured
and visually inspected. A focused follow-up checks the attached-prefix lock in 16 service/theme/viewport
combinations and refreshes edit screenshots. Git whitespace checks passed in parent, Files and Notes.
The initial mockup pass changed no production code/assets and ran no Go checks
or live S3/auth acceptance. Implementation validation is recorded below. Nothing
was pushed or deployed.

The separate [Razzie Cloud landing page](../landing/README.md) introduces
the project at `razzie.cloud` and links to GitHub, Files, and the gateway.
Its [light](../landing/previews/desktop-light.png) and
[dark](../landing/previews/desktop-dark.png) screenshots show the public
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
- [Gateway: administrator access denied](../access-gateway/docs/mockups/admin-denied-desktop.png)
- [Notes: note library](../notes/docs/mockups/index-desktop.png)
- [Notes: Markdown editor](../notes/docs/mockups/edit-desktop.png)
- [Files: storage connections](../files/docs/mockups/connections-desktop.png)
- [Files: edit connection dialog](../files/docs/mockups/connections-edit-desktop.png)
- [Notes: storage settings](../notes/docs/mockups/storage-desktop.png)
- [Notes: edit connection dialog](../notes/docs/mockups/storage-edit-desktop.png)
- [Notes: notebooks](../notes/docs/mockups/notebooks-desktop.png)
- [Notes: first notebook](../notes/docs/mockups/notebooks-empty-desktop.png)
- [Notes: edit notebook dialog](../notes/docs/mockups/notebooks-edit-desktop.png)

Dark versions are also available:

- [Files: directory overview](../files/docs/mockups/dark/index-desktop.png)
- [Files: nested file browser](../files/docs/mockups/dark/browse-desktop.png)
- [Gateway: account management](../access-gateway/docs/mockups/dark/index-desktop.png)
- [Gateway: passkey sign-in](../access-gateway/docs/mockups/dark/login-desktop.png)
- [Gateway: administrator access denied](../access-gateway/docs/mockups/dark/admin-denied-desktop.png)
- [Notes: note library](../notes/docs/mockups/dark/index-desktop.png)
- [Notes: Markdown editor](../notes/docs/mockups/dark/edit-desktop.png)

Every mockup screen has a corresponding dark desktop image; the service screen
guides below link the complete sets. The preview bar switches between light and
dark versions of the current screen. Dark presentation is scoped to the mockups.

For clickable previews, run this from the **Razzie Cloud parent checkout**:

```sh
go run scripts/serve.go
```

Then visit:

- [Files](http://127.0.0.1:8765/files/docs/mockups/index.html)
- [Gateway](http://127.0.0.1:8765/access-gateway/docs/mockups/index.html)
- [Gateway sign-in](http://127.0.0.1:8765/access-gateway/docs/mockups/login.html)
- [Gateway admin access denied](http://127.0.0.1:8765/access-gateway/docs/mockups/admin-denied.html)
- [Notes](http://127.0.0.1:8765/notes/docs/mockups/index.html)
- [Files storage settings](http://127.0.0.1:8765/files/docs/mockups/connections.html)
- [Notes storage settings](http://127.0.0.1:8765/notes/docs/mockups/storage.html)
- [Notes notebooks](http://127.0.0.1:8765/notes/docs/mockups/notebooks.html)
- [Notes first notebook](http://127.0.0.1:8765/notes/docs/mockups/notebooks-empty.html)

The preview banner links between services. Use HTTP rather than opening HTML as
`file://` so HTMX can fetch the sample fragments. Stop the server with Ctrl+C.

The storage previews have **No connections** links for reviewing inline first-use
forms, plus same-screen theme switches. Existing connections show Add/Edit dialogs
with prefilled public settings and blank credentials. Cancel and Escape return
focus; sample saves close the dialog and show feedback. Error fixtures retain
the draft. Entered values are never sent or persisted. Notes gives notebook
mappings their own **Notebooks** sidebar page: existing cards with Add/Edit dialogs,
or an inline first-notebook form. **Connections** stays on its separate page.
The mockup does not change production settings.

## Files

The directory overview gives each bucket/prefix mapping a compact card. The file
browser uses a stable directory sidebar, a breadcrumb above the title, a readable
table, and a contextual detail/upload column. Sharing has a focused form with
guidance beside it. Storage settings show connection cards and an Add connection
button; Add/Edit fetch forms into a native HTML5 dialog. The first connection
form stays inline when no connections exist. The recipient view has a simpler shell
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

The administrator-access denial concept uses a centered branded 403 panel with
cloud-home and account-management exits. Both themes use absolute asset and
navigation URLs so the page can be displayed on a protected app hostname.
Its assets target the documented loopback preview server; the two exit links
target the public cloud and gateway. Chromium checks covered both themes and
four widths on two origins, including a simulated HTTP 403 response, plus keyboard
focus, theme navigation and locally intercepted exit links. See the gateway screen
guide for previews, desktop/mobile screenshots and implementation URL/CSP notes.
The reviewed page is now implemented in the gateway's forward-auth admin denial.
It preserves HTTP 403, live role checks and the existing SSO flow, uses configured
absolute asset/navigation URLs, and applies an error-response-only CSP that
permits gateway styles/images while disabling scripts. Previews remain static
fixtures; the production page follows the browser's color-scheme preference.

Implementation verification passed gateway `go build ./...`, `go vet ./...`,
`go test ./...` and `go test -race ./...`, with newly initialized disposable
loopback PostgreSQL/Redis backends. A temporary browser harness exercised the
real admin check, session storage, renderer and middleware behind a loopback
proxy stand-in. Chromium checked both themes at 320, 390, 768 and 1440 pixels,
including different page/asset hostnames, absolute references, HTTP 403, CSP,
loaded assets, headings, overflow, keyboard focus and locally intercepted exit
links. No page/CSP errors or unexpected failed requests/responses were observed;
desktop/mobile screenshots were visually reviewed. No live deployment, physical
passkeys or production backends were used.

The gateway now shares that layout across browser-facing authorization,
sign-in/callback, API, request-protection, rate-limit, method and static-asset
errors. Status-specific copy uses the same centered logo, badge and exits.
`Accept` preferences select JSON or HTML; unqualified JSON-body requests retain
JSON errors, and gateway HTMX forms keep inline error fragments and drafts.
See [the response contract](../access-gateway/docs/reference.md#error-responses).
Build, vet, full tests and race tests passed with disposable loopback
PostgreSQL/Redis. Chromium covered 104 light/dark layout cases, including different
page/asset hostnames, keyboard and absolute-link checks, real HTMX validation,
429 fragment handling with retained drafts, the passkey bridge's explicit JSON
requests, and a real admin denial negotiated as JSON. No browser/CSP errors or
unexpected failed asset loads occurred; representative screenshots were visually
reviewed. Only temporary local fixtures were used for synthetic status variants.

See the [Gateway screen guide](../access-gateway/docs/mockups/README.md).

## Notes

Notes has its own submodule and self-contained design mockups.
Screens cover the library, reading, editing, creating a note, tag collections,
tag filtering, first use, and separate connection/notebook settings with
existing/empty states.
Both themes follow the
existing service shell, controls, colors, logo, and spacing. The editor places
Markdown beside a fixed rendered example and keeps attachments below the draft.
Local downloads, sample search, attachment removal/upload fixtures, and save/failure
states make the concept reviewable without backend access. Changes are not saved.

The notebook concept mirrors connection setup: cards and an Add button when
notebooks exist, an inline form for the first notebook, and native Add/Edit dialogs.
Cards show storage location, effective access and encryption. Edit changes only
name and read-only policy; location and encryption are fixed. Add includes the
current rclone crypt controls. Errors retain drafts; successful simulations return
fixed sample cards. The empty notebook fixture has existing connections.

See the [Notes screen guide](../notes/docs/mockups/README.md) and
[implemented architecture](../notes/docs/architecture.md). The live Go service
uses a separate PicoCSS/HTMX interface with user-managed connections, optional
rclone encryption, notebook selection, explicit conditional saves,
S3 authority, PostgreSQL search and River reconciliation. Compose and Swarm route
it through the gateway; the static mockups remain broader design references.

## Implementation boundaries

These are design artifacts with sample data. Forms fetch static HTML fragments
through the existing vendored HTMX; they never call service APIs. No passkey,
share, upload, account, or storage connection is created. A small external script
opens/closes native storage dialogs and restores focus. No external assets,
frontend build step, or dependency installation is needed.
The CSP disables inline scripts/styles and HTMX evaluation/history snapshots.

The concepts show layout and interaction patterns rather than exhaustive forms:
bootstrap, advanced crypt compatibility, recovery, failure states, media preview,
and Cast. The production templates retain the existing forms and integration hooks
for those features; this change adds no recovery flow.
Directory descriptions are illustrative copy, not an existing persisted field.
Counters are sample record counts, not storage usage or quota estimates.

## Verification

The separate Notes notebook-page concept passed 88 Chromium layout checks:
22 full pages across both themes and widths of 320, 390, 768 and 1440 pixels.
Notebook empty/populated interactions covered inline first setup, native Add/Edit
dialogs, keyboard focus/return, Cancel/Close/Escape, immutable edit location,
read-only connection policy, optional crypt controls, retained error drafts,
and static saves. Theme/sidebar navigation and connection dialogs also passed.
No entered settings/passwords appeared in requests, and no browser errors or
failed requests were observed. Local links, unique IDs, theme fixture parity
and Git whitespace checks passed. Desktop/mobile screenshots were refreshed and
inspected visually. This revision changes mockups and documentation only; it
does not run Go checks, connect to storage or change the live application.

The storage-dialog concept was checked separately in Chromium: Files and Notes,
both themes, existing/empty connection states, and widths of 320, 390, 768 and
1440 pixels (32 layout cases). Add/Edit, focus containment/return, Escape,
Close/Cancel, public-settings prefill, blank credentials, validation, retained
error drafts, simulated saves and theme round trips passed. Bucket/removal and
notebook fixtures also passed. Requests contained no entered credential values;
no console/page errors or failed responses were observed. Local references,
unique IDs, synchronized dialog assets and Git whitespace checks passed.
List, empty and desktop/mobile edit screenshots were saved for both services
and themes and inspected visually. No production code/assets changed, so Go
checks and live backend acceptance were not run for this concept.

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

Notes now implements the reviewed separate Notebooks page: existing notebook
cards with Add/Edit dialogs, an inline first-notebook form, and connection setup
guidance when no provider exists. Cards include effective access, encryption and
crypt recovery downloads. Real saves refresh the notebook list; safe errors
retain browser drafts. Full-page fallbacks, legacy edit links, immutable location
and crypt settings, revisions and owner scoping are retained. The mockups remain
independent sample-data artifacts.

Files and Notes now use the reviewed storage connection cards and native HTML5
Add/Edit dialogs. HTMX loads the shared production form and refreshes settings
after saves. Empty storage keeps its first form inline; direct Add/Edit links
retain full-page fallback forms. Error fragments preserve browser drafts without
echoing submitted or saved credentials. Notes keeps its notebook, recovery,
conditional-write and encryption controls, including initialization after swaps.
Attached notebooks lock connection location controls while submitting the saved
values. Both services retain owner scoping, revision checks and existing POST
routes. Local chevrons and HTMX settling without style attributes preserve CSP.

Implementation verification ran `gofmt`, `go build ./...`, `go vet ./...`,
`go test ./... -skip '^TestConnectionBrowserHarness$'` and
`go test -race ./... -skip '^TestConnectionBrowserHarness$'` in both modules.
Only the temporary live-browser harness was excluded from the suites, then removed.
Tests used a newly initialized loopback PostgreSQL database with isolated schemas
and in-memory S3 fixtures. Regression coverage includes inline/list/fallback and
fragment states, escaped metadata, blank credential rendering, owner isolation,
credential retention, revision conflicts, location locks and error retargeting.
Chromium exercised the real handlers for both services in light/dark at 320, 390,
768 and 1440 pixels, covering 32 empty/populated layout cases with real connection
creates, updates and removals. Focus/cleanup, Add/Edit, validation/retry, retained
network-failure drafts, full-page fallback and Notes encryption initialization
after swaps passed. The final pass had no page or CSP errors. Production
screenshots were inspected visually; mockup screenshots remain separate examples.
No production storage, gateway authentication, Cast hardware or deployment was used.

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

## Shared connection implementation

Files and Notes now implement personal and administrator-managed shared S3
connections. Admin controls use the gateway's verified signed `admin` claim;
unsigned headers and legacy proxy mode cannot grant administrative authority.
Shared status is immutable in handlers, repositories and SQL. Shared-only UUID
prefixing uses the mapping owner, outside optional crypt, and cannot change while
any user's mappings are attached. Regular users can use shared connections and
continue managing their personal connections. Public Files share credential
resolution and Notes recovery/policy invalidation preserve the right owner scope.

Verification used disposable loopback PostgreSQL and in-memory S3: both modules
passed `go build ./...`, `go vet ./...`, `go test ./...` and their race suites.
Race commands were `go test -race ./... -skip '^TestSharedBrowserHarness$'`.
Only that temporary browser harness was excluded; it ran separately for browser
checks and was then removed. Final `go test ./...` included every maintained
test, followed by `go test -race ./internal/app -run '^TestShared'` to cover
the added shared-prefix/mapping concurrency regression. Tests cover
signed role checks/demotion, forged headers, immutable sharing, cross-user
mapping and recovery isolation, actual plain/crypt physical roots, prefix-off
shared objects, read-only changes and Notes validator invalidation for all owners.

Chromium checked 64 production layouts across both services, themes, roles and
320/390/768/1440-pixel widths. Real Add/Edit, conditional switches after swaps,
blank stored credentials, validation/retry with retained drafts, save focus,
connection creation, mapping creation and effective user paths passed. There
were no unexpected browser/CSP errors or failed responses; rendered screenshots
were inspected visually. Authentication used local signed assertions with real
verification, rather than a live gateway session. No production S3 or deployment
was used. Parent/component whitespace checks passed. Nothing was published or
deployed.

The Sharing block's divider now sits below its controls, separating sharing
from Name and provider settings. Files/Notes production forms and static
previews match. Verification covered 96 rendered production/mockup dialog
cases: both services, light/dark, 320/390/768/1440 pixels, and new/personal/shared
connections. Add/Edit screenshots were refreshed. Both modules passed
`go build ./...`, `go vet ./...`, `go test ./...` and `go test -race ./...`.
Database integration tests skipped because `TEST_DATABASE_URL` was unset for
this styling-only follow-up; loopback fixture tests ran. No live services were
restarted or deployed.

## Connection actions, fixed buckets and addressing defaults

Files and Notes now offer **Use connection** on personal and shared cards. The
selected connection is preselected in mapping setup. **Fixed bucket (optional)**
restricts mappings to one bucket, prefilled and read-only in the browser. Switching
back to an unrestricted connection restores the user's draft bucket. The server
resolves omitted buckets and rejects explicit overrides before S3 access; storage
constructors and locking database triggers enforce the same restriction. Applying
or changing a restriction must remain compatible with every user's existing
mappings. Clearing it preserves saved mapping buckets. New connection forms and
SQL defaults use virtual-hosted addressing; existing path-style choices remain
unchanged and the switch stays available for compatible providers/local fixtures.

The previews include a fixed Cloud storage bucket, unrestricted Team archive,
and personal Use actions. Both themes' connection lists, empty forms and Add/Edit
screenshots were refreshed. Production also loads local Pico icon overrides before
Pico so initial rendering respects the unchanged strict image CSP.

Verification used disposable loopback PostgreSQL and in-memory S3. Both modules
passed build, vet, full tests and race tests. New regression coverage checks
personal/shared creation defaults, fixed-bucket persistence and mapping prefill,
HTTP/repository/storage/SQL override rejection, compatible/incompatible restriction
updates, and updates racing with another user's mapping creation. Notes now
propagates connection-update constraint errors as conflicts, retaining drafts.
Chromium covered 96 production layouts (lists plus fixed and personal mapping
forms) across both services, themes, roles and 320/390/768/1440 widths, including
real creates, retained validation drafts, connection switching and forged submits.
Static previews passed 64 layout cases at those widths, with all Use actions,
optional/fixed forms, empty states and draft retention; entered values never
appeared in requests. Screenshots were inspected visually. Temporary browser
harnesses were removed. No live Docker services, production S3 or deployment was
used.
