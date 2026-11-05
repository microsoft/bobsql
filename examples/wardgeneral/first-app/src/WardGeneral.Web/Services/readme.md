# Web UI context services

[PageContext.cs](PageContext.cs) holds per-circuit encounter/unit context and
describes the current view for the assistant dock.

Keep this scoped to the current user's view. It is context for grounding,
not an authorization mechanism or a replacement for database/RLS checks.
See the [web project](../readme.md) and
[Agentic AI](../../../../agentic-ai/README.md) for integration.
