using Azure.Identity;
using CaldovaNetworkScheduling.Models;

namespace CaldovaNetworkScheduling.Services;

public static class StorageFillCommand
{
    public static async Task RunAsync()
    {
        var configuration = new ConfigurationBuilder().AddEnvironmentVariables().Build();
        if (!configuration.GetValue<bool>("StorageFill:Approved") || configuration.GetValue<bool>("Demo:Playback"))
            throw new InvalidOperationException("Use the explicit Grow storage-seeding script to authorize the initial fill.");
        using var closing = new CancellationTokenSource();
        Console.CancelKeyPress += (_, e) => { e.Cancel = true; closing.Cancel(); };
        using var logging = LoggerFactory.Create(builder => builder.AddSimpleConsole(options => options.SingleLine = true));
        var credential = new AzureCliCredential();
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
        var monitor = new NetworkResourceMonitor(http, credential, configuration);
        var target = NetworkResourceMonitor.Target(configuration);
        var cli = new AzureCliRunner();
        var current = await cli.RunAsync(["account", "show", "--query", "id", "--output", "tsv"], closing.Token);
        if (!current.Equals(target.Subscription, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Current Azure CLI subscription does not match the approved storage target.");
        PoolScaler.ValidatePool(await monitor.ReadAsync(closing.Token));
        using var storage = new PoolStorage(configuration, credential, logging.CreateLogger<PoolStorage>());
        foreach (var provider in ProviderProfiles.All) await storage.SetupAsync(provider, closing.Token);
        await SeedAsync(storage, closing.Token);
        Console.WriteLine("Initial storage fill verified. No scheduling rows, pool configuration, servers, or preview settings were changed.");
    }

    public static async Task SeedAsync(PoolStorage storage, CancellationToken token)
    {
        using var closing = CancellationTokenSource.CreateLinkedTokenSource(token);
        await Task.WhenAll(ProviderProfiles.All.Select(async provider =>
        {
            try
            {
                var goal = PoolStorage.SeedTarget(provider.Key);
                var nextReport = 0.0;
                var final = await storage.FillToAsync(provider, goal, reading =>
                {
                    if (reading.UsedGiB >= nextReport || reading.UsedGiB >= goal)
                    {
                        Console.WriteLine($"{provider.Database}: {reading.UsedGiB:F3} / {goal} GiB used; {reading.AllocatedGiB:F3} GiB allocated");
                        nextReport = Math.Floor(reading.UsedGiB) + 1;
                    }
                }, TimeSpan.FromHours(2), closing.Token);
                Console.WriteLine($"VERIFIED {provider.Database}: {final.UsedGiB:F3} GiB used; {final.AllocatedGiB:F3} GiB allocated.");
            }
            catch
            {
                closing.Cancel();
                throw;
            }
        }));
        PoolStorage.ValidateSeeded(await storage.ReadAllAsync(closing.Token));
    }
}
