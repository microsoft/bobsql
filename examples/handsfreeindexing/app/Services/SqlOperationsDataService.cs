using System.Data;
using System.Diagnostics;
using System.Text.RegularExpressions;
using CaldovaPatientAccessOps.Models;
using Microsoft.Data.SqlClient;

namespace CaldovaPatientAccessOps.Services;

public sealed partial class SqlOperationsDataService(IConfiguration configuration) : IOperationsDataService
{
    private readonly string connectionString = configuration.GetConnectionString("Caldova") ?? string.Empty;

    public async Task<OperationsDashboardData> GetDashboardDataAsync(
        int serviceRegionId,
        DateTime fromAtUtc,
        CancellationToken cancellationToken = default)
    {
        EnsureConfigured();

        var rows = new List<DashboardBreakdownItem>();
        long logicalReads = 0;
        await using var connection = new SqlConnection(connectionString);
        connection.InfoMessage += (_, eventArgs) =>
        {
            foreach (SqlError error in eventArgs.Errors)
            {
                foreach (Match match in LogicalReadsRegex().Matches(error.Message))
                {
                    logicalReads += long.Parse(match.Groups[1].Value);
                }
            }
        };

        await connection.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SET STATISTICS IO ON;
            EXEC demo.usp_PatientAccessDashboard
                 @ServiceRegionId = @regionId,
                 @FromAt = @fromAt;
            SET STATISTICS IO OFF;
            """;
        command.Parameters.Add("@regionId", SqlDbType.Int).Value = serviceRegionId;
        command.Parameters.Add("@fromAt", SqlDbType.DateTime2).Value = fromAtUtc;
        command.CommandTimeout = 120;

        var stopwatch = Stopwatch.StartNew();
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                rows.Add(new DashboardBreakdownItem(
                    reader.GetString(0),
                    reader.GetByte(1),
                    reader.GetInt64(2),
                    Convert.ToDouble(reader.GetValue(3)),
                    reader.GetInt64(4),
                    reader.GetInt64(5)));
            }
        }
        stopwatch.Stop();

        await RecordDashboardMeasurementAsync(connection, stopwatch.ElapsedMilliseconds, logicalReads, cancellationToken);

        var appointmentVolume = rows.Sum(row => row.AppointmentCount);
        var weightedWait = appointmentVolume == 0
            ? 0
            : rows.Sum(row => row.AverageWaitMinutes * row.AppointmentCount) / appointmentVolume;
        var cancelledCount = CountStatus(rows, "Cancelled");

        return new OperationsDashboardData(
            serviceRegionId,
            fromAtUtc,
            DateTime.UtcNow,
            appointmentVolume,
            CountStatus(rows, "Requested"),
            CountStatus(rows, "Scheduled"),
            CountStatus(rows, "Confirmed"),
            CountStatus(rows, "Completed"),
            cancelledCount,
            weightedWait,
            appointmentVolume == 0 ? 0 : cancelledCount * 100.0 / appointmentVolume,
            rows.Sum(row => row.InstructionBytes),
            rows.Sum(row => row.RevisionCount),
            stopwatch.ElapsedMilliseconds,
            logicalReads,
            rows);
    }

    public async Task<IReadOnlyList<IndexHealthSample>> GetIndexHealthTimelineAsync(
        CancellationToken cancellationToken = default)
    {
        EnsureConfigured();
        var samples = new List<IndexHealthSample>();
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
         command.CommandText = "EXEC demo.usp_GetIndexHealthTimeline;";
        command.CommandTimeout = 30;

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            samples.Add(new IndexHealthSample(
                reader.GetInt64(0),
                reader.GetDateTime(1),
                reader.GetString(2),
                reader.IsDBNull(3) ? null : reader.GetString(3),
                reader.GetBoolean(4),
                reader.GetBoolean(5),
                reader.IsDBNull(6) ? null : reader.GetDecimal(6),
                reader.IsDBNull(7) ? null : reader.GetInt64(7),
                reader.IsDBNull(8) ? null : reader.GetInt64(8),
                reader.IsDBNull(9) ? null : reader.GetDecimal(9),
                reader.IsDBNull(10) ? null : reader.GetInt64(10),
                reader.IsDBNull(11) ? null : reader.GetInt64(11),
                reader.IsDBNull(12) ? null : reader.GetDateTime(12),
                reader.IsDBNull(13) ? null : reader.GetString(13),
                reader.IsDBNull(14) ? null : reader.GetBoolean(14)));
        }

        return samples;
    }

    public async Task CaptureIndexHealthAsync(CancellationToken cancellationToken = default)
    {
        EnsureConfigured();
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = "EXEC demo.usp_CaptureIndexHealth;";
        command.CommandTimeout = 120;
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<DemoControlState> GetDemoControlStateAsync(CancellationToken cancellationToken = default)
    {
        EnsureConfigured();
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = "EXEC demo.usp_GetDemoControlState;";
        command.CommandTimeout = 30;

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException("The demo control state is unavailable.");
        }

        return new DemoControlState(
            reader.GetString(0),
            reader.GetBoolean(1),
            reader.GetBoolean(2),
            reader.GetBoolean(3));
    }

    public async Task<bool> IsReadyAsync(CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            return false;
        }

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = connection.CreateCommand();
            command.CommandText = "EXEC demo.usp_IsAppReady;";
            command.CommandTimeout = 15;
            return Convert.ToBoolean(await command.ExecuteScalarAsync(cancellationToken));
        }
        catch (SqlException)
        {
            return false;
        }
    }

    private async Task RecordDashboardMeasurementAsync(
        SqlConnection connection,
        long durationMs,
        long logicalReads,
        CancellationToken cancellationToken)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = "EXEC demo.usp_RecordDashboardMeasurement @durationMs, @logicalReads;";
        command.Parameters.Add("@durationMs", SqlDbType.BigInt).Value = durationMs;
        command.Parameters.Add("@logicalReads", SqlDbType.BigInt).Value = logicalReads;
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private void EnsureConfigured()
    {
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new InvalidOperationException(
                "ConnectionStrings:Caldova is not configured. No synthetic data is available.");
        }
    }

    private static long CountStatus(IEnumerable<DashboardBreakdownItem> rows, string status) =>
        rows.Where(row => string.Equals(row.AppointmentStatus, status, StringComparison.OrdinalIgnoreCase))
            .Sum(row => row.AppointmentCount);

    [GeneratedRegex(@"logical reads\s+(\d+)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex LogicalReadsRegex();
}