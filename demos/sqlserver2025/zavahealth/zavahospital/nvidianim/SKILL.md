---
name: nvidianim
description: 'NVIDIA NIM on AKS with GPU — vector embeddings and chat completions from SQL Server 2025 T-SQL using GPU-accelerated inference. Use when: deploying NIM containers on AKS, creating AKS GPU node pools, testing NIM endpoints, creating external models for NIM embeddings, Azure Local edge AI pattern, working in nvidianim/.'
---

# NVIDIA NIM + AKS + SQL Server 2025 Demo

## Architecture
- **AKS cluster** in westus2 with **2x NC4as_T4_v3** GPU nodes (1x NVIDIA T4 16GB each)
- **NIM chat**: `meta/llama-3.2-3b-instruct` on dedicated T4
- **NIM embeddings**: `nvidia/nv-embedqa-e5-v5` (1024 dims) on dedicated T4
- **SQL Server 2025** localhost, Windows auth, `FoundryLocalTest` database
- **TLS**: Self-signed cert (CN=nim-aks.local) via AKS Web Application Routing (managed NGINX ingress)
- **Hostname**: `nim-aks.local` via Windows hosts file → AKS ingress IP (get with `kubectl get ingress -n nim`)
- **Content-Type fix**: NGINX annotation `proxy_set_header Content-Type "application/json"` strips charset suffix that NIM rejects
- **NGC API key** required to pull NIM containers from `nvcr.io`

## Flow
```
SQL Server 2025 → HTTPS → AKS Ingress (TLS termination) → HTTP → NIM pods (port 8000)
```

## Setup Sequence
1. Create AKS cluster: `.\create-aks-cluster.ps1`
2. Deploy NIM containers: `.\deploy-nim.ps1` (requires `$env:NGC_API_KEY`)
3. Wait for pods + ingress ready
4. Switch to local hostname: `.\switch-hostname.ps1 -NewHostname nim-aks.local` (generates TLS cert, updates ingress, hosts file, SQL objects)
5. Test endpoints: `.\test-embedding.ps1`, `.\test-chat.ps1`
6. Run SQL scripts: `sql\00_setup.sql` through `sql\04_test_chat_completion.sql`

## PowerShell Scripts
| Script | Purpose |
|--------|---------|
| `create-aks-cluster.ps1` | Create AKS cluster + GPU node pool (2x NC4as_T4_v3) |
| `deploy-nim.ps1` | Deploy NIM containers + ingress to AKS || `switch-hostname.ps1` | TLS cert generation, K8s secrets, ingress update, hosts file, SQL cert/model || `test-chat.ps1` | Test chat completion endpoint |
| `test-embedding.ps1` | Test embedding endpoint |
| `cleanup.ps1` | Delete AKS cluster and resource group |

## K8s Manifests
| File | Purpose |
|------|---------|
| `k8s\nim-chat.yaml` | Deployment + Service for llama-3.2-3b-instruct NIM |
| `k8s\nim-embedding.yaml` | Deployment + Service for nv-embedqa-e5-v5 NIM |
| `k8s\ingress.yaml` | Web App Routing ingress with TLS for nim-aks.local |
| `k8s\tls.*` | Self-signed TLS cert files (.crt, .key, .pfx, .cer) |

## SQL Scripts (run in order)
| Script | Purpose |
|--------|---------|
| `sql\00_setup.sql` | Create `FoundryLocalTest` database (skip if exists from foundrylocal demo) |
| `sql\01_create_external_model.sql` | `CREATE EXTERNAL MODEL` → AKS NIM embedding endpoint |
| `sql\02_test_embedding.sql` | `AI_GENERATE_EMBEDDINGS` smoke test (1024-dim vector) |
| `sql\03_enable_rest_endpoint.sql` | `sp_configure` + GRANT (skip if already enabled) |
| `sql\04_test_chat_completion.sql` | `sp_invoke_external_rest_endpoint` → NIM chat |

## Azure Details (defaults — override on the command line)
- Subscription: pass with `-Subscription <your-subscription-guid>` to `create-aks-cluster.ps1`
- Region: `westus2`
- GPU: 8 vCPUs NCASv3_T4 quota (2x NC4as_T4_v3 nodes)
- Resource group: `rg-nvidianim-westus2`
- Cluster name: `aks-nvidianim`

## Key Facts
- NIM containers require **NGC API key** set as `$env:NGC_API_KEY`
- NIM images pulled from `nvcr.io/nim/` registry
- Both NIM endpoints are OpenAI API compatible (`/v1/chat/completions`, `/v1/embeddings`)
- Same T-SQL patterns as Foundry Local demo — only URLs change
- `nv-embedqa-e5-v5` produces 1024-dim embeddings (same as qwen3-embedding-0.6b)
- NIM rejects `application/json;charset=utf-8` — NGINX annotation fixes this
- Llama 3.1 8B OOMs on T4 (16GB); Llama 3.2 3B fits but needs system prompt grounding for quality answers
- Chat system prompt should include key facts from `https://learn.microsoft.com/sql/` to avoid hallucination
- `switch-hostname.ps1` handles full hostname migration (cert, K8s, hosts file, SQL objects)
- **NVIDIA NeMo Guardrails** can add content safety, jailbreak prevention, and topic control to chat completions — see https://developer.nvidia.com/nemo-guardrails
- **Same containers and K8s manifests work on Azure Local** for edge deployment

## Demo Narrative
This is the "cloud version" that proves the Azure Local edge story:
- Hospital runs SQL Server 2025 + NIM on Azure Local in their data center
- Patient data never leaves the building — zero cloud API calls
- Same code, same containers, same T-SQL — different infrastructure underneath

## Troubleshooting
- If pods stuck in `ImagePullBackOff` → check NGC_API_KEY is correct and K8s secret is created
- If pods stuck in `Pending` → GPU node pool may not have scaled up yet (wait ~5-10 min)
- If ingress has no IP → check Web Application Routing add-on is enabled
- If SQL returns TLS errors → ensure cert is in Windows Trusted Root and hosts file has correct IP
- If NIM returns "Unsupported media type" → ingress.yaml needs `proxy_set_header Content-Type` annotation
- If chat model gives bad answers → add grounding facts in the system prompt (3B model needs context)
- If 8B chat model OOMs on T4 → reduce `NIM_MAX_MODEL_LEN` or use 3B model with system prompt grounding
