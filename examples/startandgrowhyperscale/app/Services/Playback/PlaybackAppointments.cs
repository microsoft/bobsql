using CaldovaNetworkScheduling.Models;

namespace CaldovaNetworkScheduling.Services.Playback;

/// <summary>
/// In-memory appointments seeded like sql\01-scheduling-schema.sql. Shows the same query, view, and booking
/// SQL as the live service; booking is conditional, so a second booking of the same slot is rejected.
/// </summary>
public sealed class PlaybackAppointmentAvailabilityService : IAppointmentAvailabilityService
{
    private sealed class Slot(string key, long id, string clinician, string specialty, DateTime start)
    {
        public string Key { get; } = key;
        public long Id { get; } = id;
        public string Clinician { get; } = clinician;
        public string Specialty { get; } = specialty;
        public DateTime Start { get; } = start;
        public bool Booked { get; set; }
    }

    private static readonly Dictionary<string, (string Name, string Location)> Providers = new()
    {
        ["caldova"] = ("Caldova Health", "Caldova Main Campus"),
        ["northbrook"] = ("Northbrook Family Clinics", "Northbrook Elm Street Clinic"),
        ["ridgeview"] = ("Ridgeview Specialty Care", "Ridgeview Heart and Vascular"),
    };

    private static readonly (string Key, string Specialty, int LeadDays, string Clinician)[] Schedule =
    [
        ("caldova", "Cardiology", 19, "Dr. Amara Osei"), ("caldova", "Orthopedics", 16, "Dr. Marco Ruiz"),
        ("caldova", "Dermatology", 24, "Dr. Lena Fischer"), ("caldova", "Pediatrics", 9, "Dr. Priya Raman"),
        ("caldova", "Primary Care", 7, "Dr. Amara Osei"),
        ("northbrook", "Pediatrics", 2, "Dr. Hana Kim"), ("northbrook", "Primary Care", 1, "Dr. Samuel Okafor"),
        ("northbrook", "Dermatology", 6, "Dr. Elise Martin"),
        ("ridgeview", "Cardiology", 2, "Dr. Tomas Varga"), ("ridgeview", "Orthopedics", 3, "Dr. Nadia Petrov"),
        ("ridgeview", "Dermatology", 11, "Dr. Owen Brennan"),
    ];

    private readonly object gate = new();
    private readonly List<Slot> slots = [];

    public PlaybackAppointmentAvailabilityService()
    {
        var today = DateTime.UtcNow.Date;
        var nextId = new Dictionary<string, long>();
        foreach (var (key, specialty, lead, clinician) in Schedule)
        {
            for (var day = 0; day < 10; day++)
            {
                var id = nextId[key] = nextId.GetValueOrDefault(key) + 1;
                slots.Add(new Slot(key, id, clinician, specialty, today.AddDays(lead + day).AddHours(9)));
            }
        }
    }

    public string Mode => "SQL";
    public IReadOnlyList<string> Specialties { get; } =
        ["Cardiology", "Orthopedics", "Pediatrics", "Primary Care", "Dermatology"];
    public string ViewDefinition => SqlAppointmentAvailabilityService.ViewSql;

    public async Task<AvailabilityResult> FindNextAsync(string specialty, bool networkWide, CancellationToken cancellationToken = default)
    {
        if (!Specialties.Contains(specialty)) throw new ArgumentException("Unknown specialty.", nameof(specialty));
        await Task.Delay(networkWide ? 420 : 280, cancellationToken);
        lock (gate)
        {
            var now = DateTime.UtcNow;
            var open = slots.Where(s => !s.Booked && s.Specialty == specialty && s.Start >= now);
            var local = open.Where(s => s.Key == "caldova").OrderBy(s => s.Start).ThenBy(s => s.Id).Take(10).Select(ToModel).ToList();
            var result = networkWide
                ? open.OrderBy(s => s.Start).ThenBy(s => s.Key, StringComparer.Ordinal).ThenBy(s => s.Id).Take(10).Select(ToModel).ToList()
                : local;
            return new AvailabilityResult(networkWide,
                networkWide ? SqlAppointmentAvailabilityService.NetworkQuery : SqlAppointmentAvailabilityService.LocalQuery,
                result, local.FirstOrDefault());
        }
    }

    public async Task<BookingResult> BookAsync(string providerKey, long slotId, CancellationToken cancellationToken = default)
    {
        if (slotId <= 0) throw new ArgumentOutOfRangeException(nameof(slotId));
        var query = SqlAppointmentAvailabilityService.GetBookingQuery(providerKey);
        await Task.Delay(320, cancellationToken);
        lock (gate)
        {
            var slot = slots.FirstOrDefault(s => s.Key == providerKey && s.Id == slotId && !s.Booked && s.Start >= DateTime.UtcNow);
            if (slot is not null) slot.Booked = true;
            return new BookingResult(slot is not null, query);
        }
    }

    public async Task<NetworkCheck> CheckNetworkAsync(CancellationToken cancellationToken = default)
    {
        await Task.Delay(650, cancellationToken);
        lock (gate)
        {
            var providers = Providers.Keys.OrderBy(k => k, StringComparer.Ordinal)
                .Select(k => new ProviderReach(k, SqlAppointmentAvailabilityService.GetDatabase(k), slots.Count(s => s.Key == k && !s.Booked)))
                .ToList();
            return new NetworkCheck("caldova-scheduling", providers, SqlAppointmentAvailabilityService.NetworkCheckQuery, DateTimeOffset.UtcNow);
        }
    }

    private static AppointmentSlot ToModel(Slot s) => new(s.Key, Providers[s.Key].Name,
        SqlAppointmentAvailabilityService.GetSourceObject(s.Key), s.Key != "caldova", Providers[s.Key].Location,
        s.Clinician, s.Specialty, s.Start, 30, s.Id);
}
