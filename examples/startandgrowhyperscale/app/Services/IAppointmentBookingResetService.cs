namespace CaldovaNetworkScheduling.Services;

public interface IAppointmentBookingResetService
{
    bool ResetEnabled { get; }
    Task ResetAsync(string providerKey, long slotId, long appointmentId, CancellationToken cancellationToken = default);
}
