# Inside the Ward General agent payload

This companion shows how one Ward General shift-handoff conversation moves
between the clinician, Microsoft Agent Framework (MAF), the Foundry model, the
local Agent Skills provider, the DAB MCP server, and Azure SQL.

The JSON below is a **normalized teaching representation**, not a captured HTTP
trace. MAF and the Azure OpenAI SDK own the provider-specific serialization, and
field names can vary between API versions. The roles, tool boundaries, and
conversation sequence match the Agentic AI implementation.

The Agent Skills details were also verified against raw outbound request bodies
from the pinned MAF 1.17.0 and Azure OpenAI 2.9.0-beta.1 packages. The capture
contained request JSON only — no URL, headers, credential, or response body.

All patient data in this example is synthetic.

## Three payload concepts

A chat-completions-style model request has two relevant collections:

- `messages` contains the instructions and conversation history: system, user,
  assistant, and tool-result messages.
- `tools` is a top-level array of function definitions the model may request.
  There is no separate "tools message."

A tool definition tells the model the tool's name, purpose, and parameter schema.
It does not execute the tool. The model can return a structured tool request;
MAF decides how that request is handled.

Agentic AI has two kinds of tools:

| Kind | Examples | Executed by |
| --- | --- | --- |
| Local Agent Skills tools | `load_skill`, `read_skill_resource`, `run_skill_script` | MAF's `AgentSkillsProvider` |
| Imported MCP tools | `get_handoff_candidates`, `get_patient_chart`, `save_handoff` | MAF's MCP client through DAB |

`load_skill` never reaches DAB or SQL. Conversely, the DAB tools do not read the
skill directory.

## Before the first model request

At application startup, Ward General performs work that is not part of the
model conversation:

1. The application connects an MCP client to DAB.
2. The MCP client discovers DAB's seven published tools.
3. Ward General wraps every tool for tracing and wraps `save_handoff` for
   approval.
4. The application assigns those tools to `ChatOptions.Tools`.
5. The application registers an `AgentSkillsProvider` through
   `AIContextProviders`.

The skills provider advertises the `shift-handoff` skill's name and description
in system context and exposes the local `load_skill` function. It does not put
the complete `SKILL.md` body into context yet.

## Turn 1: ask which patients need a handoff

The clinician asks:

> Which patients should I prepare for a shift handoff?

### Model request 1: base instructions and advertised capabilities

The first request is conceptually:

```json
{
  "messages": [
    {
      "role": "system",
      "content": [
        "You are the Ward General clinical assistant.",
        "Answer strictly from Ward General tools.",
        "Never invent patients, encounters, values, or citations.",
        "Ground answers in tool results.",
        "Clinical suggestions are advisory.",
        "For a shift-handoff question, request the shift-handoff skill before requesting a data tool.",
        "Available skill: shift-handoff — Find the patients who most need a shift handoff, and prepare a structured SBAR handoff for one named patient."
      ]
    },
    {
      "role": "user",
      "content": "Which patients should I prepare for a shift handoff?"
    }
  ],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "load_skill",
        "description": "Loads the full content of a specific skill",
        "parameters": {
          "type": "object",
          "properties": {
            "skillName": { "type": "string" }
          },
          "required": ["skillName"],
          "additionalProperties": false
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "get_handoff_candidates",
        "description": "List active patients with shift-change evidence. Returns evidence, not a ranking.",
        "parameters": {
          "type": "object",
          "properties": {
            "SinceHours": { "type": "integer", "default": 12 },
            "Top": { "type": "integer", "default": 10 }
          }
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "get_patient_chart",
        "description": "Retrieve the complete current chart for one encounter.",
        "parameters": {
          "type": "object",
          "properties": {
            "EncounterId": { "type": "integer" }
          },
          "required": ["EncounterId"]
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "save_handoff",
        "description": "Save one prepared shift handoff. Requires explicit human approval before execution.",
        "parameters": {
          "type": "object",
          "properties": {
            "EncounterId": { "type": "integer" },
            "Situation": { "type": "string" },
            "Background": { "type": "string" },
            "Assessment": { "type": "string" },
            "Recommendation": { "type": "string" },
            "RequestKey": { "type": "string" }
          },
          "required": [
            "EncounterId",
            "Situation",
            "Background",
            "Assessment",
            "Recommendation",
            "RequestKey"
          ]
        }
      }
    }
  ]
}
```

The real request includes the other DAB tools. The provider also advertises
`read_skill_resource` and `run_skill_script`, even though this Ward General skill
has no resources or scripts. Unrelated tools are omitted here because this
walkthrough follows only the handoff conversation. The captured argument name
for the pinned packages is `skillName`.

The complete handoff procedure is not in the system message. Only its short
advertisement is present.

### Model response 1: request the skill

The model recognizes the handoff intent from the user prompt, base instructions,
and advertised skill description. It returns a structured request instead of a
clinician-facing answer:

```json
{
  "role": "assistant",
  "tool_calls": [
    {
      "id": "call_load_skill_001",
      "type": "function",
      "function": {
        "name": "load_skill",
        "arguments": {
          "skillName": "shift-handoff"
        }
      }
    }
  ]
}
```

