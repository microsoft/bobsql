using CaldovaNetworkScheduling.Models;
using Microsoft.Data.SqlClient;

namespace CaldovaNetworkScheduling.Services;

public sealed record PoolClinicReading(string Key, SqlWorkloadSnapshot Workload, IReadOnlyList<ServerlessCpuSample> Samples,
    DatabaseStorage? Storage = null, DatabaseStorage? InitialStorage = null);
public sealed record PoolSchedulingState(bool Running, DateTimeOffset? Started, string? Error,
    IReadOnlyList<PoolClinicReading> Clinics, DateTimeOffset? Finished = null, bool Growing = false);
public sealed record PoolClinicClient(ServerlessConfiguration Target, ServerlessSqlWorkload Workload, ServerlessSqlTelemetry Telemetry);

public class PoolClinicClientFactory(IConfiguration configuration, ILoggerFactory loggers, PoolStorage storage)
{
    public virtual PoolClinicClient Create(ProviderDemoProfile provider)
    {
        var target = NetworkResourceMonitor.Target(configuration);
        var resource = $"/subscriptions/{target.Subscription}/resourceGroups/{target.ResourceGroup}/providers/Microsoft.Sql/servers/{target.Server}/databases/{provider.Database}";
        var connection = new SqlConnectionStringBuilder(configuration.GetConnectionString("Scheduling"))
        {
            InitialCatalog = provider.Database
        };
        var settings = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["ConnectionStrings:Scheduling"] = connection.ConnectionString,
            ["ServerlessMonitor:EnableWorkload"] = "true"
        }).Build();
        return new(new(resource, "Online", 0, 8),
            new PoolClinicWorkload(settings, loggers.CreateLogger<ServerlessSqlWorkload>(), storage),
            new PoolClinicTelemetry(settings, storage));
    }
}

public sealed class PoolClinicTelemetry(IConfiguration configuration, PoolStorage storage) : ServerlessSqlTelemetry(configuration)
{
    protected override SqlConnection CreateConnection(string connectionString) => storage.CreateSqlConnection(connectionString);
    protected override int CommandTimeoutSeconds => 30;
}

public sealed class PoolClinicWorkload(IConfiguration configuration, ILogger<ServerlessSqlWorkload> logger, PoolStorage storage)
    : ServerlessSqlWorkload(configuration, logger)
{
    public const string SchedulingQuery = """
        DECLARE @openings bigint;
        SELECT @openings = COUNT_BIG(*) FROM (
            SELECT TOP (10) SlotId FROM dbo.AppointmentSlot
            WHERE IsBooked = 0 AND SlotStart >= SYSUTCDATETIME()
            ORDER BY SlotStart, SlotId
        ) AS openings;
        """;
    public const int CpuIterations = 100_000;
    public static readonly string SchedulingBatch = "SET NOCOUNT ON;\n" + SchedulingQuery
        + "\nDECLARE @remaining int = " + CpuIterations.ToString(System.Globalization.CultureInfo.InvariantCulture)
        + ";\n" + CpuCalculation;
    protected override string BatchQuery => SchedulingBatch;
    protected override SqlConnection CreateConnection(string connectionString) => storage.CreateSqlConnection(connectionString);
}

