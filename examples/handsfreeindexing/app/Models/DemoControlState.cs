namespace CaldovaPatientAccessOps.Models;

public sealed record DemoControlState(
    string Phase,
    bool AutomaticIndexCompactionOn,
    bool CanSimulateChanges,
    bool CanEnableAutomaticIndexCompaction);
