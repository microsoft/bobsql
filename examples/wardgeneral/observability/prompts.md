# Observability Skill Prompts

Use these prompts in VS Code Chat from the repository workspace. Each prompt is
worded to route to one of the three Observability skills and preserve that workflow's
safety boundary. Activity Log is an inline callback to Getting Started, not a separate workflow
7 skill.

## Performance

Skill: `observe-hyperscale-performance`

```text
Run the Observability performance demo for wardgeneral.
```

## Availability

Skill: `observe-hyperscale-availability`

```text
Run the Observability availability investigation for wardgeneral. Establish
Resource Health and relevant Service Health evidence using the database's
dynamically derived Azure region, run the read-only SQL replica checks with the
new sqlcmd command, summarize the authoritative baseline, and then give me the
separate Microsoft Copilot in Azure prompt to try myself. Do not initiate
failover or change replica configuration.
```

## Engine events

Skill: `observe-hyperscale-engine-events`

```text
Run the Observability engine events demo for wardgeneral.
```
