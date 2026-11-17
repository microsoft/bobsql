using System.Data;
using Microsoft.Data.SqlClient;

namespace CaldovaNetworkScheduling.Services;

public sealed record ServerlessCpuSample(DateTimeOffset At, double CpuPercent, double CpuLimit)
{
    public double UsedVCores => double.IsFinite(CpuLimit) && CpuLimit > 0
        && double.IsFinite(CpuPercent) && CpuPercent is >= 0 and <= 100
        ? CpuPercent * CpuLimit / 100
        : throw new InvalidOperationException("SQL returned an invalid CPU percentage or vCore limit.");
}

public class ServerlessSqlTelemetry(IConfiguration configuration)
{
    public static readonly TimeSpan SampleInterval = TimeSpan.FromSeconds(15);
    protected virtual SqlConnection CreateConnection(string connectionString) => new(connectionString);
    protected virtual int CommandTimeoutSeconds => 15;
    public virtual async Task<IReadOnlyList<ServerlessCpuSample>> ReadAsync(
        ServerlessConfiguration database, DateTimeOffset from, CancellationToken token)
    {
        var settings = ConnectionSettings(configuration, database, "Caldova.ServerlessTelemetry");
        const string query = """
            SELECT end_time, avg_cpu_percent, cpu_limit
            FROM sys.dm_db_resource_stats
            WHERE end_time >= @from AND replica_role = 0
            ORDER BY end_time;
            """;
        await using var connection = CreateConnection(settings.ConnectionString);
        await connection.OpenAsync(token);
        using var command = new SqlCommand(query, connection) { CommandTimeout = CommandTimeoutSeconds };
        command.Parameters.Add("@from", SqlDbType.DateTime).Value = from.UtcDateTime;
        await using var reader = await command.ExecuteReaderAsync(token);
        var samples = new List<ServerlessCpuSample>();
        while (await reader.ReadAsync(token))
        {
            if (reader.IsDBNull(2))
                throw new InvalidOperationException("The database did not report a vCore limit.");
            var sample = new ServerlessCpuSample(
                new DateTimeOffset(DateTime.SpecifyKind(reader.GetDateTime(0), DateTimeKind.Utc)),
                (double)reader.GetDecimal(1), (double)reader.GetDecimal(2));
            _ = sample.UsedVCores;
            samples.Add(sample);
        }
        return samples;
    }

    internal static SqlConnectionStringBuilder ConnectionSettings(
        IConfiguration configuration, ServerlessConfiguration database, string applicationName)
    {
        var settings = new SqlConnectionStringBuilder(configuration.GetConnectionString("Scheduling")
            ?? throw new InvalidOperationException("ConnectionStrings:Scheduling is required."));
        var parts = database.ResourceId.Split('/');
        if (parts.Length != 11
            || !settings.DataSource.Equals($"tcp:{parts[8]}.database.windows.net,1433", StringComparison.OrdinalIgnoreCase)
            || !settings.InitialCatalog.Equals(parts[10], StringComparison.OrdinalIgnoreCase)
            || settings.ApplicationIntent != ApplicationIntent.ReadWrite)
            throw new InvalidOperationException("SQL target must match the monitored database primary exactly.");
        settings.ConnectRetryCount = 0;
        settings.Pooling = false;
        settings.ApplicationName = applicationName;
        return settings;
    }
}
