# Caldova Research stage script

**Target length:** 1:50 to 2:00
**Optional named-replica extension:** 20 seconds
**Thesis:** Start small. Grow big. Keep the application contract steady.

## Preflight

- Open the app and confirm `3K`, `1M`, and `Named Replica` report `Live ready`.
- Run the stage question once on `3K` and `1M` so both plans are warm.
- Confirm the app opens on `1M`, then leave `3K`, `Hybrid`, and the Evidence tab selected.
- Speak only latency numbers that appear in a retained report.

## Live script

**0:00 | SQL query tab visible**

"I want to show you how Azure SQL Hyperscale lets you start small and scale as needed, and
how that applies to vector searching as well. This is a biomedical evidence explorer built
on Azure SQL Hyperscale. Every article is chunked into passages and embeddings, with a
vector index over it all. Let's see how this one search stays steady as the app grows."

**0:22 | Evidence tab, run the stage question**

"Let's ask it a detailed question about periodontal inflammation, blood pressure, and
cardiovascular risk. Let's also filter to peer-reviewed sources only.

This isn't just a keyword match. The meaning is what gets searched, and every answer links
back to its article."

**0:42 | Expand a result, then show the SQL query**

"Each result includes the surrounding passages, so the quote reads in context.

This is hybrid: vector search finds meaning with filters applied inside that search,
keyword search finds exact strings such as gene names or drug codes, and then we merge the
rankings with reciprocal rank fusion. The timing shown is measured inside the engine."

**1:08 | Return to Evidence, keep 3K selected**

"This 3K pilot is Hyperscale serverless. It autoscales between the minimum and maximum
vCores I set, and it auto-pauses after one hour of inactivity. When the app isn't being
used, I'm not getting billed for compute.

Now fast forward. The application grows, but its contract does not change. I point the
same app at one million indexed passages and run the same search. The application code,
the query, and the result contract are identical.

Because this search is read only, I can go one step further with a Hyperscale named
replica. It uses the same page servers and the same vector index as the primary, so there
is no data copy and no second index to build. I pick the compute size I need, and I can
have up to thirty of them. I call it read scale on the fly.

So now you've seen how Hyperscale grows with the database, vector search grows with the
data, and named replicas add read capacity when demand grows too."
