using CaldovaNetworkScheduling.Components.Pages;
using CaldovaNetworkScheduling.Models;
using CaldovaNetworkScheduling.Services;
using Microsoft.AspNetCore.Components.Web;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

internal static class PoolPresentationChecks
{
    public static async Task RunAsync(Action<bool, string> check)
    {
        var settings = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["PoolPresentation:Enabled"] = "true", ["urls"] = "http://localhost:5099"
        }).Build();
        PoolScaler.ValidateHost(settings);
        var clock = new Clock();
        var scene = new PoolPresentation(settings, clock);
        double[] finalCores = [12, 7, 5];
        check(scene.Snapshot.Clinics.Select(clinic => clinic.Storage!.UsedGiB).SequenceEqual([18.0, 12.0, 15.0])
            && scene.Snapshot.Clinics.All(clinic => clinic.Samples[^1].UsedVCores == 0)
            && scene.Snapshot.Resources.IsPlayback, "Presentation starts at the synthetic baseline and never pretends its resource model is measured");
        scene.Start();
        check(scene.Snapshot.Running && scene.Snapshot.Clinics.All(clinic => Math.Ceiling(clinic.Samples[^1].UsedVCores) == 2),
            "The presentation starts every database at two displayed CPU-used cores");
        clock.Seconds = 0.75;
        check(scene.Snapshot.Clinics.All(clinic => Math.Ceiling(clinic.Samples[^1].UsedVCores) == 2),
            "The first rendered frames stay at two cores instead of rounding immediately up to three");
        var earlier = scene.Snapshot.Clinics[0].Samples[^1].UsedVCores;
        foreach (var second in new[] { 2, 4, 6, 8, 10, 12 })
        {
            clock.Seconds = second;
            var cpu = scene.Snapshot.Clinics[0].Samples[^1].UsedVCores;
            check(cpu >= earlier && cpu <= 12, "Caldova demand rises gradually to its twelve-core cap without changing Azure compute");
            earlier = cpu;
        }
        clock.Seconds = 9;
        var beforeShift = scene.Snapshot.Clinics.Select(clinic => clinic.Samples[^1].UsedVCores).ToArray();
        clock.Seconds = 12;
        var afterShift = scene.Snapshot;
        check(beforeShift.SequenceEqual([12.0, 6.0, 4.0])
            && afterShift.Clinics.Select(clinic => clinic.Samples[^1].UsedVCores).SequenceEqual([12.0, 4.0, 6.0]),
            "Independent provider demand shifts instead of all databases converging to eight");
        check(afterShift.Resources.MinVCoresPerDatabase == 0 && afterShift.Resources.MaxVCoresPerDatabase == 12
            && afterShift.Clinics.All(clinic => clinic.Samples[^1].CpuLimit == 12),
            "The 24-core illustration models zero-to-twelve limits independently from CPU consumption");
        clock.Seconds = 15;
        check(scene.Snapshot.Running && scene.Snapshot.Clinics[0].Storage!.UsedGiB < 20
            && scene.Snapshot.Clinics[0].Storage!.AllocatedGiB == 20,
            "Allocation stays twenty until synthetic used space crosses twenty");
        clock.Seconds = 15.25;
        var expanded = scene.Snapshot;
        check(!expanded.Running && expanded.Seconds == 15.25
            && expanded.Clinics[0].Storage!.AllocatedGiB == 30
            && expanded.Clinics.Select(clinic => clinic.Samples[^1].UsedVCores).SequenceEqual(finalCores),
            "The first allocation-expansion frame stops with uneven twelve/seven/five-core readings");
        clock.Seconds = 16;
        check(scene.Snapshot.Clinics[0].Storage!.UsedGiB > 20 && scene.Snapshot.Clinics[0].Storage!.AllocatedGiB == 30
            && scene.Snapshot.Clinics.Skip(1).All(clinic => clinic.Storage!.AllocatedGiB == 20),
            "Only Caldova expands from twenty to thirty during the presentation");
        var (monitor, handler) = NetworkResourceChecks.Create(new ConfigurationBuilder().AddInMemoryCollection(
            new Dictionary<string, string?>
            {
                ["ServerlessMonitor:ResourceId"] = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.Sql/servers/test/databases/caldova-scheduling"
            }).Build());
        var services = new ServiceCollection().AddLogging().AddSingleton(scene).AddSingleton(monitor);
        await using (var provider = services.BuildServiceProvider())
        await using (var renderer = new HtmlRenderer(provider, provider.GetRequiredService<ILoggerFactory>()))
        {
            var markup = await renderer.Dispatcher.InvokeAsync(async () =>
                (await renderer.RenderComponentAsync<PoolPresentationPage>()).ToHtmlString());
            var text = System.Net.WebUtility.HtmlDecode(markup);
            check(text.Contains("20 → 30 GiB") && markup.Contains("storage-expansion")
                && !text.Contains("speed-up", StringComparison.OrdinalIgnoreCase)
                && !text.Contains("SQL samples", StringComparison.OrdinalIgnoreCase)
                && !text.Contains("15-second averages", StringComparison.OrdinalIgnoreCase),
                "The shared allocation highlight appears without a speed-up caption or false SQL-telemetry claim");
            check(System.Text.RegularExpressions.Regex.Matches(text, "Shared 24 vCores").Count == 3
                && System.Text.RegularExpressions.Regex.Matches(text, "Min 0 / Max 12 vCores per database").Count == 3,
                "Each card separates shared pool capacity from its zero-to-twelve database limits");
            async Task<string> NetworkAsync(bool live = false) => await renderer.Dispatcher.InvokeAsync(async () =>
                System.Net.WebUtility.HtmlDecode((await renderer.RenderComponentAsync<Verify>(
                    Microsoft.AspNetCore.Components.ParameterView.FromDictionary(
                        new Dictionary<string, object?> { ["Live"] = live }))).ToHtmlString()));
            handler.Failure = "Denied";
            foreach (var capacity in new[] { 8, 24, 8 })
            {
                scene.SetCapacity(capacity);
                var network = await NetworkAsync();
                check(System.Text.RegularExpressions.Regex.Matches(network, $"Shared {capacity} vCores").Count == 3
                    && System.Text.RegularExpressions.Regex.Matches(network,
                        $"Min 0 / Max {Math.Min(capacity, 12)} vCores per database").Count == 3
                    && !network.Contains("Recording illustration") && !network.Contains("Inspect live Azure resources")
                    && !network.Contains("playback", StringComparison.OrdinalIgnoreCase) && handler.Requests.Count == 0,
                    "Network shares recording capacity and limits across navigation without Azure reads or fallback");
            }
            scene.SetCapacity(24);
            handler.Failure = null;
            var liveNetwork = await NetworkAsync(live: true);
            check(liveNetwork.Contains("Shared 8 vCores") && !liveNetwork.Contains("Recording illustration")
                && handler.Requests.Count == 4,
                "Explicit live inspection ignores recording capacity and performs the original Azure reads");
            settings["PoolPresentation:Enabled"] = "false";
            var realNetwork = await NetworkAsync();
            check(realNetwork.Contains("Shared 8 vCores") && !realNetwork.Contains("Recording illustration")
                && handler.Requests.Count == 8,
                "With presentation disabled Network retains real resource inspection");
            settings["PoolPresentation:Enabled"] = "true";
        }
        clock.Seconds = 29;
        check(!scene.Snapshot.Running && scene.Snapshot.Clinics.Select(clinic => clinic.Samples[^1].UsedVCores).SequenceEqual(finalCores),
            "Presentation CPU keeps its unequal readings after the allocation-expansion ending");
        clock.Seconds = 30;
        check(!scene.Snapshot.Running && scene.Snapshot.Seconds == expanded.Seconds
            && scene.Snapshot.Clinics.Select(clinic => clinic.Samples[^1].UsedVCores).SequenceEqual(finalCores)
            && scene.Snapshot.Clinics.All(clinic => clinic.Samples[^1].UsedVCores == clinic.Workload.Active)
            && scene.Snapshot.Clinics[0].Storage!.AllocatedGiB == 30,
            "The presentation stays stopped at the growth event instead of continuing to thirty seconds");
        var completed = scene.Snapshot;
        clock.Seconds = 45;
        check(!scene.Snapshot.Running && scene.Snapshot.Seconds == expanded.Seconds
            && scene.Snapshot.Clinics.Select(clinic => clinic.Samples[^1].UsedVCores).SequenceEqual(finalCores)
            && scene.Snapshot.Clinics.All(clinic => clinic.Samples[^1].UsedVCores == clinic.Workload.Active)
            && scene.Snapshot.Clinics[0].Storage!.UsedBytes == completed.Clinics[0].Storage!.UsedBytes
            && scene.Snapshot.Clinics[0].Storage!.AllocatedBytes == completed.Clinics[0].Storage!.AllocatedBytes,
            "The completed presentation keeps its final unequal CPU and storage readings after time advances");
        scene.Start();
        check(scene.Snapshot.Clinics[0].Storage!.UsedGiB == 18 && scene.Snapshot.Clinics[0].Storage!.AllocatedGiB == 20,
            "Another presentation take resets only the in-memory scene, never a SQL database");
        clock.Seconds += 2;
        scene.Stop();
        var frozen = scene.Snapshot;
        clock.Seconds += 3;
        check(!scene.Snapshot.Running && scene.Snapshot.Seconds == frozen.Seconds
            && scene.Snapshot.Clinics.Select(clinic => clinic.Samples[^1].UsedVCores)
                .SequenceEqual(frozen.Clinics.Select(clinic => clinic.Samples[^1].UsedVCores)),
            "Stop freezes both the presentation clock and displayed CPU readings");
        scene.SetCapacity(8);
        scene.Start();
        clock.Seconds += 12;
        check(scene.Snapshot.Clinics.Sum(clinic => Math.Ceiling(clinic.Samples[^1].UsedVCores)) == 8,
            "Rounded card readings agree with the eight-core pool header at peak");
        check(scene.Snapshot.Resources.MaxVCoresPerDatabase == 8
            && scene.Snapshot.Clinics.Select(clinic => clinic.Samples[^1].UsedVCores).SequenceEqual([4.0, 2.0, 2.0]),
            "The eight-core pool has an eight-core database cap but unequal shared consumption");
        scene.SetCapacity(24);
        check(scene.Snapshot.Running && scene.Snapshot.Seconds == 12
            && scene.Snapshot.Clinics.Select(clinic => clinic.Samples[^1].UsedVCores).SequenceEqual([12.0, 4.0, 6.0]),
            "Pool scaling during the presentation changes sharing without restarting scheduling or growth");
        scene.SetCapacity(8);
        scene.Stop();
        scene.Start();
        var startedAt = clock.Seconds;
        var bounded = true;
        for (var second = 0.0; second <= 30; second += 0.25)
        {
            clock.Seconds = startedAt + second;
            var clinics = scene.Snapshot.Clinics;
            bounded &= clinics.Sum(clinic => Math.Ceiling(clinic.Samples[^1].UsedVCores)) <= 8
                && clinics.All(clinic => clinic.Samples[^1].UsedVCores is >= 0 and <= 8);
        }
        check(bounded, "Displayed cores stay inside pool and per-database limits throughout the eight-core scene");
        scene.Stop();
        scene.SetCapacity(24);
        scene.Start();
        startedAt = clock.Seconds;
        bounded = true;
        for (var second = 0.0; second <= 30; second += 0.25)
        {
            clock.Seconds = startedAt + second;
            var frame = scene.Snapshot;
            bounded &= frame.Clinics.Sum(clinic => Math.Ceiling(clinic.Samples[^1].UsedVCores)) <= 24
                && frame.Clinics.All(clinic => clinic.Samples[^1].UsedVCores is >= 0 and <= 12
                    && Math.Ceiling(clinic.Samples[^1].UsedVCores) == clinic.Workload.Active);
        }
        check(bounded, "Displayed whole-core CPU stays within the 24-core pool and twelve-core database cap for the full scene");
        scene.Stop();
        settings["urls"] = "http://0.0.0.0:5099";
        var rejected = false;
        try { PoolScaler.ValidateHost(settings); } catch (InvalidOperationException) { rejected = true; }
        check(rejected, "The presentation opt-in is restricted to localhost");
        settings["PoolPresentation:Enabled"] = "false";
        rejected = false;
        try { scene.Start(); } catch (InvalidOperationException) { rejected = true; }
        check(rejected, "Disabled hosts cannot start a presentation");
        await using (var provider = services.BuildServiceProvider())
        await using (var renderer = new HtmlRenderer(provider, provider.GetRequiredService<ILoggerFactory>()))
        {
            var markup = await renderer.Dispatcher.InvokeAsync(async () =>
                (await renderer.RenderComponentAsync<PoolPresentationPage>()).ToHtmlString());
            check(markup.Contains("disabled on this host") && !markup.Contains("provider-stats")
                && !markup.Contains("storage-expansion"),
                "Disabled hosts render no illustrative metrics or storage allocation");
        }
        var baseline = ProviderProfiles.All.Select(provider => new DatabaseStorage(provider.Key, DateTimeOffset.UtcNow,
            PoolStorage.SeedTarget(provider.Key) * DatabaseStorage.GiB, 20L * DatabaseStorage.GiB)).ToArray();
        var grown = baseline.Select(reading => reading.Key == "caldova"
            ? reading with { UsedBytes = 20L * DatabaseStorage.GiB + 8192, AllocatedBytes = 30L * DatabaseStorage.GiB }
            : reading).ToArray();
        PoolRehearsalCommand.ValidateGrowthResult(baseline, grown);
        check(true, "The separate real proof accepts actual used-space and allocation increases");
        rejected = false;
        try { PoolRehearsalCommand.ValidateGrowthResult(baseline, baseline); } catch (InvalidOperationException) { rejected = true; }
        check(rejected, "The real proof refuses to report success from an unchanged allocation");
        rejected = false;
        try { PoolRehearsalCommand.ValidateGrowthStart(grown); } catch (InvalidOperationException) { rejected = true; }
        check(rejected, "An already-expanded real database requires separate reset approval, not automatic deletion or replay");
    }

    private sealed class Clock : TimeProvider
    {
        public double Seconds { get; set; }
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override long GetTimestamp() => (long)(Seconds * TimeSpan.TicksPerSecond);
        public override DateTimeOffset GetUtcNow() => DateTimeOffset.UnixEpoch.AddSeconds(Seconds);
    }
}
