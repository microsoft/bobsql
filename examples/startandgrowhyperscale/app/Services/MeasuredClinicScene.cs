using CaldovaNetworkScheduling.Models;

namespace CaldovaNetworkScheduling.Services;

/// <summary>
/// Projects a measured SQL run onto the Patient Access scene. Staff online equals the actual number of
/// active SQL workers at the displayed CPU interval's midpoint (or current workers during resume); schedule entries are illustrative
/// and advance only while SQL batches are completing.
/// vCores and the chart come only from SQL DMV samples, never from this class.
/// </summary>
public sealed class MeasuredClinicScene
{
    private readonly List<SimulatedUser> users = [];
    private readonly Dictionary<int, DateTimeOffset> nextActionAt = [];
    private readonly List<AppActivity> activity = [];
    private Random random = new(2026);
    private int nextUserId;
    private int sequence;
    private int booked;
    private int checkedIn;
    private int rescheduled;
    private int peak;
    private long lastCompleted;
    private sealed record ClinicFrame(int Booked, int CheckedIn, int Rescheduled, int Peak,
        IReadOnlyList<SimulatedUser> Users, IReadOnlyList<AppActivity> Activity);
    private sealed record Observation(DateTimeOffset At, SqlWorkloadSnapshot Load, ClinicFrame Frame);
    private readonly List<Observation> observations = [];
    private ClinicFrame? presented;
    public DateTimeOffset? IntervalEnd { get; private set; }
    public string? IntervalStatus { get; private set; }

    public MeasuredClinicScene() => Reset();

    public static ScaleSnapshot InitialView(ScaleSnapshot snapshot) => snapshot with
    {
        Status = ServerlessStatus.Online,
        ActiveUsers = 0,
        PeakUsers = 0,
        VCores = 0,
        Booked = 0,
        CheckedIn = 0,
        Rescheduled = 0,
        Users = [],
        Activity = [],
    };

    public static string DescribeStaff(int activeWorkers, int previousWorkers, int peakWorkers, double usedVCores = 0)
    {
        if (activeWorkers == 0) return usedVCores > 0 ? "Staff signing out"
            : previousWorkers > 0 ? "Everyone has signed out" : "Staff signing in";
        var stage = previousWorkers > activeWorkers ? "Staff signing out"
            : activeWorkers >= peakWorkers ? "Staff working" : "Staff signing in";
        return $"{stage} · {activeWorkers} staff signed in";
    }

    public string CurrentStaffStatus => observations.Count == 0 ? "Staff signing in" : Describe(observations[^1]);

    private string Describe(Observation observation, double usedVCores = 0)
    {
        var load = observation.Load;
        var previous = observations.LastOrDefault(o => o.At < observation.At && o.Load.Active != load.Active);
        return DescribeStaff(load.Active, previous?.Load.Active ?? 0, load.Ramp?.PeakWorkers ?? load.Workers, usedVCores);
    }

    public void Reset()
    {
        users.Clear();
        nextActionAt.Clear();
        activity.Clear();
        random = new Random(2026);
        nextUserId = 1;
        sequence = booked = checkedIn = rescheduled = peak = 0;
        lastCompleted = 0;
        observations.Clear();
        presented = null;
        IntervalEnd = null;
        IntervalStatus = null;
    }

    public void Observe(DateTimeOffset now, SqlWorkloadSnapshot load)
    {
        Update(now, load.Active, load.Completed);
        observations.Add(new(now, load, CaptureFrame()));
    }

    private ClinicFrame CaptureFrame() => new(booked, checkedIn, rescheduled, peak,
        users.ToArray(), Enumerable.Reverse(activity).Take(7).ToArray());

    public void Present(ServerlessCpuSample sample)
    {
        if (IntervalEnd is { } end && sample.At <= end) return;
        var midpoint = sample.At - ServerlessSqlTelemetry.SampleInterval / 2;
        var observation = observations.LastOrDefault(o => o.At <= midpoint);
        if (observation is null) return;
        presented = observation.Frame;
        IntervalEnd = sample.At;
        IntervalStatus = Describe(observation, sample.UsedVCores);
    }

