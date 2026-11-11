---
name: razcloud-frontend-implementation
description: Implement or revise Razzie Cloud production frontends in embedded Go templates, PicoCSS and HTMX, including translating reviewed mockups while preserving routes, authorization, CSP and browser hooks. Use for service UI changes rather than static-only design concepts.
---

# Razzie Cloud frontend implementation

Read parent/component `AGENTS.md` and inspect existing work before editing. Keep
service code in its owning submodule. Read parent `docs/frontend-mockups.md` and
`docs/brand/README.md` for shared design decisions.

## Inspect the live contract

Gateway, Files and Notes embed `internal/web/templates.html` and local
`internal/web/static/` assets. Inspect the service's embed declaration/renderer
before adding files; loading differs by service. Landing instead embeds root
`index.html`, `landing.css` and `assets/` through its standard-library server.

Trace affected templates through handlers, JavaScript and frontend tests. Record
the contract that must survive markup changes:

- Routes, methods, field names, multipart encoding and hidden validators.
- IDs, `data-*` hooks, HTMX targets/swaps/triggers and response retarget headers.
- Role, ownership, read-only and state-dependent controls, including error views.
- Browser hooks for WebAuthn, previews, Cast, explicit saves and draft retention.

Mockups can omit advanced settings, recovery, real authorization and error states.
Keep live controls/validation absent from the mockup and use real data/routes.

## Implement in the existing frontend

Use escaped Go templates, HTMX and PicoCSS with local assets/licenses. Keep CSP
and HTMX settings, including disabled evaluation, style injection and history
snapshots. Prefer native HTML/HTMX; use external JavaScript for established
browser integration needs. Do not add a SPA, inline handlers, CDN assets or a
frontend build pipeline.

Keep navigation inside the fragment that owns its state. Gateway account
navigation updates with the account fragment; Files' main fragment contains
sidebar and view. Sign-in/out, mutations and validation errors must leave a
complete shell, including `HX-Retarget` responses. Avoid duplicate IDs, broken
replacement targets and listeners installed again after every swap. Clean up
browser resources when their content is removed.

Follow current shared CSS and brand rather than copying old mockup CSS wholesale.
Production themes follow browser preference; do not force the mockup's theme.
Keep the header aligned to the centered frame, the workspace filling its grid
column and comparable horizontal padding. Use `minmax(0,1fr)` / `min-width:0`
where long content would otherwise widen the page.

Files/Notes binary choices use Pico switches. Exclude checkbox/radio/range/file
controls from text-input sizing. Use lowercase `aria-label="breadcrumb"` for
Pico breadcrumbs. Preserve focus, contrast, skip links and reduced-motion support.
The logo cloud-home link uses configured `LANDING_ORIGIN`; the service-name link
opens the app. Preserve the supplied logo and existing machine identifiers.

For panel navigation, preserve valid-anchor behavior: repeated activation can
restart its cue, HTMX-loaded targets work after swapping, and bare/unanchored
updates do not highlight an arbitrary default panel.

Read the relevant service section of [acceptance.md](references/acceptance.md)
for UI boundaries and browser scenarios.

## Verify the rendered result

Start from existing renderer/frontend tests. Add coverage when a behavioral
change or fragile contract needs it, such as role controls, fragment navigation,
escaping or retained drafts. Avoid tests for incidental CSS classes alone.

Render real production templates for representative states. Local fixtures can
exercise markup/HTMX without credentials; retain production response headers
and CSP. Use an isolated temporary harness unless a maintained browser runner
exists. Do not add fixture routes to the production app.

Check both themes at mobile, tablet and desktop widths; include wide desktops
when frame alignment changes. Check headings, overflow, expected controls,
keyboard use and browser errors. Exercise changed controls after swaps and
failure responses; inspect screenshots visually. Fixtures do not prove live
WebAuthn, S3, database concurrency or Cast receiver behavior.

Run required module checks: format changed Go, `go build ./...`, `go vet ./...`
and relevant tests. Files/Notes require their race suite; Landing uses
`go test -race ./...`. Follow the gateway guide for integration/race checks.
Use disposable local backends only. Report exact checks, skips and remaining
browser/hardware limitations. Refresh relevant previews/docs for design changes.
Publication/deployment stays within the user's separately authorized scope.
