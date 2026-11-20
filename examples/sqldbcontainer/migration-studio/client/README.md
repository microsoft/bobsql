# AI Migration Studio · client

Standalone Azure-themed React + TypeScript + Fluent UI v9 frontend. No mock data,
browser-held source credentials, cloud actions at startup, or application cutover.
The parent .NET host on `http://localhost:5188` serves `dist/` and the real
`/api/*` endpoints on the **same origin**. This client does not start the host.

## Build and test

Node.js 22.18+ (or a current supported Node.js LTS) and npm:

```powershell
npm --prefix sqldbcontainer/migration-studio/client ci
npm --prefix sqldbcontainer/migration-studio/client test
npm --prefix sqldbcontainer/migration-studio/client run build
```

Build type-checks strict TypeScript before generating `client/dist`. Versions are
pinned in `package.json` and `package-lock.json`. The optional `npm run dev`
command is not started automatically; Vite alone has no API backend, so it
intentionally shows unavailable states unless hosted with same-origin API routing.
Do not expose a credentialed local backend through a public development server.

## API integration

- `src/types.ts`: the shared frontend contract, tolerant of extra server fields.
- `src/api.ts`: typed same-origin fetch, cookie credentials, shared
  `GET /api/session` bootstrap before reads, events, or commands; **every POST**
  sends `X-CSRF-TOKEN`.
  RFC Problem Details `title` and `detail` are shown; mutations never auto-retry.
- `src/hooks.ts`: abortable read-only requests, dependent selections cannot expose
  stale results from the previous tenant or subscription.
- `src/live.ts`: one `/api/events` EventSource; bounded 500-event activity journal;
  incremental `copilot` deltas, no simultaneous sends, terminal-event completion.
  An uncertain chat outcome remains locked awaiting a server terminal event.
- No mock/live seam: all screens call actual APIs. No SDK, SQL, shell, Azure
  credentials, or direct cloud connections run in the browser.

Implemented inventory:

```text
GET  /api/session
GET  /api/status
GET  /api/discovery/containers
POST /api/discovery/databases {containerName}   # explicit user request only
GET  /api/azure/tenants
GET  /api/azure/subscriptions?tenantId=...
GET  /api/azure/locations?subscriptionId=...
GET  /api/azure/groups?subscriptionId=...
GET  /api/azure/servers?subscriptionId=...&resourceGroup=...
GET  /api/azure/identity?tenantId=...
POST /api/plans                               # explicit review request
POST /api/plans/{id}/run
GET  /api/runs/{id}                           # poll active runs; pause on error
POST /api/runs/{id}/cancel {}
GET  /api/events                             # EventSource + copilot events
POST /api/copilot/message {text,model?}
```

The run gate requires exact text `CREATE FREE DATABASE AND MIGRATE` and an
acknowledgment that **ALL writers** are quiesced and the source is **already
READ_ONLY**, established through a separately approved operational action.
The backend must independently enforce consistency, immutable plan binding,
permissions, compatible SqlPackage, empty target, free-offer AutoPause, safe
cancellation, no source changes, no administrator replacement, and existing
narrowly scoped connectivity (no automatic firewall creation).
An unknown run submission outcome cannot simply be resubmitted: recover using
the actual backend run ID. Reload recovery is manual and read-only; state is not
stored in browser persistence.

Validation renders actual server evidence rather than claiming success for
unreported checks. Loaded skill attribution is separate from execution activity.
Service Desk links appear only when supplied by the backend. Optional cutover
is explicitly disabled.

## Layout / accessibility

Azure palette: `#0078D4`, `#005A9E`, `#50E6FF`, `#001E36`, cool white surfaces.
At 1512px: navy navigation, main workspace, persistent Copilot panel.
At 1000px: navigation and workspace, Copilot below the workspace.
At 390px: stacked cards and horizontally scrollable persistent stage navigation.
Body text and labels are at least 18px; native named selects, visible focus,
keyboard navigation, skip link, reduced-motion and forced-colors styles.
Logs are intentionally not aggressively announced; errors/status are explicit.

Tests cover pure approval/identity binding, event bounds and validation, URL
safety, and transport CSRF/error/no-retry behavior. Actual endpoint integration
and screenshot/browser checks require the parent host; no dev server or browser
is launched by this implementation.
