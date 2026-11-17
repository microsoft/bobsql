using System.Reflection;
using System.Text.Json;
using CaldovaNetworkScheduling.Components.Pages;
using CaldovaNetworkScheduling.Models;
using CaldovaNetworkScheduling.Services;
using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.Web;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;

internal static class SavedRunChecks
{
    public static async Task RunAsync(Action<bool, string> check, IConfiguration configuration)
    {
        var directory = Path.Combine(Path.GetTempPath(), $"caldova-saved-run-{Guid.NewGuid():N}");
        Directory.CreateDirectory(directory);
        var file = Path.Combine(directory, "run.json");
        var invalid = Path.Combine(directory, "invalid.json");
        var origin = new DateTimeOffset(2026, 11, 2, 20, 0, 0, TimeSpan.Zero);
        var clock = new Clock();
        var capture = new ServerlessRunRecording(new("Live", file, 2), clock);
        var cpu = new[] { 12.5, 25.0, 75.0, 100.0, 25.0, 0.0 }
            .Select((value, i) => new ServerlessCpuSample(origin.AddSeconds((i + 1) * 15), value, 8)).ToArray();
        try
        {
            capture.Begin(origin);
            for (var i = 0; i <= cpu.Length; i++)
            {
                var samples = cpu.Take(i).ToArray();
                capture.Record(origin.AddSeconds(i * 15), Scene(origin, samples, i), samples,
                    i == 0 ? null : samples[^1].At, i == 0, i * 100);
            }
            await capture.SaveAsync(CancellationToken.None);
            var saved = ServerlessRunRecording.Load(file);
            var original = await File.ReadAllBytesAsync(file);
            check(!capture.IsCapturing && saved.CpuSamples.SequenceEqual(cpu)
                && saved.Frames.Count == 7 && saved.Frames[^1].Scene.IsComplete,
                "A completed capture persists and reloads original CPU values, timestamps, and full frames");
            check(!System.Text.Encoding.UTF8.GetString(original).Contains("/subscriptions/", StringComparison.OrdinalIgnoreCase)
                && !System.Text.Encoding.UTF8.GetString(original).Contains("ConnectionString", StringComparison.OrdinalIgnoreCase),
                "Saved runs contain scene data, not Azure resource IDs or connection strings");

            capture.Begin(origin);
            capture.Record(origin, Scene(origin, [], 0), [], null, true, 0);
            await ThrowsAsync<InvalidDataException>(() => capture.SaveAsync(CancellationToken.None));
            capture.Abort();
            var afterIncomplete = await File.ReadAllBytesAsync(file);
            check(original.SequenceEqual(afterIncomplete),
                "An incomplete or aborted run cannot replace the last completed recording");
            capture.Begin(origin);
            foreach (var frame in saved.Frames)
                capture.Record(origin.AddSeconds(frame.ElapsedSeconds), frame.Scene,
                    saved.CpuSamples.Take(frame.CpuSampleCount).ToArray(), frame.CpuIntervalEnd,
                    frame.AwaitingCpu, frame.CompletedBatches);
            using (var cancellation = new CancellationTokenSource())
            {
                cancellation.Cancel();
                await ThrowsAsync<OperationCanceledException>(() => capture.SaveAsync(cancellation.Token));
            }
            var afterCanceled = await File.ReadAllBytesAsync(file);
            check(original.SequenceEqual(afterCanceled)
                && Directory.GetFiles(directory, "*.tmp").Length == 0,
                "Canceled persistence preserves the last good file and cleans its exact temporary file");

            var defaults = ServerlessRecordingSettings.Read(new ConfigurationBuilder().Build(), directory);
            check(defaults.Mode == "Live" && !defaults.CaptureEnabled && !defaults.IsReplay,
                "The default application remains live, with capture opt-in only");
            var settings = ServerlessRecordingSettings.Read(Config("Replay", file, "2"), directory);
            check(settings.IsReplay && settings.Replay is not null,
                "Replay configuration loads and validates the saved file before app startup");
            foreach (var mode in new[] { "Recorded", "live", "" })
                Throws<InvalidOperationException>(() => ServerlessRecordingSettings.Read(Config(mode, file, "2"), directory));
            foreach (var speed in new[] { "NaN", "0", "11" })
                Throws<InvalidOperationException>(() => ServerlessRecordingSettings.Read(Config("Replay", file, speed), directory));
            Throws<InvalidOperationException>(() => ServerlessRecordingSettings.Read(Config("Replay", "", "2"), directory));
            Throws<FileNotFoundException>(() => ServerlessRecordingSettings.Read(
                Config("Replay", Path.Combine(directory, "missing.json"), "2"), directory));
            Throws<InvalidOperationException>(() => ServerlessRecordingSettings.Read(
                Config("Live", Path.Combine(directory, "wwwroot", "run.json"), "2"), directory));
            Throws<InvalidOperationException>(() => ServerlessRecordingSettings.Read(
                new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["ServerlessRecording:File"] = file, ["Demo:Playback"] = "true",
                }).Build(), directory));
            check(true, "Invalid modes, speeds, missing files, public capture paths, and synthetic captures fail explicitly");

