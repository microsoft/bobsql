using CaldovaNetworkScheduling.Models;

namespace CaldovaNetworkScheduling.Services;

public sealed record PoolPresentationSnapshot(bool Running, double Seconds, NetworkResources Resources,
    IReadOnlyList<PoolClinicReading> Clinics);

public sealed class PoolPresentation(IConfiguration configuration, TimeProvider clock)
{
    public const double DurationSeconds = 30;
    private long? started;
    private double stoppedSeconds;
    private int capacity = 24;
    public bool Enabled => configuration.GetValue<bool>("PoolPresentation:Enabled");
    private double Seconds => Math.Min(DurationSeconds, started is { } at
        ? clock.GetElapsedTime(at).TotalSeconds : stoppedSeconds);

    public PoolPresentationSnapshot Snapshot
    {
        get
        {
            var seconds = Seconds;
            var caldovaUsed = 18 + 2.1 * Math.Min(seconds / 16, 1);
            if (caldovaUsed > 20 || seconds >= DurationSeconds)
            {
                started = null;
                stoppedSeconds = seconds;
            }
            var running = started is not null;
            var rise = Math.Clamp((seconds - 1) / 8, 0, 1);
            var shift = Math.Clamp((seconds - 9) / 3, 0, 1);
            var finish = Math.Clamp((seconds - 12) / 3, 0, 1);
            var factors = new[] { 1.0, 0.92, 0.98 };
            double[] demands = seconds == 0 && !running ? [0, 0, 0] :
                [2 + 10 * rise, 2 + 4 * rise - 2 * shift + 3 * finish, 2 + 2 * rise + 2 * shift - finish];
            var maximum = Math.Min(capacity, PoolScaler.PerDatabaseMaxVCores);
            var scale = demands.Sum() > capacity ? capacity / demands.Sum() : 1;
            var cpus = demands.Select(value => Math.Round(value * scale, MidpointRounding.AwayFromZero)).ToArray();
            var total = Math.Round(Math.Min(demands.Sum(), capacity), MidpointRounding.AwayFromZero);
            // Whole-core card readings must also fit within the selected pool capacity.
            while (cpus.Sum() > total)
            {
                var index = Enumerable.Range(0, cpus.Length).MaxBy(index => cpus[index] - demands[index] * scale);
                cpus[index]--;
            }
            while (cpus.Sum() < total)
            {
                var index = Enumerable.Range(0, cpus.Length).Where(index => cpus[index] < maximum)
                    .MaxBy(index => demands[index] * scale - cpus[index]);
                cpus[index]++;
            }
            var at = clock.GetUtcNow();
            var clinics = ProviderProfiles.All.Select((provider, index) =>
            {
                var cpu = cpus[index];
                var used = provider.Key == "caldova" ? caldovaUsed : PoolStorage.SeedTarget(provider.Key);
                var allocated = provider.Key == "caldova" && used > 20 ? 30 : 20;
                var initial = new DatabaseStorage(provider.Key, at,
                    PoolStorage.SeedTarget(provider.Key) * DatabaseStorage.GiB, 20L * DatabaseStorage.GiB);
                return new PoolClinicReading(provider.Key,
                    new(running, maximum, (long)(seconds * 1100 * factors[index]), 0, null, null, null,
                        (int)cpu),
                    [new ServerlessCpuSample(at, cpu * 100 / maximum, maximum)],
                    new(provider.Key, at, (long)(used * DatabaseStorage.GiB), allocated * DatabaseStorage.GiB),
                    initial);
            }).ToArray();
            var resources = new NetworkResources("caldova-network-rg", "Caldova network", "caldova-network-pool",
                "", "Hyperscale", "Gen5", "Ready", capacity, 0, maximum,
                ProviderProfiles.All.Select(provider => new NetworkDatabaseResource(provider.Database, "Online",
                    "ElasticPool", "caldova-network-pool")).ToArray(), IsPlayback: true);
            return new(running, seconds, resources, clinics);
        }
    }

    public void Start()
    {
        RequireEnabled();
        if (started is not null) throw new InvalidOperationException("Stop the current presentation before starting another.");
        stoppedSeconds = 0;
        started = clock.GetTimestamp();
    }
    public void Stop() { stoppedSeconds = Seconds; started = null; }
    public void SetCapacity(int value)
    {
        RequireEnabled();
        if (value is not (8 or 24)) throw new ArgumentOutOfRangeException(nameof(value), "Use 8 or 24 vCores.");
        capacity = value;
    }
    private void RequireEnabled()
    {
        if (!Enabled) throw new InvalidOperationException("Pool presentation is disabled on this host.");
    }
}
