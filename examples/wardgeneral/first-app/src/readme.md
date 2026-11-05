# Shared Ward General application source

The [first-app walkthrough](../README.md) builds one cumulative .NET 10 solution:

- [WardGeneral.Data](WardGeneral.Data/readme.md): SQL access, models, retry
  policy, and access context.
- [WardGeneral.Web](WardGeneral.Web/readme.md): the Blazor application.
- [WardGeneral.Agent](WardGeneral.Agent/readme.md): the agentic extension.

Run/build through the parent instructions. AI-ready SQL and Agentic AI add
database objects and configuration to this same application; do not copy it
into separate projects for each area. Generated `bin` and `obj` directories
are excluded from the source-documentation inventory.
