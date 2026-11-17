using Azure.Identity;
using CaldovaNetworkScheduling.Services;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

internal static class ServerlessLiveCheck
{
    public static async Task ObserveSqlAsync(IConfiguration configuration, DateTimeOffset from)
    {
        if (from > DateTimeOffset.UtcNow || DateTimeOffset.UtcNow - from > TimeSpan.FromHours(1))
            throw new ArgumentOutOfRangeException(nameof(from), "Use a UTC start within the last hour.");
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
        var monitor = new ServerlessMonitor(http, new DefaultAzureCredential(), configuration);
        using var limit = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var database = await monitor.ReadConfigurationAsync(limit.Token);
        await using var diagnostics = CreateDiagnostics(configuration, database);
        Console.WriteLine($"READ-ONLY SQL DMV CAPTURE: {database.ResourceId}; no workload or Azure Monitor metrics. Can resume compute and keeps SQL awake.");
        await diagnostics.OpenAsync(limit.Token);
        await diagnostics.CaptureAsync(from.UtcDateTime, limit.Token);
        diagnostics.PrintSummary();
        var appSamples = await new ServerlessSqlTelemetry(configuration).ReadAsync(database, from, limit.Token);
        if (appSamples.Count == 0) throw new InvalidOperationException("The app SQL telemetry service returned no samples.");
        Console.WriteLine($"APP SQL TELEMETRY: samples={appSamples.Count} peak-used-vCores={appSamples.Max(s => s.UsedVCores):F4}; actual primary-replica DMV reads verified with the diagnostic identity, not the App Service identity.");
        Console.WriteLine("Closing diagnostic connection. Wait deltas cover this read-only capture, not the prior workload.");
    }

    public static async Task CaptureAsync(IConfiguration configuration, DateTimeOffset from)
    {
        Console.WriteLine("MONITOR ONLY: no SQL connections or load. Use only a window whose serverless maximum was already recorded.");
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
        var monitor = new ServerlessMonitor(http, new DefaultAzureCredential(), configuration);
        using var limit = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var database = await monitor.ReadConfigurationAsync(limit.Token);
        Console.WriteLine($"TARGET: {database.ResourceId}; current maximum {database.MaxVCores}, must match the recorded window.");
        var samples = await monitor.ReadMetricsAsync(database, from, DateTimeOffset.UtcNow, limit.Token);
        foreach (var point in samples)
            Print(point, database.MaxVCores);
        if (!samples.Any(s => s.CpuPercent is not null) || !samples.Any(s => s.BilledVCoreSeconds is not null))
            throw new InvalidOperationException("Both metric series were not delivered. Capture is incomplete.");
    }

