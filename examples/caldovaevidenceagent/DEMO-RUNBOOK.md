# Caldova Evidence Agent Demo Runbook

## Purpose

Show the difference between ranked vector search and an agentic evidence investigation:

1. GPT-5 loads a formal Foundry Agent Skill.
2. The skill plans three focused evidence angles.
3. GPT-5 directly selects the DAB SQL MCP `search_evidence` tool three times.
4. Azure SQL generates query embeddings and searches the DiskANN index.
5. The agent compares three sources and returns a visual briefing.
6. A guided follow-up reuses the same evidence and conversation.

## Preflight

From the repository root:

```powershell
.\deploy\11-verify-system.ps1
```

Expected:

- The app reports the active hosted-agent version.
- Initial turn returns exactly three SQL MCP calls and three PMCIDs.
- Confidence begins with `High for mechanistic plausibility`.
- The causal follow-up contains `Strongest`, `Comparison`, and `Limitation`.
- The follow-up performs no unnecessary MCP search.

Start the local presentation window if desired:

```powershell
.\run.ps1
```

The script opens a standalone Edge app window. The deployed App Service URL printed by `deploy/09-deploy-app-service.ps1` is also suitable for the demo.

## Demo Flow

### Beat 1: Establish the question

Open **Agent**. The prefilled question is intentionally natural:

> How might intestinal microbiome disruption influence anxiety and depression?

Say:

> "I am not telling the model how many searches to run. That workflow is owned by the formal Agent Skill."

Select **Send**.

### Beat 2: Show the live agent path

While the request runs, switch to Microsoft Foundry and open the hosted agent **Log stream**.

Point out:

- Skill download and load
- SQL MCP server connection
- Discovery of `get_article_context`, `get_corpus_status`, and `search_evidence`
- Three direct `search_evidence` calls

Say:

> "Foundry is hosting my .NET agent code. GPT-5 plans the research and directly chooses governed SQL MCP tools; my application never gives the model arbitrary SQL access."

### Beat 3: Read the visual briefing

Return to the app. Point to the five completed phases:

1. Planned 3 research questions
2. Searched 3 evidence angles
3. Compared 3 distinct sources
4. Synthesized briefing
5. Ready for follow-up

Show:

- Bottom line
- Three evidence signals
- High confidence for mechanistic plausibility
- Separate qualification of human clinical causality
- Three linked PMC sources

### Beat 4: Demonstrate continuity

Select **Find strongest causal evidence**.

The follow-up should render visually with:

- **Strongest**
- **Comparison**
- **Limitation**
- Confidence
- Suggested follow-up

Say:

> "The agent retained the earlier evidence, so it did not run another search. It compared the existing sources and explained why one is more causal."

### Beat 5: Close on governance

Open `dab/dab-config.json` or run:

```powershell
.\dab\invoke-mcp.ps1 -Endpoint "<SQL_MCP_ENDPOINT>"
```

Say:

> "The SQL MCP boundary exposes exactly three stored procedures: no writes, no arbitrary SQL, and no direct database credentials for the model."

## Recovery

- If the hosted session returns `session_not_ready`, retry the same request once.
- If the app reports the wrong agent version, restart App Service or rerun `deploy/09-deploy-app-service.ps1`.
- If no MCP calls appear, verify the hosted agent environment contains `SQL_MCP_ENDPOINT` and `SKILL_NAMES`.
- If the initial page is stale, open it with a cache-busting query string.

## Reset

Select the reset icon in the Agent workspace. This clears the browser conversation and restores the initial prompt. It does not alter Azure resources or corpus data.
