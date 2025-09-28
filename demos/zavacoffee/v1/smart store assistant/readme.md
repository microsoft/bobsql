Got it—Zava + HPE edge with on‑prem AI only. Here’s a store‑ready architecture that keeps all inference local on your HPE Edgeline devices, while using SQL Server 2025 for vector search, governance, and resilience. I’ll include specific HPE, SQL 2025, and model‑serving details—and a rollout plan.

1) Why this fits Zava’s HPE edge strategy

Run entirely at the store: HPE Edgeline systems (e.g., EL4000) are rugged, compact, x86 servers designed for deep edge compute with datacenter‑class iLO management—built for places like retail outlets where connectivity can be unreliable. They are purpose‑built to analyze and act on the edge without round‑tripping data to the cloud. [HPE Edgeli...d IT | HPE], [Product fe...roduct ...]
On‑prem vector search in the DB: SQL Server 2025 adds a native VECTOR(n) type, vector functions, and DiskANN vector indexes—so semantic search happens inside SQL, locally, with no extra vector service. [Vector Sea...Server ...], [Announcing...erver 2025]
No GPU required for vector search: Microsoft notes the new vector/DiskANN path runs efficiently on modest hardware (CPU only), which matches store‑edge constraints. [What's new...rosoft.com]
Local model serving: Run Ollama (REST: /api/embeddings, /api/generate) or vLLM (OpenAI‑compatible server) on the same Edgeline host or sibling node—all on‑prem. [ollama/doc...a · GitHub], [OpenAI-Com...ver — vLLM]
Retail‑grade networking & resiliency: HPE Aruba solutions provide secure branch connectivity and optional cellular failover for stores, plus compact switching that pairs with edge servers—useful when “semi‑often” backhaul is available but not guaranteed. [HPE Aruba...owered ...]


2) Reference architecture (per store)
Hardware (edge):

HPE Edgeline chassis (e.g., EL4000) with NVMe for fast vector indexes; managed via HPE iLO. [Product fe...roduct ...]
Aruba branch networking (APs/switches; optional 100‑series Cellular Bridge for WAN failover). [HPE Aruba...owered ...]

Runtime stack (all local):

SQL Server 2025

VECTOR(n) columns for embeddings, DiskANN for ANN search, exact K‑NN via VECTOR_DISTANCE() for small candidate sets. [Vector Sea...Server ...], [Announcing...erver 2025]
Temporal tables for versioned SOPs/recipes; RLS for store‑scoped access; Regex functions for content QA. [Microsoft...Comparison], [Re: Fabric...warehouse?], [What is SQ...erver Tips]
Optional FP16 vectors to halve storage when the embedding model tolerates it. [Microsoft...rosoft ...], [SQL Server...16 support]


Local model server

Ollama for embeddings + answers (REST at localhost:11434), or
vLLM for OpenAI‑compatible /v1/embeddings and /v1/chat/completions locally. [ollama/doc...a · GitHub], [OpenAI-Com...ver — vLLM]


Assistant UI (POS/KDS/back‑office tablet)

Calls local embedding → queries SQL vector index → (optionally) asks local LLM for a grounded answer.



Networking & management:

Aruba Central / GreenLake for network lifecycle and zero‑trust access (optional NaaS); iLO for server health/firmware. [GreenLake...tion Guide], [Partner Sp...ke for ...]


3) Data model that works offline
Core tables (all live on the store node):

doc.Document (temporal) – metadata, store_scope (NULL = global), version_label, status. [Microsoft...Comparison]
doc.DocumentChunk (temporal) – chunked text with text_hash. [Microsoft...Comparison]
doc.DocumentEmbedding – VECTOR(n) per chunk & model; DiskANN index for fast ANN. [Vector Sea...Server ...], [Announcing...erver 2025]
assist.QueryLog, assist.RetrievalLog, assist.AnswerFeedback – usage/quality signals (batched to HQ when backhaul is up).
sec.UserPrincipal, sec.UserStoreRole + RLS policies – restrict content by store/role. [Re: Fabric...warehouse?]
qa.ValidationRule + Regex rules for content checks (e.g., allergen line present). [What is SQ...erver Tips]


Exact vs. ANN: for small filtered sets (e.g., a store & a category), use exact VECTOR_DISTANCE(); once vectors exceed ~50k after predicates, use an ANN DiskANN index for speed. [SQL Server...L Devs ...], [architectu...cosmos ...]


