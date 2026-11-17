using System.Net.Http.Headers;
using System.Text.Json;
using Azure.Core;

namespace CaldovaNetworkScheduling.Services;

public sealed record NetworkDatabaseResource(string Name, string Status, string Objective, string? Pool);
public sealed record NetworkResources(string ResourceGroup, string Server, string Pool, string Location,
    string Tier, string Hardware, string State, double VCores, double MinVCoresPerDatabase,
    double MaxVCoresPerDatabase, IReadOnlyList<NetworkDatabaseResource> Databases, bool IsPlayback = false);

public class NetworkResourceMonitor(HttpClient http, TokenCredential credential, IConfiguration configuration)
{
    internal static (string Subscription, string ResourceGroup, string Server, string Pool) Target(IConfiguration configuration)
    {
        var resourceId = configuration["ServerlessMonitor:ResourceId"]
            ?? throw new InvalidOperationException("The monitored database resource is not configured.");
        var parts = resourceId.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length != 10 || parts[0] != "subscriptions" || !Guid.TryParse(parts[1], out _)
            || parts[2] != "resourceGroups" || parts[4] != "providers" || parts[5] != "Microsoft.Sql"
            || parts[6] != "servers" || parts[8] != "databases" || parts[9] != "caldova-scheduling")
            throw new InvalidOperationException("Network resource inspection requires the Caldova SQL database resource.");
        _ = ServerlessSqlTelemetry.ConnectionSettings(configuration,
            new(resourceId, "", 0, 0), "Caldova.NetworkResources");
        if (!System.Text.RegularExpressions.Regex.IsMatch(parts[3], @"^[a-zA-Z0-9_-]+$")
            || !System.Text.RegularExpressions.Regex.IsMatch(parts[7], @"^[a-zA-Z0-9-]+$"))
            throw new InvalidOperationException("The demo resource group or server name is invalid.");
        return (parts[1], parts[3], parts[7], "caldova-network-pool");
    }

    public virtual async Task<NetworkResources> ReadAsync(CancellationToken token)
    {
        var target = Target(configuration);
        var serverId = $"/subscriptions/{target.Subscription}/resourceGroups/{target.ResourceGroup}/providers/Microsoft.Sql/servers/{target.Server}";
        var poolName = target.Pool;
        var poolId = $"{serverId}/elasticPools/{poolName}";
        using var poolDocument = await GetAsync(poolId, token);
        var pool = poolDocument.RootElement;
        var properties = pool.GetProperty("properties");
        var sku = pool.GetProperty("sku");
        var limits = properties.GetProperty("perDatabaseSettings");
        var databases = new List<NetworkDatabaseResource>();
        foreach (var key in new[] { "caldova", "northbrook", "ridgeview" })
        {
            var name = SqlAppointmentAvailabilityService.GetDatabase(key);
            using var document = await GetAsync($"{serverId}/databases/{name}", token);
            var database = document.RootElement.GetProperty("properties");
            var membership = database.TryGetProperty("elasticPoolId", out var value) ? value.GetString() : null;
            if (!string.IsNullOrEmpty(membership) && !membership.Equals(poolId, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException($"{name} belongs to a different elastic pool.");
            databases.Add(new(name, database.GetProperty("status").GetString()!,
                database.GetProperty("currentServiceObjectiveName").GetString()!,
                string.IsNullOrEmpty(membership) ? null : poolName));
        }
        return new(target.ResourceGroup, target.Server, poolName, pool.GetProperty("location").GetString()!,
            sku.GetProperty("tier").GetString()!, sku.GetProperty("family").GetString()!,
            properties.GetProperty("state").GetString()!, sku.GetProperty("capacity").GetDouble(),
            limits.GetProperty("minCapacity").GetDouble(), limits.GetProperty("maxCapacity").GetDouble(), databases);
    }

    private async Task<JsonDocument> GetAsync(string resourceId, CancellationToken token)
    {
        var access = await credential.GetTokenAsync(new TokenRequestContext(["https://management.azure.com/.default"]), token);
        using var request = new HttpRequestMessage(HttpMethod.Get,
            $"https://management.azure.com{resourceId}?api-version=2023-08-01");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", access.Token);
        using var response = await http.SendAsync(request, token);
        if (!response.IsSuccessStatusCode)
            throw new HttpRequestException($"Azure resource details could not be read (HTTP {(int)response.StatusCode}).",
                null, response.StatusCode);
        var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(token));
        if (!document.RootElement.TryGetProperty("id", out var id)
            || !string.Equals(id.GetString(), resourceId, StringComparison.OrdinalIgnoreCase))
        {
            document.Dispose();
            throw new InvalidOperationException("Azure returned a different resource than requested.");
        }
        return document;
    }
}
