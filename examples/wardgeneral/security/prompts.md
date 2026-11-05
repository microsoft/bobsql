# Security Skill Prompts

Use these prompts in VS Code Chat from the repository workspace. The named
skill owns each detailed workflow and its safety rules, so the reader prompts
stay short.

## Run the RLS App Demo

Use this prompt for first runs and repeat rehearsals. The skill inspects the
current state automatically, installs RLS only when absent, and otherwise
reuses the installed policy and starts DAB and Ward General in visible
terminals. It resets only for an explicit clean-state request or proven drift.
Areas 4–6 remain.

```text
Run the Security RLS app demo.
```

## Audit Ward General Activity

The separate `audit-wardgeneral` skill owns this optional two-turn
investigation, including explicit approval before billable setup and guarded
teardown. Start the bounded capture with:

```text
Start the Ward General audit.
```

The skill stops when the auditing policy and its Log Analytics route are
verified. It does not start the application. At that point, run Ward General
through the area workflow, open the unit board and one patient chart, and
then continue with:

```text
I opened a patient chart. Find my audit activity.
```

To verify how bound `SESSION_CONTEXT` values appear in auditing without
starting Ward General, use the prompt below. The skill first follows the same
approved auditing setup, then runs the finite `wardgeneral-audit-probe`, queries
its exact UTC interval in detailed mode, and compares the raw statement and
additional-information fields with the probe's unique sentinel values.

```text
Test session-context auditing without running the app.
```

When the investigation is complete, remove only the resources owned by this
example with:

```text
Tear down the Security audit.
```
