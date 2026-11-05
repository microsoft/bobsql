# WardGeneral.Agent

Agent integration for the shared [Ward General application](../readme.md).
[WardGeneralAgent.cs](WardGeneralAgent.cs) implements orchestration;
[AgentOptions.cs](AgentOptions.cs) holds configuration;
the handler and trace helpers support contextual execution and diagnostics.

Read [Agentic AI](../../../agentic-ai/README.md) before enabling this project.
Configure endpoints and identity privately, complete the SQL/DAB prerequisites,
and use the shared application's feature flags rather than creating a second
application.

The runtime [shift-handoff skill](skills/readme.md) is distinct from repository
Copilot skills. Preserve its grounding, scope, and approval requirements.
Use synthetic data and avoid logging credentials or private chart content.
