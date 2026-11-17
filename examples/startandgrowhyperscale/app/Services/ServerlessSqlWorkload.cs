using System.Collections.Immutable;
using Microsoft.Data.SqlClient;

namespace CaldovaNetworkScheduling.Services;

public sealed record SqlWorkloadSnapshot(bool Running, int Workers, long Completed, long Failed,
    DateTimeOffset? Started, DateTimeOffset? Finished, string? Error, int Active = 0, WorkloadRamp? Ramp = null);

/// <summary>
/// Staged load: InitialWorkers start immediately, then WorkersPerStep per StepUp; after Hold at peak, groups stop per StepDown.
/// WorkersPerStepDown optionally sets a different stopping group size, including with explicit increasing levels.
/// WorkerLevels optionally defines explicit increasing levels, reversed on the way down unless WorkersPerStepDown is set.
/// (last started stops first). Each stopping worker finishes its in-flight batch; no command is cancelled.
/// </summary>
public sealed record WorkloadRamp(int PeakWorkers, TimeSpan StepUp, TimeSpan Hold, TimeSpan StepDown,
    int InitialWorkers = 1, int WorkersPerStep = 1, int? WorkersPerStepDown = null,
    ImmutableArray<int> WorkerLevels = default)
{
    public WorkloadRamp(int peakWorkers, TimeSpan step, TimeSpan hold) : this(peakWorkers, step, hold, step) { }

    public static readonly TimeSpan MaximumTotal = TimeSpan.FromMinutes(10);
    public TimeSpan PeakAt => StepUp * (WorkerLevels.IsDefault
        ? (PeakWorkers - InitialWorkers + WorkersPerStep - 1) / WorkersPerStep : WorkerLevels.Length - 1);
    public TimeSpan StartAt(int worker) => WorkerLevels.IsDefault
        ? worker < InitialWorkers ? TimeSpan.Zero : StepUp * ((worker - InitialWorkers) / WorkersPerStep + 1)
        : StepUp * LevelOf(worker);
    public TimeSpan StopAt(int worker) => PeakAt + Hold
        + StepDown * (WorkerLevels.IsDefault || WorkersPerStepDown is not null
            ? (PeakWorkers - 1 - worker) / (WorkersPerStepDown ?? WorkersPerStep)
            : WorkerLevels.Length - 1 - LevelOf(worker));
    public TimeSpan Total => StopAt(0);
    public int ActiveAt(TimeSpan elapsed) =>
        Enumerable.Range(0, PeakWorkers).Count(i => elapsed >= StartAt(i) && elapsed < StopAt(i));

    private int LevelOf(int worker)
    {
        for (var i = 0; i < WorkerLevels.Length; i++)
            if (worker >= 0 && worker < WorkerLevels[i]) return i;
        throw new ArgumentOutOfRangeException(nameof(worker));
    }

    public void Validate()
    {
        if (PeakWorkers is < 1 or > 16) throw new ArgumentOutOfRangeException(nameof(PeakWorkers), "Use 1-16 peak workers.");
        if (InitialWorkers < 1 || InitialWorkers > PeakWorkers)
            throw new ArgumentOutOfRangeException(nameof(InitialWorkers), "Initial workers must be between one and the peak.");
        if (WorkersPerStep is < 1 or > 16)
            throw new ArgumentOutOfRangeException(nameof(WorkersPerStep), "Use 1-16 workers per ramp step.");
        if (WorkersPerStepDown is < 1 or > 16)
            throw new ArgumentOutOfRangeException(nameof(WorkersPerStepDown), "Use 1-16 workers per ramp-down step.");
        if (!WorkerLevels.IsDefault && (WorkerLevels.Length is < 1 or > 16
            || WorkerLevels[0] != InitialWorkers || WorkerLevels[^1] != PeakWorkers
            || Enumerable.Range(1, WorkerLevels.Length - 1).Any(i => WorkerLevels[i] <= WorkerLevels[i - 1])
            || WorkersPerStep != 1))
            throw new ArgumentOutOfRangeException(nameof(WorkerLevels),
                "Levels must increase from the initial workers to the peak, without a separate ramp-up worker-step setting.");
        if (StepUp < TimeSpan.FromSeconds(5) || StepUp > TimeSpan.FromSeconds(120)
            || StepDown < TimeSpan.FromSeconds(5) || StepDown > TimeSpan.FromSeconds(120))
            throw new ArgumentOutOfRangeException(nameof(StepUp), "Use 5-120 second ramp steps.");
        if (Hold < TimeSpan.FromSeconds(10) || Hold > TimeSpan.FromMinutes(5))
            throw new ArgumentOutOfRangeException(nameof(Hold), "Use a 10-300 second hold at peak.");
        if (Total > MaximumTotal)
            throw new ArgumentOutOfRangeException(nameof(StepUp), $"Ramp lasts {Total.TotalMinutes:0.#} minutes; the limit is {MaximumTotal.TotalMinutes} minutes.");
    }
}