            foreach (var bad in new[]
            {
                saved with { Version = 2 },
                saved with { Source = "scripted" },
                saved with { CpuSamples = [] },
                saved with { Frames = saved.Frames.Reverse().ToArray() },
                saved with { Frames = saved.Frames.Take(6).ToArray() },
                saved with { CpuSamples = [cpu[0], cpu[0]] },
                saved with { CpuSamples = cpu.Select(s => s with { CpuPercent = -1 }).ToArray() },
                saved with { Frames = saved.Frames.Select(f => f with { CpuSampleCount = 100 }).ToArray() },
                saved with { Frames = saved.Frames.Select(f => f with { Scene = f.Scene with { ActiveUsers = 99 } }).ToArray() },
                saved with { Frames = saved.Frames.Select(f => f with
                    { Scene = f.Scene with { Samples = f.Scene.Samples.Select(s => s with { VCores = 99 }).ToArray() } }).ToArray() },
            })
            {
                await File.WriteAllTextAsync(invalid, JsonSerializer.Serialize(bad,
                    new JsonSerializerOptions { IgnoreReadOnlyProperties = true }));
                try
                {
                    ServerlessRunRecording.Load(invalid);
                    throw new Exception("Invalid saved run accepted");
                }
                catch (Exception ex) when (ex is InvalidDataException or InvalidOperationException) { }
            }
            await File.WriteAllTextAsync(invalid, "{");
            Throws<JsonException>(() => ServerlessRunRecording.Load(invalid));
            check(true, "Malformed, incomplete, reordered, synthetic, or altered saved CPU data is rejected without a fallback");

