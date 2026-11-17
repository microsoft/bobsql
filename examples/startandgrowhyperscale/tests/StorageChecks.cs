using CaldovaNetworkScheduling.Models;
using CaldovaNetworkScheduling.Services;
using Azure.Core;
using Azure.Identity;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;

internal static class StorageChecks
{
    public static void Run(Action<bool, string> check)
    {
        check(ProviderProfiles.All.Select(provider => PoolStorage.SeedTarget(provider.Key)).SequenceEqual([18, 12, 15]),
            "Initial storage seeding staggers actual used-data targets at 18/12/15 GiB");
        check(PoolStorage.TargetBytes("caldova", 22) == 22L * 1073741824
            && new DatabaseStorage("caldova", DateTimeOffset.UtcNow, 18L * 1073741824, 20L * 1073741824)
                is { UsedGiB: 18, AllocatedGiB: 20 },
            "Used and allocated space remain distinct and use binary GiB consistently");
        foreach (var (key, value) in new[] { ("caldova", 0), ("caldova", 23), ("northbrook", 13), ("ridgeview", 16), ("unknown", 1) })
        {
            var rejected = false;
            try { PoolStorage.TargetBytes(key, value); }
            catch (ArgumentException) { rejected = true; }
            check(rejected, "Out-of-scope provider/size cannot request an insert");
        }
        var baseline = ProviderProfiles.All.Select(provider => new DatabaseStorage(provider.Key, DateTimeOffset.UtcNow,
            PoolStorage.TargetBytes(provider.Key, PoolStorage.SeedTarget(provider.Key)), 20L * 1073741824)).ToArray();
        PoolStorage.ValidateSeeded(baseline);
        check(true, "Measured seeded targets satisfy the Step 4 growth prerequisite");
        foreach (var readings in new IReadOnlyList<DatabaseStorage>[]
            { baseline.Take(2).ToArray(), baseline.Select(reading => reading with { UsedBytes = 24 * 1024 * 1024 }).ToArray() })
        {
            var rejected = false;
            try { PoolStorage.ValidateSeeded(readings); }
            catch (InvalidOperationException) { rejected = true; }
            check(rejected, "Missing or still-tiny databases cannot start Step 4 inserts");
        }
        using var stream = typeof(PoolStorage).Assembly.GetManifestResourceStream("DemoStorage.sql")!;
        using var reader = new StreamReader(stream);
        var sql = reader.ReadToEnd();
        check(sql.Contains("binary(7800)") && sql.Contains("DATA_COMPRESSION = NONE")
            && sql.Contains("INSERT demo.StoragePayload") && sql.Contains("CRYPT_GEN_RANDOM(7800)")
            && !sql.Contains("INSERT dbo.Appointment") && !sql.Contains("DELETE") && !sql.Contains("TRUNCATE"),
            "Only a dedicated uncompressed synthetic payload table receives inserts; scheduling data is untouched");
        check(sql.Contains("@MaxRows NOT BETWEEN 1 AND 4096") && sql.Contains("@TargetBytes IS NULL")
            && sql.Contains("@TargetBytes > @maximum") && sql.Contains("@MaxRows IS NULL")
            && sql.Contains("SET XACT_ABORT ON") && sql.Contains("@LockOwner='Transaction'")
            && sql.IndexOf("COMMIT TRANSACTION", StringComparison.Ordinal) < sql.IndexOf("SELECT @inserted", StringComparison.Ordinal),
            "SQL enforces absolute targets, batch limits, exclusive transaction ownership, and commits before acknowledging");
        check(sql.Contains("GRANT SELECT ON OBJECT::demo.StorageSize")
            && sql.Contains("GRANT EXECUTE ON OBJECT::demo.FillStorageBatch")
            && !sql.Contains("CREATE USER") && !sql.Contains("db_owner") && !sql.Contains("GRANT INSERT"),
            "The existing app user receives only size-view and bounded-procedure access, not broad table writes or roles");
    }

