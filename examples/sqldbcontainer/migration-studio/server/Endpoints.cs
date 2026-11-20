using System.Text.Json;
using Microsoft.AspNetCore.Antiforgery;
using MigrationStudio.Services;

namespace MigrationStudio;

public static class Endpoints
{
    public static void MapStudio(this WebApplication app)
    {
        app.MapGet("/health", () => TypedResults.Ok(new { app = "sql-migration-studio", status = "ready", cloudMutation = false }))
            .WithSummary("Check this local host, without connecting to SQL or invoking a model.");

        app.MapGet("/api/session", (HttpContext context, IAntiforgery antiforgery) =>
        {
            context.Session.SetString("operator", "local");
            var tokens = antiforgery.GetAndStoreTokens(context);
            return TypedResults.Ok(new { csrfToken = tokens.RequestToken });
        }).WithSummary("Establish the same-origin local operator session and request-verification token.");

        app.MapGet("/api/status", async (IStudioStatusService status, CancellationToken token) =>
            TypedResults.Ok(await status.GetAsync(token)))
            .WithSummary("Measure dependency readiness, skill attribution, and Copilot authentication; no inference.");

        app.MapGet("/api/discovery/containers", async (IOperationRunner runner, IEventStream events, CancellationToken token) =>
            TypedResults.Ok(await Discover(runner, events, "Containers", new { }, token)))
            .WithSummary("Discover local running SQL containers without exposing environment credentials.");

        app.MapPost("/api/discovery/databases", async (DiscoverDatabasesRequest request, IOperationRunner runner, IEventStream events, CancellationToken token) =>
            TypedResults.Ok(await Discover(runner, events, "Databases", request, token)))
            .WithSummary("Read database metadata in the explicitly selected container.");

        app.MapGet("/api/azure/tenants", async (IOperationRunner runner, IEventStream events, CancellationToken token) =>
            TypedResults.Ok(await Discover(runner, events, "Tenants", new { }, token)))
            .WithSummary("List tenants available to the existing Azure CLI sign-in.");
        app.MapGet("/api/azure/subscriptions", async (string tenantId, IOperationRunner runner, IEventStream events, CancellationToken token) =>
            TypedResults.Ok(await Discover(runner, events, "Subscriptions", new { tenantId = Identifier(tenantId) }, token)))
            .WithSummary("List signed-in subscriptions in the selected tenant.");
        app.MapGet("/api/azure/locations", async (string tenantId, string subscriptionId, IOperationRunner runner, IEventStream events, CancellationToken token) =>
            TypedResults.Ok(await Discover(runner, events, "Locations", new { tenantId = Identifier(tenantId), subscriptionId = Identifier(subscriptionId) }, token)))
            .WithSummary("Discover regions for the chosen subscription.");
        app.MapGet("/api/azure/groups", async (string tenantId, string subscriptionId, IOperationRunner runner, IEventStream events, CancellationToken token) =>
            TypedResults.Ok(await Discover(runner, events, "Groups", new { tenantId = Identifier(tenantId), subscriptionId = Identifier(subscriptionId) }, token)))
            .WithSummary("List existing resource groups; no group is created.");
        app.MapGet("/api/azure/servers", async (string tenantId, string subscriptionId, string resourceGroup, IOperationRunner runner, IEventStream events, CancellationToken token) =>
            TypedResults.Ok(await Discover(runner, events, "Servers", new { tenantId = Identifier(tenantId), subscriptionId = Identifier(subscriptionId), resourceGroup }, token)))
            .WithSummary("List existing logical servers in the selected group.");
        app.MapGet("/api/azure/identity", async (string tenantId, string subscriptionId, IOperationRunner runner, IEventStream events, CancellationToken token) =>
            TypedResults.Ok(await Discover(runner, events, "Identity", new { tenantId = Identifier(tenantId), subscriptionId = Identifier(subscriptionId) }, token)))
            .WithSummary("Resolve the current Azure user in the selected tenant, never infer from Copilot sign-in.");

        app.MapPost("/api/plans", async (MigrationConfiguration configuration, IMigrationWorkflow workflow, CancellationToken token) =>
        {
            var plan = await workflow.CreateAsync(configuration, token);
            return TypedResults.Created($"/api/plans/{plan.Id}", plan);
        }).WithSummary("Create an immutable review plan; no Azure changes or export.");
        app.MapGet("/api/plans/{id}", (string id, IMigrationWorkflow workflow) => TypedResults.Ok(workflow.GetPlan(id)))
            .WithSummary("Read an immutable review plan.");
        app.MapPost("/api/plans/{id}/run", async (string id, StartMigrationRequest request, IMigrationWorkflow workflow, CancellationToken token) =>
        {
            var run = await workflow.StartAsync(id, request, token);
            return TypedResults.Accepted($"/api/runs/{run.Id}", run);
        }).WithSummary("Approve and queue this exact migration; the independent source consistency gate still applies.");
        app.MapGet("/api/runs/{id}", (string id, IMigrationWorkflow workflow) => TypedResults.Ok(workflow.GetRun(id)))
            .WithSummary("Read durable execution and validation evidence.");
        app.MapPost("/api/runs/{id}/cancel", async (string id, IMigrationWorkflow workflow, CancellationToken token) =>
            TypedResults.Accepted($"/api/runs/{id}", await workflow.CancelAsync(id, token)))
            .WithSummary("Request cancellation of the specific migration process tree; retain partial resources.");
        app.MapPost("/api/copilot/message", async (CopilotMessageRequest request, ICopilotGuide copilot, CancellationToken token) =>
        {
            await copilot.QueueAsync(request, token);
            return TypedResults.Accepted("/api/events");
        }).WithSummary("Send a bounded operator question to the real Copilot agent; consumes Copilot usage.");

        app.MapGet("/api/copilot/status", async (ICopilotGuide copilot, CancellationToken token) =>
            TypedResults.Ok(await copilot.StatusAsync(token)))
            .WithSummary("Check SDK authentication and models without migration preflight or inference.");
        app.MapGet("/api/copilot/signin", async (HttpContext context, ICopilotGuide copilot, CancellationToken token) =>
            TypedResults.Ok(await copilot.SignInStateAsync(context.Session.Id, token)))
            .WithSummary("Read only this local browser session's device authorization state.");
        app.MapPost("/api/copilot/signin", async (HttpContext context, ICopilotGuide copilot, CancellationToken token) =>
            TypedResults.Ok(await copilot.BeginSignInAsync(context.Session.Id, token)))
            .WithSummary("Explicitly begin GitHub device authorization through the SDK; no inference.");
        app.MapPost("/api/copilot/signin/{id}/cancel", async (string id, HttpContext context, ICopilotGuide copilot, CancellationToken token) =>
            TypedResults.Ok(await copilot.CancelSignInAsync(context.Session.Id, id, token)))
            .WithSummary("Cancel this browser's pending authorization; does not sign out other applications.");

        app.MapGet("/api/events", async (HttpContext context, IEventStream events, CancellationToken token) =>
        {
            context.Response.ContentType = "text/event-stream";
            context.Response.Headers.CacheControl = "no-cache, no-store";
            context.Response.Headers["X-Accel-Buffering"] = "no";
            var after = long.TryParse(context.Request.Headers["Last-Event-ID"], out var last) ? last : 0;
            await context.Response.WriteAsync(": connected\n\n", token);
            await context.Response.Body.FlushAsync(token);
            await foreach (var entry in events.Subscribe(after, token))
            {
                await context.Response.WriteAsync($"id: {entry.Id}\nevent: {entry.Name}\ndata: {entry.Json}\n\n", token);
                await context.Response.Body.FlushAsync(token);
            }
        }).WithSummary("Stream real stage updates, skill/tool events, and Copilot response deltas.");
    }

