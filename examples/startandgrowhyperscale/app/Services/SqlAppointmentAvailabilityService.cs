using System.Data;
using CaldovaNetworkScheduling.Models;
using Microsoft.Data.SqlClient;

namespace CaldovaNetworkScheduling.Services;

public sealed class SqlAppointmentAvailabilityService(IConfiguration configuration) : IAppointmentAvailabilityService, IAppointmentBookingResetService
{
    public bool ResetEnabled => configuration.GetValue<bool>("BookingReset:Enabled")
        && !configuration.GetValue<bool>("Demo:Playback");
    public const string LocalQuery = """
        SELECT TOP (10) p.ProviderKey, p.ProviderName, s.SlotId,
               p.Location, s.Clinician, s.Specialty, s.SlotStart, s.DurationMinutes
        FROM network.ProviderClinic AS p
        JOIN dbo.AppointmentSlot AS s ON s.ClinicId = p.ClinicId
        WHERE p.ProviderKey = N'caldova' AND p.IsNetworkMember = 1
          AND s.IsBooked = 0 AND s.Specialty = @Specialty
          AND s.SlotStart >= SYSUTCDATETIME()
        ORDER BY s.SlotStart, s.SlotId;
        """;

    public const string NetworkQuery = """
        SELECT TOP (10) ProviderKey, ProviderName, SlotId, Location,
               Clinician, Specialty, SlotStart, DurationMinutes
        FROM network.AppointmentAvailability
        WHERE Specialty = @Specialty AND SlotStart >= SYSUTCDATETIME()
        ORDER BY SlotStart, ProviderKey, SlotId;
        """;

    public string Mode => "SQL";
    public IReadOnlyList<string> Specialties { get; } =
        ["Cardiology", "Orthopedics", "Pediatrics", "Primary Care", "Dermatology"];

    public string ViewDefinition => ViewSql;
    public static readonly string ViewSql = LoadViewSql();

    private static string LoadViewSql()
    {
        using var stream = typeof(SqlAppointmentAvailabilityService).Assembly.GetManifestResourceStream("AppointmentView.sql")
            ?? throw new InvalidOperationException("Embedded appointment view SQL is missing.");
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }

    public static string GetSourceObject(string providerKey) => providerKey switch
    {
        "caldova" => "[caldova-scheduling].dbo.AppointmentSlot",
        "northbrook" => "[northbrook-scheduling].dbo.AppointmentSlot",
        "ridgeview" => "[ridgeview-scheduling].dbo.AppointmentSlot",
        _ => throw new ArgumentException("Unknown scheduling provider.", nameof(providerKey)),
    };

    public static string GetBookingQuery(string providerKey)
    {
        var database = GetDatabase(providerKey);
        return $"""
            SET XACT_ABORT ON;
            DECLARE @booked int = 0;
            DECLARE @appointmentId bigint;
            BEGIN TRANSACTION;  -- every write goes to [{database}]

            UPDATE s
            SET IsBooked = 1
            FROM {GetSourceObject(providerKey)} AS s
            WHERE s.SlotId = @SlotId AND s.IsBooked = 0
              AND s.SlotStart >= SYSUTCDATETIME()
              AND EXISTS (
                  SELECT 1 FROM network.ProviderClinic AS p
                  WHERE p.ProviderKey = @ProviderKey AND p.ClinicId = s.ClinicId
                    AND p.IsNetworkMember = 1
              );

            IF @@ROWCOUNT = 1
            BEGIN
                INSERT [{database}].dbo.Appointment (SlotId, BookedAtUtc, BookedVia)
                VALUES (@SlotId, SYSUTCDATETIME(), N'caldova-network');
                SET @appointmentId = CONVERT(bigint, SCOPE_IDENTITY());
                SET @booked = 1;
            END;

            COMMIT TRANSACTION;
            SELECT @booked AS Booked, @appointmentId AS AppointmentId;
            """;
    }

