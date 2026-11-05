# JSON index tuning demo

A bounded JSON-index comparison on the existing Ward General database.
Read the [tuning overview](../README.md) for prerequisites and evidence.

Run [run-demo.ps1](run-demo.ps1) without `-Execute` to preview the target.
After reviewing it and approving changes, use the parent's documented
`-Execute` flow. The runner coordinates:

1. [01-setup.sql](01-setup.sql)
2. [02-before.sql](02-before.sql)
3. [03-create-index.sql](03-create-index.sql)
4. [04-after.sql](04-after.sql)
5. [05-cleanup.sql](05-cleanup.sql)

Compare plans and runtime evidence rather than assuming a speedup. Cleanup
belongs to the demo-owned index/table scope documented by the parent.