    internal sealed class Fake(IConfiguration configuration)
        : PoolStorage(configuration, new TestCredential(), NullLogger<PoolStorage>.Instance)
    {
        public Dictionary<string, int> UsedGiB { get; } = new() { ["caldova"] = 18, ["northbrook"] = 12, ["ridgeview"] = 15 };
        public Dictionary<string, int> AllocatedGiB { get; } = new() { ["caldova"] = 30, ["northbrook"] = 30, ["ridgeview"] = 30 };
        public int FillCalls { get; private set; }
        public TimeSpan LastLimit { get; private set; }
        public string? FailRead { get; set; }
        public bool FailWrite { get; set; }
        public string? FailWriteKey { get; set; }
        public Task? HoldWrite { get; set; }
        public Exception? CancellationError { get; set; }
        public Func<DatabaseStorage, bool>? LastStopWhen { get; private set; }
        public bool LastAllowPartial { get; private set; }
        public bool SimulateTimeBudgetStop { get; set; }
        public Task<DatabaseStorage> VerifyTimedStopAsync(ProviderDemoProfile provider,
            Action<DatabaseStorage> measured, CancellationToken token) => ReadAfterTimeBudgetAsync(provider, measured, token);
        public override Task<DatabaseStorage> ReadAsync(ProviderDemoProfile provider, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            if (provider.Key == FailRead) throw new InvalidOperationException("Storage read denied");
            return Task.FromResult(new DatabaseStorage(provider.Key, DateTimeOffset.UtcNow,
                UsedGiB[provider.Key] * DatabaseStorage.GiB, AllocatedGiB[provider.Key] * DatabaseStorage.GiB));
        }
        public override async Task<DatabaseStorage> FillToAsync(ProviderDemoProfile provider, int targetGiB,
            Action<DatabaseStorage> measured, TimeSpan limit, CancellationToken token,
            Func<DatabaseStorage, bool>? stopWhen = null, bool allowPartialOnTimeout = false)
        {
            FillCalls++;
            LastLimit = limit;
            LastStopWhen = stopWhen;
            LastAllowPartial = allowPartialOnTimeout;
            TargetBytes(provider.Key, targetGiB);
            var initial = await ReadAsync(provider, token);
            measured(initial);
            if (stopWhen?.Invoke(initial) == true) return initial;
            if (FailWrite || provider.Key == FailWriteKey) throw new InvalidOperationException("Commit outcome unconfirmed; inspect before rerunning.");
            if (SimulateTimeBudgetStop)
            {
                if (allowPartialOnTimeout) return await ReadAfterTimeBudgetAsync(provider, measured, token);
                throw new InvalidOperationException("Required initial fill did not complete.");
            }
            if (HoldWrite is { } pending)
            {
                try { await pending.WaitAsync(token); }
                catch (OperationCanceledException) when (token.IsCancellationRequested && CancellationError is not null)
                {
                    throw CancellationError;
                }
            }
            UsedGiB[provider.Key] = Math.Max(UsedGiB[provider.Key], targetGiB);
            if (provider.Key == "caldova" && UsedGiB[provider.Key] > 20)
                AllocatedGiB[provider.Key] = Math.Max(AllocatedGiB[provider.Key], 30);
            var result = await ReadAsync(provider, token);
            measured(result);
            return result;
        }
    }

    public static async Task CheckSeedCancellationAsync(Action<bool, string> check, IConfiguration configuration)
    {
        var held = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var storage = new Fake(configuration) { FailWriteKey = "northbrook", HoldWrite = held.Task };
        storage.UsedGiB["caldova"] = storage.UsedGiB["northbrook"] = storage.UsedGiB["ridgeview"] = 1;
        var rejected = false;
        try { await StorageFillCommand.SeedAsync(storage, CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(5)); }
        catch (InvalidOperationException) { rejected = true; }
        check(rejected && storage.FillCalls == 3 && storage.UsedGiB.Values.All(value => value == 1),
            "A failing initial fill cancels and joins sibling inserts promptly without replay or success-shaped completion");
        using var timed = new Fake(configuration) { SimulateTimeBudgetStop = true };
        timed.UsedGiB["caldova"] = 19;
        var measurements = new List<DatabaseStorage>();
        var final = await timed.VerifyTimedStopAsync(ProviderProfiles.All[0], measurements.Add, CancellationToken.None);
        check(final.UsedGiB == 19 && measurements.Single() == final && timed.FillCalls == 0,
            "Timed-stop verification publishes a fresh actual reading without inserting or claiming the growth target was met");
        timed.FailRead = "caldova";
        rejected = false;
        try { await timed.VerifyTimedStopAsync(ProviderProfiles.All[0], measurements.Add, CancellationToken.None); }
        catch (InvalidOperationException) { rejected = true; }
        check(rejected && measurements.Count == 1,
            "Failed timed-stop verification is surfaced rather than replaced with stale or invented storage");
        timed.FailRead = null;
        rejected = false;
        try
        {
            await timed.FillToAsync(ProviderProfiles.All[0], 21, measurements.Add, TimeSpan.FromSeconds(45),
                CancellationToken.None);
        }
        catch (InvalidOperationException) { rejected = true; }
        check(rejected && !timed.LastAllowPartial,
            "Initial seeding retains required-target failure semantics; only the demo explicitly accepts measured partial growth");
    }

