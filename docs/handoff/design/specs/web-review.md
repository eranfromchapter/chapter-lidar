# Build spec · web-review · Web review v2 in the HUB design system

Area key: `web-review` · Chapter Capture v2 · written Oct 21, 2026 from the "Chapter Capture v2"
Claude Design bundle (artboards **2h**, **2i**, **2j** = `canvas/web-review-v2.dc.html` with
`page = projects | project | package`; **2k** web half of `canvas/screen-tokens-v2.dc.html`;
`00-plan-screens.dc.html` "Web, review"; HUB design system `_ds/hub-design-system-730fbc76…`).
v1 (artboard 2g, `screen-review`) is what `web/` builds today.

This spec is complete on its own: every value below was read from the bundle source. Nothing
needs to be looked up in the bundle again. Where the bundle draws a placeholder (`[BRACKETS]`) the
spec names the live data field; where the data does not exist the spec says what to show.

---

## 0. Binding decisions applied here

| # | Decision (owner, Oct 21, 2026) | What it means for the web |
|---|---|---|
| B1 | Real Chapter logo and Inter everywhere; never the typed serif "chapter / RENOVATION" wordmark | The web uses the HUB "chapter" wordmark file (`canvas/hub-assets/chapter-wordmark.svg`, copied byte-identical to `web/public/brand/chapter-wordmark.svg`). No page contains the text "RENOVATION". No Times anywhere on the web (HUB headings are sans). |
| B2 | Web review in the HUB design system **as drawn** (layout, components, mint accent, pill buttons, grey page, white cards, HUB wordmark), Inter instead of Lato, fonts self-hosted, never Google | All HUB tokens are copied verbatim except the font families; `fonts.css` (Google Fonts `@import` of Lato) is **not** used. Inter comes from `web/public/brand/inter-*.woff2`. |
| B3 | Spatial report is made on the station after the checks (replaces the verdict report); the phone's `spatial_report_pdf` retires; compass with 3 states (verified / approximate / not verified, ±10° / ±30°); plan sheet made on the phone, Tabloid, no verdict | The web downloads the spatial report from the station (new endpoint), shows the plan sheet PDF from the package (`plan_pdf`), shows orientation in the three states, keeps a label for legacy `spatial_report_pdf` files in old packages. |
| B4 | Build on recent repo work, do not undo | Keep: Entra sign-in, proxy, server-only station client, short-lived download links (never rendered), plan preview streaming, decision log server action, `public/brand/chapter-logo.svg` and `inter-400/600.woff2` (the scan browser serves them from `web/public/brand`). |

Font weight rule (from B1/B2 and the repo): the repo ships Inter **400** and **600** only. Every
HUB weight 700 renders as Inter **600**; `--fw-bold: 600`; `font-synthesis: none` on `html` so a
browser never fakes a bold. (Adding a real Inter 700 is open question Q1.)

---

## 1. Scope

In scope (all in the HUB look):

1. App shell: ink sidebar (wordmark, "Capture review", nav, signed-in user), white topbar (page
   title, search, "Open the HUB").
2. **Projects** page (2h) with verdict tabs, table, empty/search/error states.
3. **Project** page (2i): packages (revisions) table, "What revision N adds", latest verdict,
   decision log summary, "Decision log" tab.
4. **Package** page (2j): verdict, plan preview per floor, downloads (spatial report, plan sheet,
   manifest, verdict.json, everything), capture checks in the report's words grouped
   Blocked › Limited › Passed › Not applicable, files with floor / role / text filter, modeling
   decision log (form + entries), capture record, field controls, station timeline, documents.
5. **Packages** and **Decision log** pages behind the sidebar items (not drawn; specified here
   from the same components).
6. **Capture-role** views (status only), **sign-in**, **empty states**, not-found, error,
   loading, configuration-error page.
7. The station API additions the pages need (`contract/openapi/station.yaml` 1.0.0 → 1.1.0) and
   the shared text helpers in `@chapter/capture-contract` so the web and the spatial report use the
   same words.

Out of scope: 3D viewer, editing packages, client-facing views, sign-out UI (not drawn, not in
v1), dark mode (HUB has none), the scan browser (`tools/scan-browser`).

---

## 2. Design system implementation (HUB, Inter, self-hosted)

### 2.1 Files

- `web/app/globals.css` — rewritten: Inter `@font-face`, HUB tokens, base element styles.
- `web/app/hub.css` — new: HUB component classes (`.hub-*`) and page layout classes.
- `web/app/layout.tsx` imports both (`import "./globals.css"; import "./hub.css";`). No CSS
  `@import` anywhere (existing brand test keeps asserting this).

### 2.2 Fonts (globals.css)

```css
@font-face { font-family: Inter; font-style: normal; font-weight: 400; font-display: swap;
  src: url("/brand/inter-400.woff2") format("woff2"); }
@font-face { font-family: Inter; font-style: normal; font-weight: 600; font-display: swap;
  src: url("/brand/inter-600.woff2") format("woff2"); }
```

No other `url(` in any web CSS. No `fonts.googleapis.com`, `fonts.gstatic.com` or "Lato" in
`web/` (test).

### 2.3 Tokens (globals.css `:root`) — HUB values verbatim, fonts replaced

Colour (verbatim from HUB `tokens/colors.css`):

| Token | Value | Token | Value |
|---|---|---|---|
| `--mint-50` | `#e7fbf6` | `--gray-50` | `#fafafa` |
| `--mint-100` | `#c5f6ec` | `--gray-100` | `#f1f1f1` |
| `--mint-200` | `#93eedd` | `--gray-200` | `#e6e6e6` |
| `--mint-300` | `#5eecd8` | `--gray-300` | `#d7d7d7` |
| `--mint-400` | `#30e3ca` (brand accent) | `--gray-400` | `#b8b8b8` |
| `--mint-500` | `#1fcbb3` | `--gray-500` | `#8c8c8c` |
| `--mint-600` | `#14a692` | `--gray-600` | `#6b6b6b` |
| `--mint-700` | `#0f8174` | `--gray-700` | `#4d4d4d` |
| `--ink-900` | `#231f20` | `--ink-a90` | `rgba(0,0,0,0.90)` |
| `--ink-800` | `#353133` | `--ink-a60` | `rgba(0,0,0,0.60)` |
| `--ink-700` | `#4a4648` | `--ink-a40` | `rgba(0,0,0,0.40)` |
| `--black` | `#000000` | `--ink-a30` | `rgba(0,0,0,0.30)` |
| `--white` | `#ffffff` | `--ink-a08` | `rgba(0,0,0,0.08)` |
| `--amber-100` | `#fdeccb` | `--ink-a05` | `rgba(0,0,0,0.05)` |
| `--amber-400` | `#f5a623` | `--red-100` | `#fbe0de` |
| `--amber-600` | `#c97f0a` | `--red-500` | `#e0584f` |
| `--green-100` | `#d8f5e6` | `--red-700` | `#b53b33` |
| `--green-500` | `#2bb673` | `--blue-100` | `#dce9fb` |
| `--blue-500` | `#3b7be0` | | |

Semantic aliases (verbatim): `--surface-page: var(--gray-100)`, `--surface-card: var(--white)`,
`--surface-muted: var(--gray-50)`, `--surface-sunken: var(--gray-100)`,
`--surface-inverse: var(--ink-900)`, `--text-strong: var(--ink-900)`,
`--text-heading: var(--black)`, `--text-body: var(--ink-a60)`, `--text-muted: var(--ink-a40)`,
`--text-on-accent: var(--ink-900)`, `--text-on-inverse: var(--white)`,
`--text-link: var(--mint-600)`, `--accent: var(--mint-400)`, `--accent-hover: var(--mint-500)`,
`--accent-soft: var(--mint-50)`, `--accent-border: var(--mint-200)`,
`--border-subtle: var(--ink-a08)`, `--border-default: var(--gray-300)`,
`--border-strong: var(--ink-900)`, `--focus-ring: var(--mint-400)`,
`--status-success: var(--green-500)`, `--status-success-bg: var(--green-100)`,
`--status-warning: var(--amber-400)`, `--status-warning-bg: var(--amber-100)`,
`--status-danger: var(--red-500)`, `--status-danger-bg: var(--red-100)`,
`--status-info: var(--blue-500)`, `--status-info-bg: var(--blue-100)`.

Typography (HUB `typography.css` with the family replaced):

```css
--font-sans: Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
--font-display: var(--font-sans);
--font-mono: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
--fw-regular: 400; --fw-bold: 600;   /* HUB 700 → Inter SemiBold (see §0) */
--text-xs: 0.75rem; --text-sm: 0.8125rem; --text-base: 0.9375rem; --text-md: 1.0625rem;
--text-lg: 1.25rem; --text-xl: 1.5rem; --text-2xl: 1.75rem; --text-3xl: 2.25rem;
--leading-tight: 1.15; --leading-snug: 1.3; --leading-normal: 1.5; --leading-relaxed: 1.8;
--tracking-tight: -0.02em; --tracking-wide: 0.08em; --tracking-eyebrow: 0.16em;
```

Layout (verbatim from HUB `layout.css`): `--space-1..10` = 4, 8, 12, 16, 24, 32, 40, 48, 64, 80 px;
`--radius-xs 4px`, `--radius-sm 6px`, `--radius-md 10px`, `--radius-lg 16px`, `--radius-xl 24px`,
`--radius-pill 100px`, `--radius-full 9999px`;
`--shadow-xs: 0 1px 2px rgba(0,0,0,.05)`;
`--shadow-sm: 0 1px 3px rgba(0,0,0,.08), 0 1px 2px rgba(0,0,0,.04)`;
`--shadow-md: 0 4px 12px rgba(0,0,0,.08)`; `--shadow-lg: 0 12px 32px rgba(0,0,0,.12)`;
`--sidebar-width: 248px`; `--topbar-height: 64px`; `--ease-standard: cubic-bezier(0.2,0,0,1)`;
`--dur-fast: 120ms`; `--dur-base: 200ms`.

Base (globals.css):

```css
* { box-sizing: border-box; }
html { font-synthesis: none; }
html, body { margin: 0; }
body { font-family: var(--font-sans); font-weight: 400; font-size: 14px; line-height: 1.5;
  color: var(--text-body); background: var(--surface-page);
  -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility; }
h1, h2, h3, h4 { font-family: var(--font-display); color: var(--text-heading); margin: 0;
  line-height: var(--leading-tight); font-weight: var(--fw-bold); }
b, strong { font-weight: var(--fw-bold); }
a { color: var(--text-link); text-decoration: none; }
a:hover { text-decoration: underline; }
button, input, select, textarea { font-family: inherit; }
:focus-visible { outline: 2px solid var(--accent-hover); outline-offset: 2px; }
.visually-hidden { position: absolute; left: -9999px; }
.mono { font-family: var(--font-mono); }
```

### 2.4 Components (hub.css + `web/components/hub/*.tsx`)

The HUB components are React with inline styles and JS hover handlers. Rebuild them as server
components with CSS classes (hover, press and focus in CSS; no client JS):

**Button** (`components/hub/Button.tsx`; renders `<button>` or, with `href`, `<a>`):
`variant: primary | accent | outline | ghost | danger`, `size: sm | md | lg`, `iconLeft?`,
`fullWidth?`, `disabled?`.

```css
.hub-btn { display:inline-flex; align-items:center; justify-content:center; gap:8px;
  font-family:var(--font-sans); font-weight:var(--fw-bold); line-height:1;
  border-radius:var(--radius-pill); white-space:nowrap; cursor:pointer; text-decoration:none;
  transition: filter var(--dur-fast) var(--ease-standard), transform var(--dur-fast) var(--ease-standard); }
.hub-btn:hover { filter:brightness(1.08); text-decoration:none; }
.hub-btn:active { transform:scale(0.97); }
.hub-btn:disabled, .hub-btn[aria-disabled="true"] { opacity:.45; cursor:not-allowed; filter:none; transform:none; }
.hub-btn--sm { padding:8px 18px; font-size:13px; }
.hub-btn--md { padding:12px 26px; font-size:14px; }
.hub-btn--lg { padding:15px 34px; font-size:15px; }
.hub-btn--primary { background:var(--ink-900); color:#fff; border:2px solid var(--ink-900); }
.hub-btn--accent  { background:var(--accent); color:var(--text-on-accent); border:2px solid var(--accent); }
.hub-btn--outline { background:transparent; color:var(--ink-900); border:2px solid var(--ink-900); }
.hub-btn--ghost   { background:transparent; color:var(--ink-900); border:2px solid transparent; }
.hub-btn--ghost:hover { background:var(--surface-page); }   /* HUB readme: ghost fills with page grey */
.hub-btn--danger  { background:var(--status-danger); color:#fff; border:2px solid var(--status-danger); }
.hub-btn--full { width:100%; }
```

**Badge** (`components/hub/Badge.tsx`): `tone: neutral | accent | success | warning | danger | info`,
`variant: soft (default) | solid`.

```css
.hub-badge { display:inline-flex; align-items:center; gap:6px; font-weight:var(--fw-bold);
  font-size:12px; line-height:1; letter-spacing:.02em; padding:6px 12px;
  border-radius:var(--radius-pill); white-space:nowrap; }
```

| tone | soft (bg / text) | solid (bg / text) |
|---|---|---|
| neutral | `#f1f1f1` / `#231f20` | `#231f20` / `#ffffff` |
| accent | `#e7fbf6` / `#0f8174` | `#30e3ca` / `#231f20` |
| success | `#d8f5e6` / `#1c7a4d` | `#2bb673` / `#ffffff` |
| warning | `#fdeccb` / `#c97f0a` | `#f5a623` / `#231f20` |
| danger | `#fbe0de` / `#b53b33` | `#e0584f` / `#ffffff` |
| info | `#dce9fb` / `#2858a8` | `#3b7be0` / `#ffffff` |

**Card** (`components/hub/Card.tsx`, renders `<section>` with `aria-labelledby` when it has a
title): `padding: none | sm | md | lg` = 0 / 16 / 24 / 32 px.

```css
.hub-card { background:var(--surface-card); border:1px solid var(--border-subtle);
  border-radius:var(--radius-lg); box-shadow:var(--shadow-sm); }
.hub-card--table { overflow:hidden; }          /* header row clips to the 16px corners */
.hub-card__scroll { overflow-x:auto; }          /* tables scroll inside the card when narrow */
```

**Tabs** (`components/hub/Tabs.tsx`) — link tabs (each tab an `<a href>` with
`aria-current="page"` when active; server-rendered, no JS):

```css
.hub-tabs { display:flex; gap:4px; border-bottom:1px solid var(--border-subtle); }
.hub-tab { position:relative; display:inline-flex; align-items:center; gap:8px; padding:12px 16px;
  font-size:14px; font-weight:var(--fw-bold); color:var(--text-muted); text-decoration:none;
  transition: color var(--dur-fast) var(--ease-standard); }
.hub-tab:hover { color:var(--text-strong); text-decoration:none; }
.hub-tab[aria-current="page"] { color:var(--text-strong); }
.hub-tab::after { content:""; position:absolute; left:0; right:0; bottom:-1px; height:3px;
  border-radius:3px 3px 0 0; background:transparent; }
.hub-tab[aria-current="page"]::after { background:var(--accent); }
.hub-tab__count { font-size:11px; font-weight:var(--fw-bold); padding:2px 8px;
  border-radius:var(--radius-pill); background:var(--surface-page); color:var(--text-muted); }
.hub-tab[aria-current="page"] .hub-tab__count { background:var(--mint-100); color:var(--mint-700); }
```

