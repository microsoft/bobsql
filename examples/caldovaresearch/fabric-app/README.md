# Hosting Caldova as a Fabric app with Rayfin

Status: **prepared, not deployed.** The application changes are done and the workspace
exists. The Rayfin CLI could not be driven to completion on the build machine, so the
final `rayfin up` is a manual step.

## What was found

Rayfin has three services that matter here, and only one of them fits Caldova.

| Service | Fits Caldova? | Why |
|---|---|---|
| `staticHosting` | Yes | Serves the built React client behind one Fabric URL with Fabric SSO. |
| `data` | **No** | Provisions its *own* SQL database from `@entity()` classes and exposes it through Data API Builder GraphQL. DAB has no `VECTOR_SEARCH`, no `WITH APPROXIMATE`, and cannot attach to an existing Hyperscale database. |
| `functions` | Not yet | Marked experimental, with no documented way to reach an external database. |

So the search path cannot move into Rayfin. Caldova searches an existing corpus with a
vector index; Rayfin's data layer is a different database with a different query surface.

## The architecture that does work

```
Fabric workspace "Caldova"
└── Rayfin app (staticHosting)         ← React client, Fabric SSO, one stable URL
        │  fetch(VITE_API_BASE_URL)
        ▼
Azure Container Apps "caldova-app"     ← Express API + query embedding service
        │  Microsoft Entra, managed identity
        ▼
Azure SQL Hyperscale "research"        ← corpus, vector index, full-text index
```

The client already supports this. `VITE_API_BASE_URL` switches it from same-origin to an
absolute API, and the API only accepts cross-origin calls from origins named in
`CALDOVA_ALLOWED_ORIGINS`.

## Deploying it

1. Sign in once:

   ```bash
   npx rayfin login
   ```

2. Build the client against the deployed API:

   ```bash
   cd caldovaresearch/app
   VITE_API_BASE_URL=https://<api-host> npm run build
   ```

3. Copy `dist/` next to `rayfin/rayfin.yml`, then:

   ```bash
   cd ../fabric-app
   npx rayfin up -w "Caldova" -y
   ```

4. Take the hosting URL it prints and allow it on the API:

   ```bash
   az containerapp update -g <resource-group> -n <container-app-name> \
     --set-env-vars CALDOVA_ALLOWED_ORIGINS=https://<hosting-url>
   ```

5. Open the Fabric URL, sign in with your organization account, and run a question.

## Known blocker

On this machine the Rayfin CLI (`@microsoft/rayfin-cli` 1.33.1) hangs before printing
anything, including `--version`, with Node v22.19.0. Node itself runs fine. Until that is
resolved the deploy has to happen from another machine or a different Node version.

## Workspace

Create a Fabric workspace on a capacity you own and deploy into it. The values below are
the ones the `rayfin.yml` in this folder expects you to supply.

| | |
|---|---|
| Workspace | `<workspace-name>` |
| Capacity | `<capacity-name>` |
| Region | The region of your capacity |