public sealed class PoolScheduling(NetworkResourceMonitor monitor, PoolClinicClientFactory clients,
    IConfiguration configuration, IHostApplicationLifetime lifetime, ILogger<PoolScheduling> logger,
    PoolStorage storage) : IAsyncDisposable
{
    public const int GrowthTargetGiB = 21;
    public static bool GrowthConfirmed(DatabaseStorage reading) => reading.Key == "caldova"
        && reading.UsedBytes > 20L * DatabaseStorage.GiB
        && reading.AllocatedBytes > 20L * DatabaseStorage.GiB;
    public static readonly TimeSpan GrowthLimit = TimeSpan.FromSeconds(45);
    public static readonly TimeSpan ObservationCooldown = TimeSpan.FromSeconds(15);
    private readonly object gate = new();
    private CancellationTokenSource? run;
    private Task? execution;
    private TaskCompletionSource? startupDone;
    private readonly Dictionary<string, PoolClinicClient> active = [];
    private readonly Dictionary<string, IReadOnlyList<ServerlessCpuSample>> samples = [];
    private readonly Dictionary<string, DatabaseStorage> sizes = [];
    private readonly Dictionary<string, DatabaseStorage> initialSizes = [];
    private bool running;
    private bool stopping;
    private bool growing;
    private DateTimeOffset? started;
    private DateTimeOffset? finished;
    private string? error;
    public bool Enabled => configuration.GetValue<bool>("PoolScaling:Enabled")
        && !configuration.GetValue<bool>("Demo:Playback");
    public bool GrowthEnabled => storage.GrowthEnabled;
    public PoolSchedulingState State
    {
        get
        {
            lock (gate) return new(running || stopping, started, error, active.Select(pair =>
                new PoolClinicReading(pair.Key, pair.Value.Workload.Snapshot, samples[pair.Key],
                    sizes.GetValueOrDefault(pair.Key), initialSizes.GetValueOrDefault(pair.Key))).ToArray(), finished, growing);
        }
    }

    public static WorkloadRamp Ramp(string key) => key switch
    {
        "caldova" or "northbrook" or "ridgeview" =>
            new(9, TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(15), TimeSpan.FromSeconds(5),
                InitialWorkers: 2, WorkersPerStep: 2, WorkersPerStepDown: 3),
        _ => throw new ArgumentException("Unknown scheduling provider.", nameof(key))
    };

    public async Task StartAsync()
    {
        if (!Enabled) throw new InvalidOperationException("Live pool scheduling is disabled on this app host.");
        TaskCompletionSource startupCompletion;
        lock (gate)
        {
            if (running || stopping) throw new InvalidOperationException("Pool scheduling is already running or stopping.");
            running = true;
            error = null;
            execution = null;
            startupDone = startupCompletion = new(TaskCreationOptions.RunContinuationsAsynchronously);
            run?.Dispose();
            run = CancellationTokenSource.CreateLinkedTokenSource(lifetime.ApplicationStopping);
        }
        var token = run.Token;
        try
        {
            PoolScaler.ValidatePool(await monitor.ReadAsync(token));
            var readings = await storage.ReadAllAsync(token);
            if (GrowthEnabled) PoolStorage.ValidateSeeded(readings);
            token.ThrowIfCancellationRequested();
            lock (gate)
            {
                active.Clear();
                samples.Clear();
                sizes.Clear();
                initialSizes.Clear();
                foreach (var reading in readings)
                {
                    initialSizes.Add(reading.Key, reading);
                    RecordStorage(reading);
                }
                started = DateTimeOffset.UtcNow;
                finished = null;
                foreach (var provider in ProviderProfiles.All)
                {
                    active.Add(provider.Key, clients.Create(provider));
                    samples.Add(provider.Key, []);
                }
                execution = RunAsync(token);
            }
        }
        catch (Exception ex) when (IsExpected(ex))
        {
            logger.LogError("Pool scheduling startup failed: {Error}", AzureCliRunner.Redact(ex.Message));
            lock (gate) { running = false; error = AzureCliRunner.Redact(ex.Message); }
            throw new InvalidOperationException(error);
        }
        finally { startupCompletion.TrySetResult(); }
    }

    private async Task RunAsync(CancellationToken token)
    {
        try
        {
            foreach (var pair in active) pair.Value.Workload.StartRamp(pair.Value.Target, Ramp(pair.Key));
            var growth = GrowthEnabled ? GrowAsync(token) : Task.CompletedTask;
            await Task.WhenAll(active.Select(pair => ObserveAsync(pair.Key, pair.Value, token)).Append(growth));
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
        catch (Exception ex) when (IsExpected(ex))
        {
            logger.LogError("Pool scheduling failed: {Error}", AzureCliRunner.Redact(ex.Message));
            lock (gate) error = AzureCliRunner.Redact(ex.Message);
        }
        finally
        {
            run?.Cancel();
            foreach (var client in active.Values) await client.Workload.DisposeAsync();
            lock (gate) { running = false; finished = DateTimeOffset.UtcNow; }
        }
    }

    private async Task GrowAsync(CancellationToken token)
    {
        lock (gate) growing = true;
        try
        {
            await storage.FillToAsync(ProviderProfiles.All.Single(provider => provider.Key == "caldova"), GrowthTargetGiB,
                RecordStorage, GrowthLimit, token, GrowthConfirmed, allowPartialOnTimeout: true);
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (SqlException ex) when (token.IsCancellationRequested)
        {
            throw new OperationCanceledException("Storage fill was stopped.", ex, token);
        }
        catch (Exception ex) when (IsExpected(ex))
        {
            run?.Cancel();
            throw new InvalidOperationException($"Caldova growth stopped before confirmation. Committed synthetic data remains. {AzureCliRunner.Redact(ex.Message)}");
        }
        finally { lock (gate) growing = false; }
    }

    private async Task ObserveAsync(string key, PoolClinicClient client, CancellationToken token)
    {
        DateTimeOffset? finished = null;
        var operation = "CPU workload";
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(3));
        try
        {
            do
            {
                operation = "CPU workload";
                if (client.Workload.Snapshot.Error is { } failure) throw new InvalidOperationException(failure);
                operation = "CPU observation";
                var current = await client.Telemetry.ReadAsync(client.Target, started!.Value.AddSeconds(-30), token);
                lock (gate) samples[key] = current;
                operation = "storage observation";
                var size = await storage.ReadAsync(ProviderProfiles.All.Single(provider => provider.Key == key), token);
                RecordStorage(size);
                if (!client.Workload.Snapshot.Running && !growing)
                {
                    finished ??= DateTimeOffset.UtcNow;
                    if (DateTimeOffset.UtcNow - finished >= ObservationCooldown) break;
                }
            } while (await timer.WaitForNextTickAsync(token));
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (SqlException ex) when (token.IsCancellationRequested)
        {
            throw new OperationCanceledException("Scheduling observation was stopped.", ex, token);
        }
        catch (Exception ex) when (IsExpected(ex))
        {
            run?.Cancel();
            throw new InvalidOperationException($"{key} {operation} failed: {AzureCliRunner.Redact(ex.Message)}");
        }
    }

    private static bool IsExpected(Exception ex) => ex is InvalidOperationException or ArgumentException
        or HttpRequestException or SqlException or System.Text.Json.JsonException or KeyNotFoundException
        or FormatException or OperationCanceledException
        or Azure.Identity.AuthenticationFailedException or Azure.Identity.CredentialUnavailableException;

    private void RecordStorage(DatabaseStorage reading)
    {
        lock (gate)
        {
            if (sizes.TryGetValue(reading.Key, out var previous) && reading.At <= previous.At) return;
            sizes[reading.Key] = reading;
        }
    }

    public async Task StopAsync()
    {
        Task? startup;
        lock (gate)
        {
            stopping = true;
            run?.Cancel();
            startup = startupDone?.Task;
        }
        try
        {
            if (startup is not null) await startup;
            if (execution is not null) await execution;
        }
        finally { lock (gate) stopping = false; }
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync();
        run?.Dispose();
    }
}
