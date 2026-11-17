namespace CaldovaNetworkScheduling.Services.Playback;

public sealed class PlaybackSqlTelemetry(IConfiguration configuration, PlaybackDatabase database) : ServerlessSqlTelemetry(configuration)
{
    public override async Task<IReadOnlyList<ServerlessCpuSample>> ReadAsync(
        ServerlessConfiguration target, DateTimeOffset from, CancellationToken token)
    {
        await database.EnsureOnlineAsync(token);
        return database.SamplesFrom(from);
    }
}

public sealed class PlaybackResume(IConfiguration configuration, ILogger<ServerlessResume> logger, PlaybackDatabase database)
    : ServerlessResume(configuration, logger)
{
    public override async Task<ResumeResult> SignInAsync(ServerlessConfiguration target, Action<int>? onAttempt, CancellationToken token)
    {
        var clock = System.Diagnostics.Stopwatch.StartNew();
        var attempt = 1;
        onAttempt?.Invoke(attempt);
        database.BeginResume();
        await Task.Delay(TimeSpan.FromMilliseconds(600), token);
        while (database.Status != "Online")
        {
            await Task.Delay(Backoff(attempt), token);
            attempt++;
            onAttempt?.Invoke(attempt);
        }
        database.Touch();
        return new(clock.Elapsed, attempt, DateTimeOffset.UtcNow);
    }
}

public sealed class PlaybackSqlWorkload(IConfiguration configuration, ILogger<ServerlessSqlWorkload> logger, PlaybackDatabase database)
    : ServerlessSqlWorkload(configuration, logger)
{
    // Batches per second per worker, close to the measured completion rate.
    private const double BatchesPerSecond = 0.85;
    private readonly object gate = new();
    private CancellationTokenSource? cancellation;
    private Task? execution;
    private SqlWorkloadSnapshot snapshot = new(false, 0, 0, 0, null, null, null);

    public override bool Enabled => true;
    public override SqlWorkloadSnapshot Snapshot { get { lock (gate) return snapshot; } }

    public override void Start(ServerlessConfiguration target, int workers, int minutes) =>
        Launch(workers, TimeSpan.FromMinutes(minutes), null);

    public override void Start(ServerlessConfiguration target, int workers, TimeSpan duration) =>
        Launch(workers, duration, null);

    public override void StartRamp(ServerlessConfiguration target, WorkloadRamp ramp)
    {
        ramp.Validate();
        Launch(ramp.PeakWorkers, ramp.Total, ramp);
    }

    private void Launch(int workers, TimeSpan limit, WorkloadRamp? ramp)
    {
        lock (gate)
        {
            if (snapshot.Running) throw new InvalidOperationException("Stop the current workload before starting another.");
            cancellation?.Dispose();
            cancellation = new CancellationTokenSource();
            snapshot = new(true, workers, 0, 0, DateTimeOffset.UtcNow, null, null, 0, ramp);
            execution = RunAsync(workers, limit, ramp, cancellation.Token);
        }
    }

    private async Task RunAsync(int workers, TimeSpan limit, WorkloadRamp? ramp, CancellationToken token)
    {
        try
        {
            await database.EnsureOnlineAsync(token);
            var clock = System.Diagnostics.Stopwatch.StartNew();
            double completed = 0;
            while (!token.IsCancellationRequested && clock.Elapsed < limit)
            {
                var active = ramp?.ActiveAt(clock.Elapsed) ?? workers;
                database.SetActive(active);
                completed += active * BatchesPerSecond * 0.25;
                lock (gate) snapshot = snapshot with { Active = active, Completed = (long)completed };
                await Task.Delay(250, token);
            }
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
        finally
        {
            database.SetActive(0);
            lock (gate) snapshot = snapshot with { Running = false, Active = 0, Finished = DateTimeOffset.UtcNow };
        }
    }

    public override async Task StopAsync()
    {
        cancellation?.Cancel();
        if (execution is not null) await execution;
    }

    public override async ValueTask DisposeAsync()
    {
        await StopAsync();
        cancellation?.Dispose();
    }
}
