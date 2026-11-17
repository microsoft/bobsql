using Azure.Identity;
using CaldovaNetworkScheduling.Models;

namespace CaldovaNetworkScheduling.Services;

public static class PoolRehearsalCommand
{
    public static async Task RunAsync()
    {
        var configuration = new ConfigurationBuilder().AddEnvironmentVariables().Build();
        if (!configuration.GetValue<bool>("PoolRehearsal:Approved")
            || configuration.GetValue<bool>("Demo:Playback") || configuration.GetValue<bool>("PoolPresentation:Enabled"))
            throw new InvalidOperationException("Use the approved real-pool rehearsal script, not presentation mode.");
        using var closing = new CancellationTokenSource(TimeSpan.FromMinutes(5));
        ConsoleCancelEventHandler cancel = (_, e) => { e.Cancel = true; closing.Cancel(); };
        Console.CancelKeyPress += cancel;
        try
        {
            using var logging = LoggerFactory.Create(builder => builder.AddSimpleConsole(options => options.SingleLine = true));
            var credential = new AzureCliCredential();
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
            var monitor = new NetworkResourceMonitor(http, credential, configuration);
            var target = NetworkResourceMonitor.Target(configuration);
            var current = await new AzureCliRunner().RunAsync(["account", "show", "--query", "id", "--output", "tsv"], closing.Token);
            if (!current.Equals(target.Subscription, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Current CLI subscription does not match the approved rehearsal target.");
            PoolScaler.ValidatePool(await monitor.ReadAsync(closing.Token));
            using var storage = new PoolStorage(configuration, credential, logging.CreateLogger<PoolStorage>());
            var before = await storage.ReadAllAsync(closing.Token);
            if (storage.GrowthEnabled) ValidateGrowthStart(before);
            await using var scheduling = new PoolScheduling(monitor, new(configuration, logging, storage), configuration,
                new Lifetime(closing), logging.CreateLogger<PoolScheduling>(), storage);
            var lastCpu = new Dictionary<string, DateTimeOffset>();
            var peaks = ProviderProfiles.All.ToDictionary(provider => provider.Key, _ => 0.0);
            DatabaseStorage? lastStorage = null;
            try
            {
                await scheduling.StartAsync();
                while (true)
                {
                    var state = scheduling.State;
                    foreach (var clinic in state.Clinics)
                    {
                        if (clinic.Samples.LastOrDefault() is { } cpu && lastCpu.GetValueOrDefault(clinic.Key) != cpu.At)
                        {
                            lastCpu[clinic.Key] = cpu.At;
                            peaks[clinic.Key] = Math.Max(peaks[clinic.Key], cpu.UsedVCores);
                            Console.WriteLine($"{cpu.At:O} {clinic.Key}: {cpu.UsedVCores:F3} CPU-used vCores; {clinic.Workload.Completed} successful queries.");
                        }
                        if (clinic.Key == "caldova" && clinic.Storage is { } size
                            && (lastStorage is null || lastStorage.UsedBytes != size.UsedBytes
                                || lastStorage.AllocatedBytes != size.AllocatedBytes))
                        {
                            lastStorage = size;
                            Console.WriteLine($"{size.At:O} Caldova: {size.UsedGiB:F3} GiB used / {size.AllocatedGiB:F3} GiB allocated.");
                        }
                    }
                    if (!state.Running) break;
                    await Task.Delay(TimeSpan.FromSeconds(1), closing.Token);
                }
                if (scheduling.State.Error is { } error) throw new InvalidOperationException(error);
                var after = await storage.ReadAllAsync(closing.Token);
                if (storage.GrowthEnabled) ValidateGrowthResult(before, after);
                foreach (var provider in ProviderProfiles.All)
                {
                    if (!lastCpu.ContainsKey(provider.Key))
                        throw new InvalidOperationException($"No SQL CPU measurement was captured for {provider.Name}.");
                    if (scheduling.State.Clinics.Single(clinic => clinic.Key == provider.Key).Workload.Completed <= 0)
                        throw new InvalidOperationException($"No successful scheduling query was captured for {provider.Name}.");
                    Console.WriteLine($"Measured peak {provider.Name}: {peaks[provider.Key]:F3} CPU-used vCores.");
                }
                Console.WriteLine(storage.GrowthEnabled
                    ? "VERIFIED real scheduling activity and Caldova allocation increase. No reset, booking, or compute-scale operation was performed."
                    : "VERIFIED real scheduling activity. No storage insert, booking, reset, or compute-scale operation was performed.");
            }
            finally { await scheduling.StopAsync(); }
        }
        finally { Console.CancelKeyPress -= cancel; }
    }

    public static void ValidateGrowthStart(IReadOnlyList<DatabaseStorage> readings)
    {
        PoolStorage.ValidateSeeded(readings);
        var caldova = readings.Single(reading => reading.Key == "caldova");
        if (caldova.AllocatedBytes != 20L * DatabaseStorage.GiB || PoolScheduling.GrowthConfirmed(caldova))
            throw new InvalidOperationException("A fresh allocation-growth rehearsal requires Caldova at 20 GiB allocated. Approve a separate reset first.");
    }

    public static void ValidateGrowthResult(IReadOnlyList<DatabaseStorage> before, IReadOnlyList<DatabaseStorage> after)
    {
        ValidateGrowthStart(before);
        var first = before.Single(reading => reading.Key == "caldova");
        var final = after.Single(reading => reading.Key == "caldova");
        if (!PoolScheduling.GrowthConfirmed(final) || final.AllocatedBytes <= first.AllocatedBytes)
            throw new InvalidOperationException($"Real allocation growth was not confirmed: {final.UsedGiB:F3} GiB used / {final.AllocatedGiB:F3} GiB allocated. Committed data remains.");
    }

    private sealed class Lifetime(CancellationTokenSource closing) : IHostApplicationLifetime
    {
        public CancellationToken ApplicationStarted => CancellationToken.None;
        public CancellationToken ApplicationStopping => closing.Token;
        public CancellationToken ApplicationStopped => CancellationToken.None;
        public void StopApplication() => closing.Cancel();
    }
}
