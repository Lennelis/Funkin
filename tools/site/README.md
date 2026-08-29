# The tools site

The five modding tools, published as one site so they can be opened on any
device and added to a phone's home screen.

Each tool in `tools/` stays a single self-contained file that works on its own
from your disk. The build only folds a shared touch layer and the app plumbing
into a *copy* of each one — nothing here is needed for a tool to run.

## Building

```sh
cd tools/site
node build.mjs        # writes dist/
```

No dependencies, no install step. To look at it as a phone would:

```sh
cd dist && python3 -m http.server 8000
```

A service worker only registers over `http(s)`, so opening `dist/index.html`
straight off the disk gives you the tools but not the offline caching.

## Publishing

`.github/workflows/pages.yml` builds and deploys on any push that touches
`tools/`. It needs Pages pointed at Actions once, under **Settings → Pages →
Build and deployment → Source → GitHub Actions**.

## What is here

| | |
|---|---|
| `hub.html` | The home screen. `/*FONTS*/` is replaced at build time with the two faces lifted out of a tool, so the fonts are embedded once rather than fetched. |
| `mobile.css` | The touch layer. Only applies under 900px; the desktop layout is untouched. |
| `mobile.js` | Builds the pane switcher every tool shares, remembers which panel you were on per tool, and registers the worker. |
| `sw.js` | Caches the whole set on first visit. `__VERSION__` and `__FILES__` are filled in by the build, so a new build replaces the old cache. |
| `build.mjs` | Puts it together. |
| `icon.mjs` | Redraws the icons. Only needed if you want to change them; the PNGs are committed. |

## Adding a tool

Drop the file in `tools/`, add its name to `TOOLS` in `build.mjs`, and add a
card to `hub.html`. It picks up the touch layer and the offline caching on its
own, as long as it is built from the same shell: a `.topbar`, a `.workspace`
holding `.rail`, `.stage-col` and `.inspector`, and a `.drawer`.
