namespace CaldovaNetworkScheduling.Models;

public sealed record AppointmentSlot(
    string ProviderKey,
    string ProviderName,
    string SourceObject,
    bool IsRemote,
    string Location,
    string Clinician,
    string Specialty,
    DateTime SlotStart,
    int DurationMinutes,
    long SlotId);

public sealed record AvailabilityResult(
    bool NetworkWide,
    string QueryText,
    IReadOnlyList<AppointmentSlot> Slots,
    AppointmentSlot? EarliestCaldovaOnly);

public sealed record BookingResult(bool Booked, string QueryText, long? AppointmentId = null);

public sealed record ProviderReach(string ProviderKey, string Database, long OpenSlots);

public sealed record NetworkCheck(string SourceDatabase, IReadOnlyList<ProviderReach> Providers, string QueryText, DateTimeOffset CheckedAt);
