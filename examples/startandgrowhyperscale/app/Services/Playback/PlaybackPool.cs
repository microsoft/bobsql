namespace CaldovaNetworkScheduling.Services.Playback;

public sealed record PoolSecond(DateTimeOffset At, double Succeeded, double Failed, double LatencyMs, double CpuPercent, string Phase);
public sealed record PoolEvent(DateTimeOffset At, string Text, string Kind);
public sealed record PoolDatabase(string Name, string Provider, double DataGb, bool Loading);
public sealed record PoolSnapshot(int VCores, int? TargetVCores, string ScaleState, bool WorkloadRunning, bool Loading,
    IReadOnlyList<PoolSecond> Seconds, IReadOnlyList<PoolEvent> Events, IReadOnlyList<PoolDatabase> Databases,
    long SucceededTotal, long FailedTotal);

/// <summary>
/// Scripted Part 2 pool workload: network scheduling traffic, an online pool scale with a brief
/// switch-over, and bounded history inserts that grow one database while compute stays fixed.
/// </summary>
public sealed class PlaybackPool : IDisposable
{
    private const double OfferedRequestsPerSecond = 640;
    private const double RequestsPerVCore = 52;
    private static readonly TimeSpan Prepare = TimeSpan.FromSeconds(40);
    private static readonly TimeSpan SwitchOver = TimeSpan.FromSeconds(4);
    private static readonly TimeSpan HistoryLoad = TimeSpan.FromSeconds(100);
    private const double HistoryGbPerSecond = 0.124;

    private readonly object gate = new();
    private readonly Random random = new(16);
    private readonly CancellationTokenSource stop = new();
    private readonly List<PoolSecond> seconds = [];
    private readonly List<PoolEvent> events = [];
    private readonly Dictionary<string, (string Provider, double DataGb)> databases = [];
    private int vCores;
    private int? targetVCores;
    private DateTimeOffset? scaleStarted;
    private DateTimeOffset? loadStarted;
    private bool workload;
    private double succeededTotal;
    private double failedTotal;

    public PlaybackPool()
    {
        ResetCore();
        _ = LoopAsync();
    }

    public event Action? Changed;

    public PoolSnapshot GetSnapshot()
    {
        lock (gate)
        {
            return new(vCores, targetVCores, ScaleState(DateTimeOffset.UtcNow), workload, loadStarted is not null,
                seconds.ToArray(), events.AsEnumerable().Reverse().ToArray(),
                databases.Select(d => new PoolDatabase(d.Key, d.Value.Provider, d.Value.DataGb,
                    loadStarted is not null && d.Key == "northbrook-scheduling")).ToArray(),
                (long)succeededTotal, (long)failedTotal);
        }
    }

    public void StartWorkload()
    {
        lock (gate)
        {
            if (workload) return;
            workload = true;
            Log("Workload started · staff search and book across Caldova, Northbrook, and Ridgeview", "info");
        }
        Changed?.Invoke();
    }

    public void StopWorkload()
    {
        lock (gate)
        {
            if (!workload) return;
            workload = false;
            Log("Workload stopped", "info");
        }
        Changed?.Invoke();
    }

    public void Scale(int target)
    {
        lock (gate)
        {
            if (scaleStarted is not null || target == vCores) return;
            targetVCores = target;
            scaleStarted = DateTimeOffset.UtcNow;
            Log($"Scale requested · caldova-network-pool {vCores} → {target} vCores", "info");
            Log("Preparing new compute · databases stay online and keep serving requests", "info");
        }
        Changed?.Invoke();
    }

    public void LoadHistory()
    {
        lock (gate)
        {
            if (loadStarted is not null) return;
            loadStarted = DateTimeOffset.UtcNow;
            Log("Loading Northbrook encounter history · bounded synthetic inserts, compute unchanged", "info");
        }
        Changed?.Invoke();
    }

    public void Reset()
    {
        lock (gate) ResetCore();
        Changed?.Invoke();
    }

    private void ResetCore()
    {
        vCores = 8;
        targetVCores = null;
        scaleStarted = null;
        loadStarted = null;
        workload = false;
        succeededTotal = failedTotal = 0;
        seconds.Clear();
        events.Clear();
        databases.Clear();
        databases["caldova-scheduling"] = ("Caldova Health", 41.6);
        databases["northbrook-scheduling"] = ("Northbrook Family Clinics", 18.2);
        databases["ridgeview-scheduling"] = ("Ridgeview Specialty Care", 27.9);
    }

    private string ScaleState(DateTimeOffset now)
    {
        if (scaleStarted is not { } started) return "Ready";
        var elapsed = now - started;
        return elapsed < Prepare ? "Preparing" : elapsed < Prepare + SwitchOver ? "Switching" : "Ready";
    }

    private void Log(string text, string kind) => events.Add(new(DateTimeOffset.UtcNow, text, kind));

    private double Jitter(double amount) => 1 + (random.NextDouble() - 0.5) * amount;

    private async Task LoopAsync()
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(1));
        try
        {
            while (await timer.WaitForNextTickAsync(stop.Token))
            {
                var now = DateTimeOffset.UtcNow;
                lock (gate)
                {
                    var state = ScaleState(now);
                    if (scaleStarted is { } started && now - started >= Prepare && state == "Switching"
                        && !events.Any(e => e.Kind == "warn" && e.At >= started))
                        Log("Switching over · open connections reset (error 40613); the app reconnects and retries reads", "warn");
                    if (scaleStarted is not null && state == "Ready" && targetVCores is { } target)
                    {
                        vCores = target;
                        targetVCores = null;
                        scaleStarted = null;
                        Log($"Scale complete · {vCores} vCores · traffic recovered after a {SwitchOver.TotalSeconds:0}-second switch-over", "done");
                    }
                    if (loadStarted is { } load)
                    {
                        var current = databases["northbrook-scheduling"];
                        databases["northbrook-scheduling"] = current with { DataGb = current.DataGb + HistoryGbPerSecond * Jitter(0.2) };
                        if (now - load >= HistoryLoad)
                        {
                            loadStarted = null;
                            Log($"History loaded · northbrook-scheduling now {databases["northbrook-scheduling"].DataGb:0.0} GB · no storage size set or changed", "done");
                        }
                    }
                    if (workload)
                    {
                        var capacity = vCores * RequestsPerVCore;
                        double ok, failed, latency, cpu;
                        if (state == "Switching")
                        {
                            ok = 0;
                            failed = 28 * Jitter(0.4);
                            latency = 0;
                            cpu = 0;
                        }
                        else
                        {
                            var loading = loadStarted is not null ? 0.06 : 0;
                            ok = Math.Min(OfferedRequestsPerSecond, capacity * (1 - loading)) * Jitter(0.06);
                            failed = 0;
                            var saturated = OfferedRequestsPerSecond > capacity * (1 - loading);
                            latency = (saturated ? 172 : 41 + loading * 120) * Jitter(0.18);
                            cpu = Math.Min(99, (ok / capacity * 100 + loading * 100) * Jitter(0.04));
                        }
                        succeededTotal += ok;
                        failedTotal += failed;
                        seconds.Add(new(now, ok, failed, latency, cpu, state));
                        if (seconds.Count > 180) seconds.RemoveAt(0);
                    }
                }
                Changed?.Invoke();
            }
        }
        catch (OperationCanceledException) { }
    }

    public void Dispose()
    {
        stop.Cancel();
        stop.Dispose();
    }
}
