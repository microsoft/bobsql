using System.Reflection;
using CaldovaNetworkScheduling.Components.Pages;
using CaldovaNetworkScheduling.Services;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;

internal static class ResumeActivityChecks
{
    public static async Task CheckRenderingAsync(Action<bool, string> check,
        Microsoft.AspNetCore.Components.Web.HtmlRenderer renderer)
    {
        async Task<string> RenderAsync(bool connected, bool completed, bool paused = false) =>
            await renderer.Dispatcher.InvokeAsync(async () =>
                (await renderer.RenderComponentAsync<ResumeView>(
                    Microsoft.AspNetCore.Components.ParameterView.FromDictionary(
                        new Dictionary<string, object?> { ["Connected"] = connected, ["Completed"] = completed, ["Paused"] = paused }))).ToHtmlString());

        var paused = await RenderAsync(false, false, true);
        check(paused.Contains("callout-done") && paused.Contains("Clinic day complete.")
            && paused.Contains("Staff activity complete.") && paused.Contains("Clinics are quiet"),
            "The paused opening screen renders the standard clinic-day and staff-activity completion banner");
        var connecting = await RenderAsync(false, false);
        var empty = System.Text.RegularExpressions.Regex.Match(connecting,
            "<div class=\"board-empty[^\"]*\">(?<contents>.*?)</div>",
            System.Text.RegularExpressions.RegexOptions.Singleline);
        check(empty.Success && string.IsNullOrWhiteSpace(System.Text.RegularExpressions.Regex.Replace(
                empty.Groups["contents"].Value, "<!--.*?-->", "")),
            "Online resume renders an empty schedule until activity arrives, with no status or staff-count placeholder");
        check(!connecting.Contains("callout-done") && !connecting.Contains("Clinic day complete."),
            "The clinic-day completion banner clears when the resumed database is online");
        var working = await RenderAsync(true, false);
        var boardStart = working.IndexOf("<div class=\"board\">", StringComparison.Ordinal);
        var boardEnd = working.IndexOf("<aside", boardStart, StringComparison.Ordinal);
        var board = working[boardStart..boardEnd];
        check(board.Contains("board-row") && board.Contains("avatar-xs") && !board.Contains("board-empty")
            && !board.Contains("Staff activity") && !board.Contains("staff signed in") && !board.Contains("Staff working"),
            "Online resume renders only live scheduling rows in its board before CPU telemetry is available");
        check(working.Contains("<strong>4</strong>") && working.Contains("staff online"),
            "Rendered resume badges show the four connected staff rather than a forced single staff member");
        var completed = await RenderAsync(true, true);
        check(completed.Contains("Live schedule") && completed.Contains("vCores in use (CPU)")
            && completed.Contains(">Active</strong>") && completed.Contains("staff online")
            && completed.Contains("board-row") && !completed.Contains("callout-done")
            && !completed.Contains("Recorded peak") && !completed.Contains("staff at peak")
            && !completed.Contains("Recorded schedule") && !completed.Contains("last CPU used"),
            "The completed resume renders the normal live-app appearance with scheduling rows and no recording banner");
    }