**TextField / Select** (`components/hub/TextField.tsx`, `Select.tsx`; native `<input>` /
`<select>` with `<label for>`): label 13px / 600 / `--text-strong`, 7px below it the control;
control border `1.5px solid var(--border-default)` (`#d7d7d7`), radius 10px, background white,
14px `--text-strong`; input padding `11px 0` inside a `0 14px` wrapper (height 43px); select
padding `11px 38px 11px 14px`, `appearance:none`, caret at right 14px, vertically centred,
`pointer-events:none`, colour `--text-muted`: the HUB draws the character "▾" at 11px; draw it as
an inline SVG (`width="10" height="6" viewBox="0 0 10 6"`, path `M1 1l4 4 4-4`, stroke
`currentColor` 1.5, no fill) because the self-hosted Inter subset has no U+25BE. (All other
characters used on these pages — · — → › ± ° × − … “ ” — are in the subset, see
`WEB_UNICODES` in `tools/brand/generate_plan_brand.py`.) Focus (`:focus-within` on the wrapper / `:focus` on select):
border `var(--accent)` and `box-shadow: 0 0 0 3px rgba(48,227,202,0.18)`. Error: border
`var(--status-danger)`, message 12px `--status-danger` 6px below. Hint 12px `--text-muted`
6px below. `fullWidth` default true; `false` = `width:auto` (filter bar fields have fixed widths).
Placeholder colour `--text-muted`.

**Avatar** (`components/hub/Avatar.tsx`): circle, `size` px (34 in the sidebar), background
`--mint-100` `#c5f6ec`, text `--mint-700` `#0f8174`, weight 600, font size `round(size × 0.4)`
(14 px at 34). Initials = first letter of each of the first two words, uppercased; empty → "?".
`aria-hidden="true"` (the name is printed next to it).

**StatusGlyph** (`components/hub/StatusGlyph.tsx`): inline SVG, `aria-hidden="true"`,
`viewBox="0 0 10 10"`, `fill="currentColor"` (or a given fill), default 9×9 px:

| kind | shape |
|---|---|
| `circle` (Ready / Passed / done) | `<circle cx="5" cy="5" r="4.6"/>` |
| `triangle` (Limited) | `<path d="M5 .6 9.6 9.4H.4z"/>` |
| `square` (Blocked / failed) | `<rect x=".6" y=".6" width="8.8" height="8.8"/>` |
| `dash` (Not applicable) | `<rect x="1" y="4.3" width="8" height="1.4"/>` |
| `ring` (waiting) | `<circle cx="5" cy="5" r="4" fill="none" stroke="currentColor" stroke-width="1.4"/>` |

**VerdictBadge** (`components/hub/VerdictBadge.tsx`): from a package `status` and optional
`outcome`:

| Input | Badge |
|---|---|
| outcome `ready` | tone success, circle glyph, "Ready" |
| outcome `limited` | tone warning, triangle glyph, "Limited" |
| outcome `blocked` | tone danger, square glyph, "Blocked" |
| status `uploading` or `checks_queued` | tone neutral, no glyph, "Not checked yet" |
| status `checking` | tone neutral, no glyph, "Checks running" |
| status `check_error` | tone neutral, no glyph, "Checks did not finish" |

Props `suffix?: string` (e.g. " · latest") and `variant?: "soft" | "solid"`.

**ProgressBar** (`components/hub/ProgressBar.tsx`): `role="progressbar"`,
`aria-valuemin=0`, `aria-valuemax=100`, `aria-valuenow`, `aria-label`; track
`background:#e6e6e6` (`--gray-200`), fill `--accent` `#30e3ca`. Sizes: `table` = 140×4 px,
radius 2px, 6px margin-top; `block` = 100% × 6 px, radius 3px.

**Eyebrow** classes: `.hub-eyebrow` 13px, uppercase, `letter-spacing:.16em`, `--text-muted`,
weight 600 (aside card titles); `.hub-eyebrow--sm` same at 12px (verdict card columns).

**Tables** (`.hub-table`):

```css
.hub-table { width:100%; border-collapse:collapse; }
.hub-table th { text-align:left; background:var(--surface-muted); padding:12px 22px;
  font-size:11px; text-transform:uppercase; letter-spacing:.1em; color:var(--text-muted);
  font-weight:var(--fw-bold); white-space:nowrap; }
.hub-table td { padding:14px 22px; }            /* projects, packages tables */
.hub-table--compact td { padding:12px 22px; vertical-align:top; }  /* checks, files */
.hub-table tbody tr { border-top:1px solid var(--border-subtle); }
.hub-table tbody tr:hover { background:var(--surface-muted); }
.hub-table td.hub-table__action { padding:8px 22px; text-align:right; }
.hub-cell-title { font-weight:var(--fw-bold); color:var(--text-strong); }
.hub-cell-sub { font-size:12px; color:var(--text-muted); }
.hub-cell-sub.mono { font-family:var(--font-mono); }
```

A visually hidden header label for action columns: `<th><span class="visually-hidden">Open</span></th>`
(the bundle uses `position:absolute; left:-9999px`, same thing).

Icons: inline SVG, `viewBox="0 0 24 24"`, `fill="none"`, `stroke="currentColor"` (or as stated),
`stroke-width="2"`, `stroke-linecap="round"`, `stroke-linejoin="round"`, `aria-hidden="true"`:

| Icon | Paths |
|---|---|
| Projects (folder) | `M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z` |
| Packages (box) | `M21 8l-9-5-9 5v8l9 5 9-5z` and `M3 8l9 5 9-5M12 13v9` |
| Decision log | `M10 6h11M10 12h11M10 18h11M3 6l1.5 1.5L7 5M3 12l1.5 1.5L7 11M3 18l1.5 1.5L7 17` |
| Intake guide (book) | `M2 4h6a4 4 0 0 1 4 4v12a3 3 0 0 0-3-3H2zM22 4h-6a4 4 0 0 0-4 4v12a3 3 0 0 1 3-3h7z` |
| Search | `<circle cx="11" cy="11" r="7"/>` and `M20 20l-3.5-3.5` |
| Back | `M19 12H5M12 19l-7-7 7-7` |
| Download | `M12 3v12M6 11l6 6 6-6M4 21h16` (stroke-width 2.2) |

Put them in `components/hub/icons.tsx`.

---

## 3. App shell

`web/app/(review)/layout.tsx` (server): reads `getViewerSession()` (React-cached; pages still
call `requireViewerSession(returnTo)` so the sign-in return path is kept). Renders:

```
<div class="shell">            display:flex; min-height:100vh; background:var(--surface-page)
  <Sidebar viewer=… links=… /> 248px, sticky
  <div class="shell__body">    flex:1; min-width:0; display:flex; flex-direction:column
    {children}                 each page renders <Topbar title=…/> then <main class="page">
```

### 3.1 Sidebar (`components/shell/Sidebar.tsx`, nav part `SidebarNav.tsx` is a client component using `usePathname`)

- `<aside>`: width 248px, `flex:none`, `position:sticky; top:0; height:100vh`, background
  `--surface-inverse` `#231f20`, `display:flex; flex-direction:column; padding:22px 16px`.
