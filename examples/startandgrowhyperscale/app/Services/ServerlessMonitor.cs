using System.Net.Http.Headers;
using System.Text.Json;
using Azure.Core;

namespace CaldovaNetworkScheduling.Services;

public sealed record ServerlessConfiguration(string ResourceId, string Status, double MinVCores, double MaxVCores);
public sealed record ServerlessMetric(DateTimeOffset At, double? CpuPercent, double? BilledVCoreSeconds, double? MemoryPercent = null)
{
    public double? UsedVCores(double maximum) => CpuPercent * maximum / 100;
    public double? BilledVCores => BilledVCoreSeconds / 60;
}

public sealed class ServerlessMonitor(HttpClient http, TokenCredential credential, IConfiguration configuration)
{
    public static string ResolveConfiguredResourceId(IConfiguration configuration, bool offline = false)
    {
        var resourceId = configuration["ServerlessMonitor:ResourceId"]
            ?? throw new InvalidOperationException("ServerlessMonitor:ResourceId is required.");
        if (!resourceId.Contains("{subscription-id}", StringComparison.Ordinal)) return resourceId;
        if (offline) return resourceId.Replace("{subscription-id}", Guid.Empty.ToString("D"), StringComparison.Ordinal);
        var configured = configuration["Azure:SubscriptionId"] ?? configuration["AZURE_SUBSCRIPTION_ID"];
        if (!Guid.TryParse(configured, out var subscription) || subscription == Guid.Empty)
            throw new InvalidOperationException("Configure Azure:SubscriptionId in local .NET user-secrets or AZURE_SUBSCRIPTION_ID in the environment. Do not publish the real identifier.");
        return resourceId.Replace("{subscription-id}", subscription.ToString("D"), StringComparison.Ordinal);
    }

    public string ResourceId => configuration["ServerlessMonitor:ResourceId"]
        ?? throw new InvalidOperationException("ServerlessMonitor:ResourceId is required.");

    public string PortalUrl => $"https://portal.azure.com/#resource{ResourceId}/overview";

    public async Task<ServerlessConfiguration> ReadConfigurationAsync(CancellationToken cancellationToken)
    {
        var parts = ResourceId.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length != 10 || parts[0] != "subscriptions" || !Guid.TryParse(parts[1], out _)
            || parts[2] != "resourceGroups" || parts[4] != "providers" || parts[5] != "Microsoft.Sql"
            || parts[6] != "servers" || parts[8] != "databases")
            throw new InvalidOperationException("ServerlessMonitor:ResourceId must identify an Azure SQL database.");