    public static async Task CheckTokensAsync(Action<bool, string> check, IConfiguration configuration)
    {
        var credential = new CountingCredential();
        using var storage = new TokenStorage(configuration, credential);
        await Task.WhenAll(Enumerable.Range(0, 12).Select(_ => storage.TokenAsync(CancellationToken.None)));
        check(credential.Calls == 1 && credential.Scope == "https://database.windows.net/.default",
            "Concurrent provider observations share one SQL token acquisition instead of spawning repeated CLI processes");
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        var rejected = false;
        try { await storage.TokenAsync(cancelled.Token); }
        catch (OperationCanceledException) { rejected = true; }
        check(rejected && credential.Calls == 1, "Cancelled observations do not acquire or return credentials");

        var expiring = new CountingCredential { ExpiresOn = DateTimeOffset.UtcNow.AddMinutes(1) };
        using var refresh = new TokenStorage(configuration, expiring);
        await refresh.TokenAsync(CancellationToken.None);
        expiring.ExpiresOn = DateTimeOffset.UtcNow.AddHours(1);
        await refresh.TokenAsync(CancellationToken.None);
        await refresh.TokenAsync(CancellationToken.None);
        check(expiring.Calls == 2, "SQL tokens refresh inside the five-minute expiry margin and then remain shared");

        var failing = new CountingCredential { Fail = true };
        using var failure = new TokenStorage(configuration, failing);
        rejected = false;
        try { await failure.TokenAsync(CancellationToken.None); }
        catch (AuthenticationFailedException) { rejected = true; }
        check(rejected && failing.Calls == 1, "Credential failures surface immediately without automatic retries or cache clearing");
        failing.Fail = false;
        await failure.TokenAsync(CancellationToken.None);
        await failure.TokenAsync(CancellationToken.None);
        check(failing.Calls == 2, "Failed authentication does not poison subsequent explicit token acquisition");

        var expired = new CountingCredential { ExpiresOn = DateTimeOffset.UtcNow.AddMinutes(-1) };
        using var invalid = new TokenStorage(configuration, expired);
        rejected = false;
        try { await invalid.TokenAsync(CancellationToken.None); }
        catch (InvalidOperationException) { rejected = true; }
        check(rejected && expired.Calls == 1, "Expired credential responses cannot open SQL connections");
    }

    private sealed class TokenStorage(IConfiguration configuration, TokenCredential credential)
        : PoolStorage(configuration, credential, NullLogger<PoolStorage>.Instance)
    {
        public Task<AccessToken> TokenAsync(CancellationToken token) => GetSqlTokenAsync(token);
    }

    private sealed class CountingCredential : TokenCredential
    {
        public int Calls { get; private set; }
        public string? Scope { get; private set; }
        public bool Fail { get; set; }
        public DateTimeOffset ExpiresOn { get; set; } = DateTimeOffset.UtcNow.AddHours(1);
        public override AccessToken GetToken(TokenRequestContext context, CancellationToken token) =>
            throw new NotSupportedException("Only asynchronous credential acquisition is expected.");
        public override async ValueTask<AccessToken> GetTokenAsync(TokenRequestContext context, CancellationToken token)
        {
            Calls++;
            Scope = context.Scopes.Single();
            await Task.Delay(10, token);
            if (Fail) throw new AuthenticationFailedException("Encrypted CLI cache could not be decrypted.");
            return new("offline-test-token", ExpiresOn);
        }
    }
}
