namespace CaldovaNetworkScheduling.Services.Playback;

/// <summary>
/// In-memory stand-in for the Part 1 serverless database. Produces 15-second CPU intervals from the
/// number of active workers (shaped on the 2026-10-25 measured run), auto-pauses after an idle delay,
/// and resumes on the next connection. No Azure or SQL access.
/// </summary>
public sealed class PlaybackDatabase : IDisposable
{
    public const double MaxVCores = 8;
    public const double MinVCores = 1;
    private static readonly TimeSpan Interval = TimeSpan.FromSeconds(15);

    private readonly object gate = new();
    private readonly List<ServerlessCpuSample> samples = [];
    private readonly Random random = new(20261025);
    private readonly CancellationTokenSource stop = new();
    private readonly TimeSpan autoPause;
    private readonly TimeSpan resumeTime;
    private string status;
    private double vCores;
    private double intervalSum;
    private int intervalCount;
    private int active;
    private DateTimeOffset lastActivity = DateTimeOffset.UtcNow;
    private DateTimeOffset resumeAt;

    public PlaybackDatabase(IConfiguration configuration)
    {
        autoPause = TimeSpan.FromSeconds(configuration.GetValue("Playback:AutoPauseSeconds", 60));
        resumeTime = TimeSpan.FromSeconds(configuration.GetValue("Playback:ResumeSeconds", 14));
        status = configuration.GetValue("Playback:StartPaused", false) ? "Paused" : "Online";
        _ = LoopAsync();
    }

    public string Status { get { lock (gate) return status; } }

    public void SetActive(int workers)
    {
        lock (gate)
        {
            active = workers;
            lastActivity = DateTimeOffset.UtcNow;
        }
    }

    public void Touch() { lock (gate) lastActivity = DateTimeOffset.UtcNow; }

    public void Pause() { lock (gate) { status = "Paused"; vCores = 0; } }

    public void BeginResume()
    {
        lock (gate)
        {
            if (status != "Paused") return;
            status = "Resuming";
            resumeAt = DateTimeOffset.UtcNow + resumeTime;
        }
    }

    public async Task EnsureOnlineAsync(CancellationToken token)
    {
        BeginResume();
        while (Status != "Online") await Task.Delay(250, token);
        Touch();
    }

    public IReadOnlyList<ServerlessCpuSample> SamplesFrom(DateTimeOffset from)
    {
        lock (gate) return samples.Where(s => s.At >= from).ToList();
    }

    private async Task LoopAsync()
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMilliseconds(250));
        var now = DateTimeOffset.UtcNow;
        var intervalEnd = new DateTimeOffset(now.Ticks - now.Ticks % Interval.Ticks, TimeSpan.Zero) + Interval;
        try
        {
            while (await timer.WaitForNextTickAsync(stop.Token))
            {
                now = DateTimeOffset.UtcNow;
                lock (gate)
                {
                    if (status == "Resuming" && now >= resumeAt)
                    {
                        status = "Online";
                        lastActivity = now;
                    }
                    if (status == "Online")
                    {
                        // About 0.93 vCores per CPU-bound worker, as measured; the rise is faster than the fall.
                        var target = active == 0 ? 0.02 : Math.Min(7.6, active * 0.93);
                        vCores += (target - vCores) * (target > vCores ? 0.03 : 0.02);
                        intervalSum += vCores;
                        intervalCount++;
                        if (active == 0 && now - lastActivity > autoPause)
                        {
                            status = "Paused";
                            vCores = 0;
                        }
                    }
                    if (now >= intervalEnd)
                    {
                        if (intervalCount > 0)
                        {
                            var average = intervalSum / intervalCount * (1 + (random.NextDouble() - 0.5) * 0.06);
                            var percent = Math.Round(Math.Clamp(average / MaxVCores * 100, 0, 100), 2);
                            samples.Add(new ServerlessCpuSample(intervalEnd, percent, MaxVCores));
                        }
                        intervalSum = 0;
                        intervalCount = 0;
                        intervalEnd += Interval;
                    }
                }
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
