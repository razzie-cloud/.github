# Audit 3: preserve native form origins

Status: implemented in Files commit `92c5a6c` and Gateway commit `9b1adb2`.
No deployment performed.

## Problem and evidence

Files' [outer handler](../../files/internal/app/app.go) sets `Referrer-Policy: no-referrer` before routing to management or public shares. The management POST guard requires the exact Files origin. The [public-share POST guard](../../files/internal/app/shares.go) independently requires the exact sharing origin.

Gateway's [request middleware](../../access-gateway/internal/app/security.go) has the same response policy and exact POST origin check. Its [UI renderer](../../access-gateway/internal/app/ui.go) produces the pages and activity fragments containing forms with native `method`/`action` attributes.

The audit's Chromium reproduction observed these native, same-origin form requests:

| Document response policy | Browser-generated POST Origin |
| --- | --- |
| `no-referrer` | `null` |
| `same-origin` | The document's exact origin |

Both servers correctly reject `Origin: null`. The problem is the policy on the source document, not the POST validation. The reproduction used a small browser page; it did not by itself exercise an authenticated production mutation. The behavior is specified in the [Fetch origin-header algorithm](https://fetch.spec.whatwg.org/#append-a-request-origin-header).

This affects Files' native form fallbacks and public-share password unlock. Gateway device/session forms with explicit POST actions have the same problem when used natively. Several other Gateway forms have only HTMX attributes, and WebAuthn needs JavaScript; this fix does not claim to make all Gateway functions work without scripts.

## Selected design

Make two small header changes. Keep every existing origin, identity, role, ownership, method and body-size check.

1. In Files' `Server.Handler`, change the default response referrer policy to `same-origin`. Apply it before either router runs, covering management pages, public-share password forms, and the wrong-password response.
2. In Gateway's `Server.render`, set `Referrer-Policy: same-origin` after successful template rendering and before `WriteHeader`. Keep the outer middleware and `writeError` defaults at `no-referrer`.

Files needs the policy early: `publicShare` writes the wrong-password 403 status before calling `render`. A renderer-only override would arrive too late, leaving the password retry page broken. Changing that default avoids adding another response-writing path or special case.

Gateway already buffers successful UI rendering before writing headers. Its renderer can safely override the default for rendered UI documents and fragments, including activity responses that retain forms. SSO callbacks, code/state redirects, JSON authentication responses, and standalone error pages keep `no-referrer`. This preserves the stricter existing authentication-protocol behavior without adding route checks to middleware.

`same-origin` suppresses referrers to other origins, including another Razzie Cloud hostname. Same-origin requests may carry the current page URL, including a public capability path or query string. Keep existing route-based logging and the prohibition on raw capability/callback URLs. Registration tokens remain in URL fragments and request bodies; never move them into query strings. Keep explicit `rel="noopener noreferrer"` on document links.

Do not accept absent or `null` origins, infer an origin from Referer, add a CSRF bypass, add configuration, add a dependency, or expand the template fallback feature set.

## Implementation scope

| Owning repository / file | Change |
| --- | --- |
| `files/internal/app/app.go` | Change the early default header to `same-origin`; leave management POST checks intact. |
| `files/internal/app/app_test.go` | Assert the policy on a rendered management document and preserve rejection of bad origins. |
| `files/internal/app/shares_test.go` | Assert the policy on the password gate and wrong-password 403 retry page; retain correct/wrong-host unlock checks. |
| `files/internal/app/native_forms_browser_test.go` (new) | Add focused native management and password-unlock regressions using the existing browser runner and fixtures. |
| `files/internal/app/navigation_browser_test.go` | Update the manually supplied response-policy fixture to match production. |
| `files/docs/reference.md` | Correct the public-sharing response-policy paragraph: `no-store` controls caching; `same-origin` allows native forms and suppresses cross-origin referrers. |
| `access-gateway/internal/app/ui.go` | Set the UI response policy in buffered `render`, before writing status. |
| `access-gateway/internal/app/frontend_test.go` | Assert the UI-render policy, including a GET `/register` through `handler` that requires no database. Retain standalone-error expectations at `no-referrer`. |
| `access-gateway/internal/app/security_test.go` | Preserve existing missing/null/foreign/scheme/prefix origin rejection cases; add a successful UI form-render assertion if not already covered in the frontend test. |
| `access-gateway/docs/reference.md` | Describe the rendered-UI exception alongside the existing no-referrer authentication-protocol contract. |

`access-gateway/internal/app/errors.go`, `errors_test.go` and `link_login_test.go` need review, but their `no-referrer` behavior and existing assertions stay intact. Generic middleware test handlers in `security_test.go` also retain that default. No changes are needed in Notes, landing, proxy labels, configuration parsers, migrations, or shared CSS.

## Ordered implementation

1. Add the focused Files native browser regressions against the existing behavior and confirm failure comes from `Origin: null`/403, not a browser execution-context exception.
2. Make the two production header changes and add the HTTP response-policy assertions listed above. Record both successful source documents and the public password retry document.
3. Update the one Files browser fixture that hardcodes the policy and the two affected reference paragraphs. Do not blanket-replace `no-referrer` assertions: Gateway authentication errors and redirects deliberately retain it.
4. Run the validation below. Commit future implementation separately in Files and Gateway; coordinate the parent pins only after the component work exists. This design document stays in the parent repository.

## Regression tests and acceptance

### Automated browser coverage in Files

Reuse [the existing Chromium runner](../../files/tests/browser/browser.go), `shareListFixture`, and the cached password-share setup in `TestPublicSharingIsolationAndPassword`. Keep the test opt-in through `CHROMIUM_EXECUTABLE_PATH`; use test metadata and fake S3 only.

- Load `/shares` through the actual `Server.Handler`, forwarding browser request headers unchanged except the existing test proxy identity. Return an empty JavaScript response for the HTMX asset to model HTMX being unavailable. Do not inject an Origin header.
- Submit an existing share-revocation form as a native form. Assert the captured request has the exact management Origin and no `HX-Request: true`, the real handler returns its native redirect, the browser follows it, and the owner-scoped fixture removes the selected share.
- On the separate sharing host, submit a wrong password natively and then a correct password from the returned retry page. Assert both requests use the sharing Origin, the first returns the real 403 password form, and the second sets the scoped session cookie and follows the normal redirect. Verify unlock does not expose management routes.
- From a synthetic capability page, follow a cross-origin link to another intercepted test origin. Assert no Referer containing the capability is sent. No request should leave the fixture.

Observe native POST and redirect GET requests in Go-side channels. Do not await a JavaScript promise across a document replacement; use the runner's committed-navigation checks if DOM inspection is needed. This avoids the known execution-context failure in `TestShareListBrowser`.

### Gateway coverage and browser acceptance

Use existing HTTP/template tests to prove `handler -> render` returns `same-origin` for UI, while `handler -> writeError`, successful JSON link login, and SSO callback responses retain `no-referrer`. Existing request helpers often supply Origin manually, so those checks alone do not prove browser generation.

Complete one native management browser acceptance against a disposable local Gateway with an existing test session: open `/ui/activity` directly, choose an unrelated removable test session, and submit its existing native POST form with HTMX unavailable. This response contains native forms and does not require completing WebAuthn for the check. Confirm the browser supplies the configured Origin and the intended session is removed. Keep real authentication/authorization enabled and use only disposable PostgreSQL/Redis state. Do not add a separate maintained Gateway browser framework or a cross-submodule test dependency for this header fix.

For both services, continue to reject missing, `null`, foreign, wrong-scheme and wrong-port origins before mutations. In Files, also reject duplicate Origin headers and using the management origin on the sharing host. Verify an ordinary HTMX submission still works. Gateway's existing duplicate-header behavior is not changed by this plan.

### Required implementation checks

- In each affected module: `gofmt` changed Go files, `go build ./...`, `go vet ./...`, and `go test ./...`.
- Files: `go test -race ./...`, with disposable loopback `TEST_DATABASE_URL` for integration coverage.
- Gateway: `go test -race ./...`, with disposable loopback `TEST_DATABASE_URL` and `TEST_REDIS_URL`.
- Files browser regressions: set the installed Chromium path and run the new native-forms test plus `TestPanelNavigationBrowser` and `TestShareListBrowser`.
- Run existing Gateway passkey bridge scenarios to guard the unchanged fetch-based flow. Record the separate native management acceptance and any skips.

The audit saw `TestShareListBrowser` fail twice at its native navigation boundary with `Runtime.evaluate: Inspected target navigated or closed`. Treat that as an unresolved acceptance-test result. It is not proof of this Origin bug and must not be hidden by retries, broad panic recovery, or relaxed assertions. If it persists after the focused test passes, report it separately and keep any justified test-harness timing fix separate from this production change.

## Release and compatibility

There are no schema, API, form-field, cookie, identity-token, environment, or proxy changes. Files and Gateway can be released independently; mixed versions have the old fallback failure only on responses from an old replica. A freshly loaded document receives the new policy. Already open documents can retain their old policy until reloaded, so verify acceptance after a full reload.

Publish the two component images before selecting their tags or publishing parent pin updates, following the repository release workflow. No deployment is part of this plan. Rollback restores the previous form failure but requires no data migration.

## Limits and remaining risk

The accepted privacy change is that same-origin requests from Files documents and rendered Gateway UI may include their source URL as Referer. External origins still receive none. Preserve sanitized logging and test this boundary directly; do not describe `same-origin` as suppressing all referrers.

No visual layout, accessibility control, native fallback coverage for HTMX-only Gateway forms, WebAuthn behavior, Cast integration, or SSO protocol is redesigned. Planning inspected the relevant handlers, renderers, templates, tests and docs; no implementation checks or browser tests were rerun for this documentation-only task.
