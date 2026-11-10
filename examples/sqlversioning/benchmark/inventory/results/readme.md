# Captured inventory benchmark results

Timestamped JSON and text output from previous
[inventory benchmark](../readme.md) runs.

Use these captures to understand the output structure and compare observations
from their recorded configurations. They are not measurements of the current
machine and do not establish expected throughput for another environment.

Generate new evidence with the parent runner. Keep target/configuration and
timing metadata with the results, and inspect outputs for private endpoint or
authentication information before committing them.

The [slide summary](inventory-results.html) is the source for the browser
benchmark replay. Its totals and two query-specific latency tables describe
a different workload mix from the timestamped JSON runs. It reports 30 seconds
and 200K products, but not exact runtime, capture timestamp, the full worker
mix, or an order-fulfillment breakdown. Do not mix those runs or infer missing
measurements to make them match.