- Brand block: column, gap 6px, padding `4px 10px 22px`:
  - `<a href="/" aria-label="Chapter capture review, home">` containing
    `<img src="/brand/chapter-wordmark.svg" alt="" width="96" height="22">`, CSS
    `height:22px; width:auto; display:block; filter:brightness(0) invert(1)` (pure white; the
    bundle's `invert(1)` gives `#dde0e0`, the HUB readme says the wordmark "reverses to white").
  - Label "Capture review": 11px, `letter-spacing:.16em`, uppercase, `rgba(255,255,255,0.45)`,
    weight 600.
- `<nav aria-label="Main">`: column, gap 3px. Items are links: `display:flex; align-items:center;
  gap:12px; padding:11px 12px; border-radius:10px; font-size:14px; font-weight:600;
  text-decoration:none`. Inactive colour `rgba(255,255,255,0.55)`, hover
  `rgba(255,255,255,0.85)` (no underline). Active: `aria-current="page"`,
  background `rgba(255,255,255,0.10)`, colour `#fff`, icon stroke `var(--accent)` `#30e3ca`.
  Icon 18×18.

  | Item | href | Active when pathname | Shown to |
  |---|---|---|---|
  | "Projects" (folder) | `/` | `/`, `/projects/…`, `/packages/<id>…` | everyone |
  | "Packages" (box) | `/packages` | exactly `/packages` | everyone |
  | "Decision log" (list) | `/decisions` | `/decisions` | bim, admin only (hidden for capture) |
  | "Intake guide" (book) | `INTAKE_GUIDE_URL` | never | everyone, only when the env var is set; `target="_blank" rel="noopener noreferrer"` plus visually hidden " (opens in a new tab)" |

- User block: `margin-top:auto; display:flex; align-items:center; gap:10px; padding:10px;
  border-top:1px solid rgba(255,255,255,0.08)`. Avatar 34 px (initials of `viewer.name`), then
  a block with `line-height:1.2`: name 13px / 600 / `#fff` (`viewer.name`); second line 12px
  `rgba(255,255,255,0.45)`: `"{roleLabel} · Entra"` where roleLabel = "Admin" | "BIM operator" |
  "Capture operator" | "No station role" (`lib/roles.ts roleLabel`, unchanged). Drawn:
  "BIM operator · Entra".

### 3.2 Topbar (`components/shell/Topbar.tsx`)

- `<header>`: height 64px, `flex:none`, `display:flex; align-items:center;
  justify-content:space-between; padding:0 32px; background:var(--surface-card);
  border-bottom:1px solid var(--border-subtle)`.
- Left: `<h1>` 22px / 600 / `--text-heading` `#000`, margin 0, one line, ellipsis on overflow.
  Text per page (exact): Projects page "Capture review"; Packages page "Packages"; Decision log
  page "Decision log"; Project page = project title; Package page = `{project title} · Revision {n}`.
- Right: `display:flex; align-items:center; gap:16px`:
  - Search (`components/shell/SearchField.tsx`): `<form role="search" action="/" method="get">`
    with a `<label>` styled as a pill: `display:flex; align-items:center; gap:8px;
    background:var(--surface-page); border-radius:100px; padding:9px 16px; width:260px`; search
    icon 16×16 stroke `--text-muted`; `<input type="search" name="q" maxlength="200"
    autocomplete="off" placeholder="Address, deal or capture id" aria-label="Search projects">`
    `border:none; background:transparent; outline:none; font-size:13px;
    color:var(--text-strong); width:100%`. Focus: the pill gets
    `box-shadow:0 0 0 3px rgba(48,227,202,0.18)` (`:focus-within`). Prefilled with the current
    `q` on the Projects page. Submitting goes to `/?q=…` (Projects page).
  - Button outline sm "Open the HUB" → `HUB_APP_URL` (§9.3), `target="_blank"
    rel="noopener noreferrer"`, visually hidden " (opens in a new tab)". Not rendered when
    `HUB_APP_URL` is unset.

### 3.3 Page body

`<main class="page" id="main">`: `padding:24px 32px 40px; display:flex; flex-direction:column;
gap:20px; font-size:14px; line-height:1.5; color:var(--text-body)`. Max content width: none (the
drawing is 1440 wide: 1440 − 248 = 1192, minus 64 padding = 1128 px content).

Two-column grid (project and package pages): `.page-grid { display:grid;
grid-template-columns:minmax(0,1fr) 340px; gap:20px; align-items:start; }`, each column
`display:flex; flex-direction:column; gap:20px; min-width:0`.

Page heading block (h2): 26px / 600 / `--text-heading`, `letter-spacing:-0.02em`, margin 0.
Card title (h3): 16px / 600 / `--text-heading`, margin 0.

### 3.4 Responsive (not drawn; keep the drawing exact at ≥ 1200 px)

- 1200 px and wider: as drawn.
- 900–1199 px: `.page-grid` becomes one column; the aside cards follow the main cards in a
  `grid-template-columns: repeat(auto-fill, minmax(320px, 1fr))` grid. Topbar search width
  200px.
- Below 900 px: the sidebar becomes a top bar (`position:static; width:100%; height:auto;
  flex-direction:row; flex-wrap:wrap; padding:12px 16px; gap:12px`): brand block left, nav as a
  horizontal row that scrolls (`overflow-x:auto`), user block hidden. `.shell` becomes
  `flex-direction:column`. Topbar wraps: title on its own line, search 100% wide, "Open the HUB"
  hidden. Page padding `16px 16px 32px`. Tables scroll inside their card (min-width 760px).
  Decision form one column.

---

## 4. Routes

| URL | File | Who | Notes |
|---|---|---|---|
| `/` | `app/(review)/page.tsx` | all roles | Projects (2h). Query: `q` (≤200 chars), `tab` = `all` (default) \| `blocked` \| `limited` \| `ready` \| `progress` |
| `/packages` | `app/(review)/packages/page.tsx` | all roles | Packages list (not drawn, §6.2). Query `q` |
| `/projects/[dealId]` | `app/(review)/projects/[dealId]/page.tsx` | all roles | Project (2i). Query `tab` = `packages` (default) \| `log` (bim, admin; capture → treated as `packages`) |
| `/packages/[packageId]` | `app/(review)/packages/[packageId]/page.tsx` | all roles | Package (2j). Query: `file` (deep link from the HUB, kept from v1), `floor` (areaKey of the plan preview) |
| `/packages/[packageId]/decisions` | `app/(review)/packages/[packageId]/decisions/page.tsx` | — | v1 page; now `permanentRedirect(`/packages/${id}#decisions`)` so old links keep working |
| `/decisions` | `app/(review)/decisions/page.tsx` | bim, admin | Global decision log (not drawn, §6.5); capture → "No access" card |
| `/packages/[id]/files/download?path=` | `app/(review)/packages/[packageId]/files/download/route.ts` | bim, admin | Unchanged behaviour (303 to the station's 10-minute link, `no-store`, `no-referrer`); also accepts the manifest path (§9.1 F) |
| `/packages/[id]/files/preview?path=` | `…/files/preview/route.ts` | bim, admin | Unchanged (plan PNG streamed through the app) |
| `/packages/[id]/report/download` | `…/report/download/route.ts` (new) | bim, admin | 303 to the station's spatial report link (§9.1 G) |
| `/packages/[id]/verdict.json` | `…/verdict.json/route.ts` (new) | bim, admin | Streams `GET /v1/packages/{id}/verdict` as `application/json`, `content-disposition: attachment; filename="verdict-r{revision}.json"`, `cache-control: no-store`; 404 text "No verdict yet." when not ready |
| `/packages/[id]/archive` | `…/archive/route.ts` (new, phase 3) | bim, admin | "Download all" (§6.4.1, §9.1 H) |
| `/sign-in` | `app/sign-in/page.tsx` | no session | HUB look (§6.7) |

Route handlers move with their pages into the `(review)` group (URLs unchanged; layouts do not
apply to route handlers). The proxy matcher is unchanged
(`/((?!api/auth|brand/|_next/static|_next/image|favicon.ico).*)`), so `/brand/chapter-wordmark.svg`
is served without a session.

Page `<title>` (metadata, static): "Projects · Capture review", "Packages · Capture review",
"Project · Capture review", "Package · Capture review", "Decision log · Capture review",
"Sign in · Capture review"; root default "Capture review · Chapter".

---

## 5. Shared text rules (one implementation, used by every page)

Put the verdict/check wording in `contract/ts/src/review-text.ts` (exported from
`@chapter/capture-contract`) so the station's spatial report (pdfkit, TypeScript) prints the same
words. Dependency: `spatial-report` (whichever area lands first creates it; the other imports
it). Formatting helpers that only the web uses stay in `web/lib/format.ts`.

### 5.1 Verdict words

| outcome | word | glyph | headline (`verdictHeadline(verdict)`) | headline colour on white |
|---|---|---|---|---|
| ready | "Ready" | circle | `Ready for ${lowerFirst(verdict.task)}` → "Ready for preliminary existing-condition plans" | `#1c7a4d` |
| limited | "Limited" | triangle | "Limited: usable with named limitations" | `--amber-600` `#c97f0a` |
| blocked | "Blocked" | square | "Blocked: missing information prevents the task" | `--red-700` `#b53b33` |

`lowerFirst` lower-cases the first character only when the second character is lower case.
Verdicts always show a word and a shape; colour is never alone.

### 5.2 Capture check rows (`checkRows(verdict)`)

For each `verdict.checks[i]` (in that order) build one row:

- `findings` = `verdict.findings` with the same `ruleId`, ordered blocker, limitation, info
  (station order inside each severity).
- `result`:
  - `check.status = "not_applicable"` → `not_applicable`, word "Not applicable", glyph dash,
    badge tone neutral;
  - else any blocker finding → `blocked`, "Blocked", square, tone danger;
  - else `check.status = "failed"` or any limitation finding → `limited`, "Limited", triangle,
    tone warning;
  - else → `passed`, "Passed", circle, tone success.
- "What was found": one block per finding. Line 1 (inherits `--text-body`): the finding's
  `message`, prefixed `"{capture label}: "` when the package has more than one capture and the
  finding has `captureId` (label from the capture record, else the areaKey). Line 2 (12px
  `--text-muted`): `"Measured: {measured}"` and/or `"Expected: {expected}"` joined by " · ";
  omitted when both are absent. Blocks 6px apart. No findings → "—".
- "Next action": the distinct `nextAction` values of the row's findings that are not "None",
  one per line; none left → "None" in `--text-muted`.
- Findings whose `ruleId` is not in `verdict.checks` get an extra row at the end with
  `title = ruleId` and the result from their worst severity.

`sortCheckRows(rows)` (web only): stable sort blocked → limited → passed → not applicable.

`checkCounts(rows)` and `countsLine(counts)`:
`"{b} blocker(s) · {l} limitation(s) · {p} passed · {n} not applicable"` with singular "1 blocker",
"1 limitation"; e.g. "0 blockers · 2 limitations · 5 passed · 2 not applicable". Counts are of
check rows, not findings (this changes v1, which counted findings).

`ruleSetLabel(verdict.evaluator)` → `"station-checks v{evaluator.version}"` (report and web).

### 5.3 Orientation (compass) words

Input: the per-capture compass fields the `compass` area adds to `capture-record.json`
(`heading` 0–360°, `headingAccuracy` °, `headingSource` `"true" | "magnetic"`,
`headingRecordedAt`), through the shared `orientationOf(capture)` (owned by `compass`; if it does
not exist when this area is built, implement it in `contract/ts/src/review-text.ts` with exactly
these rules):

- no `heading` → `not_verified`, reason "no compass reading";
- `headingAccuracy > 30` → `not_verified`, reason "accuracy worse than ±30°";
- `headingSource = "true"` and `headingAccuracy ≤ 10` → `verified`;
- otherwise (accuracy 10–30, or magnetic with accuracy ≤ 30) → `approximate`.

Degrees are rounded to whole numbers.

| state | Plan card "Orientation" value | Capture record "Compass" value |
|---|---|---|
| verified | "Verified · true north · compass ±{acc}° · {hdg}°" | "Read at scan start · ±{acc}° · true north" |
| approximate | "Approximate · compass ±{acc}° · {true \| magnetic} heading" | "Read at scan start · ±{acc}° · approximate" |
| not verified, no reading | "Not verified · no compass reading. North is not shown." (drawn) | "Not read · orientation not verified" (drawn) |
| not verified, too coarse | "Not verified · accuracy worse than ±30°. North is not shown." | "Read at scan start · ±{acc}° · not verified" |

Until the compass feature ships every package is "not verified, no reading".

### 5.4 Numbers, sizes, dates (web/lib/format.ts)

| Helper | Output | Example |
|---|---|---|
| `formatBytes(n)` | decimal units, 1 decimal below 10, unit "B", "KB", "MB", "GB" (drawn "14 KB") | 14 KB · 1.2 MB · 96 MB · 768 MB |
| `formatMm(n)` | rounded, en-US grouping, " mm" | 7,520 mm · 2,490 mm |
| `formatSqFt(n)` | 1 decimal, grouping, " sq ft" | 807.5 sq ft |
| `formatDate(iso)` | America/New_York, "MMM D, YYYY" (unchanged) | Jan 25, 2025 |
| `formatDateTime24(iso)` | America/New_York, `MMM D, YYYY HH:mm` 24 h, no zone | May 16, 2026 14:02 |
| `formatDayTime(iso, previous?)` | "MMM D · HH:mm"; only "HH:mm" when on the same NY day as `previous` | May 16 · 13:58 · 14:01 |
| `dayLabel(iso, now)` | "Today" when the NY calendar day equals now's, else `formatDate` | Today · Jan 25, 2025 |
| `updatedAgo(iso, now)` | "just now" (< 1 min), "{m} min ago" (< 60), "{h} h ago" (< 24 h), else `formatDate` without year when same year | 2 min ago |
| `shortSha(sha)` | first 4 + "…" + last 4 (unchanged) | 9f2c…a41e |
| `shortId(uuid)` | first 8 characters + "…" | 3f6c2a9e… |
| `plural(n, word)` | unchanged | 1 floor · 2 floors |

Every abbreviated time or id has the full value in a `title` attribute (`formatDateTime`
"Oct 17, 2026, 11:20 AM EDT", full UUID, full SHA-256). `<time dateTime={iso}>` around times.

Areas noun: "floor"/"floors" when every capture's mode is `floor`, else "area"/"areas"
(`areaCount`, unchanged). Mode labels: `room` "one room", `floor` "whole floor", `exterior`
"exterior". `modeSummary` now always prints the count: "whole floor × 1", "whole floor × 2",
"whole floor × 1, exterior × 1" (drawn "whole floor × 1").

### 5.5 Project title

`projectTitle = HubProject.projectName ?? HubProject.address.formatted`. When the project has a
name, the address is printed in the meta line. Fallbacks when the HUB no longer knows the deal
(`getProject` 404): newest sealed capture record `hub.projectName ?? address.formatted`, else
"HUB deal {dealId}".

### 5.6 Not-scanned rooms

From each capture's `omittedRooms` and `inaccessibleRooms` (capture record, `roomNote
{name, reason?}`): omitted → `"{name} ({reason})"`, or `"{name} (not scanned)"` without a reason;
inaccessible → `"{name} (could not enter)"`. Joined with " · ". With more than one capture each
capture's list is prefixed `"{label}: "` and captures are separated by a line break. None → "None".
Drawn: "Primary closet (locked) · Storage room (could not enter)".

---

## 6. Screens

All sizes px, colours as tokens (hex in §2.3). "Muted" = `--text-muted`, "ink" =
`--text-strong` `#231f20`, "body" = `--text-body`.

### 6.1 Projects (2h) — `/`

Data: `GET /v1/review/projects?q=` (§9.1 C). Tab counts and the tab filter are computed in the
web from the returned list.

Layout (top to bottom, gap 20):

1. **Heading row**: `display:flex; justify-content:space-between; align-items:flex-end; gap:16px`.
   - Left column (gap 4): h2 "Projects" (26/600, tracking −0.02em); 14px muted
     "Capture packages from the station, by project. Verdicts are the station's; re-sealing a
     Blocked package happens on the phone."
   - Right: 13px muted `"{n} project(s) · updated {updatedAgo(max latest.updatedAt)}"`
     (drawn "5 projects · updated 2 min ago"). With `q`, n is the number of matches (same text).
     Hidden when n = 0.
2. **Tabs** (link tabs, `?tab=`; `q` kept in every href):
   "All {n}", "Blocked {n}", "Limited {n}", "Ready {n}", "Uploading {n}" — ids `all`, `blocked`,
   `limited`, `ready`, `progress`. Membership by the project's **latest** package: verdict
   outcome for the first three; `progress` = latest has no verdict (status `uploading`,
   `checks_queued`, `checking` or `check_error`). All tabs always shown, counts may be 0.
3. **Table card** (Card padding none, `.hub-card--table`), `.hub-table`:

   | Column header | Cell |
   |---|---|
   | "Project" | line 1 `.hub-cell-title` project title (§5.5); line 2 12px muted mono `deal {dealId}` |
   | "Latest package" | Sealed: `Revision {n} · sealed {formatDate(sealedAt)}`. Uploading: `Revision {n} · uploading from the phone` + ProgressBar `table` (140×4, 6px above) at `bytesVerified / bytesTotal`, `aria-label="Upload {pct}%"`. Checks queued/running/error: `Revision {n} · sealed {date}` |
   | "Verdict" | VerdictBadge (soft) of the latest package |
   | "Floors" | number of captures of the latest package (`latest.captures.length`); "—" when 0 |
   | "Captured" | Sealed: `{dayLabel(captureRecord.visitedAt)} · {operator.name}` (from `latest.visitedAt`, `latest.operatorName`). Uploading (no capture record yet): `{dayLabel(createdAt)} · {createdBy.name}`; missing name → date only |
   | "In the HUB" | `publication.status = published` → `Published {formatDate(publishedAt)}`; `pending`/`publishing` → "Publishing…" muted; `publish_failed` → "Publishing failed" in `--red-700`; no publication and outcome blocked → "Not published · re-seal needed"; no publication otherwise → "—" muted |
   | (hidden "Open") | `.hub-table__action`: Button outline sm "Open" → `/projects/{dealId}` (accessible name "Open {project title}") |

   Rows in the station's order (most recent package activity first). Row hover tint.
4. **Legend** 12px muted: "Verdicts always show a word and a shape: ● Ready · ▲ Limited · ■ Blocked."
   (The drawn second sentence "Capture-role users see this list and the status only." is a design
   annotation; it is not rendered.) The ● ▲ ■ marks are drawn as 9px StatusGlyph SVGs
   (`aria-hidden`) inline before each word, not as font characters (the self-hosted Inter subset
   is not guaranteed to contain them).
5. **Truncated** (station returned `truncated: true`): row under the table inside the card,
   `padding:10px 22px 14px; border-top:1px solid var(--border-subtle)`, 12px muted:
   "Showing the {n} most recently active projects. Search by address, deal or capture id to find
   others."

States:

| State | What shows (inside the table card, replacing the table body) |
|---|---|
| No projects at all (station has no packages) | Empty state: centred column, padding 48px 24px, gap 8: box icon 32×32 stroke `--text-muted`; 16/600 heading-colour "No capture packages yet"; 14px body "Packages appear here when the Chapter Capture app uploads a sealed capture."; tabs still shown with 0 counts; heading-row right text hidden |
| Search matches nothing | Same empty layout: "No project matches “{q}”" / "Search by address, deal or capture id." + Button ghost sm "Clear search" → `/` |
| Tab empty | 14px muted single row `colspan=7`, padding 24px 22px: "No {Blocked/Limited/Ready} projects." or for progress "No packages uploading or being checked." |
| Station error | Problem card (§6.8) instead of tabs + table |
| No station role | "No access" problem card (§6.8) |

### 6.2 Packages (sidebar "Packages", not drawn) — `/packages`

Data: `GET /v1/review/packages?q=` (§9.1 D). Topbar title "Packages". Heading h2 "Packages",
sub 14px muted "Every package revision the station has, newest first." Right 13px muted
`"{n} package(s)"`. Table card columns: "Package" (title line: project title; sub line 12px
muted: `Revision {n} · ` + mono `capture {shortId}`), "Verdict" (VerdictBadge), "Captured"
(as §6.1), "Checked" (`formatDateTime24(verdict.evaluatedAt)` or "—"), "In the HUB" (as §6.1),
action Button outline sm "Open" → `/packages/{packageId}`. Empty: "No capture packages yet"
(same empty state as §6.1). Truncated line: "Showing the {n} newest packages. Search by address,
deal or capture id to find others."

### 6.3 Project (2i) — `/projects/[dealId]`

Data: `getProject(dealId)`, `listPackages(dealId)` (extended summaries), `getVerdict` of the
newest package that has a verdict, bim/admin: `GET /v1/modeling-decisions?dealId=` (§9.1 E),
revision diff inputs (§6.3.4).

1. **Back link**: `<a href="/">` "Projects" with the back icon 15×15; 13px / 600 / muted,
   `display:inline-flex; gap:6px; align-self:flex-start`.
2. **Title row**: `display:flex; align-items:flex-start; justify-content:space-between; gap:16px`.
   - Left column (gap 6):
     - Row (gap 12, align center): h2 project title (26/600, −0.02em) + VerdictBadge (soft) of
       the newest package **with a verdict**, suffix " · latest" (drawn "▲ Limited · latest").
       No badge when no package has a verdict.
     - Meta row 14px muted, `display:flex; gap:16px; flex-wrap:wrap`: address (only when the
       project has a name, §5.5); mono `deal {dealId}`; `"{n} package(s)"` (drawn "2 packages").
       The drawn "PM [NAME]" is **not available** (the HUB project has no PM field in the
       station API) → not rendered.
   - Right (gap 10): Button outline sm "Open in the HUB" → HUB deal URL (§9.3; hidden when not
     configured); Button primary sm `Spatial report PDF · r{revision}` → report download route of
     the newest package whose `report.status = ready` (bim/admin only; hidden otherwise).
3. **Tabs**: "Packages {packageCount}" (`?tab=packages`) and, bim/admin only,
   "Decision log {decisionCount}" (`?tab=log`).
4. **Grid** (`.page-grid`):

#### 6.3.1 Main column, tab "Packages"

**Packages table** (Card none, table):

| Header | Cell |
|---|---|
| "Package" | title `Revision {n}`; sub line 12px muted: sealed → mono `capture {shortId(first captureId)}` (+ ` +{k}` when more captures; full ids in `title`); uploading → "uploading from the phone · {pct}%"; checks queued/running → "sealed · checks running"; check error → "sealed · checks did not finish". When the project has packages from more than one `visitId`, prefix the sub line with `visit {formatDate(visitedAt or createdAt)} · ` |
| "Verdict" | VerdictBadge (soft) |
| "Captured" | as §6.1 |
| "Checked" | `formatDateTime24(checks.finishedAt ?? verdict.evaluatedAt)`; "—" muted without |
| "Contents" | With a verdict or sealed: `"{floors} · {rooms} rooms · {files} files · {size}"` where floors = `plural(captures, "floor"/"area")`, rooms = sum of `report.floors[].roomsScanned` (omit the "rooms" part when the report has no floors facts), files = `totals.files`, size = `formatBytes(totals.bytes)` (drawn "1 floor · 12 rooms · 75 files · 768 MB"). A revision > 1 without a verdict: the compact diff line (§6.3.4) e.g. "+ primary closet · + 1 control · + 3 photos" |
| "In the HUB" | as §6.1 ("Published May 16, 2026" or "—") |
| (hidden "Open") | Button outline sm "Open" → `/packages/{packageId}` |

Newest first (station order). A revision the phone has sealed but not started uploading is not
known to the station and is not listed (the drawn row "Revision 2 · not sealed · on the phone" is
**not available**; the closest real state is "uploading from the phone").

**"What revision N adds" card** (Card md): shown when the newest package of the newest visit has
`revision > 1` and no verdict yet.
- Header row (`justify-content:space-between; align-items:baseline`): h3 `What revision {n} adds`;
  12px muted right: uploading → "uploading from the phone, not checked yet"; sealed without
  verdict → "sealed, checks running"; check error → "sealed, checks did not finish".
- Tiles grid `repeat(3, minmax(0,1fr))`, gap 12 (wraps to more rows). Tile: padding 12px 14px,
  radius 10, background `--surface-muted`, border 1px `--border-subtle`; title 14px / 600 / ink;
  sub 13px muted. Tiles from §6.3.4, at most 6, then a 13px muted line "+{k} more changes".
- Footer 12px muted: "Revision {prev} stays unchanged and keeps its verdict. The station checks
  revision {n} as a whole package and issues a new spatial report."

#### 6.3.2 Main column, tab "Decision log" (bim, admin)

Card md: header row h3 "Modeling decision log" + right 13px muted
`"{n} entries · newest first"`. Entries newest first across every package of the project, each:
the entry layout of §6.4.7 plus a neutral soft Badge `Revision {n}` before the element. Below the
list, 13px: link `Log a decision on revision {n} →` → `/packages/{newest packageId}#decisions`.
Empty: 13px muted "No decisions logged yet."

#### 6.3.3 Aside

**Latest verdict card** (Card md, column gap 12) — newest package with a verdict:
- Eyebrow 13px: `Latest verdict · revision {n}`.
- Word row: glyph 14×14 + word, 18px / 600, colour per §5.1 (`#c97f0a` for Limited), gap 8.
- 14px ink: `verdict.summary`.
- Group (gap 6): 12px / 600 / ink "Limitations"; each `verdict.limitations[i]` 13px. Omitted when
  empty.
- Group: "Next actions"; each `verdict.nextActions[i]` 13px. Omitted when empty.
- Button ghost sm "Capture checks →" → `/packages/{packageId}#checks` (bim/admin only).
- No package with a verdict: eyebrow "Latest verdict", 14px muted "No verdict yet. The station
  checks a package after it is sealed."

**Decision log card** (bim/admin; Card md, gap 12):
- Eyebrow `Decision log · {n} entries` ("1 entry").
- The newest two entries, each column gap 4, padding-bottom 10 and hairline bottom border except
  the last: 13px ink `<b>{element}</b> — {decision}`; 12px muted `{decidedBy.name} ·
  {formatDateTime24(decidedAt)}`.
- Button ghost sm "All entries →" → `?tab=log`.
- Empty: 13px muted "No decisions logged yet." and no button.

#### 6.3.4 Revision diff (`web/lib/revision-diff.ts`)

Inputs: the new package `B` (newest, revision > 1) and `A` = the package with
`packageId = B.supersedesPackageId` (fetch with `getPackage`; when absent at the station: no diff,
card shows only the footer). Compare files by `path` and `sha256`; captures by `captureId`.

| Change | Tile title | Tile sub | Compact text |
|---|---|---|---|
| capture in B not in A | `{label} scanned` (label from B's capture record, else the areaKey humanised: "primary-closet" → "Primary closet") | `{mode label} · {k} files` (mode unknown → `new capture · {k} files`) | `+ {label lower-cased}` |
| capture in A not in B | `{label} removed` | `not in revision {B.revision}` | `− {label lower-cased}` |
| field controls added/changed (both packages have `fieldControls`, §9.1 B) | per added or changed control: distance `Distance {axis}, {method}` / ceiling `{room} ceiling height, {method}` / opening `{room} {label}, {method}` / floor to floor `Floor to floor, {method}` / landmark `Landmark: {label}` | distance `{from} to {to} · {mm}`; ceiling `{mm}`; opening `{width mm} wide`; floor to floor `{location} · {mm}`; landmark `{n} captures` | `+ {k} control(s)` |
| field-controls file changed but B not sealed yet | "Field controls updated" | "field-controls.json changed" | `+ controls` |
| photos added | `{k} photos` | capture labels of the added photos joined " · " (lower-cased) | `+ {k} photos` |
| other files changed (same path, other sha) | `{k} files changed` | role labels joined ", " | `{k} files changed` |

Drawn examples: "Primary closet scanned", "Room 4 ceiling height, tape" / "2,490 mm",
"3 photos". The drawn subs "answers limitation 1 · coverage" / "answers limitation 2 · …" are
**not available** (nothing links a change to a limitation) and are replaced by the subs above.

### 6.4 Package (2j) — `/packages/[packageId]`

Data: `getPackage(id)` (extended, §9.1 A/B), `getVerdict(id)` when `status = verdict_ready`,
`getProject(dealId)` (title), `listPackages(dealId)` (newer revisions), bim/admin:
`listModelingDecisions(id)`.

#### 6.4.1 Header

1. **Breadcrumb** (13px muted, flex gap 8, align center): link "Projects" (`/`, 600, link colour);
   "/"; link project title (`/projects/{dealId}`); "/"; `Revision {n}` (muted).
2. **Title row** (`justify-content:space-between; align-items:flex-start; gap:16px`):
   - Left (column gap 6, `min-width:0`):
     - Row (gap 12, wrap): h2 `{project title} · Revision {n}` (26/600, −0.02em); VerdictBadge
       **solid** (Limited = `#f5a623` / ink with triangle); publication Badge neutral soft:
       published → "Published to the HUB"; pending/publishing → "Publishing to the HUB"; failed →
       "Not published"; none → no badge.
     - Meta row 14px muted, gap 14, wrap — each item present only when its data is:
       `Captured {formatDate(visitedAt)} by {operator.name}`;
       `{device.marketingName ?? device.model} · app {app.version}`;
       `{modeSummary}` (e.g. "whole floor × 1");
       `sealed {formatDate(sealedAt)}`;
       `checked {formatDateTime24(evaluatedAt)} · rules {ruleSetLabel}`;
       mono `capture {captureId}` (all ids: `captures {id1}, {id2}`).
       Not sealed: only `uploading since {formatDateTime24(createdAt)}`.
   - Right (gap 10, `flex:none`), bim/admin only:
     - Button ghost sm `Download all · {formatBytes(totals.bytes)}` (phase 3, §9.1 H; not rendered
       until the station offers the archive; not rendered while `uploading`). While the archive is
       being prepared: label `Preparing download · {size}`, `aria-disabled="true"`, and the page
       polls (client component `DownloadAllButton`, every 5 s for at most 10 min) then navigates
       to `/packages/{id}/archive`.
     - Button outline sm "Plan sheet PDF": one capture with a verified `plan_pdf` → download route
       of that file; several → `href="#documents"`; none → not rendered.
     - Button primary sm with the download icon (14×14, stroke 2.2) "Spatial report PDF" →
       `/packages/{id}/report/download`; rendered only when `report.status = ready`.

#### 6.4.2 Verdict card (main column, first; Card md) — status `verdict_ready`

Grid `minmax(0,1.2fr) minmax(0,1fr) minmax(0,1fr)`, gap 24:

- Column 1 (column gap 8):
  - Headline row: glyph 16×16 (flex none) + `verdictHeadline`, 18px / 600, line-height 1.2,
    colour per §5.1, gap 10.
  - 14px ink: `verdict.summary`.
  - 13px muted: `countsLine` (§5.2).
  - 12px muted, `margin-top:auto`: `verdict.statement` verbatim ("This verdict is an automated
    check of the intake package. It does not certify any property model or measurement.") —
    the drawn shortened sentence is replaced by the contract's fixed statement, same words as the
    report.
- Column 2 (gap 6): eyebrow-sm "Limitations"; each limitation 13px ink; none → 13px ink "None."
- Column 3 (gap 6): eyebrow-sm "Next actions"; each next action 13px ink; none → "None.". When a
  newer revision of the same visit exists at the station, 12px muted with `margin-top:4px`:
  uploading → `Revision {m} is uploading from the phone.`; sealed without verdict →
  `Revision {m} is being checked.`; with a verdict → `Revision {m} has a newer verdict:` +
  inline VerdictBadge soft; then 13px link `Open revision {m} →`. (Drawn: "Revision 2 is in
  progress on the phone with both." — the station cannot know what a revision fixes, so the text
  states only its status.)

`<section aria-label="Verdict: {word}" data-outcome="{outcome}">` (kept for tests).

#### 6.4.3 Status card (replaces 6.4.2 while there is no verdict; Card md, column gap 10)

| Status | Title (18/600 ink) | Body (14 body) | Extra |
|---|---|---|---|
| `uploading` | "Uploading from the phone" | "Not every file is verified and sealed yet. The checks start when the package is sealed." | ProgressBar `block` + 13px muted `"{formatBytes(bytesVerified)} of {formatBytes(bytesTotal)} · {pct}%"` |
| `checks_queued`, `checking` | "Checks running" | "The station is checking this package. The verdict and findings appear here when the checks finish." | — |
| `check_error` | "The checks could not complete" (`role="alert"`) | "The station could not finish the acceptance checks. This is not a verdict; the station retries or an admin intervenes." | — |

#### 6.4.4 Plan card (main column; Card md; bim/admin) — `id="plan"`

- Header row (`justify-content:space-between; align-items:center; gap:12; wrap`):
  - Left (gap 12): h3 "Plan"; Badge accent soft `{capture label} · {mode label}` (drawn
    "Floor 1 · whole floor").
  - Right (gap 14, 13px / 600): links "plan.png", "plan.dxf", "plan sheet PDF" → download route of
    the selected capture's `plan_png`, `plan_dxf`, `plan_pdf` (each only when that file exists and
    is verified).
- More than one capture: under the header a link Tabs bar, one tab per capture in capture-record
  order, label = capture label, `href="?floor={areaKey}#plan"`; selected = `floor` param, default
  the first capture. (Single capture: no tabs, as drawn.)
- Body grid `minmax(0,1fr) 220px`, gap 20, `align-items:start`:
  - Preview box: background `--surface-muted`, border 1px `--border-subtle`, radius 10, padding 20,
    `display:flex; justify-content:center; overflow:hidden`. Inside: `<img
    src="/packages/{id}/files/preview?path={plan_png path}" alt="Plan of {label}">` with
    `max-width:100%; max-height:420px; height:auto; width:auto`. Client component
    `PlanPreview` swaps to 13px muted text "The plan preview could not be loaded. Download
    plan.png instead." on `error`. No verified `plan_png`: 13px muted "No plan preview: this
    capture has no verified plan.png." (centred, padding 40px 0).
  - Facts column (gap 10, 13px): pairs label 12px muted / value ink (gap 2):
    - "Preview": "From plan.png · fitted, not to scale. Use the plan sheet PDF for the drawing to
      scale." (drawn "…for the 1:50 drawing"; the sheet's scale is not exposed to the web and can
      differ for a large floor, so the number is not printed).
    - "Orientation": §5.3 for the selected capture.
    - "Rooms": `"{roomsScanned} scanned · {formatSqFt(floorAreaSqFt)}, sum of rooms"` +
      `" · {roomsUnlabeled} unlabeled"` when > 0, from `report.floors[]` of the selected capture
      (drawn "12 scanned · 807.5 sq ft, sum of rooms · 5 unlabeled"). Pair omitted without report
      facts.
    - "Not scanned": §5.6 for the selected capture ("None" when empty).

#### 6.4.5 Capture checks card (main column; Card none; bim/admin; `id="checks"`) — only with a verdict

- Header (`padding:18px 22px 12px; justify-content:space-between; align-items:center; gap:12`):
  h3 "Capture checks"; 13px muted
  `"{rows} rules · evaluated {formatDateTime24(evaluatedAt)} · same table as page {report.checksPage} of the spatial report"`
  (without `report.checksPage`: "… · same table as the spatial report"). Drawn "9 rules · evaluated
  May 16, 2026 14:02 · same table as page 4 of the spatial report".
- `.hub-table.hub-table--compact` columns:
  - "Check": `.hub-cell-title` `check.title`; 12px muted mono `ruleId`.
  - "Result": Badge soft, tone and glyph per §5.2, text = word ("Passed", "Limited", "Blocked",
    "Not applicable").
  - "What was found": §5.2.
  - "Next action": §5.2.
- Rows: `sortCheckRows(checkRows(verdict))`. Each `<tr data-result="{result}">`.
- Footer `padding:12px 22px 16px`, 12px muted: "Every rule the station ran is listed. Exports of
  one scan that agree with each other are not independent measurements." (drawn "[EXAMPLE RULE
  SET]" is a placeholder marker, not text).

#### 6.4.6 Files card (main column; Card none; bim/admin; `id="files"`)

Client component `FilesCard` gets the full row list from the server (no links are signed on the
client; rows only carry app URLs).

- Header (`padding:14px 22px; justify-content:space-between; align-items:center; gap:12; wrap`):
  h3 `Files · {totals.files}` (package files = manifest entries; drawn "Files · 75"); controls row
  (gap 10, align center):
  - Select (fullWidth false, width 140, `aria-label="Floor"`): "All floors", then each capture
    label in capture-record order. Visit-wide rows (capture record, field controls, manifest,
    spatial report) appear only under "All floors".
  - Select (width 160, `aria-label="Role"`): "All roles", then the role groups **present** in the
    package, in this order: "Plan DXF", "Rooms CSV", "Plan sheet PDF", "Plan PNG", "Plan SVG",
    "Mesh GLB", "OBJ + MTL", "Point cloud LAS", "Raw RoomPlan", "Depth", "Capture model",
    "Site photo", "Field controls", "Capture record", "Manifest", "Spatial report".
  - TextField (width 200, `aria-label="Search files"`, placeholder "Search files"): case-insensitive
    substring of the display name or path.
- Table `.hub-table--compact`: "File" (`.hub-cell-title`, display name, full path in `title`),
  "Role", "Size", "SHA-256" (mono 12px, `shortSha`, full in `title`; "per file" for a photo
  group), "In the HUB" (Badge), hidden "Download" (`.hub-table__action`: Button ghost sm
  "Download" `aria-label="Download {display name}"` `rel="nofollow"`; unverified file → 13px muted
  "Not verified"; photo group → Button ghost sm "Show photos"/"Hide photos"
  `aria-expanded`).
- Role → label (row "Role" column) and filter group:

  | role | Row label | Filter group |
  |---|---|---|
  | `plan_dxf` | Plan DXF | Plan DXF |
  | `rooms_csv` | Rooms CSV | Rooms CSV |
  | `plan_pdf` | Plan sheet PDF | Plan sheet PDF |
  | `plan_png` | Plan PNG | Plan PNG |
  | `plan_svg` | Plan SVG | Plan SVG |
  | `mesh_glb` | Mesh GLB | Mesh GLB |
  | `mesh_obj` | Mesh OBJ | OBJ + MTL |
  | `mesh_mtl` | Mesh MTL | OBJ + MTL |
  | `texture` | Texture | OBJ + MTL |
  | `point_cloud_las` | Point cloud LAS | Point cloud LAS |
  | `raw_roomplan_json` | Raw RoomPlan | Raw RoomPlan |
  | `raw_depth` | Depth | Depth |
  | `capture_model` | Capture model | Capture model |
  | `photo` | Site photo | Site photo |
  | `field_controls` | Field controls | Field controls |
  | `capture_record` | Capture record | Capture record |
  | manifest (virtual row) | Manifest | Manifest |
  | station spatial report (virtual row) | Spatial report · station | Spatial report |
  | `spatial_report_pdf` (legacy phone file in old packages) | Spatial report · phone (retired) | Spatial report |

- Display names: `fileDisplayName` (unchanged): `"{capture label} / {name}"` for capture files
  (drawn "Floor 1 / plan.dxf"), bare name for visit-wide files ("capture-record.json",
  "field-controls.json", "manifest.json"), "spatial-report.pdf" for the station report row.
- Photos: one **group row per capture**: name `Site Photos / {k} files` (prefixed `{label} / ` when
  the package has more than one capture), role "Site photo", size = sum, SHA "per file", HUB badge
  = the photos' common state (mixed → neutral "Mixed"). "Show photos" expands the group's photo
  rows directly under it (name cell `padding-left:40px`), each with its own Download.
- Order: by role in this order — `plan_dxf`, `rooms_csv`, `plan_pdf`, `plan_png`, `mesh_glb`,
  `point_cloud_las`, photo groups, station spatial report, `plan_svg`, `mesh_obj`, `mesh_mtl`,
  `texture`, `capture_model`, `raw_roomplan_json`, `raw_depth`, `field_controls`,
  `capture_record`, manifest, legacy `spatial_report_pdf`; inside a role by capture-record capture
  order, then path. (Drawn first eight: plan.dxf, rooms.csv, plan-sheet.pdf, plan.png, mesh.glb,
  points.las, Site Photos, spatial-report.pdf.)
- "In the HUB" badge from the station's publication state (§9.1 B), not from a rule in the web:
  `uploaded` → neutral "Uploaded"; `linked` + `too_large` → info "Linked · over 45 MB";
  `linked` + `not_published` → info "Linked"; not published yet → 13px muted "—".
- Collapsed by default to the first **8** rows of the filtered list. Footer row
  (`padding:10px 22px 14px; border-top:1px solid var(--border-subtle);
  justify-content:space-between`): 12px muted "Files over 45 MB stay in Chapter's storage and are
  linked from the HUB. Compare a download with its SHA-256 fingerprint." and Button ghost sm
  `Show all {n} files` / "Show fewer files" (hidden when ≤ 8 rows). The drawn "Fingerprints are
  checked on download." is not true of a browser download and is replaced.
- No rows after filtering: one row, 14px muted, padding 24px 22px: "No files match these
  filters." + Button ghost sm "Clear filters".
- Deep link `?file={path}` (v1 behaviour kept): filters reset to All, the list expands, a photo
  group containing the file expands, the row gets `id="file-target"`, `aria-current="true"`,
  background `--accent-soft` `#e7fbf6`, and is scrolled into view (`ScrollToTarget`).

#### 6.4.7 Decision log card (main column; Card md; bim/admin; `id="decisions"`)

- Header row (`justify-content:space-between; align-items:center; gap:12`): h3 "Modeling decision
  log"; 13px muted `"{n} entries · the source used for each modeling decision, its remaining
  uncertainty and the next check"` ("1 entry · …").
- **Form** (`<form aria-label="Log a decision">`, remounted per answer as in v1): grid 2 columns
  `minmax(0,1fr)`, gap 14, padding 16, radius 10, background `--surface-muted`, border 1px
  `--border-subtle`:
  - TextField "Element or area" (name `element`, required, maxlength 300, placeholder
    "Floor 1 · kitchen east wall").
  - Select "Source used" (name `source`, required; first option "Choose a source" disabled,
    selected) — options in §6.4.8.
  - TextField "Decision" (name `decision`, required, maxlength 2000, placeholder "Modeled as a
    native Revit wall, 4,520 mm").
  - TextField "Remaining uncertainty and next check" (name `note`, maxlength 2000, placeholder
    "Wall thickness unknown; verify at demolition").
  - Footer (span 2; `justify-content:space-between; align-items:center; gap:12; wrap`): 12px muted
    "Saved through the station with your name and time. Entries cannot be edited, only followed by
    a new one."; right: message + Button primary md `type="submit"` "Save decision" (pending:
    "Saving…", disabled). Messages 13px: error `role="alert"` `--red-700`; saved `role="status"`
    `#1c7a4d` "Decision saved." Error texts unchanged from v1 (`actions.ts stationMessage`,
    `parseDecisionForm`).
- **Entries** (column; oldest first as the station returns them): each row
  `display:flex; justify-content:space-between; gap:12px; padding:12px 0;
  border-bottom:1px solid var(--border-subtle)` (none on the last):
  - Left 14px ink: `<b>{element}</b> — {decision}` then muted spans `" · from {source text}"` and,
    when present, `" · {note}"`. Source text = each source's display name (`pathDisplayName`),
    control sources as `"Distance A (tape)"` style names (§6.4.8), joined " + ".
  - Right 12px muted `flex:none`: `{decidedBy.name} · {formatDateTime24(decidedAt)}` in `<time>`.
  - Empty: 13px muted "No decisions logged yet."

Drawn entry example: "**Living Room walls** — native Revit walls from Floor 1 / plan.dxf, checked
against Distance A (tape) · uncertainty: wall thickness; check at demolition".

#### 6.4.8 Decision sources (`web/lib/decisions.ts`)

Options are built on the server from the package and its `fieldControls`; the option **value is a
key**, resolved again on the server in the action (never trust posted paths):

| Option group (`<optgroup label>`) | Option text | value key | sources sent | captureId/areaKey sent |
|---|---|---|---|---|
| "Plans and models" | `{label} / {file name}` for each verified `plan_dxf`, `rooms_csv`, `plan_pdf`, `plan_png`, `plan_svg`, `mesh_glb`, `mesh_obj`, `point_cloud_las`, `capture_model` | `file:{path}` | `[{path}]` | the file's capture |
| "Plan checked against tape" | `{label} / plan.dxf + Distance {axis} ({method})` for each distance control of that capture; `{label} / plan.dxf + {room} ceiling height ({method})` for each ceiling height | `filectl:{dxf path}\|{controlId}` | `[{path: dxf}, {path: field-controls path, controlId}]` | the capture |
| "Field controls" | `Distance {axis} ({method}) · {from} to {to}`, `{room} ceiling height ({method})`, `{room} {label} ({method})`, `Floor to floor ({method}) · {location}`, `Landmark · {label}` | `ctl:{controlId}` | `[{path: field-controls path, controlId}]` | the control's capture (none for floor to floor / landmarks) |
| "Site photos" | `{label} / site photos ({k})` | `photos:{captureId}` | every photo path of that capture | the capture |

Drawn options "Floor 1 / plan.dxf + Distance A (tape)", "Floor 1 / mesh.glb (reference only)",
"Floor 1 / points.las", "Spatial report · room schedule", "Site photos": the plan+control and file
options are covered; "(reference only)" belongs in the decision text, not the source;
"Spatial report · room schedule" is **not offered** because the station accepts only package
files as sources (Q6); "rooms.csv" is the package's room schedule.

The server action (`app/(review)/packages/[packageId]/decisions/actions.ts`) re-loads the package
(`getPackage`), rebuilds the options, maps the key to `sources` / `captureId` / `areaKey`, and
fails with "Choose the source used." when the key is unknown. Everything else as v1 (session and
role check inside the action, `parseDecisionForm` limits, `revalidatePath(`/packages/${id}`)`).

#### 6.4.9 Aside cards (bim/admin unless noted)

All: Card md, column gap 10; eyebrow 13px first; label/value rows `display:flex;
justify-content:space-between; gap:12px; padding:7px 0; border-bottom:1px solid
var(--border-subtle); font-size:13px` (no border on the last row); label muted (`flex:none` when
the value can wrap), value ink right-aligned.

1. **"Capture record"** (from `captureRecord`):
   | Label | Value |
   |---|---|
   | "Address" | `confirmedOnSite` → success circle glyph (9px, `--status-success`) + "Confirmed on site"; else danger square glyph + "Not confirmed on site" |
   | "Floors" | `"{n} · {distinct mode labels joined ', '}"` (drawn "1 · whole floor") |
   | "Rooms" | `"{sum roomsScanned} scanned · {k} not scanned"` (drawn "12 scanned · 2 not scanned"); without report facts `"{k} not scanned"` |
   | "Not scanned" | §5.6 |
   | "Coverage notes" | each non-empty `coverageNotes` (prefixed `"{label}: "` with > 1 capture, one per line); all empty → "None" |
   | "Compass" | §5.3, one line per capture (prefixed `"{label}: "` with > 1 capture) |
   | "Device" | `"{marketingName ?? model} · app {app.version}"` |
   | "Operator" | `operator.name` |
   Not sealed: one 13px muted line "The capture record is available once the package is sealed."
2. **Field controls** (from `fieldControls`, §9.1 B): eyebrow `Field controls` + `" · tape"` /
   `" · laser"` / `" · tape and laser"` by the methods used (drawn "Field controls · tape").
   | Label | Value |
   |---|---|
   | "Long distance A" | mono `formatMm(valueMm)`; > 1 capture: one row per capture, label `"{label} · long distance A"`; missing → muted "Not recorded" |
   | "Long distance B" | same |
   | "Ceiling heights" | `"{n} rooms"` ("1 room") |
   | "Openings" | `"{n}"` |
   | "Floor to floor · landmarks" | one capture and none → "none · one floor" (drawn); else `"{f} · {l}"` |
   Footer 12px muted: "Tolerance: within 1% or 1 in (25.4 mm), whichever is larger. " + link
   "Download field-controls.json" (download route). No field-controls file → 13px muted "No field
   controls in this package."; not sealed yet → "Field controls are shown once the package is
   sealed."
3. **"Station"** (everyone, including capture): rows `display:flex; align-items:center; gap:10px;
   padding:6px 0; font-size:13px`: glyph 9px (flex none); label ink `flex:1`; time muted
   (`formatDayTime`, first row with date).
   | Step | Done | Waiting (ring glyph, muted fill) | Failed (square, `--status-danger`) |
   |---|---|---|---|
   | 1 | circle `--status-success` "Registered" · registeredAt | uploading: "Uploading · {pct}%" · "—" | — |
   | 2 | circle success `Checks run · {n} rules` · checks.finishedAt | "Checks" · "after upload" (uploading) / "Checks running" · since startedAt | "Checks did not finish" · "—" |
   | 3 | glyph per outcome in `--status-success` / `--status-warning` / `--status-danger`, `Verdict · {word}` · evaluatedAt | "Verdict" · "—" | — |
   | 4 | circle success "Published to the HUB" · publishedAt | "Publishing to the HUB" · "—"; blocked and never published: dash glyph "Not published · re-seal needed" | "Publishing to the HUB failed" · "—" |
   Then (bim/admin, publication present, HUB files URL configured, §9.3) a 13px / 600 link
   `HUB › Files › Capture › r{revision} →` (new tab). Drawn times: "May 16 · 13:58", "14:01",
   "14:02", "14:03".
4. **"Documents"** (`id="documents"`): link rows `display:flex; justify-content:space-between;
   gap:12px; padding:7px 0; border-bottom; font-size:13px; text-decoration:none`; left 600 link
   colour, right muted:
   | Left | Right | Target |
   |---|---|---|
   | "Spatial report PDF" | `"{pages} pages · {formatBytes(bytes)}"` (drawn "28 pages · 3.2 MB") | report download route |
   | "Plan sheet PDF" (`" · {label}"` per capture when > 1) | `"{formatBytes} · from the phone"` | download route of that `plan_pdf` |
   | "verdict.json" | "station" | `/packages/{id}/verdict.json` |
   | "manifest.json" | `"{n} entries · SHA-256"` (drawn "75 entries · SHA-256") | download route with the manifest path |
   Report not ready: left text muted (not a link) "Spatial report PDF", right "after the checks"
   (pending, no verdict) / "being generated" (`report.status = pending` with a verdict) / "not
   generated · ask an admin" (`failed`). No verdict: verdict.json row muted, right "after the
   checks". Not sealed: manifest row muted, right "after sealing".
   (The drawn "Tabloid · 1 sheet" is not available as data — old packages carry Letter plan PDFs
   — so the size is shown instead.)

#### 6.4.10 Package page section order

Main column: verdict card (or status card) → plan card → capture checks card → files card →
decision log card. Aside: capture record → field controls → station → documents.

### 6.5 Decision log (sidebar, not drawn) — `/decisions`

bim/admin. Topbar "Decision log". h2 "Decision log", sub 14px muted "Every modeling decision logged
against a capture package, newest first." Card md with the entries of §6.4.7 (newest first,
`GET /v1/modeling-decisions?limit=100`), each entry prefixed by a 13px / 600 link
`{project title} · Revision {n}` → `/packages/{packageId}#decisions` on its own line. Truncated →
12px muted "Showing the 100 newest decisions." Empty → "No decisions logged yet." Capture role →
problem card "No access" / "Modeling decisions are read and logged by BIM operators and admins.
Your account can see the package status only." (v1 copy).

### 6.6 Capture-role views (status only)

Rule from 2k: "capture: projects list and status only; downloads and the form are hidden, not
disabled." Hidden elements are **not in the DOM** (not `disabled`, not `display:none`).

| Page | Capture role sees | Not rendered |
|---|---|---|
| Shell | Projects, Packages, Intake guide | Decision log nav item |
| Projects, Packages | identical to bim | — |
| Project | back link, title, badge, meta, "Open in the HUB", Packages tab only, packages table, "What revision N adds", Latest verdict card without "Capture checks →" | "Spatial report PDF · r{n}", Decision log tab and card |
| Package | breadcrumb, title, badges, meta row, verdict card (or status card), Station card (without the HUB link), and at the end 13px muted "Checks, files and downloads are shown to BIM operators and admins." | all header buttons, plan card, checks card, files card, decision log card, capture record, field controls, documents |
| `/decisions` | "No access" card | — |
| Route handlers (download, preview, report, verdict.json, archive) | 403 text "Only BIM operators and admins can download package files." without calling the station (v1 behaviour) | — |

### 6.7 Sign-in, not found, error, loading, configuration error

**Sign-in** (`app/sign-in/page.tsx`, no shell, no data): page background `--surface-page`, column
centred, `max-width:440px; margin:15vh auto 0; padding:0 16px; gap:20px`:
- Brand: `<img src="/brand/chapter-wordmark.svg" alt="Chapter" height="28">` (ink, unfiltered) and
  below it the eyebrow "Capture review" (11px, `.16em`, uppercase, muted, 600), gap 8.
- Card lg (padding 32), column gap 16: h1 "Sign in" (26/600, −0.02em); 14px body "Use your Chapter
  Microsoft account to see projects, capture packages, verdicts and files."; after an Auth.js
  error an alert box (`role="alert"`, background `--status-danger-bg` `#fbe0de`, colour `--red-700`
  `#b53b33`, radius 10, padding 12px 14px, 13px): 600 "Sign-in did not finish" + line "Try again. If
  it keeps happening, ask a Chapter admin." (error code never echoed); the form (hidden
  `callbackUrl` = `safeReturnPath`) with Button primary md fullWidth `type="submit"` "Sign in with
  Microsoft".