            var replay = new ServerlessRunRecording(settings, clock);
            check(!replay.IsPlaying && replay.GetReplayFrame().Scene.StatusDetail == "Press Run to start the day.",
                "Saved results wait for Run instead of playing automatically");
            replay.Play();
            for (var i = 1; i <= 3; i++)
            {
                clock.Advance(TimeSpan.FromSeconds(7.5));
                var frame = replay.GetReplayFrame();
                check(frame.CpuSampleCount == i && frame.Scene.VCores == cpu[i - 1].UsedVCores
                    && frame.Scene.ActiveUsers == new[] { 1, 2, 6 }[i - 1]
                    && frame.Scene.Booked == i * 3 && replay.SourceSeconds == i * 15
                    && replay.ReplaySamples(i).SequenceEqual(cpu.Take(i)),
                    $"At 2x, frame {i} keeps staff, counters, raw samples, and CPU synchronized without interpolation");
            }
            replay.Pause();
            clock.Advance(TimeSpan.FromHours(1));
            check(replay.SourceSeconds == 45 && !replay.IsPlaying && replay.GetReplayFrame().Scene.ActiveUsers == 6,
                "Stop freezes every saved surface and its shared clock");
            replay.Play();
            clock.Advance(TimeSpan.FromSeconds(7.5));
            check(replay.GetReplayFrame().Scene.ActiveUsers == 8 && replay.SourceSeconds == 60,
                "Run continues a stopped saved run from the same frame");
            clock.Advance(TimeSpan.FromSeconds(15));
            check(replay.GetReplayFrame().Scene.IsComplete && !replay.IsPlaying && replay.SourceSeconds == 90,
                "A 90-second source run completes in exactly 45 playing seconds at 2x");
            replay.Play();
            check(replay.SourceSeconds == 0 && replay.GetReplayFrame().CpuSampleCount == 0,
                "Run after completion restarts the same saved data from the beginning");
            replay.Reset();
            check(!replay.IsPlaying && replay.SourceSeconds == 0 && !replay.GetReplayFrame().Scene.IsComplete,
                "Reset returns saved playback to its initial ready state");
            var faster = new ServerlessRunRecording(settings with { Speed = 4 }, clock);
            faster.Play();
            clock.Advance(TimeSpan.FromSeconds(7.625));
            check(faster.SourceSeconds == 30.5 && faster.GetReplayFrame().Scene.VCores == 2,
                "Changing speed changes only the clock; values between source frames are held, never synthesized");
            var pendingClock = new Clock();
            var pendingFrame = saved.Frames[0] with
            {
                ElapsedSeconds = 6,
                Scene = saved.Frames[1].Scene with
                {
                    Samples = [], VCores = 0, ScriptSeconds = 6,
                    Booked = 10, CheckedIn = 2, Rescheduled = 1,
                    StatusDetail = "Waiting for the first staff/CPU interval",
                    Activity = Enumerable.Range(1, 3).Select(i => saved.Frames[1].Scene.Activity[0]
                        with { Sequence = i, RecordedAt = origin.AddSeconds(i + 2) }).ToArray(),
                },
            };
            var pendingReplay = new ServerlessRunRecording(settings with
            {
                Replay = saved with { Frames = [saved.Frames[0], pendingFrame, .. saved.Frames.Skip(1)] },
            }, pendingClock);
            pendingReplay.Play();
            check(pendingReplay.GetReplayFrame().Scene.StatusDetail == "Staff signing in",
                "The saved run begins with the staff sign-in phase without CPU-waiting text");
            pendingClock.Advance(TimeSpan.FromSeconds(3.5));
            var pendingView = pendingReplay.GetReplayFrame();
            check(pendingView.Scene.StatusDetail == "Staff signing in"
                && pendingView.Scene.Activity.Count == 0 && pendingView.Scene.ActiveUsers == 0
                && pendingView.Scene.Booked == 0 && pendingView.Scene.CheckedIn == 0 && pendingView.Scene.Rescheduled == 0
                && pendingView.CpuSampleCount == 0 && pendingFrame.Scene.Activity.Count == 3 && pendingFrame.Scene.Booked == 10,
                "Unaligned startup previews stay empty while the original saved rows and counters remain unchanged");
            pendingClock.Advance(TimeSpan.FromSeconds(4));
            check(pendingReplay.GetReplayFrame().Scene.StatusDetail == "Staff signing in · 1 staff signed in",
                "The first CPU sample does not replace the staff phase with a metric message");
            var alignedStart = pendingReplay.GetReplayFrame();
            check(alignedStart.Scene.Activity.Count == 1 && alignedStart.Scene.Booked == 3,
                "The first aligned activity appears once, without showing a newer preview and resetting backward");
            var phases = new List<string>();
            for (var i = 0; i <= 6; i++)
            {
                var phaseClock = new Clock();
                var phaseReplay = new ServerlessRunRecording(settings, phaseClock);
                phaseReplay.Play();
                phaseClock.Advance(TimeSpan.FromSeconds(i * 7.5));
                phases.Add(phaseReplay.GetReplayFrame().Scene.StatusDetail);
            }
            check(phases.SequenceEqual(["Staff signing in", "Staff signing in · 1 staff signed in",
                "Staff signing in · 2 staff signed in", "Staff signing in · 6 staff signed in",
                "Staff working · 8 staff signed in", "Staff signing out · 2 staff signed in", "Everyone has signed out"]),
                "Saved status follows signing in, working, signing out, and completion in step with the left-hand staff frames");
            var trailingCpu = cpu.Select((sample, i) => i == cpu.Length - 1
                ? sample with { CpuPercent = 6.25 } : sample).ToArray();
            var trailingFrame = saved.Frames[^1] with { Scene = Scene(origin, trailingCpu, 6) };
            var trailingClock = new Clock();
            var trailingReplay = new ServerlessRunRecording(settings with
            {
                Replay = saved with { CpuSamples = trailingCpu, Frames = [.. saved.Frames.SkipLast(1), trailingFrame] },
            }, trailingClock);
            trailingReplay.Play();
            trailingClock.Advance(TimeSpan.FromSeconds(45));
            var trailingView = trailingReplay.GetReplayFrame();
            check(trailingView.Scene.ActiveUsers == 0 && trailingView.Scene.VCores == 0.5
                && trailingView.Scene.StatusDetail == "Staff signing out" && trailingView.Scene.IsComplete
                && trailingFrame.Scene.StatusDetail == "Everyone has signed out",
                "Even a completed saved frame with trailing CPU retains sign-out wording without altering CPU, staff, or source status");
            await CheckPageAsync(check, configuration, settings, clock);
            await CheckPageAsync(check, configuration, settings with
            {
                Replay = saved with { CpuSamples = trailingCpu, Frames = [.. saved.Frames.SkipLast(1), trailingFrame] },
            }, new Clock());
        }
        finally
        {
            if (File.Exists(file)) File.Delete(file);
            if (File.Exists(invalid)) File.Delete(invalid);
            Directory.Delete(directory);
        }
    }

    private static async Task CheckPageAsync(Action<bool, string> check, IConfiguration configuration,
        ServerlessRecordingSettings settings, Clock clock)
    {
        var forbidden = new ForbiddenWorkload(configuration);
        var http = new ForbiddenHttp();
        var monitor = new ServerlessMonitor(new HttpClient(http), new TestCredential(), configuration);
        var replay = new ServerlessRunRecording(settings, clock);
        var page = new Scale();
        Set(page, "Recording", replay);
        Set(page, "Workload", forbidden);
        Set(page, "Monitor", monitor);
        Set(page, "Script", new ScriptedScaleWorkload(Microsoft.Extensions.Options.Options.Create(new ServerlessScriptOptions())));
        Set(page, "Logger", NullLogger<Scale>.Instance);
        Invoke(page, "OnAfterRender", true);
        check(Field(page, "statusLoop") is null, "Saved mode never starts the Azure management-status loop");
        Invoke(page, "Run");
        check((string)Property(page, "Readout")! == "0.00"
            && (double)Property(page, "DisplayVCores")! == 0
            && ((ScaleSnapshot)Field(page, "snap")!).Samples.Count == 0,
            "Replay starts at zero while CPU is pending without inventing a zero chart sample");
        clock.Advance(TimeSpan.FromSeconds(22.5));
        Invoke(page, "Refresh");
        var snapshot = (ScaleSnapshot)Field(page, "snap")!;
        check(snapshot.ActiveUsers == 6 && snapshot.Booked == 9 && snapshot.VCores == 6
            && (string)Property(page, "ElapsedTime")! == "00:00:45"
            && snapshot.Activity.Single().RecordedAt == replay.ReplayOrigin.AddSeconds(44),
            "The actual Run handler replays CPU, patient activity, counters, staff, and source elapsed time together");
        await (Task)Invoke(page, "ResumeAsync")!;
        await (Task)Invoke(page, "StopAsync")!;
        clock.Advance(TimeSpan.FromMinutes(1));
        Invoke(page, "Refresh");
        check(!replay.IsPlaying && ((ScaleSnapshot)Field(page, "snap")!).VCores == 6 && http.Calls == 0,
            "Resume is disabled and Stop performs no SQL or Azure work in saved mode");
        Invoke(page, "Reset");
        check(replay.SourceSeconds == 0 && !replay.IsPlaying, "The page Reset control resets only the saved timeline");
        await page.DisposeAsync();
        check(http.Calls == 0, "Disposing a saved-run page does not contact Azure or stop a SQL workload");

        var services = new ServiceCollection();
        services.AddLogging();
        services.AddSingleton<IConfiguration>(configuration);
        services.AddSingleton<TimeProvider>(clock);
        services.AddSingleton(settings);
        services.AddScoped<ServerlessRunRecording>();
        services.AddOptions<ServerlessScriptOptions>();
        services.AddScoped<IScaleWorkload, ScriptedScaleWorkload>();
        services.AddSingleton(monitor);
        services.AddSingleton<ServerlessSqlWorkload>(forbidden);
        services.AddSingleton<ServerlessSqlTelemetry>(new ServerlessSqlTelemetry(configuration));
        services.AddSingleton<ServerlessResume>(new ServerlessResume(configuration, NullLogger<ServerlessResume>.Instance));
        services.AddSingleton<NavigationManager>(new Navigation());
        await using var provider = services.BuildServiceProvider();
        await using var renderer = new HtmlRenderer(provider, provider.GetRequiredService<ILoggerFactory>());
        var root = await renderer.Dispatcher.InvokeAsync(async () => await renderer.RenderComponentAsync<Scale>());
        var html = await renderer.Dispatcher.InvokeAsync(root.ToHtmlString);
        check(html.Contains("▶ Run") && !html.Contains("Sign in (resume)") && !html.Contains("Load generation is disabled")
            && !html.Contains("replay", StringComparison.OrdinalIgnoreCase)
            && !html.Contains("compressed", StringComparison.OrdinalIgnoreCase) && !html.Contains("2×"),
            "Saved mode retains the Run button without playback/speed labels or a live resume control");
        check(!html.Contains("class=\"app-clock\"") && html.Contains("0.00")
            && !html.Contains("pending", StringComparison.OrdinalIgnoreCase) && !html.Contains("minimum vCores")
            && html.Contains("vCores in use (CPU)")
            && html.Contains("gauge-fill\" style=\"width:0%"),
            "Replay starts at zero without an elapsed clock, pending label, or one-vCore minimum");
        var renderedRecording = provider.GetRequiredService<ServerlessRunRecording>();
        await renderer.Dispatcher.InvokeAsync(renderedRecording.Play);
        clock.Advance(TimeSpan.FromSeconds(7.5));
        await Task.Delay(650);
        var runningHtml = await renderer.Dispatcher.InvokeAsync(root.ToHtmlString);
        check(runningHtml.Contains("1.00") && runningHtml.Contains("Demo patient")
            && runningHtml.Contains("00:00:14") && runningHtml.Contains("■ Stop")
            && !runningHtml.Contains("class=\"app-clock\"") && http.Calls == 0,
            "The rendered replay timer advances saved patient rows, source timestamps, CPU, and controls without live dependencies");
        check(!runningHtml.Contains("Staff shown for the same interval.") && !runningHtml.Contains("CPU interval 00:"),
            "The presentation omits the CPU interval/staff explanation line while retaining measured data");
        check(runningHtml.Contains("<span>staff online</span>")
            && !runningHtml.Contains("staff online at CPU interval"),
            "The staff header uses a separate label for spacing and omits the CPU interval qualifier");
        clock.Advance(TimeSpan.FromSeconds(37.5));
        await Task.Delay(650);
        var endingHtml = await renderer.Dispatcher.InvokeAsync(root.ToHtmlString);
        var endingFrame = renderedRecording.GetReplayFrame();
        var onlineMarkup = System.Text.RegularExpressions.Regex.Match(endingHtml,
            "<span class=\"online-label\">(.*?)</span>", System.Text.RegularExpressions.RegexOptions.Singleline).Groups[1].Value;
        var onlineText = System.Text.RegularExpressions.Regex.Replace(onlineMarkup, "<[^>]+>", "").Trim();
        if (endingFrame.Scene.VCores > 0)
        {
            check(endingFrame.Scene.ActiveUsers == 0 && endingFrame.Scene.VCores == 0.5
                && onlineText == "Staff signing out",
                "The left staff header shows sign-out instead of zero staff during the trailing 0.5-vCore interval");
        }
        else
        {
            check(endingFrame.Scene.ActiveUsers == 0 && onlineText.StartsWith("0", StringComparison.Ordinal)
                && onlineText.Contains("staff online"),
                "The left staff header returns to the real zero staff count once measured CPU reaches zero");
            check(endingHtml.Contains("Staff activity complete.") && endingHtml.Contains("Everyone has signed out")
                && endingHtml.Contains("Live schedule") && endingHtml.Contains("vCores in use (CPU)")
                && !endingHtml.Contains("Recorded schedule") && !endingHtml.Contains("last CPU used")
                && !endingHtml.Contains("class=\"app-clock\""),
                "The completed presentation keeps matching staff, schedule, CPU, and completion labels without an elapsed clock");
        }
    }

    private static ScaleSnapshot Scene(DateTimeOffset origin, IReadOnlyList<ServerlessCpuSample> samples, int index)
    {
        var active = new[] { 0, 1, 2, 6, 8, 2, 0 }[index];
        var seconds = index * 15;
        return new(index < 6, index == 6, seconds, 90, new(7, 0),
            active > 0 ? ServerlessStatus.Active : ServerlessStatus.Online,
            active > 0 ? $"{active} staff in this CPU interval" : "Everyone has signed out",
            active, 8, samples.Count == 0 ? 0 : samples[^1].UsedVCores, 1, 8, "caldova-scheduling", "serverless", 60,
            index * 3, index, 0,
            samples.Select(s => new ScaleSample((s.At - origin).TotalSeconds, 0, s.UsedVCores, ServerlessStatus.Active)).ToArray(),
            Enumerable.Range(1, active).Select(i => new SimulatedUser(i, $"Staff {i}", "Scheduler", "Clinic")).ToArray(),
            index == 0 ? [] : [new(index, new(7, 0), 1, "Booked", "Demo patient", "Cardiology", "Clinic", "Tomorrow",
                origin.AddSeconds(seconds - 1))]);
    }

    private static IConfiguration Config(string mode, string file, string speed) =>
        new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["ServerlessRecording:Mode"] = mode, ["ServerlessRecording:File"] = file, ["ServerlessRecording:Speed"] = speed,
        }).Build();

    private static void Throws<T>(Action action) where T : Exception
    {
        try { action(); }
        catch (T) { return; }
        throw new Exception($"Expected {typeof(T).Name}");
    }

    private static async Task ThrowsAsync<T>(Func<Task> action) where T : Exception
    {
        try { await action(); }
        catch (T) { return; }
        throw new Exception($"Expected {typeof(T).Name}");
    }

    private static object? Invoke(Scale page, string method, params object[] args) =>
        typeof(Scale).GetMethod(method, BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(page, args);
    private static object? Field(Scale page, string name) =>
        typeof(Scale).GetField(name, BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(page);
    private static object? Property(Scale page, string name) =>
        typeof(Scale).GetProperty(name, BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(page);
    private static void Set(Scale page, string name, object value) =>
        typeof(Scale).GetProperty(name, BindingFlags.NonPublic | BindingFlags.Instance)!.SetValue(page, value);

    private sealed class Clock : TimeProvider
    {
        private long ticks;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override long GetTimestamp() => ticks;
        public void Advance(TimeSpan duration) => ticks += duration.Ticks;
    }

    private sealed class Navigation : NavigationManager
    {
        public Navigation() => Initialize("http://localhost:5099/", "http://localhost:5099/");
        protected override void NavigateToCore(string uri, bool forceLoad) => Uri = ToAbsoluteUri(uri).ToString();
    }

    private sealed class ForbiddenWorkload(IConfiguration configuration)
        : ServerlessSqlWorkload(configuration, NullLogger<ServerlessSqlWorkload>.Instance)
    {
        public override bool Enabled => throw new Exception("Replay read live workload settings");
        public override SqlWorkloadSnapshot Snapshot => throw new Exception("Replay read a live SQL workload");
        public override void StartRamp(ServerlessConfiguration database, WorkloadRamp ramp) =>
            throw new Exception("Replay started real SQL workers");
        public override Task StopAsync() => throw new Exception("Replay stopped a real SQL workload");
        public override ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }

    private sealed class ForbiddenHttp : HttpMessageHandler
    {
        public int Calls { get; private set; }
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            throw new Exception("Replay contacted Azure");
        }
    }
}
