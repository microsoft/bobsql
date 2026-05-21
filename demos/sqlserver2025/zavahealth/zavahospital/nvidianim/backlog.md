# NVIDIA NIM on AKS — Backlog

## Prerequisites
- [x] GPU quota approved (8 vCPUs NCASv3_T4 in westus2)
- [ ] Get NGC API key from https://org.ngc.nvidia.com/ and set `$env:NGC_API_KEY`

## Infrastructure
- [x] Create AKS cluster + GPU node pool: `.\create-aks-cluster.ps1`
  - Creates `rg-nvidianim-westus2` resource group
  - AKS cluster `aks-nvidianim` with 1 system node (DS2_v2)
  - GPU node pool: 2x NC4as_T4_v3 (1x T4 16GB each)
  - Installs NVIDIA device plugin
  - Enables App Routing add-on

## Deploy NIM
- [ ] Set `$env:NGC_API_KEY` in terminal
- [ ] Deploy NIM containers: `.\deploy-nim.ps1`
  - Creates NGC registry pull secret + API key secret
  - Deploys nv-embedqa-e5-v5 (embedding) pod on T4 #1
  - Deploys llama-3.2-3b-instruct (chat) pod on T4 #2
  - Creates ingress routing /v1/embeddings and /v1/chat/completions
- [ ] Wait for pods to be Ready: `kubectl get pods -w` (5-10 min for model download)
- [ ] Get ingress IP: `kubectl get ingress nim-ingress`

## Test NIM Endpoints
- [ ] Test embedding: `.\test-embedding.ps1 -IngressIP <IP>`
- [ ] Test chat: `.\test-chat.ps1 -IngressIP <IP>`

## SQL Server 2025 Integration
- [ ] Run `sql\00_setup.sql` — create FoundryLocalTest db (skip if exists)
- [ ] Update `sql\01_create_external_model.sql` — replace `<INGRESS_IP>` with actual IP
- [ ] Run `sql\01_create_external_model.sql` — CREATE EXTERNAL MODEL → NIM embeddings
- [ ] Run `sql\02_test_embedding.sql` — AI_GENERATE_EMBEDDINGS smoke test
- [ ] Run `sql\03_enable_rest_endpoint.sql` — enable sp_invoke (skip if already enabled)
- [ ] Update `sql\04_test_chat_completion.sql` — replace `<INGRESS_IP>` with actual IP
- [ ] Run `sql\04_test_chat_completion.sql` — chat completion from T-SQL

## Healthcare Scenario (later)
- [ ] Bring in clinic/healthcare SQL scripts
- [ ] Vector search on patient data using NIM embeddings
- [ ] Chat completion for clinical decision support

## Future: Azure Local / DELL NVIDIA AI Factory
- [ ] Port same K8s manifests to AKS on Azure Local
- [ ] Same NIM containers, same SQL — different infrastructure
- [ ] Separate scenario folder TBD

## Cleanup
- [ ] `.\cleanup.ps1` — deletes resource group (GPU nodes cost ~$0.53/hr each)
- [ ] `DROP EXTERNAL MODEL NIMEmbeddingModel;` in SQL Server
