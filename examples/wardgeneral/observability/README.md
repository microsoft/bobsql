# Observability — Observability, Monitoring, and Troubleshooting

Observability packages three bounded example surfaces with matching skills:
performance, availability, and engine events. Storage administration is not a
separate topic.
Activity Log was already demonstrated in Getting Started and appears only as an
inline callback here. Other queries, portal views, plans, and counters appear
inline in the area. Security owns SQL auditing and Defender for SQL.

| Folder | Question | Status |
| --- | --- | --- |
| [`perf/`](perf/) | What caused the visible CPU spike, and how far did the reads travel? | Built and live-validated |
| [`availability/`](availability/) | What is the current Hyperscale replica and service-health state, and can Microsoft Copilot in Azure summarize the same evidence? | Built and live-validated |
| [`engineevents/`](engineevents/) | How can retained errors, current engine events, and connection history be inspected? | Log Analytics lifecycle built; database-scoped health session and `master` connection-history queries live-validated |

Use the canonical VS Code Chat invocations in [`prompts.md`](prompts.md).

Start with the README inside the folder for the investigation being performed.
The examples diagnose and preserve evidence. They do not tune queries, scale
compute, create replicas, trigger failovers, configure auditing, or change
security policy; later areas own those actions.

The availability walkthrough establishes the result first with Azure Resource
Health and repeatable SQL queries for replica role, synchronization, endpoint,
and topology. It states that the DMVs do not expose direct priming status. It
then asks Microsoft Copilot in Azure to
summarize Resource Health, relevant Service Health events, replica
synchronization, and dropped connections, with evidence sources and timestamps.
The reader compares that response with the portal and SQL results. Copilot is
an optional assistant, not the source of record; skip that step when preview
access is unavailable or its output cannot be independently verified.

> **New here?** Read the [repository README](../../README.md) first. The examples
> assume the Getting Started `wardgeneral` deployment and synthetic dataset already
> exist.

**All data is synthetic. There is no real patient data (PHI) here.**
