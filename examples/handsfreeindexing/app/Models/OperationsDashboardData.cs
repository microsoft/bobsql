namespace CaldovaPatientAccessOps.Models;

public sealed record OperationsDashboardData(
    int ServiceRegionId,
    DateTime FromAtUtc,
    DateTime CapturedAtUtc,
    long AppointmentVolume,
    long RequestedCount,
    long ScheduledCount,
    long ConfirmedCount,
    long CompletedCount,
    long CancelledCount,
    double AverageWaitMinutes,
    double CancellationRatePercent,
    long InstructionBytes,
    long InstructionRevisions,
    long QueryDurationMs,
    long LogicalReads,
    IReadOnlyList<DashboardBreakdownItem> Breakdown);

public sealed record DashboardBreakdownItem(
    string AppointmentStatus,
    byte SpecialtyCode,
    long AppointmentCount,
    double AverageWaitMinutes,
    long InstructionBytes,
    long RevisionCount);
