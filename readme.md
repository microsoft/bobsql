# BobSQL

SQL Server and Azure SQL examples, book companion scripts, and hands-on
troubleshooting guides.

## Start here

| Collection | Starting point |
| --- | --- |
| Examples | [Demo catalog](examples/readme.md) |
| Book companion material | [Chapter scripts](books/) |
| Troubleshooting | [tempdb diagnostics](troubleshoot/tempdb/readme.md) |

Read the selected collection's README for prerequisites, execution order, and
cleanup. There is no shared build or deployment command. Use disposable labs for
demos, and obtain approval for billable or disruptive operations.

## New Hyperscale examples

Four standalone Caldova examples are available in the [demo catalog](examples/readme.md):

- [Evidence Agent](examples/caldovaevidenceagent/README.md): native embeddings,
  DiskANN vector search, governed SQL MCP tools, and a Microsoft Foundry hosted agent.
- [Research](examples/caldovaresearch/README.md): serverless evidence search,
  a one-million-row vector-search target, and named-replica read scale-out.
- [Hands-Free Indexing](examples/handsfreeindexing/README.md): automatic index
  creation and Automatic Index Compaction with live measurements.
- [Start and Grow Hyperscale](examples/startandgrowhyperscale/README.md):
  serverless scheduling, elastic pools, and native cross-database queries.

Read each example's prerequisites and runbook before deploying billable resources.
See [corpus attribution](examples/THIRD-PARTY-NOTICES.md) for the evidence-search datasets.

## New Azure SQL Database container example

- [Azure SQL Database container](examples/sqldbcontainer/README.md): run the
  public preview Azure SQL Database engine locally with a Customer Service Desk
  app demonstrating JSON, dynamic data masking, and vector search, plus a
  separate approval-gated SQL Migration Studio.

Read the example's README for prerequisites, image license terms, and cleanup.

## Copilot skills

Open this repository in VS Code to use the
[workspace skills](.github/skills/) for demos and troubleshooting. Ask for a
scenario or invoke its skill from the chat slash-command menu.

## Contributing and security

Include a local README with prerequisites and cleanup when adding a demo, and
update its catalog entry and skill.

Follow [Secret scanning](SECRET-SCANNING.md) for contributor checks and safe
credential handling. See [Security policy](SECURITY.md) to report vulnerabilities.

## License

This repository is licensed under the [MIT License](LICENSE).