public class ServerlessSqlWorkload(IConfiguration configuration, ILogger<ServerlessSqlWorkload> logger) : IAsyncDisposable
{
    protected const string CpuCalculation = """
        DECLARE @value varbinary(32) = 0x43616C646F7661;
        WHILE @remaining > 0
        BEGIN
            SET @value = HASHBYTES('SHA2_256', @value);
            SET @remaining -= 1;
        END;
        SELECT @value;
        """;
    public const string Query = "SET NOCOUNT ON;\nDECLARE @remaining int = 50000;\n" + CpuCalculation;
    private readonly object gate = new();
    protected virtual string BatchQuery => Query;
    protected virtual SqlConnection CreateConnection(string connectionString) => new(connectionString);
    private CancellationTokenSource? cancellation;
    private Task? execution;
    private SqlWorkloadSnapshot snapshot = new(false, 0, 0, 0, null, null, null);
    public virtual bool Enabled => configuration.GetValue<bool>("ServerlessMonitor:EnableWorkload");
    public virtual SqlWorkloadSnapshot Snapshot { get { lock (gate) return snapshot; } }

    public virtual void Start(ServerlessConfiguration database, int workers, int minutes)
    {
        if (workers is < 1 or > 16 || minutes is < 1 or > 10)
            throw new ArgumentOutOfRangeException(nameof(workers), "Use 1-16 workers for 1-10 minutes.");
        Start(database, workers, TimeSpan.FromMinutes(minutes));
    }

    public virtual void Start(ServerlessConfiguration database, int workers, TimeSpan duration)
    {
        if (!Enabled) throw new InvalidOperationException("SQL load generation is disabled. Enable only for an approved, access-restricted demo.");
        if (workers is < 1 or > 16 || duration < TimeSpan.FromSeconds(15) || duration > TimeSpan.FromMinutes(10))
            throw new ArgumentOutOfRangeException(nameof(duration), "Use 1-16 workers for 15-600 seconds.");
        Launch(database, workers, duration, null);
    }

    public virtual void StartRamp(ServerlessConfiguration database, WorkloadRamp ramp)
    {
        if (!Enabled) throw new InvalidOperationException("SQL load generation is disabled. Enable only for an approved, access-restricted demo.");
        ramp.Validate();
        // The schedule stops workers itself; the token is only a backstop for an overrunning batch.
        Launch(database, ramp.PeakWorkers, ramp.Total + TimeSpan.FromSeconds(30), ramp);
    }

    private void Launch(ServerlessConfiguration database, int workers, TimeSpan limit, WorkloadRamp? ramp)
    {
        var settings = ServerlessSqlTelemetry.ConnectionSettings(configuration, database, "Caldova.ServerlessDemo");
        lock (gate)
        {
            if (snapshot.Running) throw new InvalidOperationException("Stop the current workload before starting another.");
            cancellation?.Dispose();
            cancellation = new CancellationTokenSource(limit);
            snapshot = new(true, workers, 0, 0, DateTimeOffset.UtcNow, null, null, 0, ramp);
            execution = RunAsync(settings.ConnectionString, workers, ramp, cancellation.Token);
        }
    }

    private async Task RunAsync(string connectionString, int workers, WorkloadRamp? ramp, CancellationToken token)
    {
        var clock = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            await Task.WhenAll(Enumerable.Range(0, workers).Select(i =>
                WorkerAsync(connectionString, ramp?.StartAt(i) ?? TimeSpan.Zero, ramp?.StopAt(i), clock, token)));
        }
        finally
        {
            lock (gate) snapshot = snapshot with { Running = false, Finished = DateTimeOffset.UtcNow };
        }
    }

    private async Task WorkerAsync(string connectionString, TimeSpan startAt, TimeSpan? stopAt,
        System.Diagnostics.Stopwatch clock, CancellationToken token)
    {
        var active = false;
        try
        {
            var delay = startAt - clock.Elapsed;
            if (delay > TimeSpan.Zero) await Task.Delay(delay, token);
            await using var connection = CreateConnection(connectionString);
            await connection.OpenAsync(token);
            lock (gate) snapshot = snapshot with { Active = snapshot.Active + 1 };
            active = true;
            while (!token.IsCancellationRequested && (stopAt is null || clock.Elapsed < stopAt))
            {
                using var command = new SqlCommand(BatchQuery, connection) { CommandTimeout = 15 };
                var result = await command.ExecuteScalarAsync(token);
                if (result is null or DBNull)
                    throw new InvalidOperationException("The CPU calculation returned no result.");
                lock (gate) snapshot = snapshot with { Completed = snapshot.Completed + 1 };
            }
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
        catch (SqlException) when (token.IsCancellationRequested) { }
        catch (Exception ex) when (ex is SqlException or InvalidOperationException)
        {
            logger.LogError(ex, "Measured serverless workload failed; stopping all workers without retry");
            lock (gate) snapshot = snapshot with { Failed = snapshot.Failed + 1, Error = ex.Message };
            cancellation?.Cancel();
        }
        finally
        {
            if (active) lock (gate) snapshot = snapshot with { Active = snapshot.Active - 1 };
        }
    }

    public virtual async Task StopAsync()
    {
        cancellation?.Cancel();
        if (execution is not null) await execution;
    }

    public virtual async ValueTask DisposeAsync()
    {
        await StopAsync();
        cancellation?.Dispose();
    }
}
