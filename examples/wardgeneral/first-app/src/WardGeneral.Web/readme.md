# WardGeneral.Web

The .NET 10 Blazor host for the [Ward General application](../readme.md).
Start and configure it through the [first-app walkthrough](../../README.md).

- [Program.cs](Program.cs): application startup and service registration.
- [Components](Components/readme.md): root components, pages, and layouts.
- [Options](Options/readme.md): feature flags.
- [Services](Services/readme.md): shared UI context.
- [wwwroot](wwwroot/readme.md): static presentation assets.

Configuration files describe application settings; supply credentials and
private endpoints through the parent's supported configuration mechanisms.
Enable AI surfaces only after their owning area is deployed. The web process
runs locally in the main walkthrough and connects to Azure SQL over the network.