    public static async Task RunAsync(Action<bool, string> check, IConfiguration configuration)
    {
        CheckIntervalAlignment(check);
        CheckPatientActivityAlignment(check);
        CheckLiveElapsedClock(check);
        CheckCompletedLiveScene(check);
        CheckResumeStartup(check);
        await CheckResumeCompletionAsync(check, configuration);
        await CheckRunControlsAsync(check, configuration);
        foreach (var scenario in new[] { "enabled", "fresh", "disabled", "failed" })
        {
            var signIn = new SignIn(configuration) { Fail = scenario == "failed" };
            var workload = new Workload(configuration, signIn) { Allow = scenario != "disabled" };
            var page = CreatePage();
            var monitor = new ServerlessMonitor(new HttpClient(new MonitorHandler("{}", "{}", "{}")),
                new TestCredential(), configuration);
            Set(page, "Monitor", monitor);
            Set(page, "Resume", signIn);
            Set(page, "Workload", workload);
            Set(page, "Telemetry", new Telemetry(configuration));
            Set(page, "Logger", NullLogger<Scale>.Instance);
            var oldSample = new ServerlessCpuSample(DateTimeOffset.UtcNow.AddHours(-2), 50, 8);
            var oldSamples = new[] { oldSample with { At = oldSample.At.AddSeconds(-30) },
                oldSample with { At = oldSample.At.AddSeconds(-15) }, oldSample };
            if (scenario != "fresh")
            {
                Field("samples").SetValue(page, oldSamples);
                Field("runStart").SetValue(page, oldSample.At.AddMinutes(-1));
                Field("elapsedStart").SetValue(page, oldSample.At.AddMinutes(-1));
                Field("elapsedEnd").SetValue(page, oldSample.At);
            }
            var lifetime = (CancellationTokenSource)Field("lifetime").GetValue(page)!;
            try
            {
                check(workload.Starts == 0, "Opening the page does not launch resume activity");
                await (Task)typeof(Scale).GetMethod("ResumeAsync", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(page, null)!;
                var elapsedStart = (DateTimeOffset)Field("elapsedStart").GetValue(page)!;
                check(scenario == "fresh" ? elapsedStart > DateTimeOffset.UtcNow.AddSeconds(-5)
                    : elapsedStart == oldSample.At.AddMinutes(-1),
                    "Resume preserves elapsed time from Run, or starts at sign-in on a fresh page");
                if (scenario is "enabled" or "fresh")
                {
                    check(signIn.Succeeded && workload.Starts == 1 && workload.Workers == 4
                        && workload.Duration == TimeSpan.FromMinutes(10),
                        "A successful sign-in starts four workers until manual Stop, bounded by the ten-minute safety limit");
                    var samples = (IReadOnlyList<ServerlessCpuSample>)Field("samples").GetValue(page)!;
                    check(scenario == "fresh" ? samples.Count == 2 :
                        samples.Count == 5 && samples.Take(3).SequenceEqual(oldSamples) && samples[3].At > oldSample.At.AddHours(1),
                        "Resume observation retains original raw history and the real gap without filling it");
                    check(samples[^2].CpuPercent == 0 && samples[^1].CpuPercent > 0
                        && samples[^1].At - samples[^2].At == TimeSpan.FromSeconds(15),
                        "A real baseline and rising CPU sample form a visible segment for the short resume burst");
                    check((TimeSpan)Field("planned").GetValue(page)! == TimeSpan.FromSeconds(60)
                        && (DateTimeOffset)Field("resumeChartStart").GetValue(page)! <= DateTimeOffset.UtcNow.AddSeconds(-30),
                        "Both fresh and existing pages focus resume on the 60-second baseline/activity window");
                    check(Field("phase").GetValue(page)!.ToString() == "Load", "Resume activity enters the normal measured load phase");
                    check(Field("elapsedEnd").GetValue(page) is null,
                        "A new resume activity unfreezes the elapsed clock without changing its origin");
                    typeof(Scale).GetMethod("Refresh", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(page, null);
                    var segments = (System.Collections.IEnumerable)typeof(Scale)
                        .GetMethod("Segments", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(page, null)!;
                    check(segments.Cast<Array>().Any(segment => segment.Length >= 2),
                        "The actual chart emits a drawable segment during post-resume observation");
                    var plotted = segments.Cast<CaldovaNetworkScheduling.Models.ScaleSample[]>().ToArray();
                    var chartStart = (double)typeof(Scale).GetProperty("ChartStartSeconds", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(page)!;
                    var sx = typeof(Scale).GetMethod("SX", BindingFlags.NonPublic | BindingFlags.Instance)!;
                    var latestSegment = plotted[^1];
                    check((double)sx.Invoke(page, [chartStart])! == 0
                        && Math.Abs((double)sx.Invoke(page, [chartStart + 60])! - 300) < 0.000001
                        && (double)sx.Invoke(page, [latestSegment[^1].ScriptSeconds])!
                            - (double)sx.Invoke(page, [latestSegment[0].ScriptSeconds])! >= 30,
                        "A 15-second resume rise spans at least 30 of 300 chart pixels, even after a two-hour pause");
                    var chartSnapshot = (CaldovaNetworkScheduling.Models.ScaleSnapshot)Field("snap").GetValue(page)!;
                    check(plotted.SelectMany(segment => segment).All(point => point.ScriptSeconds >= chartStart)
                        && chartSnapshot.Samples.Count == samples.Count
                        && (scenario == "fresh" || chartSnapshot.Samples[0].ScriptSeconds
                            == (oldSamples[0].At - (DateTimeOffset)Field("runStart").GetValue(page)!).TotalSeconds),
                        "The focused resume plot excludes old segments without removing or retiming the original samples");
                    var rawSamples = new[] { samples[^2] with { At = workload.Snapshot.Started!.Value }, samples[^1] with
                    {
                        At = workload.Snapshot.Started!.Value.AddSeconds(15),
                        CpuPercent = 3.25,
                    } };
                    Field("samples").SetValue(page, rawSamples);
                    typeof(Scale).GetMethod("Refresh", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(page, null);
                    var readout = typeof(Scale).GetProperty("Readout", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(page);
                    check((string)readout! == "0.50", "CPU readout rounds 0.26 up to the next quarter vCore");
                    Field("phase").SetValue(page, Enum.Parse(Field("phase").FieldType, "Complete"));
                    check((string)typeof(Scale).GetProperty("Readout", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(page)! == "0.50",
                        "Completed activity retains the same quarter-vCore readout");
                    var roundedSegments = (System.Collections.Generic.IEnumerable<CaldovaNetworkScheduling.Models.ScaleSample[]>)
                        typeof(Scale).GetMethod("Segments", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(page, null)!;
                    check(roundedSegments.Last()[^1].VCores == 0.5
                        && (double)typeof(Scale).GetProperty("DisplayVCores", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(page)! == 0.5
                        && rawSamples[^1].UsedVCores == 0.26,
                        "Readout, gauge, and chart agree while the original CPU measurements remain unchanged");
                }
                else
                {
                    check(workload.Starts == 0, $"{scenario} sign-in never starts SQL activity");
                    if (scenario == "failed")
                        check(Field("error").GetValue(page) is string, "Failed sign-in displays an error");
                }
            }
            finally
            {
                lifetime.Cancel();
                if (Field("runTask").GetValue(page) is Task task) await task;
                (Field("run").GetValue(page) as CancellationTokenSource)?.Dispose();
                lifetime.Dispose();
            }
            check(!workload.Snapshot.Running, "Disposing the page stops the bounded resume workload");
        }
        var round = typeof(Scale).GetMethod("RoundVCores", BindingFlags.NonPublic | BindingFlags.Static)!;
        foreach (var (value, expected) in new[] { (0.0, 0.0), (0.01, 0.25), (0.25, 0.25), (0.26, 0.5),
            (0.5, 0.5), (0.51, 0.75), (0.75, 0.75), (0.76, 1.0), (1.0, 1.0), (3.336, 3.5), (8.0, 8.0) })
            check((double)round.Invoke(null, [value])! == expected,
                $"Quarter-vCore rounding preserves zero and exact boundaries: {value} -> {expected}");
        var formatElapsed = typeof(Scale).GetMethod("FormatElapsed", BindingFlags.NonPublic | BindingFlags.Static)!;
        foreach (var (seconds, expected) in new[] { (0.0, "00:00:00"), (65.9, "00:01:05"),
            (3661.0, "01:01:01"), (90061.0, "25:01:01"), (-30.0, "-00:00:30") })
            check((string)formatElapsed.Invoke(null, [seconds])! == expected,
                $"Elapsed formatting handles seconds, long gaps, and pre-sign-in samples: {expected}");
        var clockPage = CreatePage();
        var origin = new DateTimeOffset(2026, 10, 28, 23, 59, 50, TimeSpan.Zero);
        Field("elapsedStart").SetValue(clockPage, origin);
        var elapsedAt = typeof(Scale).GetMethod("ElapsedAt", BindingFlags.NonPublic | BindingFlags.Instance)!;
        check((string)elapsedAt.Invoke(clockPage, [origin.AddSeconds(20)])! == "00:00:20"
            && (string)elapsedAt.Invoke(clockPage, [origin.AddSeconds(-30)])! == "-00:00:30",
            "Sample timestamps use the run origin across midnight without changing or clipping baseline times");
        var scene = new MeasuredClinicScene();
        scene.Update(origin, 1, 0);
        scene.Update(origin.AddSeconds(20), 1, 1);
        var snapshot = scene.Snapshot(true, false, origin.AddSeconds(20), origin, TimeSpan.FromMinutes(5),
            [], null, "");
        var activity = snapshot.Activity.Single();
        check(activity.RecordedAt == origin.AddSeconds(20)
            && (string)typeof(Scale).GetMethod("ActivityTime", BindingFlags.NonPublic | BindingFlags.Instance)!
                .Invoke(clockPage, [activity])! == "00:00:20",
            "Schedule event times retain their UTC date internally but display elapsed time from Run");
        Field("resumeChartStart").SetValue(clockPage, origin);
        typeof(Scale).GetMethod("ResetMeasured", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(clockPage, null);
        check(Field("elapsedStart").GetValue(clockPage) is null && Field("elapsedEnd").GetValue(clockPage) is null
            && Field("resumeChartStart").GetValue(clockPage) is null
            && (string)typeof(Scale).GetProperty("ElapsedTime", BindingFlags.NonPublic | BindingFlags.Instance)!
                .GetValue(clockPage)! == "00:00:00",
            "Reset returns the elapsed clock to zero");
        ((CancellationTokenSource)Field("lifetime").GetValue(clockPage)!).Dispose();
    }

    private static void CheckResumeStartup(Action<bool, string> check)
    {
        var page = CreatePage();
        var start = DateTimeOffset.UtcNow;
        var scene = (MeasuredClinicScene)Field("scene").GetValue(page)!;
        var refresh = typeof(Scale).GetMethod("Refresh", BindingFlags.NonPublic | BindingFlags.Instance)!;
        var observe = typeof(Scale).GetMethod("ObserveWorkload", BindingFlags.NonPublic | BindingFlags.Instance)!;
        try
        {
            scene.Update(start, 1, 0);
            Field("phase").SetValue(page, Enum.Parse(Field("phase").FieldType, "Load"));
            Field("resumeChartStart").SetValue(page, start.AddSeconds(-30));
            Field("samples").SetValue(page, new[] { new ServerlessCpuSample(start, 0, 8) });
            Field("load").SetValue(page, new SqlWorkloadSnapshot(true, 4, 0, 0, start, null, null, 0));
            observe.Invoke(page, null);
            refresh.Invoke(page, null);
            var pending = (CaldovaNetworkScheduling.Models.ScaleSnapshot)Field("snap").GetValue(page)!;
            check(pending.ActiveUsers == 1 && pending.Users.Count == 1 && pending.Activity.Count == 0,
                "Resume retains one signing-in staff member while connections and CPU telemetry are pending");
            Field("load").SetValue(page, new SqlWorkloadSnapshot(true, 4, 10, 0, start, null, null, 4));
            observe.Invoke(page, null);
            refresh.Invoke(page, null);
            pending = (CaldovaNetworkScheduling.Models.ScaleSnapshot)Field("snap").GetValue(page)!;
            check(pending.ActiveUsers == 4 && pending.Users.Count == 4
                && (string)typeof(Scale).GetProperty("Readout", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(page)! == "1.00",
                "Resume badges follow the four connected workers while CPU telemetry is still pending");
            scene.Observe(start.AddSeconds(3), new(true, 4, 20, 0, start, null, null, 4));
            refresh.Invoke(page, null);
            pending = (CaldovaNetworkScheduling.Models.ScaleSnapshot)Field("snap").GetValue(page)!;
            check(pending.ActiveUsers == 4 && pending.Activity.Count > 0
                && pending.Activity.All(activity => activity.StaffId <= pending.ActiveUsers),
                "Resume scheduling rows advance from completed batches before the first CPU interval arrives");
            Field("samples").SetValue(page, new[] { new ServerlessCpuSample(start.AddSeconds(15), 40, 8) });
            refresh.Invoke(page, null);
            var working = (CaldovaNetworkScheduling.Models.ScaleSnapshot)Field("snap").GetValue(page)!;
            check(working.ActiveUsers == 4 && working.Users.Count == 4
                && (string)typeof(Scale).GetProperty("Readout", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(page)! == "3.25",
                "Resume keeps connected staff and scheduling activity visible when the first CPU interval arrives");
        }
        finally
        {
            ((CancellationTokenSource)Field("lifetime").GetValue(page)!).Dispose();
        }
    }

    private static async Task CheckResumeCompletionAsync(Action<bool, string> check, IConfiguration configuration)
    {
        foreach (var verified in new[] { true, false })
        {
            var page = CreatePage();
            var start = DateTimeOffset.UtcNow.AddSeconds(-30);
            var scene = (MeasuredClinicScene)Field("scene").GetValue(page)!;
            var workload = new Workload(configuration, new SignIn(configuration));
            workload.HoldActive(start);
            var sample = new ServerlessCpuSample(start.AddSeconds(30), verified ? 45 : 0, 8);
            var refresh = typeof(Scale).GetMethod("Refresh", BindingFlags.NonPublic | BindingFlags.Instance)!;
            var lifetime = (CancellationTokenSource)Field("lifetime").GetValue(page)!;
            Set(page, "Workload", workload);
            Set(page, "Logger", NullLogger<Scale>.Instance);
            scene.Observe(start, new(true, 4, 0, 0, start, null, null, 4));
            scene.Observe(start.AddSeconds(20), new(true, 4, 30, 0, start, null, null, 4));
            Field("phase").SetValue(page, Enum.Parse(Field("phase").FieldType, "Load"));
            Field("resumeChartStart").SetValue(page, start.AddSeconds(-30));
            Field("runStart").SetValue(page, start.AddSeconds(-30));
            Field("samples").SetValue(page, new[] { sample });
            using var run = new CancellationTokenSource();
            Field("run").SetValue(page, run);
            var polling = WaitForCancellationAsync(run.Token);
            Field("polling").SetValue(page, polling);
            var watcher = (Task)typeof(Scale).GetMethod("WatchResumeActivityAsync",
                BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(page, [run.Token])!;
            Field("runTask").SetValue(page, watcher);
            try
            {
                check(!watcher.IsCompleted && workload.Snapshot.Running
                    && Field("phase").GetValue(page)!.ToString() == "Load",
                    "Resume remains running at four staff after thirty seconds until manual Stop");
                await ((Task)typeof(Scale).GetMethod("StopAsync",
                    BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(page, null)!).WaitAsync(TimeSpan.FromSeconds(2));
                refresh.Invoke(page, null);
                var snapshot = (CaldovaNetworkScheduling.Models.ScaleSnapshot)Field("snap").GetValue(page)!;
                check(!workload.Snapshot.Running && watcher.IsCompleted && polling.IsCompleted,
                    "Manual Stop stops resume workers and joins telemetry and observation");
                if (!verified)
                {
                    check(Field("phase").GetValue(page)!.ToString() == "Stopped"
                        && !snapshot.IsComplete && Field("error").GetValue(page) is null,
                        "Stopping before a positive four-staff CPU interval returns the ordinary stopped view without inventing a peak");
                    continue;
                }
                check(Field("phase").GetValue(page)!.ToString() == "ResumeComplete"
                    && snapshot.IsComplete && !snapshot.IsRunning && snapshot.ActiveUsers == 4
                    && snapshot.Users.Count == 4 && snapshot.Activity.Count > 0 && snapshot.VCores == sample.UsedVCores,
                    "Manual Stop holds the four-staff frame without a sign-out or cooldown phase");
                check(!(bool)typeof(Scale).GetProperty("HistoricalCpu", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(page)!
                    && (string)typeof(Scale).GetProperty("StatusLabel", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(page)! == "Active"
                    && !(bool)typeof(Scale).GetProperty("SigningOutWithCpu", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(page)!
                    && (string)typeof(Scale).GetProperty("Readout", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(page)! == "3.75"
                    && (string)typeof(Scale).GetProperty("StatusDetail", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(page)!
                        == "Staff working · 4 staff signed in",
                    "The held resume ending retains the normal Active, live-schedule appearance without recording labels or sign-out");
                Field("armStatus").SetValue(page, "Paused");
                refresh.Invoke(page, null);
                var held = (CaldovaNetworkScheduling.Models.ScaleSnapshot)Field("snap").GetValue(page)!;
                check(held.ActiveUsers == 4 && held.VCores == sample.UsedVCores
                    && held.Activity.SequenceEqual(snapshot.Activity),
                    "Later Azure pause does not replace the explicitly recorded resume ending");
                typeof(Scale).GetMethod("ResetMeasured", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(page, null);
                refresh.Invoke(page, null);
                check(Field("phase").GetValue(page)!.ToString() == "Ready"
                    && ((CaldovaNetworkScheduling.Models.ScaleSnapshot)Field("snap").GetValue(page)!).ActiveUsers == 0,
                    "Reset clears the held resume frame for a new take");
            }
            finally
            {
                lifetime.Cancel();
                if (!run.IsCancellationRequested) run.Cancel();
                await watcher;
                await polling;
                lifetime.Dispose();
            }
        }
        var limitedPage = CreatePage();
        Set(limitedPage, "Workload", new Workload(configuration, new SignIn(configuration)));
        Set(limitedPage, "Logger", NullLogger<Scale>.Instance);
        var limitedLifetime = (CancellationTokenSource)Field("lifetime").GetValue(limitedPage)!;
        try
        {
            limitedLifetime.Cancel();
            await (Task)typeof(Scale).GetMethod("WatchResumeActivityAsync",
                BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(limitedPage, [CancellationToken.None])!;
            check(Field("phase").GetValue(limitedPage)!.ToString() == "Failed"
                && Field("error").GetValue(limitedPage) is string message && message.Contains("10-minute safety limit"),
                "A non-manual resume stop surfaces the safety-limit error instead of silently completing the shot");
        }
        finally
        {
            limitedLifetime.Dispose();
        }
    }

    private static void CheckCompletedLiveScene(Action<bool, string> check)
    {
        var page = CreatePage();
        var origin = DateTimeOffset.UtcNow.AddMinutes(-4);
        var sample = new ServerlessCpuSample(origin.AddSeconds(75), 0, 8);
        var scene = (MeasuredClinicScene)Field("scene").GetValue(page)!;
        scene.Observe(origin, new(true, 10, 0, 0, origin, null, null, 1));
        scene.Observe(origin.AddSeconds(60), new(false, 10, 100, 0, origin, origin.AddSeconds(60), null, 0));
        Field("runStart").SetValue(page, origin);
        Field("elapsedStart").SetValue(page, origin);
        Field("samples").SetValue(page, new[] { sample });
        Field("phase").SetValue(page, Enum.Parse(Field("phase").FieldType, "Complete"));
        var refresh = typeof(Scale).GetMethod("Refresh", BindingFlags.NonPublic | BindingFlags.Instance)!;
        try
        {
            refresh.Invoke(page, null);
            var snapshot = (CaldovaNetworkScheduling.Models.ScaleSnapshot)Field("snap").GetValue(page)!;
            check(snapshot.IsComplete && snapshot.ActiveUsers == 0 && snapshot.VCores == 0
                && (string)typeof(Scale).GetProperty("Readout", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(page)! == "0.00"
                && (string)typeof(Scale).GetProperty("StatusDetail", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(page)! == "Everyone has signed out",
                "A completed live scene matches replay's zero staff, zero CPU, and signed-out ending");
            check(!(bool)typeof(Scale).GetProperty("HistoricalCpu", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(page)!,
                "Completed live and replay use the same schedule heading and CPU label, unlike an interrupted run");
            Field("armStatus").SetValue(page, "Paused");
            refresh.Invoke(page, null);
            check(((CaldovaNetworkScheduling.Models.ScaleSnapshot)Field("snap").GetValue(page)!).Status
                == CaldovaNetworkScheduling.Models.ServerlessStatus.Paused
                && (string)typeof(Scale).GetProperty("StatusDetail", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(page)!
                    == "Paused · no compute charges",
                "The completed live scene can still transition to verified Azure pause without another SQL run");
        }
        finally
        {
            ((CancellationTokenSource)Field("lifetime").GetValue(page)!).Dispose();
        }
    }

    private static void CheckLiveElapsedClock(Action<bool, string> check)
    {
        var page = CreatePage();
        var origin = DateTimeOffset.UtcNow.AddSeconds(-200);
        Field("elapsedStart").SetValue(page, origin);
        var refresh = typeof(Scale).GetMethod("Refresh", BindingFlags.NonPublic | BindingFlags.Instance)!;
        var elapsed = typeof(Scale).GetProperty("ElapsedTime", BindingFlags.NonPublic | BindingFlags.Instance)!;
        try
        {
            foreach (var phase in new[] { "Starting", "Load", "Cooldown" })
            {
                Field("phase").SetValue(page, Enum.Parse(Field("phase").FieldType, phase));
                refresh.Invoke(page, null);
                check(Field("elapsedEnd").GetValue(page) is null,
                    $"The live elapsed clock continues during {phase}, including trailing CPU observation");
            }
            foreach (var phase in new[] { "Complete", "Stopped", "Failed", "Ready" })
            {
                Field("elapsedEnd").SetValue(page, null);
                Field("phase").SetValue(page, Enum.Parse(Field("phase").FieldType, phase));
                var before = DateTimeOffset.UtcNow;
                refresh.Invoke(page, null);
                var ended = (DateTimeOffset)Field("elapsedEnd").GetValue(page)!;
                check(ended >= before && ended <= DateTimeOffset.UtcNow,
                    $"Entering {phase} freezes the live elapsed clock at the actual end, not the planned duration");
                var recordedEnd = origin.AddSeconds(197.5466713);
                Field("elapsedEnd").SetValue(page, recordedEnd);
                refresh.Invoke(page, null);
                refresh.Invoke(page, null);
                check((string)elapsed.GetValue(page)! == "00:03:17"
                    && (DateTimeOffset)Field("elapsedEnd").GetValue(page)! == recordedEnd,
                    $"Later {phase} refreshes retain the final duration instead of counting idle time");
            }
            typeof(Scale).GetMethod("ResetMeasured", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(page, null);
            check(Field("elapsedEnd").GetValue(page) is null && (string)elapsed.GetValue(page)! == "00:00:00",
                "Reset clears a frozen finish time for the next live run");
        }
        finally
        {
            ((CancellationTokenSource)Field("lifetime").GetValue(page)!).Dispose();
        }
    }

    private static async Task CheckRunControlsAsync(Action<bool, string> check, IConfiguration configuration)
    {
        var workingPage = CreatePage();
        Field("phase").SetValue(workingPage, Enum.Parse(Field("phase").FieldType, "Load"));
        Field("load").SetValue(workingPage, new SqlWorkloadSnapshot(true, 8, 10, 0,
            DateTimeOffset.UtcNow, null, null, 1));
        ((MeasuredClinicScene)Field("scene").GetValue(workingPage)!).Observe(DateTimeOffset.UtcNow,
            (SqlWorkloadSnapshot)Field("load").GetValue(workingPage)!);
        check((string)typeof(Scale).GetProperty("StatusDetail", BindingFlags.NonPublic | BindingFlags.Instance)!
                .GetValue(workingPage)! == "Staff signing in",
            "Live startup shows only the sign-in phase until the first aligned CPU frame");
        typeof(Scale).GetMethod("Refresh", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(workingPage, null);
        var initial = (CaldovaNetworkScheduling.Models.ScaleSnapshot)Field("snap").GetValue(workingPage)!;
        check(initial.ActiveUsers == 0 && initial.Activity.Count == 0
            && initial.Booked == 0 && initial.CheckedIn == 0 && initial.Rescheduled == 0,
            "Live capture never exposes newer startup activity before older aligned CPU frames arrive");
        ((CancellationTokenSource)Field("lifetime").GetValue(workingPage)!).Dispose();
        var pendingPage = CreatePage();
        Field("phase").SetValue(pendingPage, Enum.Parse(Field("phase").FieldType, "Starting"));
        typeof(Scale).GetMethod("Refresh", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(pendingPage, null);
        var readout = typeof(Scale).GetProperty("Readout", BindingFlags.NonPublic | BindingFlags.Instance)!;
        var awaitingCpu = typeof(Scale).GetProperty("AwaitingCpu", BindingFlags.NonPublic | BindingFlags.Instance)!;
        var display = typeof(Scale).GetProperty("DisplayVCores", BindingFlags.NonPublic | BindingFlags.Instance)!;
        check((string)readout.GetValue(pendingPage)! == "1.00" && (bool)awaitingCpu.GetValue(pendingPage)!
            && (double)display.GetValue(pendingPage)! == 1,
            "Run shows the configured 1-vCore minimum immediately in the readout and gauge while CPU is pending");
        var segments = (System.Collections.IEnumerable)typeof(Scale).GetMethod("Segments",
            BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(pendingPage, null)!;
        check(!segments.Cast<Array>().Any()
            && ((IReadOnlyList<ServerlessCpuSample>)Field("samples").GetValue(pendingPage)!).Count == 0,
            "The pending minimum creates no CPU samples or chart points");
        Field("samples").SetValue(pendingPage, new[] { new ServerlessCpuSample(DateTimeOffset.UtcNow, 3.25, 8) });
        typeof(Scale).GetMethod("Refresh", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(pendingPage, null);
        check((string)readout.GetValue(pendingPage)! == "0.50" && !(bool)awaitingCpu.GetValue(pendingPage)!,
            "The first real sample replaces the pending minimum with rounded measured CPU");
        Field("samples").SetValue(pendingPage, new[] { new ServerlessCpuSample(DateTimeOffset.UtcNow, 0, 8) });
        typeof(Scale).GetMethod("Refresh", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(pendingPage, null);
        check((string)readout.GetValue(pendingPage)! == "0.00" && (double)display.GetValue(pendingPage)! == 0,
            "A real zero is never replaced with the configured minimum");
        var gaugePercent = typeof(Scale).GetMethod("GaugePercent", BindingFlags.NonPublic | BindingFlags.Instance)!;
        var gaugeTicks = (IEnumerable<double>)typeof(Scale).GetProperty("GaugeTicks", BindingFlags.NonPublic | BindingFlags.Instance)!
            .GetValue(pendingPage)!;
        check(gaugeTicks.SequenceEqual([1, 2, 6, 8])
            && gaugeTicks.Select(value => (double)gaugePercent.Invoke(pendingPage, [value])!)
                .SequenceEqual([12.5, 25, 75, 100]),
            "The live gauge scale positions each hash mark using the same numeric mapping as the fill");
        Field("samples").SetValue(pendingPage, new[] { new ServerlessCpuSample(DateTimeOffset.UtcNow, 75, 8) });
        typeof(Scale).GetMethod("Refresh", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(pendingPage, null);
        check((string)readout.GetValue(pendingPage)! == "6.00"
            && (double)gaugePercent.Invoke(pendingPage, [display.GetValue(pendingPage)!])! == 75,
            "Six CPU-used vCores fill exactly to the six-vCore hash mark");
        typeof(Scale).GetMethod("ResetMeasured", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(pendingPage, null);
        typeof(Scale).GetMethod("Refresh", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(pendingPage, null);
        check((string)readout.GetValue(pendingPage)! == "–" && !(bool)awaitingCpu.GetValue(pendingPage)!,
            "An idle page still shows no CPU measurement instead of a minimum placeholder");
        ((CancellationTokenSource)Field("lifetime").GetValue(pendingPage)!).Dispose();
        check((TimeSpan)typeof(Scale).GetField("SamplePollInterval", BindingFlags.NonPublic | BindingFlags.Static)!
            .GetValue(null)! == TimeSpan.FromSeconds(3),
            "The app checks for newly published 15-second SQL samples every three seconds");
        var workload = new RampWorkload(configuration);
        var page = CreatePage();
        Field("elapsedEnd").SetValue(page, DateTimeOffset.UtcNow.AddMinutes(-1));
        Set(page, "Monitor", new ServerlessMonitor(new HttpClient(new MonitorHandler("{}", "{}", "{}")),
            new TestCredential(), configuration));
        Set(page, "Telemetry", new Telemetry(configuration));
        Set(page, "Workload", workload);
        Set(page, "Logger", NullLogger<Scale>.Instance);
        var lifetime = (CancellationTokenSource)Field("lifetime").GetValue(page)!;
        try
        {
            typeof(Scale).GetMethod("Run", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(page, null);
            var started = await Task.WhenAny(workload.Started.Task, Task.Delay(TimeSpan.FromSeconds(2)));
            check(started == workload.Started.Task && workload.Snapshot.Active == 1,
                "The actual Run handler starts one worker immediately without an idle baseline");
            check(Field("elapsedEnd").GetValue(page) is null,
                "Run clears the previous frozen clock before starting the next measured activity");
            var actualRamp = await workload.Started.Task;
            check(actualRamp.Total == TimeSpan.FromSeconds(165)
                && actualRamp.PeakWorkers == 10 && actualRamp.InitialWorkers == 1
                && actualRamp.WorkerLevels.SequenceEqual([1, 2, 6, 10])
                && actualRamp.StepUp == TimeSpan.FromSeconds(15) && actualRamp.StepDown == actualRamp.StepUp
                && actualRamp.Hold == TimeSpan.FromSeconds(60) && actualRamp.WorkersPerStepDown == 2
                && (TimeSpan)Field("planned").GetValue(page)! == TimeSpan.FromSeconds(195),
                "The actual Run handler sustains 10 peak workers then stops pairs within a 195-second timeline");
        }
        finally
        {
            lifetime.Cancel();
            if (Field("runTask").GetValue(page) is Task task) await task;
            if (Field("polling").GetValue(page) is Task polling) await polling;
            (Field("run").GetValue(page) as CancellationTokenSource)?.Dispose();
            lifetime.Dispose();
        }
        foreach (var phase in new[] { "Starting", "Load", "Cooldown" })
        {
            var stoppedPage = CreatePage();
            var stoppedWorkload = new RampWorkload(configuration);
            var run = new CancellationTokenSource();
            var sample = new ServerlessCpuSample(DateTimeOffset.UtcNow, 25, 8);
            var retainedSamples = new[] { sample };
            Set(stoppedPage, "Workload", stoppedWorkload);
            Field("run").SetValue(stoppedPage, run);
            Field("phase").SetValue(stoppedPage, Enum.Parse(Field("phase").FieldType, phase));
            Field("samples").SetValue(stoppedPage, retainedSamples);
            var scene = (MeasuredClinicScene)Field("scene").GetValue(stoppedPage)!;
            scene.Update(DateTimeOffset.UtcNow, 1, 0);
            var polling = WaitForCancellationAsync(run.Token);
            var runTask = WaitForCancellationAsync(run.Token);
            Field("polling").SetValue(stoppedPage, polling);
            Field("runTask").SetValue(stoppedPage, runTask);
            try
            {
                var stop = (Task)typeof(Scale).GetMethod("StopAsync", BindingFlags.NonPublic | BindingFlags.Instance)!
                    .Invoke(stoppedPage, null)!;
                await stop.WaitAsync(TimeSpan.FromSeconds(2));
                check(run.IsCancellationRequested && polling.IsCompleted && runTask.IsCompleted,
                    $"Stop during {phase} cancels and joins observation and orchestration without a cooldown delay");
                check(Field("phase").GetValue(stoppedPage)!.ToString() == "Stopped"
                    && !(bool)typeof(Scale).GetProperty("Busy", BindingFlags.NonPublic | BindingFlags.Instance)!
                        .GetValue(stoppedPage)!
                    && !stoppedWorkload.Snapshot.Running,
                    $"Stop during {phase} returns controls to idle and stops all workers");
                check(ReferenceEquals(Field("samples").GetValue(stoppedPage), retainedSamples)
                    && scene.Snapshot(false, false, DateTimeOffset.UtcNow, null, TimeSpan.FromMinutes(4.5),
                        retainedSamples, null, "").ActiveUsers == 0,
                    $"Stop during {phase} clears online staff without erasing measured samples");
                check((bool)typeof(Scale).GetProperty("HistoricalCpu", BindingFlags.NonPublic | BindingFlags.Instance)!
                        .GetValue(stoppedPage)!,
                    $"Stop during {phase} identifies retained CPU and schedule activity as historical");
            }
            finally
            {
                run.Cancel();
                await polling;
                await runTask;
                run.Dispose();
                ((CancellationTokenSource)Field("lifetime").GetValue(stoppedPage)!).Dispose();
            }
        }
    }

    private static void CheckIntervalAlignment(Action<bool, string> check)
    {
        var ramp = new WorkloadRamp(8, TimeSpan.FromSeconds(15), TimeSpan.FromSeconds(15),
            TimeSpan.FromSeconds(15), WorkerLevels: [1, 2, 6, 8]);
        var origin = DateTimeOffset.UtcNow.AddMinutes(-3);
        var scene = new MeasuredClinicScene();
        int[] levels = [1, 2, 6, 8, 6, 2, 1, 0];
        for (var i = 0; i < levels.Length; i++)
            scene.Observe(origin.AddSeconds(i * 15),
                new(i < 7, 8, i * 100, 0, origin, null, null, levels[i], ramp));
        for (var i = 0; i < levels.Length; i++)
        {
            var sample = new ServerlessCpuSample(origin.AddSeconds((i + 1) * 15), 90 - i * 10, 8);
            scene.Present(sample);
            var snapshot = scene.Snapshot(true, false, origin.AddMinutes(3), origin, TimeSpan.FromSeconds(135),
                [sample], null, "");
            var expected = i == 3 ? "Staff working" : i < 3 ? "Staff signing in" : "Staff signing out";
            check(snapshot.ActiveUsers == levels[i] && scene.IntervalEnd == sample.At
                && scene.IntervalStatus!.StartsWith(expected, StringComparison.Ordinal)
                && snapshot.VCores == sample.UsedVCores,
                $"Delayed interval {i + 1} uses its observed {levels[i]} staff and stage, without changing CPU");
        }
        var previousActivity = scene.Snapshot(true, false, origin.AddMinutes(3), origin, TimeSpan.FromSeconds(135),
            [], null, "").Activity;
        scene.Present(new(origin.AddSeconds(60), 100, 8));
        check(scene.IntervalEnd == origin.AddSeconds(120)
            && scene.Snapshot(true, false, origin.AddMinutes(3), origin, TimeSpan.FromSeconds(135),
                [], null, "").Activity.SequenceEqual(previousActivity),
            "Repeated or older intervals never replay staff activity or move the displayed stage backward");
        check(scene.IntervalStatus == "Staff signing out",
            "Zero observed staff with trailing positive CPU remains in the sign-out phase");
        scene.Present(new(origin.AddSeconds(135), 0, 8));
        check(scene.IntervalStatus == "Everyone has signed out",
            "The live sign-out phase completes only when the measured CPU reaches zero");
        scene.Reset();
        scene.Present(new(origin.AddSeconds(-15), 50, 8));
        check(scene.IntervalEnd is null && scene.IntervalStatus is null
            && scene.Snapshot(true, false, origin, origin, TimeSpan.FromSeconds(135), [], null, "").ActiveUsers == 0,
            "Reset clears worker history; an interval without observations invents no staff stage");
        scene.Observe(origin, new(true, 8, 0, 0, origin, null, null, 6, ramp));
        scene.Observe(origin.AddSeconds(50), new(true, 8, 10, 0, origin, null, null, 8, ramp));
        var lateConnectionSample = new ServerlessCpuSample(origin.AddSeconds(52.5), 50, 8);
        scene.Present(lateConnectionSample);
        check(scene.Snapshot(true, false, origin.AddSeconds(60), origin, TimeSpan.FromSeconds(135),
                [lateConnectionSample], null, "").ActiveUsers == 6 && scene.IntervalStatus!.StartsWith("Staff signing in", StringComparison.Ordinal),
            "Late worker connections use actual observations, not the scheduled peak or CPU value");

        var page = CreatePage();
        var pageScene = (MeasuredClinicScene)Field("scene").GetValue(page)!;
        for (var i = 0; i < 6; i++)
            pageScene.Observe(origin.AddSeconds(i * 15),
                new(true, 8, i * 100, 0, origin, null, null, levels[i], ramp));
        Field("phase").SetValue(page, Enum.Parse(Field("phase").FieldType, "Load"));
        Field("samples").SetValue(page, new[] { new ServerlessCpuSample(origin.AddSeconds(60), 95, 8) });
        Field("load").SetValue(page, new SqlWorkloadSnapshot(true, 8, 500, 0, origin, null, null, 2, ramp));
        typeof(Scale).GetMethod("Refresh", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(page, null);
        var snapshotField = Field("snap");
        var status = typeof(Scale).GetProperty("StatusDetail", BindingFlags.NonPublic | BindingFlags.Instance)!;
        check((string)status.GetValue(page)! == "Staff working · 8 staff signed in"
            && ((CaldovaNetworkScheduling.Models.ScaleSnapshot)snapshotField.GetValue(page)!).ActiveUsers == 8,
            "The actual page shows peak-interval staff even when the current workload is already signing out");
        Field("samples").SetValue(page, new[] { new ServerlessCpuSample(origin.AddSeconds(75), 70, 8) });
        typeof(Scale).GetMethod("Refresh", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(page, null);
        check((string)status.GetValue(page)! == "Staff signing out · 6 staff signed in"
            && ((CaldovaNetworkScheduling.Models.ScaleSnapshot)snapshotField.GetValue(page)!).ActiveUsers == 6,
            "Sign-out status and avatars advance only when the corresponding CPU interval arrives");
        Field("phase").SetValue(page, Enum.Parse(Field("phase").FieldType, "Cooldown"));
        check((string)status.GetValue(page)! == "Staff signing out · 6 staff signed in",
            "Trailing telemetry keeps interval-aligned status rather than prematurely saying everyone signed out");
        ((CancellationTokenSource)Field("lifetime").GetValue(page)!).Dispose();
    }

    private static void CheckPatientActivityAlignment(Action<bool, string> check)
    {
        var ramp = new WorkloadRamp(8, TimeSpan.FromSeconds(15), TimeSpan.FromSeconds(15),
            TimeSpan.FromSeconds(15), WorkerLevels: [1, 2, 6, 8]);
        var origin = new DateTimeOffset(2026, 11, 2, 20, 0, 0, TimeSpan.Zero);
        var scene = new MeasuredClinicScene();
        var prefix = new MeasuredClinicScene();
        long completed = 0;
        for (var tick = 0; tick <= 240; tick++)
        {
            var elapsed = TimeSpan.FromSeconds(tick * 0.5);
            var active = ramp.ActiveAt(elapsed);
            completed += active * 5;
            var load = new SqlWorkloadSnapshot(active > 0, 8, completed, 0, origin, null, null, active, ramp);
            scene.Observe(origin + elapsed, load);
            if (elapsed <= TimeSpan.FromSeconds(7.5)) prefix.Observe(origin + elapsed, load);
        }
        var expectedPrefix = prefix.Snapshot(true, false, origin.AddSeconds(7.5), origin,
            TimeSpan.FromSeconds(135), [], null, "");
        var firstSample = new ServerlessCpuSample(origin.AddSeconds(15), 15, 8);
        scene.Present(firstSample);
        var first = scene.Snapshot(true, false, origin.AddSeconds(120), origin,
            TimeSpan.FromSeconds(135), [firstSample], null, "");
        check(first.Activity.Count > 0 && first.ActiveUsers == 1
            && first.Booked == expectedPrefix.Booked && first.CheckedIn == expectedPrefix.CheckedIn
            && first.Rescheduled == expectedPrefix.Rescheduled && first.Activity.SequenceEqual(expectedPrefix.Activity),
            "The first staff member already has patient activity in the first CPU interval, with matching historical counters");
        var secondSample = new ServerlessCpuSample(origin.AddSeconds(30), 25, 8);
        scene.Present(secondSample);
        var second = scene.Snapshot(true, false, origin.AddSeconds(120), origin,
            TimeSpan.FromSeconds(135), [secondSample], null, "");
        check(second.ActiveUsers == 2 && second.Activity.Any(a => a.StaffId == 2)
            && second.Activity.Any(a => a.RecordedAt > origin.AddSeconds(15)),
            "Newly signed-in staff perform patient activity within their own CPU interval, not one interval later");
        for (var i = 3; i <= 8; i++)
        {
            var sample = new ServerlessCpuSample(origin.AddSeconds(i * 15), 20, 8);
            scene.Present(sample);
            var snapshot = scene.Snapshot(true, false, origin.AddSeconds(120), origin,
                TimeSpan.FromSeconds(135), [sample], null, "");
            var midpoint = sample.At - ServerlessSqlTelemetry.SampleInterval / 2;
            check(snapshot.ActiveUsers == ramp.ActiveAt(midpoint - origin)
                && snapshot.Activity.All(a => a.RecordedAt is { } at && at <= midpoint
                    && a.StaffId <= ramp.ActiveAt(at - origin)),
                $"CPU interval {i} uses patient rows from the same historical frame and only staff active when each row occurred");
        }
        var quietSample = new ServerlessCpuSample(origin.AddSeconds(120), 1, 8);
        var quiet = scene.Snapshot(true, false, origin.AddSeconds(120), origin,
            TimeSpan.FromSeconds(135), [quietSample], null, "");
        check(quiet.ActiveUsers == 0 && quiet.Activity.All(a => a.RecordedAt < origin.AddSeconds(105))
            && quiet.Booked + quiet.CheckedIn + quiet.Rescheduled > first.Booked + first.CheckedIn + first.Rescheduled,
            "Patient activity builds during real batch completion and stops when the last worker signs out");
        var frozen = new MeasuredClinicScene();
        frozen.Observe(origin, new(true, 8, 0, 0, origin, null, null, 1, ramp));
        frozen.Observe(origin.AddSeconds(5), new(true, 8, 10, 0, origin, null, null, 1, ramp));
        frozen.Present(firstSample);
        var before = frozen.Snapshot(true, false, origin.AddSeconds(15), origin,
            TimeSpan.FromSeconds(135), [firstSample], null, "");
        frozen.Observe(origin.AddSeconds(20), new(true, 8, 100, 0, origin, null, null, 6, ramp));
        frozen.Present(firstSample);
        var after = frozen.Snapshot(true, false, origin.AddSeconds(20), origin,
            TimeSpan.FromSeconds(135), [firstSample], null, "");
        check(after.ActiveUsers == before.ActiveUsers && after.Booked == before.Booked
            && after.CheckedIn == before.CheckedIn && after.Rescheduled == before.Rescheduled
            && after.Activity.SequenceEqual(before.Activity),
            "Current worker and patient activity never leak into a still-displayed older CPU interval");
        var stalled = new MeasuredClinicScene();
        for (var tick = 0; tick <= 30; tick++)
            stalled.Observe(origin.AddSeconds(tick * 0.5), new(true, 8, 0, 0, origin, null, null, 1, ramp));
        stalled.Present(firstSample);
        check(stalled.Snapshot(true, false, origin.AddSeconds(15), origin, TimeSpan.FromSeconds(135),
                [firstSample], null, "").Activity.Count == 0,
            "Patient activity is never generated when SQL batches are not completing");
    }

    private static async Task WaitForCancellationAsync(CancellationToken token)
    {
        try { await Task.Delay(Timeout.InfiniteTimeSpan, token); }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
    }

    private static Scale CreatePage()
    {
        var page = new Scale();
        Set(page, "Recording", new ServerlessRunRecording(new("Live", null, 2), TimeProvider.System));
        return page;
    }

    private static FieldInfo Field(string name) =>
        typeof(Scale).GetField(name, BindingFlags.NonPublic | BindingFlags.Instance)!;

    private static void Set(Scale page, string name, object value) =>
        typeof(Scale).GetProperty(name, BindingFlags.NonPublic | BindingFlags.Instance)!.SetValue(page, value);

    public sealed class ResumeView : Scale
    {
        [Microsoft.AspNetCore.Components.Parameter] public bool Connected { get; set; }
        [Microsoft.AspNetCore.Components.Parameter] public bool Completed { get; set; }
        [Microsoft.AspNetCore.Components.Parameter] public bool Paused { get; set; }

        protected override void OnInitialized() { }
        protected override void OnAfterRender(bool firstRender) { }
        protected override void OnParametersSet()
        {
            var start = DateTimeOffset.UtcNow.AddSeconds(-20);
            var scene = (MeasuredClinicScene)Field("scene").GetValue(this)!;
            scene.Reset();
            scene.Update(start, 1, 0);
            if (Connected)
            {
                scene.Observe(start, new(true, 4, 0, 0, start, null, null, 4));
                scene.Observe(start.AddSeconds(5), new(true, 4, 20, 0, start, null, null, 4));
            }
            Field("phase").SetValue(this, Enum.Parse(Field("phase").FieldType, Paused ? "Ready" : Completed ? "ResumeComplete" : "Load"));
            Field("armStatus").SetValue(this, Paused ? "Paused" : null);
            Field("resumeChartStart").SetValue(this, Paused ? null : start.AddSeconds(-30));
            Field("runStart").SetValue(this, start.AddSeconds(-30));
            Field("planned").SetValue(this, TimeSpan.FromSeconds(60));
            Field("samples").SetValue(this, Completed
                ? new[] { new ServerlessCpuSample(start.AddSeconds(15), 40, 8) } : Array.Empty<ServerlessCpuSample>());
            typeof(Scale).GetMethod("Refresh", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(this, null);
        }
    }

    private sealed class SignIn(IConfiguration configuration)
        : ServerlessResume(configuration, NullLogger<ServerlessResume>.Instance)
    {
        public bool Fail { get; init; }
        public bool Succeeded { get; private set; }
        public override Task<ResumeResult> SignInAsync(ServerlessConfiguration database, Action<int>? onAttempt, CancellationToken token)
        {
            if (Fail) throw new InvalidOperationException("Test sign-in failure");
            Succeeded = true;
            return Task.FromResult(new ResumeResult(TimeSpan.FromSeconds(15), 1, DateTimeOffset.UtcNow));
        }
    }

    private sealed class Workload(IConfiguration configuration, SignIn signIn)
        : ServerlessSqlWorkload(configuration, NullLogger<ServerlessSqlWorkload>.Instance)
    {
        public bool Allow { get; init; }
        public int Starts { get; private set; }
        public int Workers { get; private set; }
        public TimeSpan Duration { get; private set; }
        private SqlWorkloadSnapshot state = new(false, 0, 0, 0, null, null, null);
        public override bool Enabled => Allow;
        public override SqlWorkloadSnapshot Snapshot => state;
        public override void Start(ServerlessConfiguration database, int workers, TimeSpan duration)
        {
            if (!signIn.Succeeded) throw new Exception("Workload began before successful sign-in");
            Starts++;
            Workers = workers;
            Duration = duration;
            state = new(true, workers, 3, 0, DateTimeOffset.UtcNow, null, null, workers);
        }
        public override Task StopAsync()
        {
            state = state with { Running = false, Active = 0 };
            return Task.CompletedTask;
        }
        public void HoldActive(DateTimeOffset start) =>
            state = new(true, 4, 30, 0, start, null, null, 4);
    }

    private sealed class Telemetry(IConfiguration configuration) : ServerlessSqlTelemetry(configuration)
    {
        public override Task<IReadOnlyList<ServerlessCpuSample>> ReadAsync(
            ServerlessConfiguration database, DateTimeOffset from, CancellationToken token) =>
            Task.FromResult<IReadOnlyList<ServerlessCpuSample>>([new(from, 0, 8), new(from.AddSeconds(15), 25, 8)]);
    }

    private sealed class RampWorkload(IConfiguration configuration)
        : ServerlessSqlWorkload(configuration, NullLogger<ServerlessSqlWorkload>.Instance)
    {
        public TaskCompletionSource<WorkloadRamp> Started { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private SqlWorkloadSnapshot state = new(true, 8, 0, 0, DateTimeOffset.UtcNow, null, null, 1);
        public override bool Enabled => true;
        public override SqlWorkloadSnapshot Snapshot => state;
        public override void StartRamp(ServerlessConfiguration database, WorkloadRamp ramp)
        {
            state = state with { Active = ramp.ActiveAt(TimeSpan.Zero), Ramp = ramp };
            Started.SetResult(ramp);
        }
        public override Task StopAsync()
        {
            state = state with { Running = false, Active = 0 };
            return Task.CompletedTask;
        }
    }
}
