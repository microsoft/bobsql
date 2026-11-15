# Caldova architecture illustrations

Self-contained text sources for an offline architecture player, two editable
slide generators, and optional video exports. These are conceptual illustrations
of a synthetic regional-care scenario, not live application traffic or evidence
that a cloud deployment, database, or AI model was executed or verified.

## Offline player

Open `architecture-player.html` directly in a modern browser. It contains its
own CSS, JavaScript, and SVG; no web server, npm install, external assets, Azure
credentials, SQL Server, or model service is required for playback.

The five bottom buttons select Overview, Patient + search, Briefing, Ledger
audit, and Disconnected. Views do not automatically advance. Search embedding
traffic animates once; Briefing leaves its optional embedding connections static.
Ledger audit sequences generation, validation, atomic persistence, and an
append-only audit; select that button again to replay it. External ledger digest
verification is not configured in the illustrated scenario.

Connected mode depicts Azure-hosted management and AVD brokering with local
session-host, application, SQL, and inference compute. Disconnected is a
separately provisioned conceptual alternative, not a runtime switch or proof of
an air-gapped deployment. Offline playback of this HTML is independent of those
infrastructure requirements. Model/product names, including Nemotron and
gpt-oss-20b, identify illustrated components, not installed dependencies.

## Optional development tools

Run commands from this directory. Use a supported Node.js LTS release (Node.js
22 or newer recommended) and npm, then install the declared public packages:

```powershell
npm install
```

Dependencies:

- `playwright` 1.57.0: drives an **installed Microsoft Edge** browser through
  `channel: "msedge"` in both verification and export scripts. They use headless
  Edge, not Playwright's downloaded Chromium. Install Edge separately if absent;
  downloading Chromium alone does not satisfy these scripts.
- `@ffmpeg-installer/ffmpeg` 1.1.0: supplies the platform-specific FFmpeg binary
  used by the exporter. Installation needs registry access and an OS/CPU covered
  by that package. FFmpeg must execute locally and support PNG input, libx264,
  and H.264 decoding. A system FFmpeg on PATH is not used.
- `pptxgenjs` 4.0.1: generates both editable slides locally. It is resolved from
  this package, with no sibling repository or workspace tools required.

Internet access is needed for initial package/Edge installation, not player
playback. PowerPoint or another compatible viewer is optional for viewing the
generated decks; it is not needed to generate them. The generators specify
Segoe UI/Segoe UI Semibold, so install those fonts on the viewing/rendering
machine for the intended appearance. Other platforms may substitute fonts.

## npm scripts

| Command | Behavior |
| --- | --- |
| `npm run verify` | Launches headless Edge to test player navigation, flow branches, animation sequencing, geometry and interactive/export layouts at five sizes from 1024 x 768 to 1920 x 1080. Does not connect to SQL or Azure. |
| `npm run export` | Launches headless Edge and FFmpeg to generate and verify all five videos in `exports`. |
| `npm run build:business` | Creates `caldova-business-scenario.pptx`, a single editable business-scenario slide with notes. |
| `npm run build:comparison` | Creates `platform-comparison-visual.pptx`, a single editable platform-comparison slide with caveats and public reference links in its notes. |

The slide scripts can also be run directly with
`node build-business-scenario.cjs` and `node build-platform-comparison.cjs`.
They overwrite their corresponding decks when rerun. They do **not** create PNG
previews; use a presentation viewer's export function if a preview is needed.
The comparison's source-check dates are retained author notes, not a claim that
publication preparation rechecked all product capabilities or linked pages.

## Video exports

Each silent conceptual clip is 18 seconds, 1920 x 1080, 30 fps,
H.264/yuv420p with fast-start MP4 layout. The selected bottom button stays visible
throughout. The five filenames are:

- `01-overview.mp4`
- `02-patient-and-vector-search.mp4`
- `03-grounded-briefing.mp4`
- `04-briefing-and-ledger-audit.mp4`
- `05-disconnected.mp4`

```powershell
npm run export -- --chapter audit
npm run export -- ".\exports-new" --chapter search
```

Supported chapter IDs are `overview`, `search`, `briefing`, `audit`, and
`disconnected`. Omit `--chapter` for all five. Exporting is frame-by-frame and
can take time. The exporter refuses to overwrite an existing target; choose a
fresh output directory. It fully decodes each clip, verifies duration, frame
count, codec, animation, fast-start structure, absence of audio, and sampled
navigation-button colors before publishing it.

For HTML embedding, `?export=1` hides navigation and uses an explicit animation
clock; `?export=1&buttons=1` retains buttons. These modes are intended for the
exporter's `window.caldova.render` calls, not ordinary automatic playback.

## Generated files and verification limits

Only text sources are published here. `.gitignore` excludes `node_modules`,
`exports`, render work files, `.cache`, and generated PNG/PPTX/MP4 files.
Custom output directories' MP4 files are also ignored. No videos, slide decks,
previews, caches, or installed dependencies are supplied.

Publication preparation checked JavaScript syntax with `node --check`
(including the HTML's inline script), parsed `package.json`, and scanned text for
private identifiers and machine-specific paths. It did not install dependencies,
launch a browser, render slides, or run video exports. To perform functional
player verification yourself after installing dependencies and Edge, run
`npm run verify`. Passing that suite checks the illustration only, not the
availability, correctness, security, or performance of a live cloud demo.
