using Azure.Core;
using CaldovaNetworkScheduling.Models;
using Microsoft.Data.SqlClient;
using System.Data;
using System.Text.RegularExpressions;

namespace CaldovaNetworkScheduling.Services;

public sealed record DatabaseStorage(string Key, DateTimeOffset At, long UsedBytes, long AllocatedBytes)
{
    public const long GiB = 1073741824;
    public double UsedGiB => (double)UsedBytes / GiB;
    public double AllocatedGiB => (double)AllocatedBytes / GiB;
}

public class PoolStorage(IConfiguration configuration, TokenCredential credential, ILogger<PoolStorage> logger) : IDisposable
{
    private readonly SemaphoreSlim tokenGate = new(1, 1);
    private AccessToken? sqlToken;
    public const string ReadQuery = """
        SELECT DB_NAME(), SYSUTCDATETIME(), UsedBytes, AllocatedBytes, DataFiles, MissingFiles
        FROM demo.StorageSize;
        """;
    public bool GrowthEnabled => configuration.GetValue<bool>("PoolGrowth:Enabled")
        && configuration.GetValue<bool>("PoolScaling:Enabled") && !configuration.GetValue<bool>("Demo:Playback");
    public static int SeedTarget(string key) => key switch
    {
        "caldova" => 18, "northbrook" => 12, "ridgeview" => 15,
        _ => throw new ArgumentException("Unknown storage provider.", nameof(key))
    };
    public static long TargetBytes(string key, int targetGiB)
    {
        var maximum = key == "caldova" ? 22 : SeedTarget(key);
        if (targetGiB < 1 || targetGiB > maximum)
            throw new ArgumentOutOfRangeException(nameof(targetGiB), "Storage target exceeds the approved provider limit.");
        return targetGiB * DatabaseStorage.GiB;
    }
    public static void ValidateSeeded(IReadOnlyList<DatabaseStorage> readings)
    {
        foreach (var provider in ProviderProfiles.All)
            if (!readings.Any(reading => reading.Key == provider.Key
                && reading.UsedBytes >= TargetBytes(provider.Key, SeedTarget(provider.Key))))
                throw new InvalidOperationException("Run Grow storage seeding first: Caldova 18 GiB, Northbrook 12 GiB, Ridgeview 15 GiB used.");
    }
    private async Task<SqlConnection> OpenAsync(ProviderDemoProfile provider, CancellationToken token)
    {
        if (!ProviderProfiles.All.Contains(provider)) throw new ArgumentException("Unknown provider.", nameof(provider));
        _ = NetworkResourceMonitor.Target(configuration);
        var source = new ServerlessConfiguration(configuration["ServerlessMonitor:ResourceId"]!, "Online", 0, 8);
        var settings = ServerlessSqlTelemetry.ConnectionSettings(configuration, source, "Caldova.PoolStorage");
        settings.InitialCatalog = provider.Database;
        var connection = CreateSqlConnection(settings.ConnectionString);
        try { await connection.OpenAsync(token); return connection; }
        catch { await connection.DisposeAsync(); throw; }
    }
    public SqlConnection CreateSqlConnection(string connectionString)
    {
        var settings = new SqlConnectionStringBuilder(connectionString);
        if (settings.IntegratedSecurity || settings.UserID.Length != 0 || settings.Password.Length != 0)
            throw new InvalidOperationException("Pool operations require Entra SQL authentication without SQL credentials.");
        settings.Authentication = SqlAuthenticationMethod.NotSpecified;
        return new(settings.ConnectionString) { AccessTokenCallback = AuthenticateSqlAsync };
    }
    private async Task<SqlAuthenticationToken> AuthenticateSqlAsync(SqlAuthenticationParameters parameters, CancellationToken token)
    {
        if (!parameters.Resource.TrimEnd('/').Equals("https://database.windows.net", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Pool authentication is restricted to the Azure SQL token audience.");
        var access = await GetSqlTokenAsync(token);
        return new(access.Token, access.ExpiresOn);
    }
    protected async Task<AccessToken> GetSqlTokenAsync(CancellationToken token)
    {
        await tokenGate.WaitAsync(token);
        try
        {
            if (sqlToken is { } cached && cached.ExpiresOn > DateTimeOffset.UtcNow.AddMinutes(5))
                return cached;
            var access = await credential.GetTokenAsync(new TokenRequestContext(["https://database.windows.net/.default"]), token);
            if (string.IsNullOrWhiteSpace(access.Token) || access.ExpiresOn <= DateTimeOffset.UtcNow)
                throw new InvalidOperationException("The SQL credential returned an empty or expired access token.");
            sqlToken = access;
            return access;
        }
        finally { tokenGate.Release(); }
    }
    public void Dispose() => tokenGate.Dispose();
    public static string SetupSql(string sql, IConfiguration configuration)
    {
        if (!sql.Contains(DemoResourceNames.AppNameVariable, StringComparison.Ordinal)) return sql;
        return sql.Replace(DemoResourceNames.AppNameVariable, DemoResourceNames.ResolveAppName(configuration), StringComparison.Ordinal);
    }
    public virtual async Task SetupAsync(ProviderDemoProfile provider, CancellationToken token)
    {
        using var stream = typeof(PoolStorage).Assembly.GetManifestResourceStream("DemoStorage.sql")
            ?? throw new InvalidOperationException("The demo storage SQL resource is missing.");
        using var reader = new StreamReader(stream);
        var sql = SetupSql(await reader.ReadToEndAsync(token), configuration);
        await using var connection = await OpenAsync(provider, token);
        foreach (var batch in Regex.Split(sql, @"^[ \t]*GO[ \t]*\r?$", RegexOptions.Multiline | RegexOptions.IgnoreCase)
            .Where(batch => !string.IsNullOrWhiteSpace(batch)))
        {
            using var command = new SqlCommand(batch, connection) { CommandTimeout = 120 };
            await command.ExecuteNonQueryAsync(token);
        }
    }
    public virtual async Task<DatabaseStorage> ReadAsync(ProviderDemoProfile provider, CancellationToken token)
    {
        await using var connection = await OpenAsync(provider, token);
        return await ReadAsync(connection, provider, token);
    }
    public async Task<IReadOnlyList<DatabaseStorage>> ReadAllAsync(CancellationToken token) =>
        await Task.WhenAll(ProviderProfiles.All.Select(provider => ReadAsync(provider, token)));
    private static async Task<DatabaseStorage> ReadAsync(SqlConnection connection, ProviderDemoProfile provider, CancellationToken token)
    {
        using var command = new SqlCommand(ReadQuery, connection) { CommandTimeout = 30 };
        await using var reader = await command.ExecuteReaderAsync(token);
        if (!await reader.ReadAsync(token) || reader.GetString(0) != provider.Database
            || reader.IsDBNull(2) || reader.IsDBNull(3) || reader.GetInt32(4) == 0 || reader.GetInt32(5) != 0)
            throw new InvalidOperationException("SQL storage measurement is missing, incomplete, or from the wrong database.");
        var result = new DatabaseStorage(provider.Key,
            new(DateTime.SpecifyKind(reader.GetDateTime(1), DateTimeKind.Utc)), reader.GetInt64(2), reader.GetInt64(3));
        if (result.UsedBytes < 0 || result.AllocatedBytes <= 0 || result.UsedBytes > result.AllocatedBytes)
            throw new InvalidOperationException("SQL reported invalid data-file space.");
        return result;
    }
    protected async Task<DatabaseStorage> ReadAfterTimeBudgetAsync(ProviderDemoProfile provider,
        Action<DatabaseStorage> measured, CancellationToken token)
    {
        using var verification = CancellationTokenSource.CreateLinkedTokenSource(token);
        verification.CancelAfter(TimeSpan.FromSeconds(10));
        try
        {
            var final = await ReadAsync(provider, verification.Token);
            measured(final);
            return final;
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (SqlException ex) when (token.IsCancellationRequested)
        {
            throw new OperationCanceledException("Storage verification was stopped.", ex, token);
        }
        catch (Exception ex) when (ex is SqlException or OperationCanceledException or InvalidOperationException)
        {
            logger.LogError("Storage verification after timed stop failed for {Provider}: {Error}",
                provider.Key, AzureCliRunner.Redact(ex.Message));
            throw new InvalidOperationException($"{provider.Name} storage measurements could not be verified after stopping. Committed data remains; check SQL access.", ex);
        }
    }
    public virtual async Task<DatabaseStorage> FillToAsync(ProviderDemoProfile provider, int targetGiB,
        Action<DatabaseStorage> measured, TimeSpan limit, CancellationToken token,
        Func<DatabaseStorage, bool>? stopWhen = null, bool allowPartialOnTimeout = false)
    {
        var target = TargetBytes(provider.Key, targetGiB);
        if (limit <= TimeSpan.Zero || limit > TimeSpan.FromHours(2)) throw new ArgumentOutOfRangeException(nameof(limit));
        using var bounded = CancellationTokenSource.CreateLinkedTokenSource(token);
        bounded.CancelAfter(limit);
        try
        {
            await using var connection = await OpenAsync(provider, bounded.Token);
            var current = await ReadAsync(connection, provider, bounded.Token);
            measured(current);
            var initial = current.UsedBytes;
            while (current.UsedBytes < target && stopWhen?.Invoke(current) != true)
            {
                bounded.Token.ThrowIfCancellationRequested();
                using var command = new SqlCommand("demo.FillStorageBatch", connection)
                {
                    CommandType = CommandType.StoredProcedure, CommandTimeout = 120
                };
                command.Parameters.Add("@TargetBytes", SqlDbType.BigInt).Value = target;
                command.Parameters.Add("@MaxRows", SqlDbType.Int).Value = 4096;
                try { await command.ExecuteScalarAsync(bounded.Token); }
                catch (Exception ex) when (token.IsCancellationRequested && ex is SqlException or OperationCanceledException)
                {
                    throw new OperationCanceledException("Storage fill was stopped.", ex, token);
                }
                catch (Exception ex) when (bounded.IsCancellationRequested && ex is SqlException or OperationCanceledException)
                {
                    throw new OperationCanceledException("Storage fill time limit reached.", ex, bounded.Token);
                }
                catch (Exception ex) when (ex is SqlException or OperationCanceledException or InvalidOperationException)
                {
                    logger.LogError("Storage batch failed for {Provider}: {Error}", provider.Key, AzureCliRunner.Redact(ex.Message));
                    throw new InvalidOperationException($"{provider.Name} storage insert outcome may be unconfirmed. Committed synthetic data remains; inspect measured space before rerunning. {AzureCliRunner.Redact(ex.Message)}");
                }
                var next = await ReadAsync(connection, provider, bounded.Token);
                if (next.UsedBytes <= current.UsedBytes)
                    throw new InvalidOperationException("Storage insertion did not increase measured used space. No batch will be retried.");
                if (next.UsedBytes > target + 64 * 1024 * 1024L)
                    throw new InvalidOperationException("Storage exceeded the target tolerance. Stop and inspect concurrent data changes.");
                current = next;
                measured(current);
            }
            logger.LogInformation("{Provider} used data: {Before:F3} to {After:F3} GiB; ceiling {Target} GiB",
                provider.Key, (double)initial / DatabaseStorage.GiB, current.UsedGiB, targetGiB);
            return current;
        }
        catch (Exception ex) when (!token.IsCancellationRequested && bounded.IsCancellationRequested
            && ex is SqlException or OperationCanceledException)
        {
            if (allowPartialOnTimeout)
            {
                logger.LogWarning("Storage demo stopped at its {Seconds}-second budget for {Provider}; verifying actual committed space without replaying writes",
                    limit.TotalSeconds, provider.Key);
                return await ReadAfterTimeBudgetAsync(provider, measured, token);
            }
            logger.LogError("Storage fill reached its {Seconds}-second limit for {Provider}", limit.TotalSeconds, provider.Key);
            throw new InvalidOperationException($"{provider.Name} storage fill reached its {limit.TotalSeconds:0}-second limit before SQL confirmation. Committed data remains; inspect measured space before another growth run.", ex);
        }
    }
}