4) All‑on‑prem inference (no cloud calls)
Ollama (one process, CPU or GPU if available):
Shell# install and pull a local embed modelollama pull nomic-embed-textcurl -s http://localhost:11434/api/embeddings \  -d '{"model":"nomic-embed-text","prompt":"steam milk to 60–65C"}'# embeddings REST call (local only)Show more lines
(Ollama exposes /api/embeddings and /api/generate over localhost; works offline.) [ollama/doc...a · GitHub]
vLLM (OpenAI‑compatible, on your Edgeline):
Shell# serve an embedding or chat model locallyvllm serve your-hf-repo/embedding-model --host 0.0.0.0 --port 8000 --task embedShow more lines
(vLLM’s server implements OpenAI‑style /v1/* endpoints for chat/completions/embeddings.) [OpenAI-Com...ver — vLLM]

Either way, embeddings never leave the store. SQL stores vectors locally and answers queries locally.


5) Update & sync pattern (semi‑often connectivity)

HQ → Stores (content & models)

Author/review SOPs centrally; build a release package (docs, chunks, model tag).
When a store is online, push the package (rsync/agent) → apply to temporal tables; rebuild DiskANN index as needed. [Microsoft...Comparison], [Announcing...erver 2025]


Stores → HQ (telemetry & QA)

Batch upload assist.* logs and qa.ValidationFinding when the link returns.
If you adopt cloud later, SQL 2025 Change Event Streaming can stream row changes to Event Hubs; until then, keep the offline‑first batch. [Fabric Mir...review ...]




6) Security & operations

RLS in the database enforces store/role scope—no accidental data sprawl if tools connect directly. [Re: Fabric...warehouse?]
Temporal retains prior SOP versions for audit/rollback (“show as of Friday 18:00”). [Microsoft...Comparison]
Aruba: zero‑trust access control and optional cellular WAN resilience for payment/ops; compact switches pair with edge servers. [HPE Aruba...owered ...]
HPE iLO: lifecycle and out‑of‑band management for Edgeline systems at the store. [Product fe...roduct ...]


7) Sizing guidance (conservative, CPU‑first)

CPU & RAM: Vector search in SQL 2025 is optimized for CPU; aim for multi‑core Xeon with 32–64 GB RAM per node for comfortable ANN + local LLM. (No GPU required for vector search itself.) [What's new...rosoft.com]
Storage: NVMe for DiskANN graphs (fast random I/O). Consider FP16 vectors to halve footprint if quality holds for your embed model. [Announcing...erver 2025], [SQL Server...16 support]
Network: Standard wired LAN; optional Aruba cellular backup for scheduled sync windows. [HPE Aruba...owered ...]


8) Deployment blueprint (pilot → 50 stores)
Phase 0 – Lab (1–2 weeks)

Stand up SQL Server 2025 (preview features on) + Ollama on an Edgeline test node; ingest 200–500 SOP pages; test exact vs ANN queries. [Vector Sea...Server ...], [Announcing...erver 2025]

Phase 1 – Pilot (2 stores, 3–4 weeks)

Add RLS, temporal, regex QA; run barista usability tests; confirm ANN recall/latency; package & apply offline updates. [Re: Fabric...warehouse?], [Microsoft...Comparison], [What is SQ...erver Tips]

Phase 2 – Rollout (48 stores)

Use an HPE/Aruba‑managed rollout (iLO + GreenLake/Aruba Central inventory) to push content/model releases & monitor health. [GreenLake...tion Guide]


9) What you gain by keeping all AI on‑prem

Deterministic performance in every store (no WAN round‑trips).
Data stays in the building (embeddings + queries never leave).
One engine for search and governance (temporal, RLS, regex) with SQL skills you already have. [Vector Sea...Server ...], [Microsoft...Comparison], [Re: Fabric...warehouse?], [What is SQ...erver Tips]


10) Want me to package this into a store image?
I can deliver:


Edge image (scripts + services):

SQL 2025 DB creation, DiskANN index build, temporal/RLS policies;
Ollama or vLLM service unit; health probes.



Release tooling (HQ):

Chunk/embed packager; store delta applier; ANN index rebuild orchestration.



Benchmark harness:

Exact vs ANN, FP32 vs FP16 vectors on your SOP corpus; target recall & p95 latency. [SQL Server...L Devs ...], [SQL Server...16 support]



If you confirm you’re standardizing on Ollama or vLLM, I’ll generate the deployment scripts + runbook next.