    public static async Task RunAsync(IConfiguration configuration, int workers = 4, WorkloadRamp? ramp = null)
    {
        if (workers is < 1 or > 16) throw new ArgumentOutOfRangeException(nameof(workers));
        ramp?.Validate();
        Console.WriteLine(ramp is null
            ? $"LIVE: approved real compute usage; {workers} small-working-set scalar CPU workers for at most 3 minutes. No table access, writes, cache flushes, or Azure changes."
            : $"LIVE RAMP: approved real compute usage; 0 -> {ramp.PeakWorkers} -> 0 scalar CPU workers, one per {ramp.StepUp.TotalSeconds:0}s up / {ramp.StepDown.TotalSeconds:0}s down, {ramp.Hold.TotalSeconds:0}s hold at peak, {ramp.Total.TotalMinutes:0.#} minutes total. No table access, writes, cache flushes, or Azure changes.");
        var settings = new ConfigurationBuilder().AddConfiguration(configuration)
            .AddInMemoryCollection(new Dictionary<string, string?> { ["ServerlessMonitor:EnableWorkload"] = "true" }).Build();
        using var logging = LoggerFactory.Create(builder => builder.AddConsole());
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
        var monitor = new ServerlessMonitor(http, new DefaultAzureCredential(), settings);
        await using var workload = new ServerlessSqlWorkload(settings, logging.CreateLogger<ServerlessSqlWorkload>());
        using var limit = new CancellationTokenSource((ramp?.Total ?? TimeSpan.FromMinutes(3)) + TimeSpan.FromMinutes(7));
        var database = await monitor.ReadConfigurationAsync(limit.Token);
        await using var diagnostics = CreateDiagnostics(settings, database);
        Console.WriteLine($"TARGET: {database.ResourceId}, ARM status {database.Status}, configured range {database.MinVCores}-{database.MaxVCores}.");
        Console.WriteLine("SQL DMV observation only; no Azure Monitor metrics. Diagnostic reads keep the database awake.");
        await diagnostics.OpenAsync(limit.Token);
        var from = DateTime.UtcNow;
        await diagnostics.CaptureAsync(from, limit.Token);
        Console.WriteLine("Recording quiet baseline for 30 seconds.");
        for (var i = 0; i < 2; i++)
        {
            await Task.Delay(TimeSpan.FromSeconds(15), limit.Token);
            await diagnostics.CaptureAsync(from, limit.Token);
        }
        if (ramp is null) workload.Start(database, workers, 3);
        else workload.StartRamp(database, ramp);
        Console.WriteLine($"SQL START: {DateTimeOffset.UtcNow:O}");
        do
        {
            await Task.Delay(TimeSpan.FromSeconds(15), limit.Token);
            await diagnostics.CaptureAsync(from, limit.Token);
            var state = workload.Snapshot;
            Console.WriteLine($"SQL: {DateTimeOffset.UtcNow:O} running={state.Running} active-workers={state.Active} completed={state.Completed} failed={state.Failed} error={state.Error}");
            if (state.Error is not null) break;
        } while (workload.Snapshot.Running);
        await workload.StopAsync();
        Console.WriteLine($"SQL STOP: {workload.Snapshot.Finished:O}. Observing SQL CPU cooldown for 60 seconds; diagnostic reads remain active.");
        for (var i = 0; i < 4; i++)
        {
            await Task.Delay(TimeSpan.FromSeconds(15), limit.Token);
            await diagnostics.CaptureAsync(from, limit.Token);
        }
        diagnostics.PrintSummary();
        if (workload.Snapshot.Error is { } failure)
            throw new InvalidOperationException($"Live workload failed; no retry performed: {failure}");
        if (workload.Snapshot.Completed == 0) throw new InvalidOperationException("No SQL work completed.");
        Console.WriteLine("LIVE DMV DATA CAPTURED. Closing all diagnostic/workload connections; no further SQL polling.");
    }

    private static ServerlessSqlDiagnostics CreateDiagnostics(IConfiguration configuration, ServerlessConfiguration database)
    {
        var settings = new SqlConnectionStringBuilder(configuration.GetConnectionString("Scheduling")
            ?? throw new InvalidOperationException("ConnectionStrings:Scheduling is required."));
        var parts = database.ResourceId.Split('/');
        if (!settings.DataSource.Equals($"tcp:{parts[8]}.database.windows.net,1433", StringComparison.OrdinalIgnoreCase)
            || !settings.InitialCatalog.Equals(parts[10], StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("SQL diagnostic target must match the monitored database exactly.");
        settings.Pooling = false;
        settings.ConnectRetryCount = 0;
        settings.ApplicationName = "Caldova.ServerlessDiagnostics";
        return new(settings.ConnectionString);
    }

    private static void Print(ServerlessMetric point, double maximum) =>
        Console.WriteLine($"{point.At:O} CPU%={point.CpuPercent?.ToString("R") ?? "Missing"} used-vCores={point.UsedVCores(maximum)?.ToString("R") ?? "Missing"} billed-vCore-seconds={point.BilledVCoreSeconds?.ToString("R") ?? "Missing"} billed-average-vCores={point.BilledVCores?.ToString("R") ?? "Missing"} app-memory%={point.MemoryPercent?.ToString("R") ?? "Missing"}");
}
