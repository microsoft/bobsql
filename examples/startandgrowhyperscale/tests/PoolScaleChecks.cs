using CaldovaNetworkScheduling.Components.Pages;
using CaldovaNetworkScheduling.Services;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging.Abstractions;
using System.Reflection;

internal static class PoolScaleChecks
{
    public static async Task RunAsync(Action<bool, string> check, IConfiguration source)
    {
        var id = source["ServerlessMonitor:ResourceId"]!;
        var parts = id.Split('/', StringSplitOptions.RemoveEmptyEntries);
        var settings = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["ServerlessMonitor:ResourceId"] = id, ["PoolScaling:Enabled"] = "true",
            ["ConnectionStrings:Scheduling"] = $"Server=tcp:{parts[7]}.database.windows.net,1433;Initial Catalog=caldova-scheduling;Encrypt=True"
        }).Build();
        settings["urls"] = "http://localhost:5099";
        PoolScaler.ValidateHost(settings);
        check(true, "Live scaling can be enabled on an explicitly loopback-bound app");
        foreach (var url in new[] { "http://0.0.0.0:5099", "http://*:5099", "https://example.com", "http://localhost:5099;http://0.0.0.0:80", "" })
        {
            settings["urls"] = url;
            var rejected = false;
            try { PoolScaler.ValidateHost(settings); }
            catch (InvalidOperationException) { rejected = true; }
            check(rejected, "Public or unspecified app bindings cannot enable live Azure CLI scaling");
        }
        settings["urls"] = "http://localhost:5099";
        var (monitor, handler) = NetworkResourceChecks.Create(settings);
        var cli = new Cli(handler, parts[1]);
        var scaler = new PoolScaler(cli, monitor, settings, new Lifetime(), NullLogger<PoolScaler>.Instance);
        var page = new PoolScale();
        Set(page, "Resources", monitor);
        Set(page, "Scaler", scaler);
        var storage = new StorageChecks.Fake(settings);
        Set(page, "Storage", storage);
        await using var scheduling = new PoolScheduling(monitor,
            new PoolClinicClientFactory(settings, NullLoggerFactory.Instance, storage), settings,
            new Lifetime(), NullLogger<PoolScheduling>.Instance, storage);
        Set(page, "Scheduling", scheduling);
        Set(page, "Logger", NullLogger<PoolScale>.Instance);
        await (Task)typeof(PoolScale).GetMethod("LoadResourcesAsync", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(page, null)!;
        check(CanScale(page, 24) && !CanScale(page, 8), "At eight cores only the scale-to-24 button is enabled");
        cli.Hold = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var scale = scaler.ScaleAsync(24);
        check(scaler.State.Running && scaler.State.Target == 24 && !CanScale(page, 8) && !CanScale(page, 24),
            "Both buttons are disabled while a real scale command is pending");
        var duplicateRejected = false;
        try { await scaler.ScaleAsync(8); }
        catch (InvalidOperationException) { duplicateRejected = true; }
        check(duplicateRejected && cli.Updates.Count == 1, "A second page cannot launch a concurrent scale");
        cli.Hold.SetResult();
        await scale;
        var update = cli.Updates.Single();
        check(update.Take(3).SequenceEqual(["sql", "elastic-pool", "update"])
            && Value(update, "--capacity") == "24"
            && Value(update, "--subscription") == parts[1] && Value(update, "--resource-group") == parts[3]
            && Value(update, "--server") == parts[7] && Value(update, "--name") == "caldova-network-pool"
            && Value(update, "--db-min-capacity") == "0" && Value(update, "--db-max-capacity") == "12"
            && !update.Contains("--no-wait"),
            "Scale pins the exact CLI target, waits for completion, and sets the 24-core pool's per-database cap to twelve");
        check(!scaler.State.Running && scaler.State.Error is null && handler.Capacity == 24 && handler.MaxPerDatabase == 12,
            "Success requires independently verified 24-core ARM capacity and twelve-core per-database limit");
        cli.Hold = null;
        await (Task)typeof(PoolScale).GetMethod("ScaleAsync", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(page, [8])!;
        var refreshed = (NetworkResources)typeof(PoolScale).GetField("resources", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(page)!;
        check(refreshed.VCores == 8 && cli.Updates.Count == 2 && Value(cli.Updates[1], "--capacity") == "8"
            && Value(cli.Updates[1], "--db-max-capacity") == "8" && refreshed.MaxVCoresPerDatabase == 8
            && CanScale(page, 24) && !CanScale(page, 8),
            "The page's scale-back handler executes once and refreshes all shared-capacity cards to eight");
        await scaler.ScaleAsync(8);
        check(cli.Updates.Count == 2, "Already-at-target clicks make no Azure update");
        cli.Subscription = Guid.NewGuid().ToString();
        await MustFailAsync(check, () => scaler.ScaleAsync(24), "A different current CLI subscription blocks submission");
        check(cli.Updates.Count == 2, "Subscription mismatch never submits a mutation");
        cli.Subscription = parts[1];
        handler.Standalone = true;
        await MustFailAsync(check, () => scaler.ScaleAsync(24), "All three providers must be Online in the same pool before scaling");
        check(cli.Updates.Count == 2, "Mixed membership blocks submission");
        handler.Standalone = false;
        cli.Fail = true;
        await MustFailAsync(check, () => scaler.ScaleAsync(24), "A CLI failure remains an explicit error, with no retry or success claim");
        check(scaler.State.Error is not null && !scaler.State.Error.Contains(parts[1]) && !scaler.State.Running,
            "CLI failure resets busy state and redacts Azure IDs in the displayed error");
        cli.Fail = false;
        cli.IgnoreUpdate = true;
        await MustFailAsync(check, () => scaler.ScaleAsync(24), "CLI exit zero alone is not sufficient without verified final capacity");
        settings["PoolScaling:Enabled"] = "false";
        var count = cli.Updates.Count;
        await MustFailAsync(check, () => scaler.ScaleAsync(24), "Scaling is opt-in and disabled hosts cannot execute it");
        check(cli.Updates.Count == count, "Disabled hosts launch no command");
        settings["PoolScaling:Enabled"] = "true";
        var invalidRejected = false;
        try { await scaler.ScaleAsync(16); }
        catch (ArgumentOutOfRangeException) { invalidRejected = true; }
        check(invalidRejected && cli.Updates.Count == count, "Only the requested eight and 24 targets are accepted");
        settings["Demo:Playback"] = "true";
        check(!scaler.Enabled, "Playback cannot run a live scale command");
        settings["Demo:Playback"] = "false";
        cli.IgnoreUpdate = false;
        cli.Hold = new(TaskCreationOptions.RunContinuationsAsynchronously);
        using var shutdown = new CancellationTokenSource();
        var interrupted = new PoolScaler(cli, monitor, settings, new Lifetime(shutdown.Token), NullLogger<PoolScaler>.Instance);
        var pendingScale = interrupted.ScaleAsync(24);
        shutdown.Cancel();
        await MustFailAsync(check, () => pendingScale, "Host shutdown reports an unconfirmed scale, not success");
        check(!interrupted.State.Running && interrupted.State.Error!.Contains("may still be running"),
            "Interrupted scale monitoring explicitly warns that Azure may still be applying the operation");
        cli.Hold = null;
        handler.Capacity = 24;
        handler.MaxPerDatabase = 8;
        await (Task)typeof(PoolScale).GetMethod("LoadResourcesAsync", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(page, null)!;
        check(CanScale(page, 24), "An existing 24-core pool with the legacy eight-core cap can explicitly apply the new policy");
        await scaler.ScaleAsync(24);
        check(handler.Capacity == 24 && handler.MaxPerDatabase == 12,
            "An already-24-core pool still updates and verifies its per-database cap");
        var beforeInvalid = cli.Updates.Count;
        handler.MaxPerDatabase = 24;
        await MustFailAsync(check, () => scaler.ScaleAsync(8), "Unexpected full-pool per-database limits require separate inspection");
        handler.Capacity = 8;
        handler.MaxPerDatabase = 12;
        await MustFailAsync(check, () => scaler.ScaleAsync(24), "A per-database cap above pool capacity is rejected");
        check(cli.Updates.Count == beforeInvalid, "Invalid source limits never submit a scale");
        handler.MaxPerDatabase = 8;
        cli.IgnorePerDatabaseUpdate = true;
        await MustFailAsync(check, () => scaler.ScaleAsync(24), "Verified pool capacity alone is insufficient when the twelve-core cap was not applied");
        await page.DisposeAsync();
    }

    private static bool CanScale(PoolScale page, int capacity) => (bool)typeof(PoolScale)
        .GetMethod("CanScale", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(page, [capacity])!;
    private static void Set(PoolScale page, string property, object value) =>
        typeof(PoolScale).GetProperty(property, BindingFlags.NonPublic | BindingFlags.Instance)!.SetValue(page, value);
    private static string Value(IReadOnlyList<string> args, string name) => args[args.ToList().IndexOf(name) + 1];
    private static async Task MustFailAsync(Action<bool, string> check, Func<Task> action, string message)
    {
        var failed = false;
        try { await action(); }
        catch (InvalidOperationException) { failed = true; }
        check(failed, message);
    }

    private sealed class Cli(NetworkResourceChecks.ResourceHandler handler, string subscription) : IAzureCliRunner
    {
        public string Subscription { get; set; } = subscription;
        public List<string[]> Updates { get; } = [];
        public TaskCompletionSource? Hold { get; set; }
        public bool Fail { get; set; }
        public bool IgnoreUpdate { get; set; }
        public bool IgnorePerDatabaseUpdate { get; set; }
        public async Task<string> RunAsync(IReadOnlyList<string> arguments, CancellationToken token)
        {
            if (arguments[0] == "account") return Subscription;
            Updates.Add(arguments.ToArray());
            if (Hold is { } hold) await hold.Task.WaitAsync(token);
            if (Fail) throw new InvalidOperationException($"CLI denied resource in subscription {Subscription}");
            if (!IgnoreUpdate)
            {
                handler.Capacity = int.Parse(Value(arguments, "--capacity"));
                if (!IgnorePerDatabaseUpdate)
                    handler.MaxPerDatabase = int.Parse(Value(arguments, "--db-max-capacity"));
            }
            return "";
        }
    }

    internal sealed class Lifetime(CancellationToken stopping = default) : IHostApplicationLifetime
    {
        public CancellationToken ApplicationStarted => CancellationToken.None;
        public CancellationToken ApplicationStopping => stopping;
        public CancellationToken ApplicationStopped => CancellationToken.None;
        public void StopApplication() { }
    }
}