    public void Update(DateTimeOffset now, int activeWorkers, long completedBatches)
    {
        while (users.Count < activeWorkers)
        {
            var id = nextUserId++;
            var seat = ClinicCast.Seats[(id - 1) % ClinicCast.Seats.Length];
            users.Add(new SimulatedUser(id, $"Staff {id:00}", seat.Role, seat.Location));
            nextActionAt[id] = now.AddSeconds(0.3 + random.NextDouble() * 1.2);
        }
        // The ramp stops the most recently started worker first.
        while (users.Count > activeWorkers)
        {
            nextActionAt.Remove(users[^1].Id);
            users.RemoveAt(users.Count - 1);
        }
        peak = Math.Max(peak, users.Count);

        var flowing = completedBatches > lastCompleted;
        lastCompleted = completedBatches;
        if (!flowing) return;
        foreach (var user in users)
        {
            if (now < nextActionAt[user.Id]) continue;
            Record(user, now);
            nextActionAt[user.Id] = now.AddSeconds(2.0 + random.NextDouble() * 2.5);
        }
    }

    public ScaleSnapshot Snapshot(bool running, bool complete, DateTimeOffset now, DateTimeOffset? start, TimeSpan planned,
        IReadOnlyList<ServerlessCpuSample> samples, ServerlessConfiguration? database, string statusDetail,
        ServerlessStatus? azureStatus = null, bool alignActivityToCpu = true)
    {
        var origin = start ?? now;
        var points = samples.Select(s => new ScaleSample((s.At - origin).TotalSeconds, 0, s.UsedVCores, ServerlessStatus.Active)).ToArray();
        var total = Math.Max(planned.TotalSeconds, points.Length == 0 ? 0 : points[^1].ScriptSeconds);
        var frame = alignActivityToCpu && presented is not null && samples.Count > 0 && IntervalEnd == samples[^1].At
            && azureStatus != ServerlessStatus.Resuming ? presented : CaptureFrame();
        var displayedUsers = (running || complete) && azureStatus is not (ServerlessStatus.Paused or ServerlessStatus.Resuming)
            ? frame.Users : users.ToArray();
        return new ScaleSnapshot(
            IsRunning: running,
            IsComplete: complete,
            ScriptSeconds: start is null ? 0 : (now - origin).TotalSeconds,
            TotalScriptSeconds: Math.Max(15, total),
            SimulatedTime: TimeOnly.FromDateTime(now.UtcDateTime),
            Status: azureStatus ?? (displayedUsers.Count > 0 ? ServerlessStatus.Active : ServerlessStatus.Online),
            StatusDetail: statusDetail,
            ActiveUsers: displayedUsers.Count,
            PeakUsers: frame.Peak,
            VCores: samples.Count == 0 ? 0 : samples[^1].UsedVCores,
            MinVCores: database?.MinVCores ?? 1,
            MaxVCores: Math.Max(database?.MaxVCores ?? 8, samples.Count == 0 ? 0 : samples.Max(s => s.CpuLimit)),
            DatabaseName: database?.ResourceId.Split('/').Last() ?? "caldova-scheduling",
            ServiceObjective: "serverless",
            AutoPauseDelayMinutes: 0,
            Booked: frame.Booked,
            CheckedIn: frame.CheckedIn,
            Rescheduled: frame.Rescheduled,
            Samples: points,
            Users: displayedUsers,
            Activity: frame.Activity);
    }

    private void Record(SimulatedUser user, DateTimeOffset now)
    {
        var roll = random.NextDouble();
        var service = ClinicCast.Services[random.Next(ClinicCast.Services.Length)];
        var patient = ClinicCast.Patients[random.Next(ClinicCast.Patients.Length)];
        var at = TimeOnly.FromDateTime(now.UtcDateTime);
        string kind, when;
        if (roll < 0.6) { kind = "Booked"; booked++; when = ClinicCast.FutureSlot(random); }
        else if (roll < 0.85) { kind = "Checked in"; checkedIn++; when = $"Today {at:h:mm tt}"; }
        else { kind = "Rescheduled"; rescheduled++; when = ClinicCast.FutureSlot(random); }
        activity.Add(new AppActivity(++sequence, at, user.Id, kind, patient, service.Specialty, service.Clinic, when, now));
        if (activity.Count > 100) activity.RemoveRange(0, activity.Count - 100);
    }
}
