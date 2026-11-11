---
name: razcloud-frontend-mockups
description: Create or revise interactive HTML frontend mockups for Razzie Cloud apps using the shared brand, local PicoCSS and HTMX assets, light/dark previews, and screenshots. Use for design exploration and sample interactions; live template changes belong to razcloud-frontend-implementation.
---

# Razzie Cloud frontend mockups

Create reviewable browser pages using the project's existing visual language.
A mockup request alone does not call for a backend or production template changes.

## Find the baseline

Work from the parent checkout. Read parent/component `AGENTS.md`, inspect existing
Git work, and read `docs/frontend-mockups.md` and `docs/brand/README.md`. Mockups
belong in the owning component's `docs/mockups/`; coordination belongs in parent.

| Example | Useful patterns |
| --- | --- |
| `files/docs/mockups/` | Navigation shell, cards, breadcrumbs, tables, contextual forms, public view |
| `access-gateway/docs/mockups/` | Account activity, device disclosures, sign-in/enrollment panels |
| `notes/docs/mockups/` | Library, editor, tags, first use, explicit save/conflict fixtures |
| `landing/index.html`, `landing/landing.css` | Public homepage and app cards |

Historical mockup documentation can predate the service. Confirm current
capabilities in source and component guides before writing product claims.

## Match the shared design

- Display **Razzie Cloud**. Preserve `docs/brand/razzie-cloud-logo.png`, its aspect
  ratio and exact component-local copies. Machine identifiers are separate.
- Inspect current embedded `internal/web/static/app.css` and templates for shared
  shell behavior. Older mockup CSS can retain superseded width limits; do not
  blindly copy it into new layouts.
- Light pages use pale slate backgrounds, white panels, navy text/actions and
  warm gold selected navigation. Dark pages use existing navy surfaces and gold
  accents. Preserve status colors. Read actual CSS variables rather than creating
  another palette or downloading a font.
- Reuse small line icons, spacing, cards and forms. Desktop navigation sits beside
  the workspace, with contextual forms beside main content. Narrow layouts wrap
  navigation and stack columns. Align the header with the application frame;
  long content must not expand a grid column.
- Use Pico controls, semantic tables, labels and keyboard focus. Files/Notes use
  `type="checkbox" role="switch"` for binary choices. Pico breadcrumb styling
  expects lowercase `aria-label="breadcrumb"`.

## Build sample interactions

Use HTML/CSS and vendored HTMX. Existing sets use `mockup.css`, optional
screen-specific CSS, `dark.css`, counterpart pages under `dark/`, and `fragments/`.
Preserve the established structure, keep both themes/relative links in sync,
and make theme navigation return to the same screen.

Reuse component-local embedded PicoCSS/HTMX assets with licenses, or make exact
local copies when self-contained previews are needed, as Notes does. These
mockups need no frontend build pipeline or external runtime assets.

Simulate mutations by fetching static authored fragments with `hx-get`. Never
send mockup forms to real APIs. Credential fields must not transmit entered
values; attachment fixtures must not upload selected files. Omit submitted names
or use `hx-params="none"` as appropriate and inspect actual network requests.
Downloads can contain harmless local sample files.

Keep success, failure, empty, read-only and conflict states honest. A fixed
Markdown preview is a fixed example; a simulated save does not persist. Preserve
draft inputs when demonstrating failures. Sample counters must not imply live
usage/quota tracking. Put simulation feedback near the action.

Retain the mockups' CSP, external script/style files and HTMX configuration:
`allowEval:false`, `includeIndicatorStyles:false`, `historyCacheSize:0`. Avoid
inline handlers and evaluated HTMX expressions; native disclosures and authored
fragments cover most interactions here.

## Preview and verify

Serve parent-linked previews over loopback HTTP:

```sh
python3 -m http.server 8765 --bind 127.0.0.1
```

Open `/files/docs/mockups/index.html`, for example. `file://` prevents normal
HTMX fixture loading. Choose an unused port if necessary. Self-contained Notes
previews can also run from its repository. Stop the server afterward and keep
real credentials out of fixtures.

Use an available browser runner to render every changed full page in both themes.
Check widths such as 320, 390, 768 and 1440 pixels, one primary heading, loaded
assets, usable keyboard focus and page-level overflow. Exercise navigation,
theme switches and changed fragment interactions. Capture console/page errors
and failed responses. Inspect screenshots visually; DOM checks alone do not
establish layout quality.

Save useful screenshots beside the mockups with existing names such as
`index-desktop.png` and `dark/index-desktop.png`. Update component screen guides
and parent links when screens change. Report actual theme/viewport/interaction
coverage, distinguishing fixtures from live acceptance. Static-only mockups need
no Go build unless embedded production assets changed; follow component checks
whenever production code/assets are touched.