**Not found**: `app/(review)/not-found.tsx` inside the shell (topbar "Not found"; Card md: h2 "Not
found", 14px "There is no project, package or page at this address.", Button outline sm "Back to
the projects" → `/`). `app/not-found.tsx` (outside the group, no session needed): the sign-in
layout with the same card.

**Error**: `app/(review)/error.tsx` (client) inside the shell: Card md, h2 "Something went wrong",
14px "The review screen could not load this page, so nothing is shown. If it keeps happening, send
the reference below to a Chapter admin.", 12px muted `Reference ` + mono digest (when present),
Button primary sm "Try again" (`reset`). Root `app/error.tsx` the same without the shell.

**Loading**: `app/(review)/loading.tsx`: topbar with an empty title and a Card none with 5 static
skeleton rows (each `height:12px; border-radius:6px; background:var(--gray-200)`, widths 40% /
25% / 15%, row padding 18px 22px, hairline borders). No animation (HUB: no infinite loops).

**Configuration error page** (`lib/config.ts configErrorResponse`, 503): same markup rules,
inline styles only (no app CSS is loaded): background `#f1f1f1`, Inter 400 `@font-face` from
`/brand/inter-400.woff2` (and 600), wordmark `<img src="/brand/chapter-wordmark.svg"
alt="Chapter" height="28">`, white card radius 16 border `rgba(0,0,0,.08)` padding 32: h1 26px /
600 `#000` "Capture review is not configured", p 14px `rgba(0,0,0,.6)` "Sign-in or the station
connection is not set up for this deployment, so no data is shown. Ask a Chapter admin to complete
the review screen settings." No Times, no `chapter-logo.svg`.

### 6.8 Problem cards (`components/StationProblem.tsx`, restyled)

Card md, `role="alert"`, column gap 8: 16/600 heading-colour title + 14px body text + optional
Button outline sm. Titles and texts are v1's:

| Case | Title | Text | Button |
|---|---|---|---|
| station 401 | "Sign in again" | "The station did not accept your sign-in." | "Sign in again" → `/sign-in` |
| station 403 | "No access" | "Your account does not have a station role that can open this." | — |
| no station role | "No access" | "Your account has no Chapter Capture station role. Ask a Chapter admin for the bim role to review packages." | — |
| other / unreachable | "The station could not answer" | "The data could not be loaded from the station (status {status}). Try again in a moment." | "Try again" → same URL |
| 404 | the not-found page (`notFound()`) | | |

`Notice` (`components/Notice.tsx`) is restyled the same way and kept for the status cards.

---

## 7. Data: where every value comes from

| UI value | Source | Not available → |
|---|---|---|
| Project title, address | `HubProject` (`GET /projects/{dealId}`; `review/projects` rows) | §5.5 fallbacks |
| PM name ("PM [NAME]") | — | not rendered |
| Latest package, revision, status, sealedAt, createdAt | `PackageSummary` | — |
| Upload progress | `PackageSummary.totals.filesVerified/bytesVerified/bytesTotal` (new) | bar omitted |
| Floors (count, labels, modes) | `PackageSummary.captures` (new; labels/modes once sealed) | count from distinct captureIds; label = humanised areaKey |
| Captured date / operator | `visitedAt`, `operatorName` (new summary fields, from capture record) or `createdAt`, `createdBy.name` (new) while uploading | date only |
| Verdict word, summary, limitations, next actions, task, statement, checks, findings, evaluator, evaluatedAt | `GET /packages/{id}/verdict` (verdict.json, unchanged) | status card |
| Checks finished, rules run | `PackageSummary.checks` (new) | `verdict.evaluatedAt`, `verdict.checks.length` |
| Registered time | `PackageSummary.registeredAt` (new; `packages.registered_at`) | "—" |
| Published / HUB state per package | `PackageSummary.publication` (new; `hub_publications`) | "—" |
| HUB state per file | `PackageFile.hub` (new; `hub_publications.files`) | "—" |
| Spatial report (pages, size, sha, checks page, per-floor rooms / area / unlabeled) | `PackageSummary.report` (new, filled by `spatial-report`) | rows omitted, document row muted |
| Orientation | capture record compass fields (`compass` area) via `orientationOf` | "not verified · no compass reading" |
| Not scanned rooms, coverage notes, address confirmation, device, app, operator | `captureRecord` (unchanged) | "None" / record line |
| Field controls values | `Package.fieldControls` (new; parsed at seal) | "Not recorded" / card message |
| Plan preview | `plan_png` file via `/files/preview` (unchanged) | preview message |
| Manifest entries, size, sha | `Package.manifestFile` (new) + `manifest.files.length` | muted row |
| Decisions | `GET /packages/{id}/modeling-decisions` (unchanged), `GET /modeling-decisions` (new) | empty texts |
| Revision diff | two `getPackage` results + `fieldControls` | footer only |
| "updated 2 min ago" | max `PackageSummary.updatedAt` (new; `packages.updated_at`) | text omitted |
| HUB links | web env (§9.3) | buttons and links not rendered |

---

## 8. Mapping to the current code

### 8.1 web/ — changed, new, removed

| Path | Change |
|---|---|
| `web/app/layout.tsx` | import `./hub.css`; keep metadata (robots noindex) |
| `web/app/globals.css` | **rewritten** (§2.2–2.3); all v1 classes (`.app-header`, `.frame`, `.project-nav`, `.verdict`, `.table-card`, `.decision-form`, `.button-primary`, tone classes…) removed |
| `web/app/hub.css` | **new** (§2.4, §3, §6 layout classes) |
| `web/app/(review)/layout.tsx` | **new** shell |
| `web/app/(review)/page.tsx` | **moved** from `app/page.tsx`, rewritten (Projects) |
| `web/app/(review)/packages/page.tsx` | **new** (Packages) |
| `web/app/(review)/projects/[dealId]/page.tsx` | **moved**, rewritten (Project) |
| `web/app/(review)/packages/[packageId]/page.tsx` | **moved**, rewritten (Package) |
| `web/app/(review)/packages/[packageId]/decisions/page.tsx` | **moved**, now a permanent redirect to `#decisions` |
| `web/app/(review)/packages/[packageId]/decisions/actions.ts` | **moved**; source keys (§6.4.8), revalidates the package page |
| `web/app/(review)/packages/[packageId]/files/download/route.ts`, `…/files/preview/route.ts` | **moved**; download accepts the manifest path |
| `web/app/(review)/packages/[packageId]/report/download/route.ts` | **new** |
| `web/app/(review)/packages/[packageId]/verdict.json/route.ts` | **new** |
| `web/app/(review)/packages/[packageId]/archive/route.ts` | **new**, phase 3 |
| `web/app/(review)/decisions/page.tsx` | **new** |
| `web/app/(review)/loading.tsx`, `error.tsx`, `not-found.tsx` | **new** |
| `web/app/sign-in/page.tsx`, `web/app/not-found.tsx`, `web/app/error.tsx` | restyled (§6.7) |
| `web/components/hub/{Button,Badge,Card,Tabs,TextField,Select,Avatar,StatusGlyph,VerdictBadge,ProgressBar,EmptyState,icons}.tsx` | **new** |
| `web/components/shell/{Sidebar,SidebarNav,Topbar,SearchField}.tsx` | **new** (SidebarNav client) |
| `web/components/projects/ProjectsTable.tsx`, `web/components/packages/PackagesListTable.tsx` | **new** |
| `web/components/project/{ProjectHeader,PackagesTable,RevisionDiffCard,LatestVerdictCard,DecisionSummaryCard,ProjectDecisionLog}.tsx` | **new** |
| `web/components/package/{PackageHeader,VerdictCard,StatusCard,PlanCard,PlanPreview,ChecksCard,FilesCard,DecisionLogCard,CaptureRecordCard,FieldControlsCard,StationCard,DocumentsCard,DownloadAllButton}.tsx` | **new** (`PlanPreview`, `FilesCard`, `DownloadAllButton` client) |
| `web/components/DecisionForm.tsx`, `DecisionList.tsx` | reworked: HUB fields, option groups, entry layout |
| `web/components/Notice.tsx`, `StationProblem.tsx` | restyled (§6.8) |
| `web/components/ScrollToTarget.tsx` | kept |
| `web/components/PageFrame.tsx`, `ProjectNav.tsx`, `VerdictCard.tsx`, `FindingsTable.tsx`, `FilesTable.tsx`, `PackageHeading.tsx` | **removed** (replaced above) |
| `web/lib/format.ts` | new helpers (§5.4), `ROLE_LABEL` v2 + `ROLE_FILTER_GROUP`, `modeSummary` with "× n"; `hubState`, `HUB_UPLOAD_ROLES`, `HUB_LINK_THRESHOLD_BYTES`, `OUTCOME`, `outcomeLabel`, `outcomeHeadline`, `SEVERITY_*`, `severityLabel`, `PACKAGE_STATUS` **removed** (HUB state now comes from the station; words from `review-text`) |
| `web/lib/review.ts` | **new** (replaces `lib/projects.ts`): `loadReviewProjects`, `tabOf`, `tabCounts`, `loadReviewPackages`, `projectTitle` |
| `web/lib/projects.ts` | **removed** (N+1 nav loading replaced by `review/projects`) |
| `web/lib/packages.ts` | `loadPackageBase` returns `{pkg, project, title}`; `newerRevisions(pkgs, pkg)` |
| `web/lib/revision-diff.ts`, `web/lib/files-view.ts`, `web/lib/links.ts` | **new** (diff §6.3.4; file rows/order/groups/filters §6.4.6; HUB/intake URLs §9.3) |
| `web/lib/decisions.ts` | source options + key resolution (§6.4.8); limits unchanged |
| `web/lib/station.ts` | new client methods: `listReviewProjects(q)`, `listReviewPackages(q)`, `listDecisions({dealId?, limit})`, `getReportDownloadLink(id)`, `requestArchive(id)`; `getFileDownloadLink` unchanged |
| `web/lib/station-types.ts` | new/extended types (§9.1) |
| `web/lib/config.ts` | optional `HUB_APP_URL`, `HUB_DEAL_URL_TEMPLATE`, `HUB_FILES_URL_TEMPLATE`, `INTAKE_GUIDE_URL` (https only; invalid → ignored with one `console.warn` naming the variable, never fail closed); config page restyled |
| `web/lib/roles.ts`, `viewer.ts`, `token.ts`, `auth-redirect.ts`, `auth.ts`, `proxy.ts` | unchanged |
| `web/public/brand/chapter-wordmark.svg` | **new**, byte-identical copy of the bundle's `canvas/hub-assets/chapter-wordmark.svg` (sha256 `8621b72b323ef1394a205fe6ba29f84b2c4ad0cff23fc883f9ee23947a8f2d71`, viewBox `0 0 147 33.8`, fill `#221f1f`) |
| `web/public/brand/NOTICE.md` | add: "`chapter-wordmark.svg`: the chapter wordmark used in the HUB (HelloChapter backoffice `public/images/logo.svg`, via the HUB design system). A trademark of Chapter; not covered by any open license. Copied by hand from `tools/brand/chapter-wordmark.svg`." |
| `tools/brand/chapter-wordmark.svg` | **new**, same bytes (source of truth next to `chapter-logo.svg`) |
| `web/public/brand/chapter-logo.svg`, `inter-400.woff2`, `inter-600.woff2` | kept (scan browser uses them; the web no longer references `chapter-logo.svg`) |
| `web/.env.example` | add the four optional variables with comments |
| `web/package.json` | devDependency `@playwright/test` (exact version), script `"e2e": "playwright test"` |

### 8.2 contract/

| Path | Change |
|---|---|
| `contract/openapi/station.yaml` | `info.version` 1.0.0 → **1.1.0**; additions in §9.1 (additive only) |
| `contract/ts/src/review-text.ts` | **new**: `verdictHeadline`, `checkRows`, `checkCounts`, `countsLine`, `ruleSetLabel`, `notScannedText`, and `orientationOf` + `orientationText` if `compass` has not shipped them; exported from `contract/ts/src/index.ts` |
| `contract/ts/test/review-text.test.ts` | **new** |
| `contract/ts/package.json` | version 1.0.0 → 1.1.0 (web and station depend on `1.1.0`) |
| `contract/schema/capture-record.schema.json` | compass fields — owned by `compass`, read here |

### 8.3 station/

| Path | Change |
|---|---|
| `station/db/migrations/0009_review-read-model.sql` | **new**: `ALTER TABLE packages ADD COLUMN field_controls jsonb CHECK (field_controls IS NULL OR (manifest IS NOT NULL AND jsonb_typeof(field_controls) = 'object')), ADD COLUMN manifest_bytes bigint CHECK (manifest_bytes IS NULL OR manifest_bytes >= 0)`; index `package_files (capture_id)` if absent; index `modeling_decisions (decided_at DESC)` |
| `station/api/src/routes/uploads/index.ts` | at seal also store `field_controls` (parsed, `validateFieldControls`; absent file → NULL) and `manifest_bytes` |
| `station/api/src/routes/packages/store.ts` | summary/detail extended (§9.1 A/B): joins on `package_files` aggregates, latest `check_runs`, `hub_publications`, `created_by_name`, `updated_at`, `registered_at`, capture record fields |
| `station/api/src/routes/packages/schemas.ts`, `index.ts` | new fields; manifest path accepted by `files/download` |
| `station/api/src/routes/packages/download.ts` | manifest original link (same SAS + audit) |
| `station/api/src/routes/packages/report.ts` | **new** `GET /packages/{id}/report/download` (or implemented by `spatial-report`, same contract) |
| `station/api/src/routes/review/{index,schemas,store}.ts` | **new** `GET /review/projects`, `GET /review/packages` |
| `station/api/src/routes/decisions/index.ts` | **new** `GET /modeling-decisions` |
| `station/api/src/routes/packages/archive.ts`, `station/worker/src/archive-job.ts`, `station/worker/src/worker.ts`, migration for the `archive` job type | phase 3 (§9.1 H) |
| `station/api/test/review/*.test.ts`, `station/api/test/packages/*` | tests incl. OpenAPI conformance |
| `scripts` | one-off backfill: fill `field_controls` and `manifest_bytes` of sealed packages from the stored originals |

### 8.4 docs/

`docs/waves/design/DESIGN.md`: add "Turn 2 v2 (2026-10-21): screen-review is replaced by
web-review-v2 (2h, 2i, 2j) in the HUB design system with Inter and the HUB chapter wordmark; Times
is not used on the web." `docs/waves/specs/F10.md`: AC5 points at 2h/2i/2j; AC2 wording "every
check and finding in the report's words"; add the new ACs of §12.

---

## 9. API and configuration

### 9.1 Station API 1.1.0 (additive; `contract/openapi/station.yaml`)

All new properties follow the existing conventions (omitted, never null; UTC whole-second
DateTimes; lowercase UUIDs). Every new route is added to the OpenAPI file (the conformance coverage
test fails otherwise).

**A. `PackageSummary` (therefore also `Package`) — new properties**

```yaml
updatedAt:            # required in responses
  $ref: "#/components/schemas/DateTime"
  description: Last change of the package (status, files, verdict, publication).
registeredAt:
  $ref: "#/components/schemas/DateTime"
  description: When the station accepted the seal. Present once sealed.
createdBy:
  type: object
  additionalProperties: false
  required: [name]
  properties: { name: { type: string, minLength: 1, maxLength: 200 } }
  description: Who opened the upload session. Omitted when the name is unknown.
visitedAt:   { $ref: "#/components/schemas/DateTime", description: capture record visitedAt. Present once sealed. }
operatorName: { type: string, minLength: 1, maxLength: 200, description: capture record operator.name. Present once sealed. }
captures:             # required in responses; may be empty
  type: array
  items:
    type: object
    additionalProperties: false
    required: [captureId, areaKey]
    properties:
      captureId: { $ref: "#/components/schemas/Uuid" }
      areaKey:   { $ref: "#/components/schemas/AreaKey" }
      label:     { type: string, minLength: 1, maxLength: 100, description: From the capture record, once sealed. }
      mode:      { enum: [room, floor, exterior], description: From the capture record, once sealed. }
  description: Capture-record order once sealed, else first appearance in path order.
totals:               # required in responses
  type: object
  additionalProperties: false
  required: [files, bytes, filesVerified, bytesVerified]
  properties:
    files: { type: integer, minimum: 0 }
    bytes: { type: integer, format: int64, minimum: 0 }
    filesVerified: { type: integer, minimum: 0 }
    bytesVerified: { type: integer, format: int64, minimum: 0 }
checks:
  type: object
  additionalProperties: false
  required: [status]
  properties:
    status: { enum: [queued, running, completed, failed] }
    startedAt: { $ref: "#/components/schemas/DateTime" }
    finishedAt: { $ref: "#/components/schemas/DateTime" }
    rules: { type: integer, minimum: 0, description: Rules run (completed only). }
  description: The latest check run. Omitted before the seal.
publication:
  type: object
  additionalProperties: false
  required: [status, hubFolder]
  properties:
    status: { enum: [pending, publishing, published, publish_failed] }
    publishedAt: { $ref: "#/components/schemas/DateTime" }
    hubFolder: { type: string, description: "Visit-wide HUB folder, for example Capture/<visitId>/r1." }
  description: HUB publication of this revision. Omitted when nothing was queued.
report:
  $ref: "#/components/schemas/ReportSummary"
```

`ReportSummary` (contract owned jointly with `spatial-report`, which fills it):

```yaml
ReportSummary:
  type: object
  additionalProperties: false
  required: [status]
  properties:
    status: { enum: [pending, ready, failed] }
    generatedAt: { $ref: "#/components/schemas/DateTime" }   # ready
    pages: { type: integer, minimum: 1 }                      # ready
    bytes: { type: integer, format: int64, minimum: 1 }       # ready
    sha256: { $ref: "#/components/schemas/Sha256" }           # ready
    checksPage: { type: integer, minimum: 1 }                 # ready
    floors:                                                    # ready
      type: array
      items:
        type: object
        additionalProperties: false
        required: [captureId, areaKey, roomsScanned, roomsUnlabeled, floorAreaSqFt]
        properties:
          captureId: { $ref: "#/components/schemas/Uuid" }
          areaKey: { $ref: "#/components/schemas/AreaKey" }
          roomsScanned: { type: integer, minimum: 0 }
          roomsUnlabeled: { type: integer, minimum: 0 }
          floorAreaSqFt: { type: number, minimum: 0, description: Sum of rooms, 0.1 sq ft. }
    hub: { $ref: "#/components/schemas/HubFileState" }
```

**B. `Package` — new properties; `PackageFile.hub`**

```yaml
Package.fieldControls:
  $ref: "../schema/field-controls.schema.json"
  description: The package's field-controls file, parsed at sealing. Present once sealed when the package has one.
Package.manifestFile:
  type: object
  additionalProperties: false
  required: [path, sha256, bytes]
  properties:
    path: { $ref: RelativePath }    # Source Register/<visitId>/manifest.json
    sha256: { $ref: Sha256 }
    bytes: { type: integer, format: int64, minimum: 0 }
    hub: { $ref: HubFileState }
  description: The sealed manifest file. Present once sealed.
PackageFile.hub:
  $ref: "#/components/schemas/HubFileState"
  description: Where the file is in the HUB after the last successful publication. Omitted before.
HubFileState:
  type: object
  additionalProperties: false
  required: [state]
  properties:
    state: { enum: [uploaded, linked] }
    reason: { enum: [too_large, not_published], description: Present when state is linked. }
```

**C. `GET /review/projects`** — tag `review`, operationId `listReviewProjects`, x-roles
`[capture, bim, admin]`. Query `q` (string 1–200, optional), `limit` (1–200, default 100).
Projects that have at least one package, most recent package change first.

```yaml
200:
  required: [projects, truncated]
  properties:
    projects:
      type: array
      items:
        type: object
        additionalProperties: false
        required: [dealId, address, packageCount, latest]
        properties:
          dealId: { $ref: DealId }
          projectName: { type: string, minLength: 1, maxLength: 200 }
          address: { $ref: "#/components/schemas/HubProject/properties/address" }
          packageCount: { type: integer, minimum: 1 }
          latest: { $ref: PackageSummary }
    truncated: { type: boolean }
```

Address/name: `projects_cache` (also when expired), else the newest sealed capture record
(`address.formatted`, `hub.projectName`), else `"HUB deal {dealId}"`. `q` matches,
case-insensitively, a substring of project name or address (cache or capture records), the deal id
(prefix), or a capture id / package id (prefix of at least 8 hex characters). 400 for bad
parameters, 401, 403.

**D. `GET /review/packages`** — operationId `listReviewPackages`, x-roles all three, `q`, `limit`
(1–200, default 100). `{ packages: (PackageSummary + projectName? + address)[], truncated }`,
newest first.

**E. `GET /modeling-decisions`** — tag `modeling-decisions`, operationId
`listAllModelingDecisions`, x-roles `[bim, admin]`. Query `dealId` (optional), `limit` (1–200,
default 100). `{ decisions: (ModelingDecision + dealId + revision)[], truncated }`, newest first.

**F. `GET /packages/{packageId}/files/download?path=`** — also accepts the sealed manifest path
(`Source Register/<visitId>/manifest.json`) once the package is sealed (404 before). Same SAS,
same audit entry (role recorded as `manifest`).

**G. `GET /packages/{packageId}/report/download`** — operationId `getReportDownloadLink`, x-roles
`[bim, admin]`, 200 `DownloadLink` (path `spatial-report.pdf`), 404 `report_not_ready` /
`not_found`, audited like file links. Implemented with the report storage from `spatial-report`.

**H. Phase 3 — `POST /packages/{packageId}/archive`** — operationId `requestPackageArchive`,
x-roles `[bim, admin]`. 200 `DownloadLink` (path `{revision}.zip`) when the archive exists; 202
`{ status: "preparing", startedAt }` after queuing a worker job `archive` that writes a store-only
ZIP of every verified package file at its manifest path, plus `manifest.json`, `verdict.json` and
`spatial-report.pdf` when present, to blob storage (kept 7 days); 409 `package_not_sealed`.
`GET` on the same path returns the current state without queuing. Until this ships the web does
not render "Download all".

### 9.2 Web client types (`web/lib/station-types.ts`)

Mirror §9.1 exactly (`PackageSummary` gains `updatedAt`, `registeredAt?`, `createdBy?`,
`visitedAt?`, `operatorName?`, `captures`, `totals`, `checks?`, `publication?`, `report?`;
`StationPackage` gains `fieldControls?`, `manifestFile?`; `PackageFile` gains `hub?`; new
`ReviewProject`, `ReviewPackage`, `ReportSummary`, `HubFileState`, `DecisionWithContext`,
`ArchiveState`). The fake station in `web/test/support/station.ts` answers the new operations.

### 9.3 Web configuration (optional; `web/.env.example`)

| Variable | Example | Used for | Unset or invalid |
|---|---|---|---|
| `HUB_APP_URL` | `https://hub.hellochapter.com` | topbar "Open the HUB" | button not rendered |
| `HUB_DEAL_URL_TEMPLATE` | `https://hub.hellochapter.com/deals/{dealId}` | project "Open in the HUB" | button not rendered |
| `HUB_FILES_URL_TEMPLATE` | `https://hub.hellochapter.com/deals/{dealId}/files?folder={folder}` | Station card `HUB › Files › Capture › r{n} →` (`folder` = `publication.hubFolder`, URL-encoded) | link not rendered |
| `INTAKE_GUIDE_URL` | link to the File Intake Guide R01 | sidebar "Intake guide" | item not rendered |

Rules: https only; templates must contain their placeholders; values are substituted with
`encodeURIComponent`; invalid values are ignored with one `console.warn` naming the variable.
These are never required (the review screen must not fail closed over a link).

---

## 10. Security

- Unchanged: Entra sign-in, proxy fail-closed, server-only station client, token never in the
  browser, signed links never rendered (download/report/archive routes fetch the link on click and
  answer 303 with `cache-control: no-store` and `referrer-policy: no-referrer`), preview streamed
  through the app.
- Every new route handler starts with `authorizeFileRequest` (session, bim/admin, UUID check)
  before any station call. `verdict.json` streams JSON with `content-type: application/json;
  charset=utf-8`, `x-content-type-options: nosniff`, `content-security-policy: default-src 'none'`.
- Decision sources are resolved from server-side keys; posted paths are never forwarded.
- External links (`HUB_*`, `INTAKE_GUIDE_URL`) only from server env, https only, `rel="noopener
  noreferrer"`.
- Capture-role hiding is not the boundary: the station enforces roles on every call (unchanged).
- Search `q` is length-limited (200) and sent as a query parameter; never interpolated into HTML
  unescaped (React).

---

## 11. Dependencies on other areas

| Area key | What this area needs | If missing when web-review is built |
|---|---|---|
| `spatial-report` | Station stores the spatial report PDF per verdict, fills `PackageSummary.report` (status, pages, bytes, sha256, checksPage, floors facts, hub state) and serves `GET /packages/{id}/report/download`; uses `checkRows` / `countsLine` / `verdictHeadline` / `ruleSetLabel` from `@chapter/capture-contract` for page 4; replaces the verdict report in the HUB publication | Report buttons/rows hidden or muted ("after the checks"), Rooms facts omitted, "same table as the spatial report" without a page number |
| `compass` | capture-record compass fields per capture (`heading`, `headingAccuracy`, `headingSource`, `headingRecordedAt`) and `orientationOf` with ±10° / ±30° | Every package shows "Not verified · no compass reading" |
| `phone-package` | revision 2 behaviour (`supersedesPackageId`, unchanged files reused); retirement of `spatial_report_pdf` | Legacy label covers old packages; diff works on any revision > 1 |
| `plan-sheet` | `plan_pdf` is the Tabloid plan sheet per capture | The web only links the file; no change needed |
| station API / worker owners (if split out as their own area) | §9.1 A–H, migration 0009, backfill | Projects page cannot be built without §9.1 C; package page degrades field by field per §7 |

---

## 12. Test plan and acceptance criteria

### 12.1 Unit (vitest, `web/test/*.test.ts`; node:test in contract/station)

- `contract/ts/test/review-text.test.ts`: `checkRows` for the contract example and every generated
  fixture verdict (result per rule, findings grouped, "None" next action, orphan finding rule);
  `countsLine` singular/plural ("1 blocker", "0 blockers · 2 limitations · 5 passed · 2 not
  applicable"); `verdictHeadline` for all three outcomes; `orientationOf` boundaries (10 → verified,
  10.5 → approximate, 30 → approximate, 30.5 → not verified, magnetic 5 → approximate, missing →
  not verified); `notScannedText` (reason, no reason, inaccessible, multi-capture).
- `web/test/format.test.ts`: `formatBytes` ("14 KB", "1.2 MB", "768 MB"), `formatMm` ("7,520 mm"),
  `formatSqFt`, `formatDateTime24` across DST (EDT/EST), `formatDayTime` same/other day,
  `dayLabel` "Today", `updatedAgo` thresholds, `modeSummary` "whole floor × 1".
- `web/test/files-view.test.ts`: order, photo grouping, floor/role/text filters, visit-wide rows
  only under "All floors", collapsed 8 rows, `?file` expands, HUB badge mapping (uploaded / linked
  too_large / linked not_published / none / mixed), legacy `spatial_report_pdf`.
- `web/test/revision-diff.test.ts`: new capture, removed capture, control added/changed (each
  kind), field-controls changed before seal, photos added, other files changed, compact line.
- `web/test/decision-sources.test.ts`: option groups and texts from fixture field controls, key
  round-trip, unknown key rejected, captureId/areaKey set.
- `web/test/links.test.ts`: env validation (https only, placeholders, encoding), unset → null.

### 12.2 Component tests (vitest + Testing Library, jsdom; fake station)

- `shell.test.tsx`: wordmark `img[src="/brand/chapter-wordmark.svg"]` in the sidebar link "Chapter
  capture review, home"; "Capture review" label; nav items and `aria-current` per path; avatar
  initials; "BIM operator · Entra"; capture role has no "Decision log" link; "Open the HUB" only
  with `HUB_APP_URL`; no element's text contains "RENOVATION".
- `projects.test.tsx`: heading, sub text verbatim, count line, tab counts and filtering, row cells
  for verdict_ready / uploading (progress bar value) / checking / check_error / blocked
  unpublished, legend, truncated line, empty state, search-no-match + "Clear search", station
  error card, no-role card.
- `project.test.tsx`: title, latest badge, meta (no PM), buttons per role, tabs, packages table
  cells ("1 floor · 12 rooms · 75 files · 768 MB" from a fixture with report facts), revision diff
  card shown only for revision > 1 without verdict, latest verdict card, decision summary (2 newest,
  "All entries →"), log tab newest first; capture role: no report button, no log tab/card.
- `package-detail.test.tsx` (rewrite of v1): for every fixture verdict (12 cases) — verdict card
  headline, summary, counts line, limitations, next actions, statement; checks table rows equal
  `sortCheckRows(checkRows(verdict))` cell by cell, Blocked rows before Limited before Passed before
  Not applicable; header meta line; status cards for uploading (progress) / checks running /
  check_error; plan card (preview src through `/files/preview`, links, orientation text, rooms
  facts, not scanned, floor tabs with 2 captures); files card (count, filters, download hrefs to
  this app only, "Not verified", photo group, `?file` highlight + scroll); capture record, field
  controls (values in mm, "none · one floor"), station timeline per state, documents rows and
  muted states; newer-revision note.
- `decision-log.test.tsx`: form fields/labels/placeholders, option groups, save → station receives
  the resolved sources and captureId/areaKey → entry listed with author and `formatDateTime24`;
  station 422 message kept with values; validation before calling the station; v1 URL redirects
  to `#decisions`.
- `auth.test.ts` (updated paths): proxy rules unchanged; capture role sees no download/preview/
  report/verdict.json/archive links, no plan/checks/files/decision/capture-record/field-control/
  documents sections (asserted absent from the DOM); route handlers 403 without station calls;
  new routes covered by the "every page and route handler" check.
- `brand.test.tsx` (rewritten): `web/public/brand/chapter-wordmark.svg` sha256 equals
  `8621b72b…2d71` and equals `tools/brand/chapter-wordmark.svg`; CSS `url()`s are exactly
  `/brand/inter-400.woff2` and `/brand/inter-600.woff2` and exist; no `@import`; no
  "googleapis", "gstatic", "Lato", "Times" in `web/app`, `web/components`, `web/lib`;
  `--font-sans` starts with `Inter`; `--accent: var(--mint-400)` and `--mint-400: #30e3ca`;
  `.hub-btn` radius `var(--radius-pill)` and `--radius-pill: 100px`; config error page uses the
  wordmark and no Times.
- `sign-in.test.tsx`: wordmark, eyebrow, "Sign in", body text, button, error box without code,
  safe return path (unchanged cases).

### 12.3 Station tests (node:test, `station/api/test`)

- `review/review-projects.test.ts`: one row per deal with packages, latest = newest, `packageCount`,
  ordering by last change, address fallbacks (cache, expired cache, capture record, "HUB deal …"),
  `q` by address / name / deal prefix / capture id prefix / package id prefix, `limit` +
  `truncated`, roles (capture allowed), 400 on bad `limit`.
- `packages/summary-extensions.test.ts`: `updatedAt`, `registeredAt`, `createdBy`, `captures`
  before/after seal, `totals` during upload, `checks` states, `publication` states, `PackageFile.hub`
  from `hub_publications.files`, `fieldControls`, `manifestFile`.
- `packages/download-link.test.ts`: manifest path accepted once sealed, 404 before, audited.
- `decisions/list-all.test.ts`: newest first, `dealId` filter, roles (capture 403).
- OpenAPI conformance tests for every new operation (responses validate against 1.1.0).

### 12.4 Visual / end-to-end (Playwright, `web/e2e/`)

`web/playwright.config.ts` starts `next build && next start` with env pointing at a mock station
(`web/e2e/mock-station.ts`, a small HTTP server answering §9.1 from the 424 West End sample:
1 floor, 12 rooms, 807.5 sq ft, 5 unlabeled, Limited with the sample's limitations and next
actions, 75 files 768 MB, published May 16, 2026 14:03; plus 618 Valley Street uploading 67 %, 2
floors; 24 Shawnee Road Ready r2; one Blocked unpublished; 131 East 81st Street Ready) and a
session cookie minted with `AUTH_SECRET` (as `test/support/tokens.ts`). Viewport 1440×900, fonts
loaded (`document.fonts.ready`).

- Screenshots `projects.png` (2h), `project.png` (2i, with revision 2 uploading), `package.png`
  (2j, full page), `package-capture-role.png`, `sign-in.png`, `projects-empty.png`; baselines are
  approved once by the owner side by side with the artboards, then
  `toHaveScreenshot({ maxDiffPixelRatio: 0.01 })`.
- Flows: search → project → package; tab switching; file filters and "Show all 75 files";
  `?file=` deep link; save a decision; download click answers 303 to the mock link (never in the
  DOM); keyboard: every interactive element reachable, visible focus.
- Network assertion: no request leaves the app origin except the mock station and mock blob
  (no Google Fonts).

### 12.5 Acceptance criteria

| Id | Criterion | Verified by |
|---|---|---|
| WR-AC1 | Every web page renders in Inter (400/600 from `/brand`), with the HUB tokens of §2.3; no Lato, no Times, no Google font request | brand test, e2e network check |
| WR-AC2 | The sidebar shows the HUB chapter wordmark file (white), "Capture review", the four nav items per role and the signed-in user; no "chapter / RENOVATION" text anywhere | shell test |
| WR-AC3 | Projects page matches 2h: heading, sub, count, five tabs with counts, seven columns, verdict badges with word and shape, empty/search/error states | projects test, screenshot |
| WR-AC4 | Project page matches 2i: back link, title + "· latest" badge, packages table with Contents, "What revision N adds" from real diffs, latest verdict and decision summary | project test, screenshot |
| WR-AC5 | Package page matches 2j: verdict card, plan preview per floor with orientation and rooms facts, checks in the report's words sorted Blocked › Limited › Passed › Not applicable, files with floor/role/text filters, decision log form + entries, capture record, field controls, station, documents | package-detail test, screenshot |
| WR-AC6 | Check rows on the web equal `checkRows(verdict)` — the same function the spatial report uses | package-detail + contract tests |
| WR-AC7 | Downloads (files, manifest, spatial report, verdict.json) work for bim/admin through short-lived links fetched on click; no signed URL in any page | auth test, e2e |
| WR-AC8 | Capture role sees status only: the hidden elements of §6.6 are absent from the DOM and the routes refuse with 403 without calling the station | auth test |
| WR-AC9 | A decision saved through the station is listed with author and time; sources come from server-side keys | decision-log test |
| WR-AC10 | Sign-in, not-found, error and configuration pages use the HUB look with the wordmark | sign-in, brand tests |
| WR-AC11 | Station API 1.1.0 operations validate against the OpenAPI file | station conformance tests |
| WR-AC12 | `npm run build --workspace web`, `npm run typecheck --workspace web`, `npm test --workspace web` pass | CI |

---

## 13. Deviations from the drawing (data or truth requires them)

1. "PM [NAME]" not rendered (no PM in the station's project data).
2. Revision row "not sealed · on the phone" cannot exist at the station; the real states are
   "uploading from the phone" and later.
3. "answers limitation N · …" tile subs replaced (no link between a change and a limitation).
4. Verdict card footer uses the contract's fixed statement instead of the shortened sentence.
5. "Use the plan sheet PDF for the 1:50 drawing" → "…for the drawing to scale" (scale not known
   to the web, can differ).
6. "Fingerprints are checked on download" → "Compare a download with its SHA-256 fingerprint"
   (a browser download is not checked).
7. Documents "Plan sheet PDF · Tabloid · 1 sheet" → size + "from the phone" (paper and sheet count
   not available; old packages are Letter).
8. "Revision 2 is in progress on the phone with both." → status of the newer revision only.
9. The "Uploading" tab also holds packages being checked (every latest package without a verdict).
10. Photos show their real HUB state (today "Linked"); the drawing shows "Uploaded".
11. Role filter adds "Capture model" (a real role missing from the drawn list); lists only roles
    present.
12. Bold is Inter SemiBold 600 (the repo has no Inter Bold), Q1.
13. Wordmark rendered pure white (`brightness(0) invert(1)`) instead of `invert(1)` (#dde0e0).
14. The legend's second sentence (a design annotation) is not rendered.

## 14. Risks

- **API breadth**: the Projects page depends on `GET /review/projects`; build §9.1 A–C first.
  Without it the page would need N+1 calls and would miss projects outside the HUB's 25 most
  recently updated deals.
- **Spatial report coupling**: report fields and `checkRows` are shared with `spatial-report`;
  agree the `ReportSummary` contract before either side ships (this spec proposes it).
- **Contrast**: HUB colours as drawn fall below WCAG AA in places (muted text `rgba(0,0,0,.4)` on
  white 2.85:1; links `#14a692` 3.04:1; Limited soft badge `#c97f0a` on `#fdeccb` 2.76:1; solid
  Ready badge white on `#2bb673` 2.61:1). Kept as drawn per the owner; words and shapes carry
  every status. Flag to the HUB design-system owners.
- **Route moves**: tests import page modules by path; move tests with the pages.
- **Backfill**: `field_controls` / `manifest_bytes` for already sealed packages need the one-off
  script; until it runs those packages show "Field controls are shown once the package is sealed."
  wrongly — run the backfill in the same deploy.
- **Archive storage** (phase 3): ZIPs double storage for 7 days per request; job must stream.
- **Font metrics**: Inter is wider than Lato; long addresses in the topbar title truncate with an
  ellipsis (full text in `title`).

## 15. Open questions (with the default the build uses)

| # | Question | Default |
|---|---|---|
| Q1 | Add a real Inter Bold 700 web font (needs the Inter variable font from the Chapter OneDrive and a run of `tools/brand/generate_plan_brand.py` with weights 400, 600, 700) so HUB 700 weights render as drawn? | No: render every HUB 700 in Inter SemiBold 600 (matches the PDFs and the phone); revisit if the owner wants heavier type |
| Q2 | Exact HUB web URLs for "Open the HUB", a deal, and a deal's Files folder | Optional env templates (§9.3); links hidden until set |
| Q3 | Where "Intake guide" points | `INTAKE_GUIDE_URL` env; item hidden until set |
| Q4 | "Download all": station-built ZIP (phase 3 job, 7-day retention) or drop the button | Build the station ZIP in phase 3; the button is not rendered until it exists |
| Q5 | Should the station stop publishing Blocked revisions to the HUB (the drawing says "Not published · re-seal needed")? | No change in this area: the web shows the station's real publication state; the text appears only when a Blocked revision was not published |
| Q6 | Allow the station spatial report ("Spatial report · room schedule") as a decision source (station rule today: package files only) | Not offered; rooms.csv is the package's room schedule |

---

## Addendum (completeness critique, Oct 21, 2026) — binding, overrides the body above

Numbers refer to `00-critique.md`. Built by track **T6 web-review** (`web/**`,
`tools/brand/chapter-wordmark.svg`). The OpenAPI and `review-text.ts` changes are built by **T0**,
the station routes, read model and migrations by **T2**, the report by **T4**.

### D1. Orientation texts come from `compass` §9 (R-31)
§5.3's table and its tests are superseded. Plan card "Orientation" value:
- verified `Verified · true north from the compass, ±{ACC}°. The plan sheet shows the north arrow.`
- approximate `Approximate · compass ±{ACC}°, {true north|magnetic north}. The plan sheet shows an approximate north arrow.`
- not verified `Not verified · {phrase}. North is not shown.` with phrase `no compass reading` /
  `the compass reading was rejected` / `compass accuracy ±{ACC}°` / `the compass was not
  calibrated` / `no compass on the phone` (drawn: `Not verified · no compass reading. North is not
  shown.`).
Capture record "Compass" value: one capture verified `Verified · {HDG}° true, ±{ACC}°`;
approximate `Approximate · {HDG}° {true|magnetic}, ±{ACC}°`; not verified `Not read · orientation
not verified` (no heading; drawn) / `Rejected · orientation not verified` / `±{ACC}° · orientation
not verified`; several captures: per-floor words joined ` · ` (`Floor 1 verified · Floor 2 not
read`). Source: contract `compassState` + `web/lib/compass.ts` (this track). Accuracy is an
integer: the test boundaries become 10 → verified, 11 → approximate, 30 → approximate, 31 → not
verified; magnetic 5 → approximate; missing → not verified.

### D2. Shared words (R-15c, R-15d)
`contract/ts/src/review-text.ts` exports `RESULT_WORD`, `OUTCOME_WORD`, `lowerFirst`, `ruleResult`,
`checkRows`, `sortCheckRows`, `checkCounts`, `countsLine`, `verdictHeadline`, `ruleSetLabel`,
`notScannedText` — the spatial report imports the same module (its `verdict-words.ts` is not
created). `ruleSetLabel(evaluator)` = `"{evaluator.name} v{evaluator.version}"` (meta line:
`checked May 16, 2026 14:02 · rules station-checks v1.1.0`). `notScannedText`: inaccessible with a
reason prints `{name} (could not enter: {reason})`.

### D3. Spatial report link and summary (R-14)
- Station call: `getSpatialReportLink` → `GET /v1/packages/{id}/spatial-report` (returns
  `SpatialReportLink` with `checksPage`). The web route `/packages/[id]/report/download` keeps its
  URL and behaviour (303, `no-store`, `no-referrer`) and calls it. §9.1 G is withdrawn.
- `PackageSummary.report` is filled by the station from `spatial_reports` (status rule of R-14:
  ready / pending / failed; `checksPage`, `pages`, `bytes`, `sha256`, `floors`, `hub`). The
  station spatial report virtual row in the Files card takes its HUB badge from `report.hub`.

### D4. "Registered" (R-16)
`PackageSummary.registeredAt` is **not** added. Station card row 1: ● `Registered` ·
`formatDayTime(createdAt)` for every package (drawn `May 16 · 13:58`). While uploading, row 2 is ○
`Checks` · `after upload`; the upload percentage stays in the status card (§6.4.3). §7's
"Registered time" row reads `createdAt`.

### D5. Migration number (R-13)
`station/db/migrations/0011_review-read-model.sql` (was 0009; 0009 is phone-package's carry-over,
0010 the spatial reports).

### D6. HUB deal link (R-15b)
The project page "Open in the HUB" uses `links.hub` from the station (`HUB_WEB_DEAL_URL_TEMPLATE`
at the station). The web env `HUB_DEAL_URL_TEMPLATE` is dropped from §9.3 and `.env.example`.
`HUB_APP_URL`, `HUB_FILES_URL_TEMPLATE`, `INTAKE_GUIDE_URL` stay.

### D7. Revision n on the phone, as drawn (R-30) — deviations 2, 3 and 8 withdrawn
Data: for each visit of the project, the newest package P known to the station; `GET /packages/{P}`
returns `nextRevision` N while the phone works on revision P.revision + 1 (phone-package §10.2).
N disappears when the station receives that revision; then today's rows apply.

**Packages table**, one extra row above P's row when N exists:

| Column | Value |
|---|---|
| Package | `Revision {N.revision}`; sub line 12 px muted `not sealed · on the phone` |
| Verdict | VerdictBadge neutral, no glyph, `Not checked yet` |
| Captured | `{dayLabel(N.updatedAt)} · {N.updatedBy}` (drawn `Today · [OPERATOR]`) |
| Checked | `—` muted |
| Contents | compact line from `N.changes` in order, joined ` · `: capture added `+ {title lower-cased}`; field controls added or changed, counted `+ {k} control` / `+ {k} controls`; photos `+ {k} photos` (k = the leading integer of each photos title, summed); room names `+ room names`; retired file `− phone report` (drawn `+ primary closet · + 1 control · + 3 photos`) |
| In the HUB | `—` muted |
| (Open) | none (nothing at the station to open) |

**"What revision {N.revision} adds" card**: shown when N exists (and as in §6.3.1 for a station
revision > 1 without a verdict). Right text 12 px muted: `from the phone, not sealed yet`. Tiles
from `N.changes` (max 6, then `+{k} more changes`):

| Change subject | Tile title | Tile sub |
|---|---|---|
| capture (added) | `{title} scanned` | answering: `answers limitation {i} · coverage`; else `{detail lower-first}` |
| field_control | `{title}, {method}` when the change carries `method`, else `{title}` | answering: `answers limitation {i} · {mm}`; else `{mm}` (the detail segment that ends in ` mm`) |
| photos | `{title}` | `{detail lower-first}` (drawn `primary closet · general, ceiling, opening`) |
| room_names, retired_file | `{title}` | `{detail}` |

`{i}`: take `A = change.answersNextAction`; find the first finding `f` of the base verdict with
`f.severity == "limitation"` and `f.nextAction == A`; `L = f.captureId ? "{label}: {f.message}" :
f.message` (label from the capture record, as the station builds limitations); `i` = 1-based index
of `L` in `verdict.limitations`. Not found → no "answers" prefix.

`NextRevisionNotice.changes[]` gains optional `method: "tape" | "laser"` (T0; phone-package fills
it for field controls) so the drawn `Room 4 ceiling height, tape` is reproducible.

**Verdict card, column 3** (package page of P): when N exists, 12 px muted: `Revision
{N.revision} is in progress on the phone` + suffix by `a` = distinct base next actions named by
`answersNextAction`, `t` = `verdict.nextActions.length`: a = 0 → `.`; a = t = 1 → ` with this
next action.`; a = t = 2 → ` with both.` (drawn); a = t ≥ 3 → ` with all {t}.`; 0 < a < t →
` with {a} of the {t} next actions.` No link (nothing to open yet). Without N, §6.4.2's
station-revision lines apply.

Tests: `revision-diff.test.ts` adds notice rows, compact line, tile titles/subs, limitation index
mapping (label-prefixed limitation), suffix cases; `project.test.tsx` renders the drawn 424 state
(Revision 2 not sealed on the phone).

### D8. Plan sheet document row (R-32) — deviation 7 narrowed
Right text `Tabloid · 1 sheet · from the phone` when the `plan_pdf` entry has `generator ==
"chapter-capture-ios/PlanExport"` and `generatorVersion` ≥ `2.0.0` (semver compare); else
`{formatBytes(bytes)} · from the phone`. `PackageFile.generator`/`generatorVersion` come from the
manifest entry (T2 exposes them if they are not already in `PackageFile`).

### D9. PM (R-33)
Meta row item `PM {projectManager.name}` after the deal id when the station's `HubProject` has it
(optional, R-15); omitted otherwise (deviation 1 only in that case).

### D10. Rule count
With the station check `orientation.compass` (compass §8.2, track T3) verdicts have 13 rules and
evaluator 1.1.0. Fixture-based tests and Playwright baselines are recorded after T3 lands; the
drawn "9 rules" is mock data.

### D11. Not changed by this critique
The HUB look, Inter-only type, self-hosted fonts, capture-role hiding, routes, security and the
remaining deviations (white wordmark, Inter 600 for HUB 700, "for the drawing to scale",
"compare a download with its SHA-256", legend second sentence, photos' real HUB state, "Capture
model" role, "Uploading" tab holding checks in progress).
