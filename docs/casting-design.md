# Google Cast support for Files

Status: implemented, 2026-11-03; hardware validation pending. The user approved
proceeding with implementation before device testing and subsequently authorized
a custom-tag image release and stack deployment. The architecture and acceptance
criteria below remain the reference; release results are tracked separately.

## Scope and decisions

Use Google's Default Media Receiver for both video and pictures. The browser
owns the slideshow and sends a separate `LOAD` for each picture. No custom
receiver, Google developer registration, FFmpeg, transcoding, remuxing, or
generated slideshow video is required by this design.

Support these entry points:

- Cast an MP4 from the authenticated directory browser.
- Cast a slideshow from the current folder, including a directory's root.
- Offer the same actions on existing public file and folder shares.
- Optionally offer a slideshow action directly on subfolder rows.

Videos are served unchanged. HEVC in MP4 is included when the receiving hardware,
codec profile, resolution, and audio track are compatible. An MP4 extension
does not guarantee playback. H.264 is the compatibility baseline; unsupported
files produce an error rather than invoking conversion. Google documents HEVC
support for Chromecast Ultra, Chromecast with Google TV, and Google TV Streamer,
with model-specific limits. See [supported media](https://developers.google.com/cast/docs/media).

Start picture support with JPEG and PNG in the selected folder only. Include
all matching entries across browser listing pages, without recursive traversal.
Use deterministic filename order initially; manual paging, timed advancement,
shuffle, and loop operate on the browser's list.

The user prefers avoiding receiver registration and server-side video generation.
Receiver-managed slideshows and FFmpeg-generated slideshows were considered and
are outside this implementation. Do not add either as an automatic fallback.

## Cast feasibility and limitations

The Default Media Receiver requires no application registration. It accepts
media URLs sent by the sender; the Cast device fetches the bytes itself. It
does not receive the browser's SSO or password-unlock cookies. See
[receiver options](https://developers.google.com/cast/docs/web_receiver).

Google documents image formats, photo metadata, and individual media loads.
Its default and styled receivers do not support an image queue. This design
uses successive individual image loads, rather than queueing images on the TV.
See [media messages](https://developers.google.com/cast/docs/media/messages),
[photo metadata](https://developers.google.com/cast/docs/reference/web_sender/chrome.cast.media.PhotoMediaMetadata),
and [queue restrictions](https://developers.google.com/cast/docs/android_sender/queueing).

Repeated image loads still need a real-device proof before committing to the
full slideshow implementation. Confirm display behavior, long holds, status
events, loading delays, and idle timeouts on the user's receiver. An SDK success
response alone does not prove that the image is visibly rendered.

Automatic advancement requires the sender page to remain active. Browser
backgrounding, phone locking, closing the tab, or suspending the computer may
delay or stop advancement. The current picture might remain displayed, but
receiver idle behavior must be tested. Ordinary video playback is independent
of the browser's slideshow timer. See Chrome's
[background timer behavior](https://developer.chrome.com/blog/timer-throttling-in-chrome-88/).

Do not promise seamless transitions, unattended playback after the browser
closes, TV-remote next/previous support, or cross-device slideshow-state recovery.

## Existing implementation to reuse

All paths below are relative to the parent repository. Service code belongs in
the `files/` Git submodule; deployment changes belong in `infra/`. This document
and coordination documentation belong in the parent. Read the applicable
`AGENTS.md` files before editing or publishing.

| Area | Current source and relevant behavior |
| --- | --- |
| Routing and middleware | `files/internal/app/app.go`: management identity, POST origin checks, CSP, no-store/referrer headers, and page deadlines |
| Shares | `files/internal/app/shares.go`: public host router, creation/revocation, password sessions, and `sharedPath` containment |
| Share persistence | `files/internal/store/shares.go`: random 256-bit share IDs, immutable scope, per-share signing key, optional expiry, owner-scoped management |
| Share cache | `files/internal/app/share_cache.go`: bounded 30-second snapshot cache, local invalidation, fail-closed refresh |
| Streaming | `serveDownload` and `parseRange` in `files/internal/app/app.go`: HEAD, single byte ranges, 206/416, streamed storage reads |
| Storage | `files/internal/storage/` and `files/internal/storage/rclone/`: guarded S3 access, rclone crypt, bounded listings, range reads |
| Browser UI | `files/internal/web/templates.html`, `static/app.js`, and `static/app.css`: embedded HTMX/PicoCSS, no frontend build pipeline |
| Configuration | `files/internal/config/config.go`: flags, environment variables, exact management/share origins, listing limits |
| Ingress | Root `Caddyfile` and `infra/docker-stack.yml`: management behind SSO; public host exposes `/s/*` and `/static/*` only |

The root folder has no dedicated listing row. Folder paths use the empty string
for the root. Browser pages show 100 entries at a time; storage listings already
have an operator-configured maximum. Build slideshow lists before presentation
pagination and retain the storage limit.

Current downloads use `application/octet-stream` and attachment disposition.
Current public GET requests other than `/download` get a 45-second context
deadline. New streaming routes need correct headers and a deliberate deadline
exception. Preserve the existing download behavior.

## User flows

### Authenticated directory browser

1. Show **Cast** alongside MP4 file actions. Show **Cast slideshow** in the
   current folder's header, so the root works without inventing a root row.
   Hide or explain availability when sharing/Cast support is unavailable.
2. Open the Cast picker from the user's click. Wait for device selection before
   creating a share; canceling the picker must create no share.
3. POST to the management origin. Validate the authenticated owner's directory,
   the selected relative path, media mode, and file/folder existence.
4. Create an ordinary, passwordless, read-only share with a mandatory deadline.
   A video share covers one file; a slideshow share covers the selected folder.
5. Return the absolute public media URL or slideshow list and its expiry.
   Start playback through the default receiver.
6. Show a controller outside HTMX's replaced `#main` region. Browsing to another
   directory must not discard the active playback state or duplicate listeners.

Casting must work for read-only storage connections and directories. Share
metadata creation is permitted for the owner and does not require S3 writes.
Never derive authorization from a writable-directory UI flag.

Use one temporary share per active casting operation. Reuse it for every picture
in that slideshow; do not create one share per timer tick. Starting another
operation supersedes the old one and cleans up only the share owned by that
operation. Keep the generated shares visible in the existing Sharing UI for
inspection and manual revocation.

### Existing public shares

Offer Cast for an MP4 file and Cast slideshow for the current folder within a
directory share, including its shared root. Never let a caller expand the
original share's scope or expiration.

Passwordless shares can authorize media requests directly. Password-protected
shares need a delegated playback capability after the visitor has unlocked the
share; the TV cannot use the browser's cookie. The public flow must not create
new database shares or expose management endpoints. It can issue a signed,
time-bounded playback ticket without modifying persisted metadata.

Stopping a public-share cast must not revoke the owner's original share.

## Authorization and lifecycle

### Temporary owner-created shares

Proposed operator setting: `CAST_SHARE_TTL` / `--cast-share-ttl`, default `6h`.
Validate a positive, bounded duration and use the same deadline on every replica.
The lifetime is set by the server, not by form input. The six-hour value is a
proposed default, not a reason to add an expiry dialog to the casting flow.

Shares remain immutable: no silent deadline extension or dependency on browser
heartbeats. Long sessions must restart after expiry. Return the deadline to the
controller so it can explain expiration rather than loop through failed images.

On explicit Stop or failed initial startup, cancel the controller's pending work,
stop the owned media session where possible, and attempt authenticated revocation
of its automatically created share. Failure to reach the receiver must not prevent
the revocation attempt. Closing a tab or losing a response is not reliable cleanup;
the deadline is the fallback. Do not revoke on ordinary HTMX navigation or on a
brief visibility change.

Expiration is checked on every public request, including cached snapshots.
Revocation invalidates locally and propagates to other replicas within the
existing 30-second cache TTL. Already-delivered bytes, displayed images, and
downloads in progress cannot be recalled. Expiry denies new requests; it does
not require a cleanup job. Expired share records currently remain visible to the
owner for removal.

Reuse standard share persistence without a schema change unless implementation
needs additional persisted semantics. A standard folder capability grants the
existing folder-share access, including descendants, non-image files, and future
contents. Filtering the slideshow list to direct-child pictures does not narrow
that underlying grant. Do not claim that an ordinary folder share is an
image-only capability. A narrower persisted share type would require a separate
design and migration.

### Delegated tickets for password-protected public shares

After checking the existing password session, mint a versioned ticket bound to
the original share ID, exact file or slideshow folder, permitted media mode, and
expiry. Its deadline is no later than the temporary-playback lifetime, the
browser's password-session deadline, or the parent share deadline.

Use a domain-separated HMAC with the persisted per-share signing key, canonical
encoding, constant-time verification, and explicit size limits. Do not reuse the
password-cookie MAC format or render the signing key. Validate scope boundaries
using existing path helpers, not string-prefix matching.

Every ticket-backed media/list request must load the original share snapshot,
check share and ticket expiry, validate the signature and scope, and then use the
persisted share owner for directory, connection, and secret reads. Revocation or
directory deletion must invalidate delegated access through the same cache rules.
Tickets must work on another replica and after a service restart.

For the first version, stopping a delegated cast stops playback and discards the
browser's ticket. A stateless ticket remains valid until its deadline or parent
revocation; independent immediate ticket revocation is outside scope.

## HTTP interface and media delivery

These route names are proposed implementation interfaces, not existing APIs:

| Origin | Method and path | Purpose |
| --- | --- | --- |
| Management | `POST /directories/{id}/cast` | Validate owner/path/mode, create expiring share, return playback description |
| Management | Existing `POST /directories/{id}/shares/{share}/remove` | Revoke an automatically created share; adapt response handling for the controller if necessary |
| Public | `POST /s/{share}/cast` | Validate public access and return playback description, including delegated ticket when required |
| Public | `GET/HEAD /s/{share}/media?path=...` | Stream an allowed media file, with ticket when required |
| Public | `GET /s/{share}/slideshow?path=...` | Return the bounded direct-child image list under the authorized scope |

Use form-encoded POST bodies to fit the existing parsing and origin checks.
Management creation returns the slideshow list directly when practical, avoiding
an unnecessary cross-origin browser fetch. Public POSTs retain their exact-origin
check and body bound. GET/HEAD requests never create persisted shares.

A playback description needs the mode, title, expiry, and either a media URL/MIME
or entries containing display name, share-relative path, media URL, and MIME.
The authenticated response also identifies the created share for cleanup. Do not
return storage endpoints, S3 credentials, crypt keys, or signing keys.

Media handling requirements:

- Reuse the existing owner-scoped share resolution and rclone storage factory.
  Preserve guarded egress checks; never redirect the receiver to raw S3 URLs.
- Allow MP4, JPEG, and PNG with fixed MIME mappings and bounded content validation.
  Do not infer codec compatibility from filename alone. Reject active content
  such as HTML/SVG and malformed or mismatched media rather than broadening the
  endpoint into an arbitrary inline-file viewer.
- Preserve range responses, content length, HEAD behavior, cancellation, and
  streaming without whole-video buffering, local sync, or storage writes.
- Exclude long video responses from the public page deadline. Keep bounded
  deadlines for listing and authorization work.
- Return machine-appropriate authorization errors from media/list APIs, rather
  than a 200 HTML password form or an SSO redirect.
- Use the configured `SHARE_ORIGIN` for absolute URLs, never untrusted forwarded
  headers. Encode paths safely and rebuild list entries from validated names.
- Preserve no-store, nosniff, and no-referrer behavior. Do not put capability URLs
  or tickets into logs, analytics, or persistent browser storage.

Start with original JPEG/PNG delivery and test portrait orientation and large
photos. Google recommends optimizing Cast images to 1280x720 or smaller. If
originals are unreliable, add bounded image orientation/resizing through the
existing authorized storage path; video generation remains out of scope. See
[image guidance](https://developers.google.com/cast/docs/media).

## Browser controller

Keep HTMX/PicoCSS and embedded application assets. Add a small plain-JavaScript
controller and an adapter around the official Cast Web Sender SDK. No SPA or
frontend build pipeline is needed. Initialize once per document, using delegated
events for content replaced by HTMX.

Configure `DEFAULT_MEDIA_RECEIVER_APP_ID`. Use `MediaInfo` and `LoadRequest` via
`CastSession.loadMedia`; image loads use the image URL as the actual media source
and `PhotoMediaMetadata` for description. Thumbnail metadata alone does not load
the photo. Use SDK-defined stream-type values; do not copy obsolete constants
from old examples. See [sender integration](https://developers.google.com/cast/docs/web_sender/integrate).

Video controls use the normal Cast remote-player APIs: play/pause, seek, volume,
and stop. Handle both application controls and receiver-side state changes.
Do not call receiver-only codec-detection APIs from the sender or use the sender
browser's HEVC support as evidence of the TV's capabilities.

Slideshow state contains the source scope, expiry, ordered entries, shuffle
order, desired/displayed positions, interval, playing/paused state, timer handle,
in-flight load, latest requested selection, and an operation generation ID.
Keep URLs/tickets in memory. A full page reload loses slideshow state in the
first version; reconnecting a Cast session must not silently recreate a timer
or temporary share.

Transitions and concurrency rules:

1. Maintain at most one image LOAD in flight. Coalesce repeated clicks to the
   latest desired position; dispatch that selection when the current load settles.
2. Apply callbacks only to their current operation generation. Late responses
   from an old slideshow must not change a new video's state, schedule timers,
   or revoke the new share.
3. Arm one timeout after successful completion of the latest image load. This
   gives each picture its intended hold time without piling up network requests.
   Load acknowledgment is not a precise visible-frame timestamp.
4. Manual navigation cancels the timeout, updates the desired position, and
   resets the hold interval after loading. Paused manual paging stays paused.
5. Slideshow Pause cancels advancement without sending media Pause to a still
   image. Resume schedules a fresh full interval. Interval changes reschedule
   once. Shuffle/loop alter browser ordering without receiver image queues.
6. Stop, expiry, source replacement, and disconnect clear timers and pending
   selections. A resumed connection stays paused until an explicit user action.
7. If a picture fails, report its name and permit manual retry/skip. Automatic
   mode may skip with a bounded failure count; stop after a complete failing
   pass. Authorization/expiry errors stop immediately rather than skipping the
   entire folder or repeatedly creating new shares.

On page hiding, pause timed advancement and explain that the page must remain
active; retain manual state. Returning to the page should offer Resume, without
catch-up bursts. Do not attempt timer-throttling workarounds. Explicit manual
Stop should terminate only the session controlled by this operation.

Test the default receiver's image status events before reusing video end-of-media
logic: an image may be reported idle without meaning the user stopped the
slideshow. Browser-side prefetching also does not guarantee TV-side preloading.

## SDK, CSP, and network access

The official Google Cast SDK is an intentional external dependency and exception
to the application's current self-only script policy. Keep application code local
and load the SDK only on casting-capable pages. Start from Google's documented
`https://www.gstatic.com/cv/js/sender/v1/cast_sender.js?loadCastFramework=1` entry
point, determine its required dependencies during browser testing, and grant
only necessary CSP sources. Avoid broad wildcards, inline handlers, or enabling
unsafe evaluation. Existing management/share restrictions must remain intact.

Determine actual default-receiver CORS behavior in the proof of concept. Prefer
explicit origins and `Vary: Origin`; scope any unavoidable noncredentialed wildcard
policy to capability media endpoints. Do not enable credentialed wildcard CORS
or open management APIs. Capability checks authorize access independently of
CORS; valid device requests may have no Origin header. Add OPTIONS only where
the observed requests require it.

The sender uses HTTPS in supported Chrome desktop/Android environments. Chrome
on iOS is not supported by Google's Web Sender documentation. Discovery requires
network connectivity between the browser and receiver; the receiver must also
reach the public media hostname and Google services. This is LAN casting, not
an offline-only feature. See [sender requirements](https://developers.google.com/cast/docs/web_sender).

## Verification and acceptance

### First hardware checkpoint

Before building the full controller, use a minimal sender to load a known JPEG,
then another JPEG and a PNG through the default receiver on the user's device.
Verify actual rendering, repeat loads, portrait handling, rapid selections,
long holds, receiver idle behavior, and errors. Check the actual CORS requests
and CSP violations. Follow with H.264 and HEVC MP4 playback and seeking.

If image loads are unreliable, report the exact device/firmware behavior and
revisit the decision with the user. Do not silently introduce registration or
FFmpeg to bypass this checkpoint.

### Automated tests

- HTTP/storage tests: owner isolation; foreign directories/shares; read-only
  source support; empty-root paths; traversal and file-scope rejection; media
  type validation; 200/206/416; HEAD; encrypted range reads; long-stream deadline
  handling; and errors without secret-bearing URLs.
- Share tests: required server-selected expiry; expiration despite cached
  snapshots; revocation and deletion; cross-replica cache bounds; and cleanup
  failures without granting extra lifetime.
- Public-share tests: locked shares cannot mint tickets; tampering, scope
  escalation, wrong media mode, expired sessions/tickets/parents, and revoked
  parents are rejected. Valid tickets work across instances/restarts and public
  operations do not mutate persisted shares.
- Listing tests: root and nested folders, no-image and single-image folders,
  more than 100 entries, stable ordering, listing bounds, invalid backend names,
  and source files disappearing after the manifest is fetched.
- Browser tests with a fake SDK and clock: picker cancellation, delayed share
  creation, rapid next/previous, interval changes, pause/resume, loop/shuffle,
  failed loads, stale callbacks, visibility/disconnect, expiry, HTMX swaps, and
  changing between video and slideshow. Confirm one timer and one LOAD at a time.

Run from `files/`: format changed Go files with `gofmt`, then `go build ./...`,
`go vet ./...`, `go test ./...`, and `go test -race ./...`. Integration tests use
disposable loopback `TEST_DATABASE_URL`; in-memory S3 fixtures cover storage.
Run a container build against a local/disposable Docker daemon and the chosen
JavaScript/browser checks. Report skips and unavailable tools explicitly.
If configuration or ingress changes, validate Compose/stack configuration and
check generated Caddy routing without deploying as a validation step.

### Dev image and user acceptance

The user proposed a dev image deployment and will add a demo directory. Publish
a unique valid tag such as `cast-dev-<commit>` after the code passes checks; the
existing Files tag workflow supports it. Select that image explicitly through
ignored deployment configuration or a Make override. Retain other service tags
and the previous Files image for rollback. `make latest-tags` selects stable
numeric releases and will not select this dev tag; do not use `deploy-latest`.

Use the existing HTTPS server while the user's Chrome browser and Chromecast
are on the home LAN. A server on the LAN is also possible with device-reachable
hostnames and suitable HTTPS; current localhost URLs and loopback-only Compose
bindings are not a ready-made device test environment. No custom receiver needs
to be registered.

The demo directory should contain H.264 and HEVC MP4s, landscape/portrait JPEGs,
a PNG, and a subfolder with more pictures. Include an encrypted source in a
separate test mapping when available. Record the receiver model and firmware,
browser version, and representative video codecs/profile/audio.

Acceptance includes root and subfolder slideshows; manual and timed controls;
more than one listing page; clear background-pause behavior; video seeking;
no share after canceled selection; cleanup after Stop/startup failure; short-TTL
expiry; and casting from unlocked password-protected public shares. Inspect
Sharing and sanitized service/browser diagnostics to confirm lifecycle behavior.
Actual casting is user-assisted hardware validation; automated SDK mocks cannot
establish hardware compatibility.

## Implementation sequence

1. Complete the default-receiver image/video proof and record any limitations.
2. Add media delivery, scoped authorization, public ticket handling, and their
   HTTP/storage tests. Preserve existing download semantics and ingress boundaries.
3. Add authenticated temporary-share creation, expiry configuration, cleanup,
   and the public-share playback-description flow.
4. Integrate the SDK and video controls with narrow CSP/CORS changes.
5. Add the browser slideshow state machine, header/root action, optional
   subfolder action, and persistent controller; exercise fake-SDK tests.
6. Run module/container/configuration checks, prepare the dev image, and complete
   user-assisted acceptance. Publishing and deployment are separate actions from
   writing this document; follow the task's authorization and repository workflow.

Implementation choices still to settle are exact endpoint/response details, the
supported interval bounds/default, the maximum configured temporary-share TTL,
the minimal SDK/CORS policy observed on hardware, and whether bounded picture
resizing is needed. These should not change the core decisions: direct MP4,
sender-driven pictures, no receiver registration or video generation, automatic
share expiration, and first-class root-folder support.


## Implementation record (2026-11-03)

- Files implements the proposed management/public endpoints in
  `internal/app/cast.go`, reusing standard immutable shares and the existing
  30-second snapshot cache. No schema migration or receiver registration.
- `CAST_SHARE_TTL` / `--cast-share-ttl` defaults to 6 hours and permits positive
  durations up to 24 hours. Root Compose and the Swarm stack pass this setting;
  infra's Makefile exports overrides. Service image selections are unchanged.
- Versioned, canonical JSON/base64url HMAC tickets use a separate MAC domain
  and the persisted per-share key. Delegated slideshow access covers the exact
  folder manifest and direct-child JPEG/PNG media; video access is exact-file.
- Cast media validates up to 64 KiB of headers (JPEG/PNG config or MP4 `ftyp`),
  then streams original bytes with existing single-range/HEAD semantics. Header
  validation does not guarantee codec support or whole-file integrity. Downloads
  and previews keep their existing behavior.
- The SDK adapter and persistent controller are local embedded scripts. Image
  loads use PhotoMediaMetadata and SDK StreamType.OTHER; videos use BUFFERED.
  Picture interval defaults to 10 seconds, bounded to 2–300 seconds. Failed
  pictures pause for explicit retry/skip, with no automatic failing-image loop.
- SDK CSP exceptions cover gstatic's `/cv/js/sender/`,
  `/cast/sdk/libs/sender/`, and `/eureka/clank/` script paths. Media-only CORS
  allows the explicit `https://www.gstatic.com` receiver origin and configured
  sender/share origins, without credentials. No OPTIONS route or wildcard has
  been added; actual receiver requests and CSP dependencies need device checks.
- Go tests cover tickets, isolation, read-only sources, root and paginated
  manifests, invalid media, ranges/HEAD, expiry and revocation, and plain/crypt
  storage. Fake-clock/SDK tests cover controller concurrency and lifecycle;
  Chromium checks exercise lazy SDK loading, API timing, controls and HTMX swaps.
- Remaining acceptance: real-device image rendering/repeat loads/portrait/large
  photos/idle behavior, H.264 and HEVC playback/seeking, actual CSP/CORS behavior,
  short-TTL and password-share user acceptance. Resizing is deferred until those
  observations justify it. Dev-tag publication and deployment require separate
  task authorization, granted for the custom-tag test deployment on 2026-11-03.


### Local verification results

Passed in `files/`: `gofmt` on changed Go files, `go build ./...`,
`go vet ./...`, `go test ./...`, and `go test -race ./...`. Database tests used
a newly initialized PostgreSQL 14 instance on loopback port 55439; S3 tests used
in-memory servers, including plain and rclone crypt Cast range delivery. No
production backend was used. The disposable PostgreSQL instance was stopped
after validation.

Passed `node tests/cast-controller.test.cjs` (14 tests), `node --check
internal/web/static/cast.js`, and `python tests/cast-browser.py` with local
Playwright/Chromium and mocked SDK/HTTP responses. Browser checks cover lazy SDK
loading, CSP, picker cancellation, actual photo/video LOAD construction, controls,
receiver video state, mobile layout, HTMX persistence, and stop/revocation.

Passed `docker -H unix:///var/run/docker.sock build --network host -t
files:cast-validation .` on the verified local inactive daemon. The initial
bridge-network build could not fetch Alpine packages; host networking succeeded.
At that verification checkpoint the image was local only; nothing had been
published or deployed.

Passed root Compose configuration with `.env.example`, Files Compose with
disposable test passwords, and stack Compose configuration with `infra/.env.example`
and placeholder service tags. Checked `CAST_SHARE_TTL=5m`, the Makefile's exported
override, and preserved management/public ingress label boundaries. `make config`
was attempted but this installed Docker CLI lacks `docker stack config`, so the
documented Compose alternative was used. No ingress routes were changed.

Physical receiver, real SDK network dependencies, CORS behavior on the TV, and
HEVC compatibility remain unvalidated, as agreed with the user.