        using var document = await GetAsync($"{ResourceId}?api-version=2023-08-01", cancellationToken);
        var root = document.RootElement;
        var properties = root.GetProperty("properties");
        var sku = root.GetProperty("sku");
        if (sku.GetProperty("name").GetString() is not { } skuName || !skuName.StartsWith("HS_S_", StringComparison.Ordinal)
            || (properties.TryGetProperty("elasticPoolId", out var pool) && !string.IsNullOrEmpty(pool.GetString())))
            throw new InvalidOperationException("The measured serverless chapter requires a standalone Hyperscale serverless database.");
        var maximum = sku.GetProperty("capacity").GetDouble();
        var minimum = properties.GetProperty("minCapacity").GetDouble();
        if (minimum <= 0 || maximum < minimum)
            throw new InvalidOperationException("Azure returned an invalid serverless compute range.");
        return new(ResourceId, properties.GetProperty("status").GetString() ?? "Unknown", minimum, maximum);
    }

    public async Task<IReadOnlyList<ServerlessMetric>> ReadMetricsAsync(
        ServerlessConfiguration baseline, DateTimeOffset from, DateTimeOffset now, CancellationToken cancellationToken)
    {
        var current = await ReadConfigurationAsync(cancellationToken);
        if (current.ResourceId != baseline.ResourceId || current.MaxVCores != baseline.MaxVCores
            || current.MinVCores != baseline.MinVCores)
            throw new InvalidOperationException("Database configuration changed. Start a new observation window; historical percentages cannot use a different maximum.");
        var end = Minute(now);
        if (from >= end) return [];
        if (from != Minute(from) || end - from > TimeSpan.FromHours(2))
            throw new InvalidOperationException("Observation must use whole UTC minutes and last no more than two hours.");
        var span = Uri.EscapeDataString($"{from.UtcDateTime:O}/{end.UtcDateTime:O}");
        var path = $"{ResourceId}/providers/Microsoft.Insights/metrics?api-version=2023-10-01&interval=PT1M&AutoAdjustTimegrain=false&timespan={span}";
        using var cpu = await GetAsync($"{path}&metricnames=app_cpu_percent&aggregation=Average", cancellationToken);
        using var billed = await GetAsync($"{path}&metricnames=app_cpu_billed&aggregation=Total", cancellationToken);
        using var memory = await GetAsync($"{path}&metricnames=app_memory_percent&aggregation=Average", cancellationToken);
        return Combine(cpu.RootElement, billed.RootElement, from, end, memory.RootElement);
    }

    public static DateTimeOffset Minute(DateTimeOffset value) =>
        new(value.UtcDateTime.Year, value.UtcDateTime.Month, value.UtcDateTime.Day,
            value.UtcDateTime.Hour, value.UtcDateTime.Minute, 0, TimeSpan.Zero);

    public static IReadOnlyList<ServerlessMetric> Combine(
        JsonElement cpu, JsonElement billed, DateTimeOffset from, DateTimeOffset end, JsonElement? memory = null)
    {
        var used = ReadSeries(cpu, "app_cpu_percent", "Percent", "average");
        var charged = ReadSeries(billed, "app_cpu_billed", "Count", "total");
        var memoryUsed = memory is { } document
            ? ReadSeries(document, "app_memory_percent", "Percent", "average")
            : new Dictionary<DateTimeOffset, double?>();
        var result = new List<ServerlessMetric>();
        for (var at = from; at < end; at = at.AddMinutes(1))
            result.Add(new(at, used.GetValueOrDefault(at), charged.GetValueOrDefault(at), memoryUsed.GetValueOrDefault(at)));
        return result;
    }

    private static Dictionary<DateTimeOffset, double?> ReadSeries(JsonElement root, string metric, string unit, string aggregation)
    {
        if (root.GetProperty("interval").GetString() != "PT1M")
            throw new InvalidOperationException("Azure Monitor did not return one-minute intervals.");
        var values = root.GetProperty("value").EnumerateArray().ToArray();
        if (values.Length != 1 || values[0].GetProperty("name").GetProperty("value").GetString() != metric)
            throw new InvalidOperationException($"Azure Monitor did not return the expected metric {metric}.");
        var value = values[0];
        if (value.TryGetProperty("errorCode", out var error) && error.GetString() is { } code && code != "Success")
            throw new InvalidOperationException($"Azure Monitor metric {metric} failed: {code}.");
        // Azure labels app_cpu_billed as Count; its documented semantic unit is vCore-seconds.
        if (value.GetProperty("unit").GetString() != unit)
            throw new InvalidOperationException($"Unexpected Azure Monitor unit for {metric}.");
        var series = value.GetProperty("timeseries").EnumerateArray().ToArray();
        if (series.Length > 1)
            throw new InvalidOperationException($"Expected a single undimensioned series for {metric}.");
        var result = new Dictionary<DateTimeOffset, double?>();
        if (series.Length == 0) return result;
        foreach (var point in series[0].GetProperty("data").EnumerateArray())
        {
            var at = point.GetProperty("timeStamp").GetDateTimeOffset();
            double? amount = point.TryGetProperty(aggregation, out var number) && number.ValueKind != JsonValueKind.Null
                ? number.GetDouble() : null;
            if (at != Minute(at) || amount is { } n && (!double.IsFinite(n) || n < 0 || unit == "Percent" && n > 100))
                throw new InvalidOperationException($"Invalid Azure Monitor sample for {metric}.");
            if (!result.TryAdd(at, amount))
                throw new InvalidOperationException($"Duplicate Azure Monitor timestamp for {metric}.");
        }
        return result;
    }

    private async Task<JsonDocument> GetAsync(string path, CancellationToken cancellationToken)
    {
        var token = await credential.GetTokenAsync(
            new TokenRequestContext(["https://management.azure.com/.default"]), cancellationToken);
        using var request = new HttpRequestMessage(HttpMethod.Get, $"https://management.azure.com{path}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);
        using var response = await http.SendAsync(request, cancellationToken);
        if (!response.IsSuccessStatusCode)
            throw new HttpRequestException($"Azure management request failed ({(int)response.StatusCode}): {await response.Content.ReadAsStringAsync(cancellationToken)}",
                null, response.StatusCode);
        return JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
    }
}