    private static string Identifier(string value) => Guid.TryParse(value, out var id)
        ? id.ToString() : throw new StudioException(400, "A valid tenant or subscription identifier is required.");

    private static async Task<JsonElement> Discover(IOperationRunner runner, IEventStream events, string operation, object input, CancellationToken token)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
        timeout.CancelAfter(TimeSpan.FromSeconds(90));
        var subject = operation switch
        {
            "Containers" => "Source / Discover containers",
            "Databases" => "Source / List databases",
            "Tenants" => "Azure destination / List tenants",
            "Subscriptions" => "Azure destination / List subscriptions",
            "Locations" => "Azure destination / List regions",
            "Groups" => "Azure destination / List resource groups",
            "Servers" => "Azure destination / List logical servers",
            "Identity" => "Azure destination / Confirm Entra identity",
            _ => throw new InvalidOperationException("Unknown discovery operation.")
        };
        events.Publish("wizard", "started", "Wizard requested a read-only backend operation. No Copilot inference or skill read was requested.", subject: subject);
        try
        {
            var result = await runner.RunAsync(operation, input, null, timeout.Token);
            events.Publish("wizard", "completed", "Backend operation returned successfully. No resources were changed; result contents are not included in this trace.", subject: subject);
            return result;
        }
        catch (OperationCanceledException)
        {
            events.Publish("wizard", "cancelled", "Discovery was cancelled or timed out. No completion was assumed.", subject: subject);
            throw;
        }
        catch
        {
            events.Publish("wizard", "failed", "Backend operation failed. See the wizard for the safe error and retry action.", subject: subject);
            throw;
        }
    }
}
