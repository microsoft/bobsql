# WardGeneral.Data

Shared raw ADO.NET data-access project for the
[Ward General application](../readme.md).

| Source | Responsibility |
| --- | --- |
| [WardGeneralConnectionFactory.cs](WardGeneralConnectionFactory.cs) | SQL connection construction |
| [ChartRepository.cs](ChartRepository.cs) | Chart data retrieval |
| [ResearchRepository.cs](ResearchRepository.cs) | Research data access |
| [RetryPolicy.cs](RetryPolicy.cs) | Shared retry behavior |
| [AccessContext.cs](AccessContext.cs) and [RlsOptions.cs](RlsOptions.cs) | Access/RLS context |
| [Models](Models/readme.md) | Chart data contracts |

Use the [first-app setup](../../README.md) for configuration and the
[security area](../../../security/README.md) for RLS behavior. Preserve
passwordless authentication, parameterized access, and replica-routing
semantics when changing this project. Build it through the parent solution.
