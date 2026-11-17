using CaldovaNetworkScheduling.Models;

namespace CaldovaNetworkScheduling.Services;

/// <summary>
/// Answers "next available appointment". Standalone mode reads only Caldova's table;
/// Network mode reads the native cross-database join view.
/// </summary>
public interface IAppointmentAvailabilityService
{
    string Mode { get; }
    IReadOnlyList<string> Specialties { get; }
    string ViewDefinition { get; }
    Task<AvailabilityResult> FindNextAsync(string specialty, bool networkWide, CancellationToken cancellationToken = default);
    Task<BookingResult> BookAsync(string providerKey, long slotId, CancellationToken cancellationToken = default);
    Task<NetworkCheck> CheckNetworkAsync(CancellationToken cancellationToken = default);
}
