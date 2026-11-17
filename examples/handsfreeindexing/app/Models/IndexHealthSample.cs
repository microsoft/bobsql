namespace CaldovaPatientAccessOps.Models;

public sealed record IndexHealthSample(
    long SampleNumber,
    DateTime TimestampUtc,
    string Phase,
    string? IndexName,
    bool AutoCreated,
    bool AutomaticIndexCompactionOn,
    decimal? DensityPercent,
    long? PageCount,
    long? RecordCount,
    decimal? FragmentationPercent,
    long? LogicalReads,
    long? DashboardDurationMs,
    DateTime? MeasurementCapturedAtUtc,
    string? DashboardIndexName,
    bool? DashboardIndexAutoCreated);
