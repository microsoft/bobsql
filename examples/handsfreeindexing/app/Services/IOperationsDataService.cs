using CaldovaPatientAccessOps.Models;

namespace CaldovaPatientAccessOps.Services;

public interface IOperationsDataService
{
    Task<OperationsDashboardData> GetDashboardDataAsync(
        int serviceRegionId,
        DateTime fromAtUtc,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<IndexHealthSample>> GetIndexHealthTimelineAsync(
        CancellationToken cancellationToken = default);

    Task CaptureIndexHealthAsync(CancellationToken cancellationToken = default);

    Task<DemoControlState> GetDemoControlStateAsync(CancellationToken cancellationToken = default);

    Task<bool> IsReadyAsync(CancellationToken cancellationToken = default);
}
