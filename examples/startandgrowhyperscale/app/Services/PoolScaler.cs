using Microsoft.Extensions.Hosting;

namespace CaldovaNetworkScheduling.Services;

public sealed record PoolScaleState(bool Running, int? Target, string? Error, long Revision);

public sealed class PoolScaler(IAzureCliRunner cli, NetworkResourceMonitor monitor,
    IConfiguration configuration, IHostApplicationLifetime lifetime, ILogger<PoolScaler> logger)
{
    public const int PerDatabaseMaxVCores = 12;
    private readonly SemaphoreSlim gate = new(1, 1);
    private PoolScaleState state = new(false, null, null, 0);
    public bool Enabled => configuration.GetValue<bool>("PoolScaling:Enabled")
        && !configuration.GetValue<bool>("Demo:Playback");
    public PoolScaleState State => Volatile.Read(ref state);

    public static void ValidateHost(IConfiguration configuration)
    {
        if (!configuration.GetValue<bool>("PoolScaling:Enabled") && !configuration.GetValue<bool>("PoolGrowth:Enabled")
            && !configuration.GetValue<bool>("PoolPresentation:Enabled")
            && !configuration.GetValue<bool>("BookingReset:Enabled")) return;
        var urls = configuration["urls"]?.Split(';', StringSplitOptions.RemoveEmptyEntries);
        if (urls is null || urls.Length == 0 || urls.Any(url => !Uri.TryCreate(url, UriKind.Absolute, out var uri)
            || uri.Scheme is not ("http" or "https")
            || !(uri.Host == "localhost" || System.Net.IPAddress.TryParse(uri.Host, out var ip) && System.Net.IPAddress.IsLoopback(ip))))
            throw new InvalidOperationException("Pool scaling, storage growth, presentation, or booking reset may only be enabled on an explicitly localhost-bound demo app.");
    }

    public async Task ScaleAsync(int capacity)
    {
        if (!Enabled) throw new InvalidOperationException("Live pool scaling is disabled on this app host.");
        if (capacity is not (8 or 24)) throw new ArgumentOutOfRangeException(nameof(capacity), "Use 8 or 24 vCores.");
        if (!await gate.WaitAsync(0)) throw new InvalidOperationException("A pool scale is already running.");
        var revision = State.Revision + 1;
        Volatile.Write(ref state, new(true, capacity, null, revision));
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(lifetime.ApplicationStopping);
        timeout.CancelAfter(TimeSpan.FromMinutes(30));
        try
        {
            var target = NetworkResourceMonitor.Target(configuration);
            var account = await cli.RunAsync(["account", "show", "--query", "id", "--output", "tsv"], timeout.Token);
            if (!account.Equals(target.Subscription, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("The current Azure CLI subscription does not match the demo target. No scale was submitted.");
            var before = await monitor.ReadAsync(timeout.Token);
            ValidatePool(before);
            var maximum = Math.Min(capacity, PerDatabaseMaxVCores);
            if (before.VCores != capacity || before.MaxVCoresPerDatabase != maximum)
            {
                await cli.RunAsync(["sql", "elastic-pool", "update",
                    "--subscription", target.Subscription, "--resource-group", target.ResourceGroup,
                    "--server", target.Server, "--name", target.Pool,
                    "--capacity", capacity.ToString(System.Globalization.CultureInfo.InvariantCulture),
                    "--db-min-capacity", before.MinVCoresPerDatabase.ToString(System.Globalization.CultureInfo.InvariantCulture),
                    "--db-max-capacity", maximum.ToString(System.Globalization.CultureInfo.InvariantCulture),
                    "--only-show-errors", "--output", "none"], timeout.Token);
            }
            var after = await monitor.ReadAsync(timeout.Token);
            ValidatePool(after);
            if (after.VCores != capacity || after.MinVCoresPerDatabase != before.MinVCoresPerDatabase
                || after.MaxVCoresPerDatabase != maximum)
                throw new InvalidOperationException("Azure has not reached the requested capacity and per-database limits. Inspect the pool before trying again.");
            Volatile.Write(ref state, new(false, capacity, null, revision + 1));
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException
            or System.Text.Json.JsonException or KeyNotFoundException or FormatException
            or System.ComponentModel.Win32Exception or IOException or UnauthorizedAccessException or OperationCanceledException
            or Azure.Identity.AuthenticationFailedException or Azure.Identity.CredentialUnavailableException)
        {
            var error = ex is OperationCanceledException
                ? "Scale monitoring ended. An Azure operation may still be running; inspect the pool before trying again."
                : AzureCliRunner.Redact(ex.Message);
            logger.LogError("Pool scale to {Capacity} failed: {Error}", capacity, error);
            Volatile.Write(ref state, new(false, capacity, error, revision + 1));
            throw new InvalidOperationException(error);
        }
        finally { gate.Release(); }
    }

    internal static void ValidatePool(NetworkResources resources)
    {
        if (resources.IsPlayback || resources.Tier != "Hyperscale" || resources.Hardware != "Gen5"
            || resources.State != "Ready" || resources.VCores is not (8 or 24)
            || resources.MinVCoresPerDatabase != 0 || resources.MaxVCoresPerDatabase is not (8 or PerDatabaseMaxVCores)
            || resources.MaxVCoresPerDatabase > resources.VCores
            || !Models.ProviderProfiles.All.All(provider => resources.Databases.Any(database =>
                database.Name == provider.Database && database.Pool == resources.Pool && database.Status == "Online")))
            throw new InvalidOperationException("Scaling requires the Ready Hyperscale Gen5 demo pool at 8 or 24 vCores, all three providers Online in it, minimum zero and maximum eight or twelve per database, not exceeding pool capacity.");
    }
}
