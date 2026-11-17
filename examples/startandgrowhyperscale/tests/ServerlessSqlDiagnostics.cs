using System.Data;
using CaldovaNetworkScheduling.Services;
using Microsoft.Data.SqlClient;

internal sealed record SessionCpuSample(short Id, DateTime LoginTime, int CpuMilliseconds);

internal sealed class SessionCpuTracker
{
    private DateTime? previousAt;
    private Dictionary<(short, DateTime), int> previous = [];

    public double? Observe(DateTime at, IReadOnlyList<SessionCpuSample> sessions)
    {
        var current = sessions.ToDictionary(s => (s.Id, s.LoginTime), s => s.CpuMilliseconds);
        double? cores = null;
        if (previousAt is { } start)
        {
            if (at <= start) throw new InvalidOperationException("SQL diagnostic timestamps must increase.");
            long milliseconds = 0;
            foreach (var (key, cpu) in current)
            {
                if (previous.TryGetValue(key, out var before))
                {
                    if (cpu < before) throw new InvalidOperationException("A workload session CPU counter decreased.");
                    milliseconds += cpu - before;
                }
                else if (key.Item2 >= start)
                    milliseconds += cpu;
            }
            // Closed sessions lose their final counter; do not report an incomplete delta as zero.
            if (previous.Keys.All(current.ContainsKey)
                && current.Keys.All(key => previous.ContainsKey(key) || key.Item2 >= start))
                cores = milliseconds / (at - start).TotalMilliseconds;
        }
        previousAt = at;
        previous = current;
        return cores;
    }
}

internal sealed class ServerlessSqlDiagnostics(string connectionString) : IAsyncDisposable
{
    private readonly SqlConnection connection = new(connectionString);
    private readonly SessionCpuTracker cpu = new();
    private readonly Dictionary<DateTimeOffset, ServerlessCpuSample> samples = [];
    private Dictionary<string, (long Tasks, long Wait, long Signal)>? initialWaits;
    private Dictionary<string, (long Tasks, long Wait, long Signal)> finalWaits = [];

    public Task OpenAsync(CancellationToken token) => connection.OpenAsync(token);

    public async Task CaptureAsync(DateTime fromUtc, CancellationToken token)
    {
        const string query = """
            SET NOCOUNT ON;
            SELECT end_time, avg_cpu_percent, cpu_limit, avg_instance_cpu_percent,
                   avg_memory_usage_percent, avg_data_io_percent, avg_log_write_percent
            FROM sys.dm_db_resource_stats
            WHERE end_time >= @from AND replica_role = 0
            ORDER BY end_time;

            SELECT SYSUTCDATETIME();
            SELECT s.session_id, s.login_time, s.cpu_time, s.status,
                   r.status AS request_status, r.wait_type, r.cpu_time AS request_cpu_ms,
                   r.blocking_session_id
            FROM sys.dm_exec_sessions AS s
            LEFT JOIN sys.dm_exec_requests AS r ON r.session_id = s.session_id
            WHERE s.program_name = N'Caldova.ServerlessDemo' AND s.is_user_process = 1;

            SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms
            FROM sys.dm_db_wait_stats;
            """;
        using var command = new SqlCommand(query, connection) { CommandTimeout = 15 };
        command.Parameters.Add("@from", SqlDbType.DateTime).Value = fromUtc;
        await using var reader = await command.ExecuteReaderAsync(token);
        while (await reader.ReadAsync(token))
        {
            if (reader.IsDBNull(2))
                throw new InvalidOperationException("The database did not report a vCore limit.");
            var sample = new ServerlessCpuSample(
                new DateTimeOffset(DateTime.SpecifyKind(reader.GetDateTime(0), DateTimeKind.Utc)),
                (double)reader.GetDecimal(1), (double)reader.GetDecimal(2));
            if (!samples.TryGetValue(sample.At, out var previous) || previous != sample)
            {
                samples[sample.At] = sample;
                Console.WriteLine($"DMV: end-UTC={sample.At:O} CPU%={sample.CpuPercent} cpu_limit={sample.CpuLimit} used-vCores={sample.UsedVCores:F4} instance-CPU%={reader.GetValue(3)} memory%={reader.GetValue(4)} data-IO%={reader.GetValue(5)} log-IO%={reader.GetValue(6)}");
            }
        }
        await reader.NextResultAsync(token);
        await reader.ReadAsync(token);
        var at = reader.GetDateTime(0);
        await reader.NextResultAsync(token);
        var sessions = new List<SessionCpuSample>();
        while (await reader.ReadAsync(token))
        {
            var session = new SessionCpuSample(reader.GetInt16(0), reader.GetDateTime(1), reader.GetInt32(2));
            sessions.Add(session);
            Console.WriteLine($"SESSION: id={session.Id} login={session.LoginTime:O} cpu-ms={session.CpuMilliseconds} status={reader.GetValue(3)} request={reader.GetValue(4)} wait={reader.GetValue(5)} request-cpu-ms={reader.GetValue(6)} blocker={reader.GetValue(7)}");
        }
        var sessionCores = cpu.Observe(at, sessions);
        Console.WriteLine($"SESSION DELTA: SQL-UTC={at:O} active-sessions={sessions.Count} average-used-vCores={sessionCores?.ToString("F4") ?? "Unavailable (first sample or changed session visibility)"}");
        await reader.NextResultAsync(token);
        finalWaits = [];
        while (await reader.ReadAsync(token))
            finalWaits.Add(reader.GetString(0), (reader.GetInt64(1), reader.GetInt64(2), reader.GetInt64(3)));
        initialWaits ??= finalWaits;
    }

    public void PrintSummary()
    {
        if (samples.Count == 0) throw new InvalidOperationException("No primary-replica resource-stat samples were delivered.");
        var peak = samples.Values.MaxBy(s => s.UsedVCores)!;
        Console.WriteLine($"DMV PEAK: {peak.At:O} CPU%={peak.CpuPercent} cpu_limit={peak.CpuLimit} used-vCores={peak.UsedVCores:F4}. Interval average, not allocated compute.");
        if (initialWaits is null) throw new InvalidOperationException("No wait-stat baseline was captured.");
        var deltas = finalWaits.Select(pair =>
        {
            var before = initialWaits.GetValueOrDefault(pair.Key);
            if (pair.Value.Tasks < before.Tasks || pair.Value.Wait < before.Wait || pair.Value.Signal < before.Signal)
                throw new InvalidOperationException("Database wait counters decreased; the diagnostic window is invalid.");
            return (Type: pair.Key, Tasks: pair.Value.Tasks - before.Tasks,
                Wait: pair.Value.Wait - before.Wait, Signal: pair.Value.Signal - before.Signal);
        }).Where(d => d.Wait > 0).OrderByDescending(d => d.Wait).Take(15);
        Console.WriteLine("DATABASE WAIT DELTAS: all database activity, including diagnostic/background activity; not workload-exclusive.");
        foreach (var delta in deltas)
            Console.WriteLine($"WAIT: {delta.Type} tasks={delta.Tasks} wait-ms={delta.Wait} signal-ms={delta.Signal}");
    }

    public ValueTask DisposeAsync() => connection.DisposeAsync();
}