    private SqlConnection CreateConnection()
    {
        var connectionString = configuration.GetConnectionString("Scheduling")
            ?? throw new InvalidOperationException("ConnectionStrings:Scheduling is required.");
        var settings = new SqlConnectionStringBuilder(connectionString);
        if (!string.Equals(settings.InitialCatalog, "caldova-scheduling", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("The scheduling connection must use caldova-scheduling as its source database.");
        }
        return new SqlConnection(connectionString);
    }

    public async Task<AvailabilityResult> FindNextAsync(string specialty, bool networkWide, CancellationToken cancellationToken = default)
    {
        if (!Specialties.Contains(specialty))
            throw new ArgumentException("Unknown specialty.", nameof(specialty));

        await using var connection = CreateConnection();
        await connection.OpenAsync(cancellationToken);
        var local = await ReadAsync(connection, LocalQuery, specialty, cancellationToken);
        var slots = networkWide
            ? await ReadAsync(connection, NetworkQuery, specialty, cancellationToken)
            : local;
        return new AvailabilityResult(networkWide, networkWide ? NetworkQuery : LocalQuery, slots, local.FirstOrDefault());
    }

    private static async Task<IReadOnlyList<AppointmentSlot>> ReadAsync(
        SqlConnection connection, string query, string specialty, CancellationToken cancellationToken)
    {
        using var command = new SqlCommand(query, connection) { CommandTimeout = 30 };
        command.Parameters.Add("@Specialty", SqlDbType.NVarChar, 80).Value = specialty;
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var slots = new List<AppointmentSlot>();
        while (await reader.ReadAsync(cancellationToken))
        {
            var key = reader.GetString(0);
            slots.Add(new AppointmentSlot(key, reader.GetString(1), GetSourceObject(key), key != "caldova",
                reader.GetString(3), reader.GetString(4), reader.GetString(5),
                DateTime.SpecifyKind(reader.GetDateTime(6), DateTimeKind.Utc), reader.GetInt32(7), reader.GetInt64(2)));
        }
        return slots;
    }

    public async Task<BookingResult> BookAsync(string providerKey, long slotId, CancellationToken cancellationToken = default)
    {
        if (slotId <= 0) throw new ArgumentOutOfRangeException(nameof(slotId));
        var query = GetBookingQuery(providerKey);
        await using var connection = CreateConnection();
        await connection.OpenAsync(cancellationToken);
        using var command = new SqlCommand(query, connection) { CommandTimeout = 30 };
        command.Parameters.Add("@SlotId", SqlDbType.BigInt).Value = slotId;
        command.Parameters.Add("@ProviderKey", SqlDbType.NVarChar, 20).Value = providerKey;
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
            throw new InvalidOperationException("SQL did not return a booking response. Inspect the slot before retrying.");
        var booked = reader.GetInt32(0) == 1;
        var appointmentId = reader.IsDBNull(1) ? (long?)null : reader.GetInt64(1);
        if (booked && appointmentId is not > 0)
            throw new InvalidOperationException("SQL did not return the confirmed appointment ID. Inspect the slot before retrying.");
        return new BookingResult(booked, query, appointmentId);
    }

    public static string GetResetQuery(string providerKey)
    {
        var database = GetDatabase(providerKey);
        return $"""
            SET XACT_ABORT ON;
            BEGIN TRANSACTION;

            UPDATE s WITH (UPDLOCK, HOLDLOCK)
            SET IsBooked = 0
            FROM {GetSourceObject(providerKey)} AS s
            WHERE s.SlotId = @SlotId AND s.IsBooked = 1
              AND EXISTS (
                  SELECT 1 FROM [{database}].dbo.Appointment AS a
                  WHERE a.AppointmentId = @AppointmentId AND a.SlotId = s.SlotId
                    AND a.BookedVia = N'caldova-network'
              );
            IF @@ROWCOUNT <> 1
                THROW 50003, 'The exact booking no longer matches. No reset was performed.', 1;

            DELETE FROM [{database}].dbo.Appointment
            WHERE AppointmentId = @AppointmentId AND SlotId = @SlotId
              AND BookedVia = N'caldova-network';
            IF @@ROWCOUNT <> 1
                THROW 50004, 'The appointment changed. The reset was rolled back.', 1;

            COMMIT TRANSACTION;
            SELECT 1;
            """;
    }

    public async Task ResetAsync(string providerKey, long slotId, long appointmentId, CancellationToken cancellationToken = default)
    {
        if (!ResetEnabled) throw new InvalidOperationException("Booking reset is disabled on this host.");
        PoolScaler.ValidateHost(configuration);
        if (slotId <= 0) throw new ArgumentOutOfRangeException(nameof(slotId));
        if (appointmentId <= 0) throw new ArgumentOutOfRangeException(nameof(appointmentId));
        var query = GetResetQuery(providerKey);
        await using var connection = CreateConnection();
        await connection.OpenAsync(cancellationToken);
        using var command = new SqlCommand(query, connection) { CommandTimeout = 30 };
        command.Parameters.Add("@SlotId", SqlDbType.BigInt).Value = slotId;
        command.Parameters.Add("@AppointmentId", SqlDbType.BigInt).Value = appointmentId;
        var response = await command.ExecuteScalarAsync(cancellationToken);
        if (response is not int value || value != 1)
            throw new InvalidOperationException("SQL did not confirm the booking reset. Inspect the slot before retrying.");
    }

    public const string NetworkCheckQuery = """
        SELECT ProviderKey, COUNT_BIG(*) AS OpenSlots
        FROM network.AppointmentAvailability
        GROUP BY ProviderKey
        ORDER BY ProviderKey;
        """;

    public static string GetDatabase(string providerKey) => GetSourceObject(providerKey).Split(']')[0].TrimStart('[');

    public async Task<NetworkCheck> CheckNetworkAsync(CancellationToken cancellationToken = default)
    {
        await using var connection = CreateConnection();
        await connection.OpenAsync(cancellationToken);
        using var command = new SqlCommand(NetworkCheckQuery, connection) { CommandTimeout = 30 };
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var providers = new List<ProviderReach>();
        while (await reader.ReadAsync(cancellationToken))
        {
            var key = reader.GetString(0);
            providers.Add(new ProviderReach(key, GetDatabase(key), reader.GetInt64(1)));
        }
        return new NetworkCheck(connection.Database, providers, NetworkCheckQuery, DateTimeOffset.UtcNow);
    }
}
