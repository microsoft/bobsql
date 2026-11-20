---
name: provision-azure-sql-db
description: Guide explicit destination selection and approved creation of a free-offer Azure SQL database with verified no-paid-overage protection.
---

# Provision a protected Azure SQL destination

These are adapted instructions for SQL Migration Studio, not a general shell
grant. Upstream and revision are recorded in the application's skill catalog
and NOTICE. The host, not the agent, owns approval and execution.

1. Explain tenant, subscription, region, resource group, logical server, and
   database choices. The operator chooses actual resources in the wizard.
2. Keep Copilot authentication separate from Azure authentication. The selected
   tenant must contain the operator identity used for Entra administration.
3. Never change an existing server's administrator or authentication settings
   without a separately reviewed operation. Never grant the app admin access
   merely because the operator is the migration administrator.
4. Require the exact reviewed configuration and explicit approval before resource
   creation. A chat message is not an approval token.
5. A target must be new or demonstrably empty. The free offer is provisioned
   explicitly with useFreeLimit true and AutoPause at exhaustion. Never replace
   these with a paid tier or paid-overage fallback.
6. Report only readiness returned by inspect_readiness and workflow evidence
   returned by get_migration_status. Ask the operator to use the wizard for
   account selection and approval. Do not invent resources, limits, or progress.
7. Unsupported eligibility, unavailable regions, or unresolved firewall access
   are blockers, not permission to broaden network access or incur charges.

Only the host's fixed, validated operations can provision. No arbitrary shell,
SQL, URL fetching, file reading, credential access, or agent delegation is allowed.