The model has not read a file or executed code. It has requested an operation.

### MAF executes the local skill tool

MAF recognizes `load_skill` as a function supplied by `AgentSkillsProvider`. The
provider reads `skills/shift-handoff/SKILL.md` locally. This operation does not
use the MCP client.

The captured second request contained this shape:

```json
{
  "role": "tool",
  "tool_call_id": "call_load_skill_001",
  "content": "\"---\\r\\nname: shift-handoff\\r\\n...the complete SKILL.md body...\\r\\n\\n<available_resources />\\n\\n<available_scripts />\""
}
```

`content` is a string required by the chat-completions tool-message protocol.
Inside that string, MAF JSON-serializes the skill result, which accounts for the
visible outer quote and escaped line endings. Decoding `content` once produced
the complete 5,667-character `SKILL.md` as an exact prefix, followed by:

```xml
<available_resources />

<available_scripts />
```

The markers report that this skill has no supplementary resources or scripts.
The file itself contains the candidate-ranking, SBAR, approval, request-key, and
save-result instructions. Progressive disclosure operates at the skill level,
not at each heading inside `SKILL.md`.

### Model request 2: same conversation, now with the skill

MAF invokes the model again. The accumulated conversation is now conceptually:

```json
{
  "messages": [
    {
      "role": "system",
      "content": "Ward General base instructions plus the advertised skill list"
    },
    {
      "role": "user",
      "content": "Which patients should I prepare for a shift handoff?"
    },
    {
      "role": "assistant",
      "tool_calls": [
        {
          "id": "call_load_skill_001",
          "function": {
            "name": "load_skill",
            "arguments": {
              "skillName": "shift-handoff"
            }
          }
        }
      ]
    },
    {
      "role": "tool",
      "tool_call_id": "call_load_skill_001",
      "content": "JSON-encoded shift-handoff skill body plus empty resource and script markers"
    }
  ],
  "tools": [
    "load_skill",
    "get_handoff_candidates",
    "get_patient_chart",
    "save_handoff",
    "other registered tools omitted"
  ]
}
```

The abbreviated strings in `tools` stand for the complete function schemas from
the first request. SDKs normally resend the available definitions on subsequent
model requests.

### Model response 2: request candidate evidence

Following the loaded skill, the model returns a separate structured request:

```json
{
  "role": "assistant",
  "tool_calls": [
    {
      "id": "call_candidates_002",
      "type": "function",
      "function": {
        "name": "get_handoff_candidates",
        "arguments": {
          "SinceHours": 12,
          "Top": 10
        }
      }
    }
  ]
}
```

This is an imported MCP tool, so MAF sends it through the MCP client. The MCP
exchange is separate from the model payload and is conceptually:

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "get_handoff_candidates",
    "arguments": {
      "SinceHours": 12,
      "Top": 10
    }
  }
}
```

DAB maps `get_handoff_candidates` to
`clinical.GetHandoffCandidates`, executes the procedure against the
`wardgeneral` primary, and returns the rows through MCP.

### Candidate result returns to the model

MAF associates DAB's result with the model's request:

```json
{
  "role": "tool",
  "tool_call_id": "call_candidates_002",
  "content": [
    {
      "EncounterId": 200341,
      "PatientName": "Synthetic patient",
      "LatestSpO2": 91,
      "EarlierSpO2": 96,
      "PendingLabCount": 1,
      "OldestPendingSince": "2026-08-28T02:15:00Z"
    }
  ]
}
```

The exact result has more fields. The values above illustrate the shape and are
not a captured execution result.

MAF invokes the model again with that tool result in the conversation. The model
then produces the clinician-facing roster, ranks at most three patients, quotes
the evidence behind each choice, and stops.

```json
{
  "role": "assistant",
  "content": "1. Synthetic patient — encounter 200341. SpO2 is 91%, down from 96% earlier in the shift..."
}
```

## Turn 2: prepare one selected handoff

The application reuses the same MAF `AgentSession`. The first user prompt, the
skill load, the candidate result, and the assistant's roster remain in the
conversation history.

The clinician selects one encounter from that roster:

```json
{
  "role": "user",
  "content": "Prepare a shift handoff for encounter 200341."
}
```

The complete skill is already in this session. The model follows its second
stage and requests the current chart:

```json
{
  "role": "assistant",
  "tool_calls": [
    {
      "id": "call_chart_003",
      "type": "function",
      "function": {
        "name": "get_patient_chart",
        "arguments": {
          "EncounterId": 200341
        }
      }
    }
  ]
}
```

MAF sends this request through MCP. DAB maps `get_patient_chart` to
`clinical.GetPatientChart`, and the current chart returns as a tool-result
message. The model uses only that chart to compose the four SBAR sections.

### The model proposes the write

The skill tells the model to show the four sections and then request
`save_handoff` with those exact values and one newly generated request key. A
normalized model response is:

```json
{
  "role": "assistant",
  "content": "Situation: ...\n\nBackground: ...\n\nAssessment: ...\n\nRecommendation: ...",
  "tool_calls": [
    {
      "id": "call_save_004",
      "type": "function",
      "function": {
        "name": "save_handoff",
        "arguments": {
          "EncounterId": 200341,
          "Situation": "...",
          "Background": "...",
          "Assessment": "...",
          "Recommendation": "...",
          "RequestKey": "00000000-0000-0000-0000-000000000000"
        }
      }
    }
  ]
}
```

The GUID is illustrative. A real run generates a new key for the handoff and
reuses that same key if the proposed save is retried.

Ward General wrapped `save_handoff` with `ApprovalRequiredAIFunction`. MAF
therefore intercepts this structured request before the MCP client invokes DAB.
At this point:

- DAB has not received `save_handoff`.
- `clinical.SaveShiftHandoff` has not executed.
- No recommendation row has been written.
- The application receives a `ToolApprovalRequestContent` containing the held
  tool request and displays it to the clinician.

## Turn 3: approve or decline the held call

The approval button is application UI, not ordinary conversational consent. The
application constructs a `ToolApprovalResponseContent` tied to the pending
request ID and the exact held tool call.

Conceptually, approval looks like:

```json
{
  "approval_response": {
    "request_id": "approval_for_call_save_004",
    "approved": true,
    "tool_call": {
      "id": "call_save_004",
      "name": "save_handoff",
      "arguments": {
        "EncounterId": 200341,
        "Situation": "...",
        "Background": "...",
        "Assessment": "...",
        "Recommendation": "...",
        "RequestKey": "00000000-0000-0000-0000-000000000000"
      }
    }
  }
}
```

This is a normalized MAF-level representation, not an Azure OpenAI wire message.
Ward General passes the actual `ToolApprovalResponseContent` back into the same
agent session.

Approval resumes the held call without asking the model to choose the tool or
reconstruct its arguments again. MAF's MCP client now sends:

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "tools/call",
  "params": {
    "name": "save_handoff",
    "arguments": {
      "EncounterId": 200341,
      "Situation": "...",
      "Background": "...",
      "Assessment": "...",
      "Recommendation": "...",
      "RequestKey": "00000000-0000-0000-0000-000000000000"
    }
  }
}
```

