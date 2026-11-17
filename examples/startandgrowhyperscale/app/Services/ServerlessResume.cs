using Microsoft.Data.SqlClient;

namespace CaldovaNetworkScheduling.Services;

public sealed record ResumeResult(TimeSpan Elapsed, int Attempts, DateTimeOffset SignedInAt);

/// <summary>
/// First sign-in after auto-pause. Opens one read-only connection and retries known transient errors
/// (for example 40613 while the database resumes) with backoff. The query only reads; retrying is safe.
/// </summary>
public class ServerlessResume(IConfiguration configuration, ILogger<ServerlessResume> logger)
{
    public static readonly TimeSpan Deadline = TimeSpan.FromMinutes(3);

    // Transient connectivity errors documented for Azure SQL Database, plus a client timeout (-2).
    public static readonly IReadOnlySet<int> Transient = new HashSet<int>
        { -2, 20, 64, 233, 4060, 4221, 10053, 10054, 10060, 10928, 10929, 40143, 40197, 40501, 40540, 40613, 42108, 42109, 49918, 49919, 49920 };

    public virtual async Task<ResumeResult> SignInAsync(ServerlessConfiguration database, Action<int>? onAttempt, CancellationToken token)
    {
        var settings = ServerlessSqlTelemetry.ConnectionSettings(configuration, database, "Caldova.ServerlessResume");
        var clock = System.Diagnostics.Stopwatch.StartNew();
        var attempt = 0;
        while (true)
        {
            attempt++;
            onAttempt?.Invoke(attempt);
            try
            {
                await using var connection = new SqlConnection(settings.ConnectionString);
                await connection.OpenAsync(token);
                using var command = new SqlCommand("SELECT 1;", connection) { CommandTimeout = 30 };
                await command.ExecuteScalarAsync(token);
                return new(clock.Elapsed, attempt, DateTimeOffset.UtcNow);
            }
            catch (SqlException ex) when (ex.Errors.Cast<SqlError>().Any(e => Transient.Contains(e.Number)) && clock.Elapsed < Deadline)
            {
                logger.LogInformation("Resume sign-in attempt {Attempt} returned transient SQL error {Number}; retrying", attempt, ex.Number);
                await Task.Delay(Backoff(attempt), token);
            }
        }
    }

    public static TimeSpan Backoff(int attempt) => TimeSpan.FromSeconds(Math.Min(10, Math.Pow(2, attempt - 1)));
}
