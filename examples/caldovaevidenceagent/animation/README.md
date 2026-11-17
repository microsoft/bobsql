# Architecture animation

A 30-second silent, caption-free motion treatment of the architecture diagram.
Service names and architecture labels remain visible. All objects are fully
visible and stationary from frame zero, with crisp borders, reduced corner
rounding, and no soft shadows. Only data packets and activity highlights animate.
The sequence shows corpus loading, passage embedding, vector storage, and DiskANN
index creation first, followed by skill loading, an app conversation, reasoning,
governed MCP calls, vector search against the existing index, and returning evidence.
This is an illustrative sequence, not a recording of live requests or measured latency.

## Render a 4K MP4

Requires Node.js 22+ and Microsoft Edge. No Azure resources or credentials are used.

```powershell
cd .\caldovaevidenceagent\animation
npm ci
npm test
npm run render
```

For the dark-mode version:

```powershell
npm test -- --dark
npm run render -- --dark
```

Dark-mode output uses `caldova-architecture-dark-4k.mp4`,
`caldova-architecture-dark-preview.png`, `contact-sheet-dark.png`, and
`verification-dark.txt`, preserving the existing light-mode files.

For another Chromium installation, set `CALDOVA_VIDEO_BROWSER` to its executable
path. FFmpeg is provided by the local development dependency.

Output is written to the ignored `output` directory:

- `caldova-architecture-4k.mp4`: 3840 x 2160, 30 fps, H.264, no audio track.
- `caldova-architecture-preview.png`: full-resolution closing composition.
- `caldova-architecture-opening.png`: full-resolution frame zero.
- `contact-sheet.png`: sixteen frames across the sequence.
- `verification.txt`: complete-video decode and format verification output.

To preview interactively, serve this directory with a local static HTTP server
and open `index.html`. The player controls do not appear in the rendered video.
Add `?dark` to the preview URL for dark mode.
The deterministic timeline is in `animation.mjs`; `render.mjs` renders exactly
900 frames, encodes the MP4, then checks the dimensions, duration, frame rate,
decoded frame count, and absence of an audio track.

## Embeddings before search

The first seven seconds show database preparation: load article passages into
SQL, generate their embeddings through Azure OpenAI, store the returned passage
vectors, then build the DiskANN index. The app question starts only after this
preparation completes.

The embedding model animates only during preparation. The video does not show
embedding regeneration or a second model round trip. A DiskANN index panel inside
Hyperscale fills with connected vectors after passage embeddings are stored.
Later, a search probe traverses that same index while the embedding model remains
idle. Scene checks verify the single preparation-only round trip, index creation
and access inside Hyperscale, and stationary cards from frame zero.

The runtime portion intentionally omits question-vector generation for visual
simplicity. The actual `search_evidence` procedure still embeds each new question
through `AI_GENERATE_EMBEDDINGS` before `VECTOR_SEARCH`; it does not regenerate the
stored passage embeddings.