DAB maps `save_handoff` to `clinical.SaveShiftHandoff`. SQL returns the
`RecommendationId` and whether this request key created a new row. MAF appends
that tool result and invokes the model so it can report the completed outcome in
the past tense.

If the clinician declines, MAF does not send the MCP `tools/call`. DAB and SQL
never see the write request, and no row is created.

## The complete exchange

```text
MAF system context
  Base instructions
  Short shift-handoff skill advertisement
  Tool definitions

Clinician
  Which patients should I prepare for a shift handoff?

Model
  Structured request: load_skill

MAF AgentSkillsProvider
  Complete shift-handoff SKILL.md body

Model
  Structured request: get_handoff_candidates

MAF MCP client → DAB → SQL
  get_handoff_candidates → clinical.GetHandoffCandidates

SQL → DAB → MAF → model
  Candidate evidence

Model → clinician
  Ranked roster with encounter IDs and cited values

Clinician
  Prepare a shift handoff for encounter 200341

Model
  Structured request: get_patient_chart

MAF MCP client → DAB → SQL
  get_patient_chart → clinical.GetPatientChart

SQL → DAB → MAF → model
  Current chart

Model
  Four SBAR sections
  Structured request: save_handoff

MAF approval wrapper
  Hold the exact request before MCP

Clinician
  Approve or decline

Approve
  MAF MCP client → DAB → SQL
  save_handoff → clinical.SaveShiftHandoff

Decline
  Stop before DAB; write zero rows
```

## What this document does not claim

This document does not claim to reproduce raw HTTPS frames emitted by a specific
Azure OpenAI API version. To capture those frames, the application would need
explicit SDK-level HTTP diagnostics with careful redaction. The Agentic AI trace
instead records the application-level tool names, arguments, elapsed time, and
result size. That is sufficient to prove which tools ran without logging an
entire patient chart or duplicating model-provider internals.

## Implementation references

- Agent construction and session handling:
  [`WardGeneralAgent.cs`](../first-app/src/WardGeneral.Agent/WardGeneralAgent.cs)
- Base instructions:
  [`AgentOptions.cs`](../first-app/src/WardGeneral.Agent/AgentOptions.cs)
- Complete runtime skill:
  [`skills/shift-handoff/SKILL.md`](../first-app/src/WardGeneral.Agent/skills/shift-handoff/SKILL.md)
- DAB tool descriptions and procedure mappings:
  [`dab-config.primary.json`](dab-config.primary.json)
- Approval-gated SQL contract:
  [`11-handoff-contract.sql`](11-handoff-contract.sql)
- Candidate query:
  [`12-handoff-candidates.sql`](12-handoff-candidates.sql)

Microsoft Learn verification: [Agent Skills](https://learn.microsoft.com/agent-framework/agents/skills), accessed 2026-08-28.
