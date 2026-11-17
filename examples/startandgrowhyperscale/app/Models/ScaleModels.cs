namespace CaldovaNetworkScheduling.Models;

public enum ServerlessStatus
{
    Online,
    Active,
    IdleAwaitingPause,
    Paused,
    Resuming
}

public sealed record ScaleSample(double ScriptSeconds, int ActiveUsers, double VCores, ServerlessStatus Status);

public sealed record SimulatedUser(int Id, string Label, string Role, string Location);

public sealed record AppActivity(
    int Sequence,
    TimeOnly At,
    int StaffId,
    string Kind,
    string Patient,
    string Specialty,
    string Clinic,
    string When,
    DateTimeOffset? RecordedAt = null);

public sealed record ScaleSnapshot(
    bool IsRunning,
    bool IsComplete,
    double ScriptSeconds,
    double TotalScriptSeconds,
    TimeOnly SimulatedTime,
    ServerlessStatus Status,
    string StatusDetail,
    int ActiveUsers,
    int PeakUsers,
    double VCores,
    double MinVCores,
    double MaxVCores,
    string DatabaseName,
    string ServiceObjective,
    int AutoPauseDelayMinutes,
    int Booked,
    int CheckedIn,
    int Rescheduled,
    IReadOnlyList<ScaleSample> Samples,
    IReadOnlyList<SimulatedUser> Users,
    IReadOnlyList<AppActivity> Activity);
