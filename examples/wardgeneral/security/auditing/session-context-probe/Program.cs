using System.Data;
using Microsoft.Data.SqlClient;

if (args.Length != 2)
{
    Console.Error.WriteLine("Usage: SessionContextProbe <server> <database>");
    return 2;
}

var server = args[0];
var database = args[1];
var providerId = 2_147_483_001;
var role = $"AuditProbe-{Guid.NewGuid():N}"[..19];

var builder = new SqlConnectionStringBuilder
{
    DataSource = server,
    InitialCatalog = database,
    Encrypt = SqlConnectionEncryptOption.Mandatory,
    TrustServerCertificate = false,
    Authentication = SqlAuthenticationMethod.ActiveDirectoryDefault,
    ConnectTimeout = 30,
    ApplicationName = "wardgeneral-audit-probe",
    ApplicationIntent = ApplicationIntent.ReadWrite
};

Console.WriteLine($"ExpectedProviderId={providerId}");
Console.WriteLine($"ExpectedRole={role}");

await using var connection = new SqlConnection(builder.ConnectionString);
await connection.OpenAsync();

await using (var clock = new SqlCommand("SELECT SYSUTCDATETIME();", connection))
{
    var startUtc = DateTime.SpecifyKind(
        (DateTime)(await clock.ExecuteScalarAsync()
            ?? throw new InvalidOperationException("Azure SQL returned no UTC start time.")),
        DateTimeKind.Utc);
    Console.WriteLine($"ProbeStartUtc={startUtc:o}");
    Console.WriteLine($"AuditQueryStartUtc={startUtc.AddSeconds(-5):o}");
}

await using (var setter = new SqlCommand(
    "EXEC sys.sp_set_session_context @k1, @v1, @ro; " +
    "EXEC sys.sp_set_session_context @k2, @v2, @ro;", connection))
{
    setter.Parameters.AddWithValue("@k1", "ProviderId");
    setter.Parameters.AddWithValue("@v1", providerId);
    setter.Parameters.AddWithValue("@k2", "Role");
    setter.Parameters.AddWithValue("@v2", role);
    setter.Parameters.AddWithValue("@ro", true);
    await setter.ExecuteNonQueryAsync();
}

await using (var verifier = new SqlCommand(
    "SELECT @@SPID AS SessionId, " +
    "TRY_CAST(SESSION_CONTEXT(N'ProviderId') AS INT) AS ProviderId, " +
    "CAST(SESSION_CONTEXT(N'Role') AS NVARCHAR(128)) AS Role;", connection))
await using (var reader = await verifier.ExecuteReaderAsync())
{
    if (!await reader.ReadAsync())
        throw new InvalidOperationException("The session-context verification query returned no row.");

    var actualSessionId = reader.GetInt16(reader.GetOrdinal("SessionId"));
    var actualProviderId = reader.GetInt32(reader.GetOrdinal("ProviderId"));
    var actualRole = reader.GetString(reader.GetOrdinal("Role"));

    Console.WriteLine($"SessionId={actualSessionId}");
    Console.WriteLine($"ActualProviderId={actualProviderId}");
    Console.WriteLine($"ActualRole={actualRole}");

    if (actualProviderId != providerId || actualRole != role)
        throw new InvalidOperationException("The values read from SESSION_CONTEXT did not match the bound parameters.");
}

await using (var clock = new SqlCommand("SELECT SYSUTCDATETIME();", connection))
{
    var endUtc = DateTime.SpecifyKind(
        (DateTime)(await clock.ExecuteScalarAsync()
            ?? throw new InvalidOperationException("Azure SQL returned no UTC end time.")),
        DateTimeKind.Utc);
    Console.WriteLine($"ProbeEndUtc={endUtc:o}");
    Console.WriteLine($"AuditQueryEndUtc={endUtc.AddSeconds(5):o}");
}
Console.WriteLine("ProbeResult=PASS");
return 0;