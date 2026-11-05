# tempdb troubleshooting

Evidence-first guides for investigating tempdb growth, space pressure, and
performance incidents. Confirm the database platform before selecting diagnostics.

| Scenario | Guide |
| --- | --- |
| A normally successful warehouse upsert runs for 24 hours, tempdb grows, and the pipeline times out | [Pipeline upsert timeout](pipeline-upsert-timeout/readme.md) |

Begin with evidence collection, not shrinking files or restarting the database.
Use read-only diagnostics appropriate to the product/version, and keep production
data, query captures, and credentials out of this public repository.
