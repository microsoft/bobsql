using CaldovaNetworkScheduling.Components.Pages;
using CaldovaNetworkScheduling.Components;
using CaldovaNetworkScheduling.Models;
using CaldovaNetworkScheduling.Services;
using Microsoft.AspNetCore.Components.Web;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using System.Reflection;

internal static class PoolSchedulingChecks
{
    public static async Task RunAsync(Action<bool, string> check, IConfiguration source)
    {
        var id = source["ServerlessMonitor:ResourceId"]!;
        var parts = id.Split('/', StringSplitOptions.RemoveEmptyEntries);
        var settings = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["ServerlessMonitor:ResourceId"] = id,
            ["PoolScaling:Enabled"] = "true",
            ["ConnectionStrings:Scheduling"] = $"Server=tcp:{parts[7]}.database.windows.net,1433;Initial Catalog=caldova-scheduling;Encrypt=True"
        }).Build();
        var (monitor, handler) = NetworkResourceChecks.Create(settings);
        var factory = new Clients(settings);
        var storage = new StorageChecks.Fake(settings);
        await using var scheduling = new PoolScheduling(monitor, factory, settings,
            new PoolScaleChecks.Lifetime(), NullLogger<PoolScheduling>.Instance, storage);
        var ramps = ProviderProfiles.All.Select(provider => PoolScheduling.Ramp(provider.Key)).ToArray();
        foreach (var ramp in ramps) ramp.Validate();
        check(ramps.Select(ramp => ramp.PeakWorkers).SequenceEqual([9, 9, 9])
            && ramps.Select(ramp => ramp.Total.TotalSeconds).SequenceEqual([45, 45, 45])
            && ramps.Max(ramp => ramp.Total) + PoolScheduling.ObservationCooldown == TimeSpan.FromSeconds(60)
            && PoolScheduling.GrowthLimit + PoolScheduling.ObservationCooldown == TimeSpan.FromSeconds(60)
            && PoolScheduling.ObservationCooldown == TimeSpan.FromSeconds(15),
            "Gradual nine-worker schedules target the existing eight-core limits within a 60-second plan including DMV cooldown");
        check(ramps.Select(ramp => ramp.ActiveAt(TimeSpan.Zero)).SequenceEqual([2, 2, 2])
            && ramps.All(ramp => ramp.WorkersPerStep == 2 && ramp.WorkersPerStepDown == 3
                && ramp.PeakAt == TimeSpan.FromSeconds(20))
            && ramps.All(ramp => ramp.ActiveAt(TimeSpan.FromSeconds(20)) == ramp.PeakWorkers)
            && ramps.All(ramp => ramp.ActiveAt(ramp.Total) == 0),
            "Every clinic starts two workers and takes four smaller five-second steps to reach its peak");
        check(ramps.All(ramp => ramp.InitialWorkers <= ramp.PeakWorkers * 0.3
            && ramp.ActiveAt(TimeSpan.FromSeconds(5)) < ramp.ActiveAt(TimeSpan.FromSeconds(10))
            && ramp.ActiveAt(TimeSpan.FromSeconds(10)) < ramp.ActiveAt(TimeSpan.FromSeconds(15))
            && ramp.ActiveAt(TimeSpan.FromSeconds(15)) < ramp.ActiveAt(TimeSpan.FromSeconds(20))),
            "Every clinic starts below thirty percent of peak workers and keeps rising through the first SQL sample interval");
        check(ramps.All(ramp => Enumerable.Range(0, 10).Select(step => ramp.ActiveAt(TimeSpan.FromSeconds(step * 5)))
                .SequenceEqual([2, 4, 6, 8, 9, 9, 9, 6, 3, 0])),
            "Each clinic rises in two-worker steps, holds, and falls to zero in three-worker steps at exact boundaries");
        var symmetric = ramps[0] with { WorkersPerStepDown = null };
        symmetric.Validate();
        check(symmetric.Total == TimeSpan.FromSeconds(55)
            && Enumerable.Range(0, symmetric.PeakWorkers).All(worker => symmetric.StartAt(worker) == ramps[0].StartAt(worker)),
            "Without a ramp-down override, the original symmetric grouping remains unchanged; the override affects only stopping");
        foreach (var workersPerStep in new[] { 0, 17 })
        {
            var invalid = ramps[0] with { WorkersPerStep = workersPerStep };
            var failed = false;
            try { invalid.Validate(); }
            catch (ArgumentOutOfRangeException) { failed = true; }
            check(failed, "Invalid worker group sizes fail before duration calculation");
        }
        foreach (var workersPerStepDown in new[] { 0, 17 })
        {
            var invalid = ramps[0] with { WorkersPerStepDown = workersPerStepDown };
            var failed = false;
            try { invalid.Validate(); }
            catch (ArgumentOutOfRangeException) { failed = true; }
            check(failed, "Invalid stopping group sizes fail explicitly before duration calculation");
        }
        check(ramps.All(ramp => Enumerable.Range(0, ramp.PeakWorkers)
            .All(worker => ramp.StopAt(worker) > ramp.StartAt(worker))),
            "Every immediate or ramped worker has a bounded positive runtime");
        foreach (var initial in new[] { 0, 13 })
        {
            var invalid = ramps[0] with { InitialWorkers = initial };
            var failed = false;
            try { invalid.Validate(); }
            catch (ArgumentOutOfRangeException) { failed = true; }
            check(failed, "An invalid immediate-worker count fails explicitly");
        }
        check(PoolClinicWorkload.SchedulingQuery.Contains("dbo.AppointmentSlot")
            && PoolClinicWorkload.SchedulingQuery.Contains("IsBooked = 0")
            && PoolClinicWorkload.SchedulingQuery.Contains("@openings = COUNT_BIG")
            && !PoolClinicWorkload.SchedulingQuery.Contains("INSERT")
            && !PoolClinicWorkload.SchedulingQuery.Contains("UPDATE"),
            "Each worker reads actual scheduling openings without booking or growth writes");
        check(PoolClinicWorkload.CpuIterations == 100_000
            && PoolClinicWorkload.SchedulingBatch.Contains("DECLARE @remaining int = 100000;")
            && PoolClinicWorkload.SchedulingBatch.Contains("HASHBYTES('SHA2_256'")
            && PoolClinicWorkload.SchedulingBatch.IndexOf("@openings = COUNT_BIG", StringComparison.Ordinal)
                < PoolClinicWorkload.SchedulingBatch.IndexOf("SELECT @value", StringComparison.Ordinal)
            && ServerlessSqlWorkload.Query.Contains("DECLARE @remaining int = 50000;"),
            "Pool CPU batches are ten times smaller than the timeout-prone million-loop batch; Patient Access stays unchanged");
        var actual = new PoolClinicClientFactory(settings, NullLoggerFactory.Instance, storage);
        foreach (var provider in ProviderProfiles.All)
        {
            var client = actual.Create(provider);
            check(client.Target.ResourceId.EndsWith($"/databases/{provider.Database}")
                && client.Target.MaxVCores == 8 && client.Workload.Enabled,
                $"{provider.Key} client targets its own database, not the Caldova-only serverless monitor");
            var connectionString = new Microsoft.Data.SqlClient.SqlConnectionStringBuilder(settings.GetConnectionString("Scheduling"))
                { InitialCatalog = provider.Database }.ConnectionString;
            using var workerConnection = (Microsoft.Data.SqlClient.SqlConnection)typeof(PoolClinicWorkload)
                .GetMethod("CreateConnection", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(client.Workload, [connectionString])!;
            using var telemetryConnection = (Microsoft.Data.SqlClient.SqlConnection)typeof(PoolClinicTelemetry)
                .GetMethod("CreateConnection", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(client.Telemetry, [connectionString])!;
            using var storageConnection = storage.CreateSqlConnection(connectionString);
            check(workerConnection.AccessTokenCallback is not null
                && workerConnection.AccessTokenCallback == telemetryConnection.AccessTokenCallback
                && telemetryConnection.AccessTokenCallback == storageConnection.AccessTokenCallback
                && new Microsoft.Data.SqlClient.SqlConnectionStringBuilder(workerConnection.ConnectionString).Authentication
                    == Microsoft.Data.SqlClient.SqlAuthenticationMethod.NotSpecified,
                $"{provider.Key} workers, CPU observers, and storage share the same cached credential callback");
            check((int)typeof(PoolClinicTelemetry).GetProperty("CommandTimeoutSeconds", BindingFlags.Instance | BindingFlags.NonPublic)!
                    .GetValue(client.Telemetry)! == 30,
                $"{provider.Key} lightweight CPU observation allows 30 seconds under contention without retrying");
            await client.Workload.DisposeAsync();
        }
        await scheduling.StartAsync();
        check(scheduling.State.Running && scheduling.State.Clinics.Count == 3
            && scheduling.State.Clinics.All(clinic => clinic.Workload.Running && clinic.Samples.Count == 1)
            && scheduling.State.Clinics.Select(clinic => clinic.Workload.Active).SequenceEqual([2, 2, 2])
            && factory.Items.Values.All(client => client.Telemetry.Calls == 1),
            "Run starts and measures all three clinics independently");
        var rejected = false;
        try { await scheduling.StartAsync(); }
        catch (InvalidOperationException) { rejected = true; }
        check(rejected && factory.Created == 3, "A second window cannot start a concurrent scheduling run");
        var cpu = typeof(PoolActivityCards).GetMethod("Cpu", BindingFlags.Static | BindingFlags.NonPublic)!;
        check(scheduling.State.Clinics.Select(clinic => (string)cpu.Invoke(null, [clinic])!)
            .SequenceEqual(["2", "1", "3"]),
            "Provisioned CPU is whole-core ceiling of independent measured values");
        var totalCpu = typeof(PoolScale).GetMethod("PoolCpu", BindingFlags.Static | BindingFlags.NonPublic)!;
        check((string)totalCpu.Invoke(null, [scheduling.State])! == "5",
            "Pool usage sums raw clinic averages before whole-core rounding, not rounded card values or worker counts");
        var at = DateTimeOffset.UtcNow;
        var near24 = new PoolSchedulingState(false, at, null, ProviderProfiles.All.Select(provider =>
            new PoolClinicReading(provider.Key, new(false, 0, 0, 0, null, null, null),
                new ServerlessCpuSample[] { new(at, 99, 8) })).ToArray());
        check((string)totalCpu.Invoke(null, [near24])! == "24",
            "The total can show near-24 consumption only from measured near-eight averages on all three clinics");
        check((string)totalCpu.Invoke(null, [near24 with { Clinics = near24.Clinics.Take(2).ToArray() }])! == "–"
            && (string)totalCpu.Invoke(null, [near24 with { Clinics = near24.Clinics.Select((clinic, i) =>
                clinic with { Samples = new ServerlessCpuSample[] { new(at.AddSeconds(i * 20), 99, 8) } }).ToArray() }])! == "–",
            "A missing or misaligned clinic average cannot create a misleading pool total");
        check((string)cpu.Invoke(null, [new PoolClinicReading("test", new(false, 0, 0, 0, null, null, null), [])])! == "–"
            && (string)cpu.Invoke(null, [new PoolClinicReading("test", new(false, 0, 0, 0, null, null, null),
                new ServerlessCpuSample[] { new(DateTimeOffset.UtcNow, 0, 8) })])! == "0",
            "No measurement is missing, not fabricated as eight or zero; a real zero stays zero");
        var samples = scheduling.State.Clinics.Select(clinic => clinic.Samples).ToArray();
        await scheduling.StopAsync();
        check(!scheduling.State.Running && scheduling.State.Clinics.All(clinic => !clinic.Workload.Running)
            && scheduling.State.Finished is not null
            && scheduling.State.Clinics.Select(clinic => clinic.Samples).SequenceEqual(samples)
            && factory.Items.Values.All(client => client.Workload.Stops == 1),
            "Stop joins every workload and polling loop immediately while preserving samples");
        var page = new PoolScale();
        typeof(PoolScale).GetProperty("Scheduling", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(page, scheduling);
        check(scheduling.State.Clinics.Select(clinic => clinic.Storage!.UsedGiB).SequenceEqual([18.0, 12.0, 15.0])
            && storage.FillCalls == 0, "Disabled growth still displays actual storage and performs no inserts");
        await page.DisposeAsync();
        factory.FailKey = "northbrook";
        await scheduling.StartAsync();
        await scheduling.StopAsync();
        check(!scheduling.State.Running && scheduling.State.Error?.Contains("northbrook") == true
            && factory.Items.Values.All(client => client.Workload.Stops == 1)
            && factory.Items["northbrook"].Telemetry.Calls == 1,
            "One clinic's observation failure is explicit and stops all clinics without retries");
        factory.FailKey = null;
        factory.WorkloadFailure = "Execution Timeout Expired";
        await scheduling.StartAsync();
        await scheduling.StopAsync();
        check(scheduling.State.Error?.Contains("caldova CPU workload failed") == true
            && factory.Items["caldova"].Telemetry.Calls == 0,
            "A CPU batch timeout is identified as a worker failure, not mislabeled as an observation timeout");
        factory.WorkloadFailure = null;
        factory.OnRead = key => { if (key == "caldova") storage.FailRead = key; };
        await scheduling.StartAsync();
        await scheduling.StopAsync();
        check(scheduling.State.Error?.Contains("caldova storage observation failed") == true
            && scheduling.State.Clinics.Single(clinic => clinic.Key == "caldova").Samples.Count == 1,
            "A storage-read failure is identified separately and cannot discard an already measured CPU sample");
        factory.OnRead = null;
        storage.FailRead = null;
        var createdBeforePreflight = factory.Created;
        handler.Standalone = true;
        rejected = false;
        try { await scheduling.StartAsync(); }
        catch (InvalidOperationException) { rejected = true; }
        check(rejected && !scheduling.State.Running && factory.Created == createdBeforePreflight,
            "Mixed membership prevents SQL work and leaves an explicit startup error");
        handler.Standalone = false;
        var pending = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        handler.WaitForResponse = pending.Task;
        var startup = scheduling.StartAsync();
        await scheduling.StopAsync();
        rejected = false;
        try { await startup; }
        catch (InvalidOperationException) { rejected = true; }
        check(rejected && !scheduling.State.Running && factory.Created == createdBeforePreflight,
            "Stop during ARM preflight joins startup and opens no SQL workload");
        handler.WaitForResponse = null;
        settings["PoolGrowth:Enabled"] = "true";
        check(!(await RenderScaleAsync(monitor, scheduling, storage, settings)).Contains("class=\"storage-expansion\""),
            "Existing allocation on page load does not invent an automatic growth event");
        storage.AllocatedGiB["caldova"] = 20;
        await scheduling.StartAsync();
        await scheduling.StopAsync();
        check(storage.FillCalls == 1 && storage.LastLimit == TimeSpan.FromSeconds(45) && storage.UsedGiB["caldova"] == 21
            && storage.LastStopWhen is not null && storage.LastAllowPartial
            && storage.UsedGiB["northbrook"] == 12 && storage.UsedGiB["ridgeview"] == 15,
            "Run grows only Caldova with a 21-GiB ceiling, 45-second bound, and SQL-confirmed early completion");
        var grown = scheduling.State.Clinics.Single(clinic => clinic.Key == "caldova");
        check(grown.InitialStorage!.AllocatedGiB == 20 && grown.Storage!.AllocatedGiB == 30,
            "The run retains initial SQL allocation separately from its latest reading after Stop");
        var allocationMarkup = await RenderScaleAsync(monitor, scheduling, storage, settings);
        var decoded = System.Net.WebUtility.HtmlDecode(allocationMarkup);
        check(decoded.Contains("20 → 30 GiB") && decoded.Contains("+10 GiB allocated automatically")
            && System.Text.RegularExpressions.Regex.Matches(allocationMarkup, "class=\"storage-expansion\"").Count == 1
            && allocationMarkup.Contains("role=\"status\" aria-live=\"polite\""),
            "A refreshed stopped page prominently announces only Caldova's measured 20-to-30 allocation increase");
        if (Environment.GetEnvironmentVariable("CALDOVA_ALLOCATION_LAYOUT_PATH") is { Length: > 0 } layoutPath)
            await File.WriteAllTextAsync(layoutPath, "<!doctype html><html><head><meta charset=\"utf-8\">"
                + "<link rel=\"stylesheet\" href=\"http://localhost:5099/css/app.css?v=20261031-18\"></head>"
                + "<body><div class=\"shell\"><header style=\"height:68px\">Offline allocation-layout test — no SQL writes</header>"
                + "<main class=\"content\">" + allocationMarkup + "</main></div></body></html>");
        storage.AllocatedGiB["caldova"] = 40;
        check(System.Net.WebUtility.HtmlDecode(await RenderScaleAsync(monitor, scheduling, storage, settings))
                .Contains("20 → 40 GiB"),
            "Allocation callout numbers come from actual before/after readings, never a hardcoded 30-GiB result");
        storage.AllocatedGiB["caldova"] = 30;
        var above20 = new DatabaseStorage("caldova", at, 20L * DatabaseStorage.GiB + 8192, 30L * DatabaseStorage.GiB);
        check(storage.LastStopWhen!(above20)
            && !storage.LastStopWhen(above20 with { UsedBytes = 20L * DatabaseStorage.GiB })
            && !storage.LastStopWhen(above20 with { AllocatedBytes = 20L * DatabaseStorage.GiB })
            && !storage.LastStopWhen(above20 with { Key = "northbrook" }),
            "Growth requires actual used space above 20 GiB and higher allocation on Caldova, not reaching arbitrary 21 GiB");
        var preserved = storage.UsedGiB["caldova"];
        await storage.FillToAsync(ProviderProfiles.All[0], 21, _ => { }, TimeSpan.FromSeconds(45),
            CancellationToken.None, PoolScheduling.GrowthConfirmed);
        check(storage.UsedGiB["caldova"] == preserved, "Already-grown storage is preserved on another Run without more inserts");
        storage.UsedGiB["caldova"] = 18;
        storage.FailWrite = true;
        await scheduling.StartAsync();
        await scheduling.StopAsync();
        check(storage.FillCalls == 3 && scheduling.State.Error?.Contains("unconfirmed") == true
            && factory.Items.Values.All(client => client.Workload.Stops == 1),
            "An uncertain storage write stops all activity, surfaces the failure, and is never replayed");
        storage.FailWrite = false;
        storage.UsedGiB["caldova"] = 1;
        rejected = false;
        try { await scheduling.StartAsync(); }
        catch (InvalidOperationException) { rejected = true; }
        check(rejected && storage.FillCalls == 3, "Step 4 refuses to substitute an enormous initial fill for missing seeding");
        storage.UsedGiB["caldova"] = 18;
        var held = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        storage.HoldWrite = held.Task;
        await scheduling.StartAsync();
        await scheduling.StopAsync();
        check(!scheduling.State.Running && !scheduling.State.Growing && storage.FillCalls == 4
            && storage.UsedGiB["caldova"] == 18 && scheduling.State.Error is null,
            "Intentional Stop joins pending growth without another batch or a false growth-failure alert");
        var sqlErrors = Activator.CreateInstance(typeof(Microsoft.Data.SqlClient.SqlErrorCollection), nonPublic: true)!;
        storage.CancellationError = (Microsoft.Data.SqlClient.SqlException)typeof(Microsoft.Data.SqlClient.SqlException)
            .GetConstructor(BindingFlags.Instance | BindingFlags.NonPublic, null,
                [typeof(string), typeof(Microsoft.Data.SqlClient.SqlErrorCollection), typeof(Exception), typeof(Guid)], null)!
            .Invoke(["A severe error occurred on the current command. Operation cancelled by user.", sqlErrors, null, Guid.Empty]);
        await scheduling.StartAsync();
        await scheduling.StopAsync();
        check(!scheduling.State.Running && !scheduling.State.Growing && storage.FillCalls == 5
            && storage.UsedGiB["caldova"] == 18 && scheduling.State.Error is null,
            "SqlClient cancellation reported as a severe SQL error is still a clean intentional Stop, not an unconfirmed-growth alert");
        storage.CancellationError = null;
        storage.HoldWrite = null;
        storage.UsedGiB["caldova"] = 19;
        storage.SimulateTimeBudgetStop = true;
        await scheduling.StartAsync();
        await scheduling.StopAsync();
        check(scheduling.State.Error is null && !scheduling.State.Growing && storage.FillCalls == 6
            && scheduling.State.Clinics.Single(clinic => clinic.Key == "caldova").Storage!.UsedGiB == 19
            && !PoolScheduling.GrowthConfirmed(scheduling.State.Clinics.Single(clinic => clinic.Key == "caldova").Storage!),
            "A timed demo stop preserves measured partial growth without a red error or a false allocation-growth confirmation");
        storage.SimulateTimeBudgetStop = false;
        var markup = await RenderScaleAsync(monitor, scheduling, storage, settings);
        check(markup.Contains("Growth past 20 GiB has not been confirmed.")
            && markup.Contains("19.00 GiB used") && !markup.Contains("role=\"alert\"")
            && !markup.Contains("class=\"storage-expansion\"")
            && System.Net.WebUtility.HtmlDecode(markup).Contains("Run Scheduling & Grow"),
            "The timed-stop page shows actual partial storage and neutral incomplete-growth status, not a red error or success");
        settings["PoolGrowth:Enabled"] = "false";
        settings["PoolScaling:Enabled"] = "false";
        rejected = false;
        try { await scheduling.StartAsync(); }
        catch (InvalidOperationException) { rejected = true; }
        check(rejected && storage.FillCalls == 6, "Disabled hosts never run scheduling activity or writes");
        settings["PoolScaling:Enabled"] = "true";
        settings["Demo:Playback"] = "true";
        check(!scheduling.Enabled, "Playback cannot start real scheduling activity");
    }

    private static async Task<string> RenderScaleAsync(NetworkResourceMonitor monitor, PoolScheduling scheduling,
        PoolStorage storage, IConfiguration settings)
    {
        var renderingServices = new ServiceCollection();
        renderingServices.AddLogging();
        renderingServices.AddSingleton(monitor);
        renderingServices.AddSingleton(scheduling);
        renderingServices.AddSingleton<PoolStorage>(storage);
        renderingServices.AddSingleton(
            new PoolScaler(new AzureCliRunner(), monitor, settings, new PoolScaleChecks.Lifetime(), NullLogger<PoolScaler>.Instance));
        await using var renderingProvider = renderingServices.BuildServiceProvider();
        await using var renderer = new HtmlRenderer(renderingProvider, renderingProvider.GetRequiredService<ILoggerFactory>());
        return await renderer.Dispatcher.InvokeAsync(async () =>
            (await renderer.RenderComponentAsync<PoolScale>()).ToHtmlString());
    }

    private sealed class Clients : PoolClinicClientFactory
    {
        private readonly IConfiguration configuration;
        public Clients(IConfiguration configuration) : base(configuration, NullLoggerFactory.Instance, new StorageChecks.Fake(configuration)) =>
            this.configuration = configuration;
        public int Created { get; private set; }
        public string? FailKey { get; set; }
        public string? WorkloadFailure { get; set; }
        public Action<string>? OnRead { get; set; }
        public Dictionary<string, (Worker Workload, Telemetry Telemetry)> Items { get; } = [];
        public override PoolClinicClient Create(ProviderDemoProfile provider)
        {
            Created++;
            var worker = new Worker(configuration, provider.Key == "caldova" ? WorkloadFailure : null);
            var telemetry = new Telemetry(configuration, provider.Key, provider.Key == FailKey, OnRead);
            Items[provider.Key] = (worker, telemetry);
            return new(new("unused fake target", "Online", 0, 8), worker, telemetry);
        }
    }
    private sealed class Worker(IConfiguration configuration, string? error)
        : ServerlessSqlWorkload(configuration, NullLogger<ServerlessSqlWorkload>.Instance)
    {
        private SqlWorkloadSnapshot state = new(false, 0, 0, 0, null, null, null);
        public int Stops { get; private set; }
        public override SqlWorkloadSnapshot Snapshot => state;
        public override void StartRamp(ServerlessConfiguration target, WorkloadRamp ramp) =>
            state = new(true, ramp.PeakWorkers, 3, 0, DateTimeOffset.UtcNow, null, error, ramp.InitialWorkers, ramp);
        public override ValueTask DisposeAsync()
        {
            Stops++;
            state = state with { Running = false, Active = 0 };
            return ValueTask.CompletedTask;
        }
    }
    private sealed class Telemetry(IConfiguration configuration, string key, bool fail, Action<string>? onRead)
        : ServerlessSqlTelemetry(configuration)
    {
        public int Calls { get; private set; }
        public override Task<IReadOnlyList<ServerlessCpuSample>> ReadAsync(ServerlessConfiguration target,
            DateTimeOffset from, CancellationToken token)
        {
            Calls++;
            token.ThrowIfCancellationRequested();
            onRead?.Invoke(key);
            if (fail) throw new InvalidOperationException("Observation denied");
            var percent = key switch { "caldova" => 14, "northbrook" => 7, _ => 32 };
            return Task.FromResult<IReadOnlyList<ServerlessCpuSample>>([new(DateTimeOffset.UtcNow, percent, 8)]);
        }
    }
}
