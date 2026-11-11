# Production UI acceptance scenarios

Paths are relative to the parent. Current component guides/source take precedence
over historical design notes. Read only the affected service sections.

## Gateway

Inspect `access-gateway/internal/app/ui.go`, `activity.go`, `security.go`,
`internal/web/static/app.js` and `internal/app/frontend_test.go`.

Cover signed-out, bootstrap, enrollment, regular-user and administrator states
as relevant. Account swaps update navigation. User creation uses retargeting;
login/enrollment use the WebAuthn bridge. Exercise error rendering, activity
refresh, device disclosures, QR display and sign-out when changed.

Role/owner filtering is server-side. Current sessions and devices used by live
sessions retain protected actions. Never render session tokens/ceremony payloads.
Registration bearer secrets stay in the URL fragment, are removed from history
by the bridge, and must not move into queries.

For live acceptance in an authorized disposable environment, the guide describes
Chromium CDP's virtual authenticator: CTAP2, internal transport, resident keys
and user verification. Cover bootstrap, named login, user creation, fresh-context
device enrollment, reuse rejection and both credentials. This does not establish
physical-device acceptance.

## Files

Inspect `files/internal/app/frontend_test.go`, `templates_test.go`, `media.go`,
`document.go`, `cast.go` and the `internal/web/static/` controllers.

Cover empty/populated directories, writable/read-only settings, encrypted settings,
validation failures, sharing and public password/unlocked views as relevant.
Connection read-only policy wins over directory policy. The public shell contains
no management/mutation controls; backend guards remain essential.

Preserve multipart upload encoding/names, folder feedback, crypt disclosures,
media and Cast hooks. Test preview close/Escape, previous/next and listing
replacement; audio/video must stop and release sources. Retain document
sandboxing, safe Markdown/text handling, authorized downloads and byte ranges.
Public-share URLs remain capability-scoped on the separate hostname.

Cast checks can stub the SDK for controller behavior. Retain page-specific SDK
loading/CSP and distinguish stubs from receiver, codec, CORS and hardware checks.

## Notes

Inspect `notes/internal/app/frontend.go`, `frontend_test.go`,
`frontend_integration_test.go`, templates and `static/app.js`.

Cover storage first use, connection/notebook selection, read-only settings,
library/search, reading, editing and attachments as relevant. Saves are explicit
and conditional; preserve editor validators and conflict drafts. Failed saves
must not discard entered Markdown. Notes owns its settings independently of Files.

Markdown keeps escaping/sanitization and remote-image restrictions. Owner/notebook
scope and admin APIs remain backend-enforced; do not broaden attachment URLs.

## Landing

Inspect `landing/main.go`, `main_test.go`, `index.html`, `landing.css` and
`apps.example.json`. Verify no-app and configured-card/navigation states,
light/dark preference, narrow layouts and long labels. Sign in always targets
`auth.<DOMAIN>`; public scheme/port and links come from validated runtime settings.
Never expose configuration/source through an asset route.
