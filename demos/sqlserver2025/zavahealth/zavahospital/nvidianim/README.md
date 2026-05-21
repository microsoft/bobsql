# NVIDIA NIM on AKS — SQL Server 2025 Vector Search + Chat Completions

Deploy NVIDIA NIM inference microservices on Azure Kubernetes Service with T4 GPUs, then call them from SQL Server 2025 using `AI_GENERATE_EMBEDDINGS` and `sp_invoke_external_rest_endpoint`.

## Architecture

```
SQL Server 2025 (localhost)
  ├── AI_GENERATE_EMBEDDINGS() ──→ NIM Embedding (T4 #1)
  └── sp_invoke_external_rest_endpoint ──→ NIM Chat (T4 #2)

AKS Cluster: aks-nvidianim (westus2)
  ├── System node pool: 1x Standard_DS2_v2 (ingress, system pods)
  └── GPU node pool: 2x Standard_NC4as_T4_v3
        ├── T4 #1: nvcr.io/nim/nvidia/nv-embedqa-e5-v5:latest (1024 dims)
        └── T4 #2: nvcr.io/nim/meta/llama-3.2-3b-instruct:latest
```

Ingress via AKS App Routing (managed NGINX) with TLS:
- `https://nim-aks.local/v1/embeddings` → embedding model
- `https://nim-aks.local/v1/chat/completions` → chat model

The hostname `nim-aks.local` resolves via Windows hosts file to the AKS ingress IP. A self-signed TLS certificate (CN=nim-aks.local) is imported into both the K8s cluster and the Windows Trusted Root store.

## Prerequisites

- Azure subscription with **8 vCPUs of NCASv3_T4 quota** in westus2
- **NGC API key** from https://org.ngc.nvidia.com/ (Setup → API Key)
- Azure CLI (`az`) installed and logged in
- SQL Server 2025 instance (localhost, Windows auth)

## Quick Start

### 1. Create AKS Cluster + GPU Nodes

```powershell
cd nvidianim
.\create-aks-cluster.ps1
```

Creates resource group `rg-nvidianim-westus2`, AKS cluster with 1 CPU system node + 2 T4 GPU nodes, installs NVIDIA device plugin, configures kubectl.

### 2. Deploy NIM Containers

```powershell
$env:NGC_API_KEY = 'nvapi-your-key-here'
.\deploy-nim.ps1
```

Creates NGC pull secret + API key secret, deploys both NIM pods (embedding + chat), sets up ingress routing.

### 3. Wait for Models to Load

```powershell
kubectl get pods -w
```

NIM containers download models on first start (~5-10 min). Wait until both pods show `Ready 1/1`.

### 4. Switch to Local Hostname

```powershell
.\switch-hostname.ps1 -NewHostname nim-aks.local
```

Generates a self-signed TLS cert, updates K8s ingress + TLS secrets, adds a Windows hosts file entry, imports the cert to Windows Trusted Root, and updates SQL Server objects. Requires admin elevation for hosts file and cert store.

### 5. Test Endpoints

```powershell
.\test-embedding.ps1          # auto-detects ingress IP
.\test-chat.ps1                # auto-detects ingress IP
```

### 6. SQL Server Integration

Run SQL scripts in order against your SQL Server 2025 instance. Scripts are pre-configured with `nim-aks.local`.

| Script | Purpose |
|--------|---------|
| `sql\00_setup.sql` | Create `FoundryLocalTest` database (skip if exists) |
| `sql\01_create_external_model.sql` | `CREATE EXTERNAL MODEL` → NIM embedding endpoint |
| `sql\02_test_embedding.sql` | `AI_GENERATE_EMBEDDINGS()` smoke test |
| `sql\03_enable_rest_endpoint.sql` | Enable `sp_invoke_external_rest_endpoint` |
| `sql\04_test_chat_completion.sql` | Chat completion from T-SQL |

## File Layout

```
nvidianim/
├── README.md                  # This file
├── backlog.md                 # Progress checklist
├── SKILL.md                   # Copilot skill discovery
├── create-aks-cluster.ps1     # Step 1: AKS + GPU nodes
├── deploy-nim.ps1             # Step 2: NIM containers + ingress
├── switch-hostname.ps1        # Step 4: TLS cert + hostname + SQL objects
├── test-embedding.ps1         # Test embedding endpoint
├── test-chat.ps1              # Test chat endpoint
├── cleanup.ps1                # Delete resource group
├── k8s/
│   ├── nim-embedding.yaml     # Deployment + Service for nv-embedqa-e5-v5
│   ├── nim-chat.yaml          # Deployment + Service for llama-3.2-3b-instruct
│   └── ingress.yaml           # Ingress routes with TLS for nim-aks.local
│                              # (TLS cert is generated on-demand by switch-hostname.ps1
│                              #  and is NOT bundled in the repo — each consumer gets a
│                              #  fresh self-signed cert for CN=nim-aks.local)
└── sql/
    ├── 00_setup.sql
    ├── 01_create_external_model.sql
    ├── 02_test_embedding.sql
    ├── 03_enable_rest_endpoint.sql
    └── 04_test_chat_completion.sql
```

## NIM Containers

| Container | Image | GPU | Purpose |
|-----------|-------|-----|---------|
| Embedding | `nvcr.io/nim/nvidia/nv-embedqa-e5-v5:latest` | T4 #1 | 1024-dim embeddings for vector search |
| Chat | `nvcr.io/nim/meta/llama-3.2-3b-instruct:latest` | T4 #2 | Chat completions / clinical decision support |

## Cost

- 2x Standard_NC4as_T4_v3: ~$0.53/hr each = **~$1.06/hr** for GPU nodes
- 1x Standard_DS2_v2 system node: ~$0.10/hr
- **Run `.\cleanup.ps1` when done** to delete the resource group and stop charges

## Chat Completion Quality and Safety

The chat model (`llama-3.2-3b-instruct`) is a 3B parameter model that fits on a single T4 GPU. For accurate responses, the system prompt in `04_test_chat_completion.sql` includes grounding facts from Microsoft documentation so the model doesn't hallucinate. The 8B model (`llama-3.1-8b-instruct`) OOMs on T4 16GB.

For production or demo scenarios requiring content safety, jailbreak prevention, and response quality controls, consider adding **NVIDIA NeMo Guardrails**:

- **What it does**: Orchestrates AI guardrails for topic control, PII detection, RAG grounding, jailbreak prevention, and content safety with low latency
- **How it works**: Screens both user inputs and model outputs based on customizable policies, blocking or filtering responses that violate rules
- **Integration**: Works as a microservice alongside NIM containers — same AKS cluster, same K8s patterns
- **Resources**:
  - [NeMo Guardrails Developer Page](https://developer.nvidia.com/nemo-guardrails)
  - [Documentation](https://docs.nvidia.com/nemo/guardrails/latest/index.html)
  - [GitHub (open source toolkit)](https://github.com/NVIDIA-NeMo/Guardrails)
  - [NeMo Guardrails Microservice on NGC](https://catalog.ngc.nvidia.com/orgs/nvidia/teams/nemo-microservices/containers/guardrails)
  - [Parallel Rails Tutorial](https://github.com/NVIDIA/GenerativeAIExamples/blob/main/nemo/NeMo-Guardrails/Parallel_Rails_Tutorial.ipynb)

## Cleanup

```powershell
.\cleanup.ps1                  # Deletes rg-nvidianim-westus2 (prompts for confirmation)
```

Also remove SQL objects if desired:
```sql
DROP EXTERNAL MODEL NIMEmbeddingModel;
```
