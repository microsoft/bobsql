using System.Net;
using System.Text.Json;
using CaldovaNetworkScheduling.Services;
using Microsoft.Extensions.Configuration;

internal static class NetworkResourceChecks
{
    public static (NetworkResourceMonitor Monitor, ResourceHandler Handler) Create(IConfiguration configuration)
    {
        var source = configuration["ServerlessMonitor:ResourceId"]!;
        var parts = source.Split('/', StringSplitOptions.RemoveEmptyEntries);
        var settings = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["ServerlessMonitor:ResourceId"] = source,
            ["ConnectionStrings:Scheduling"] = $"Server=tcp:{parts[7]}.database.windows.net,1433;Initial Catalog=caldova-scheduling;Encrypt=True"
        }).Build();
        var handler = new ResourceHandler(source);
        return (new NetworkResourceMonitor(new HttpClient(handler), new TestCredential(), settings), handler);
    }

    public static async Task RunAsync(Action<bool, string> check, IConfiguration configuration)
    {
        var (monitor, handler) = Create(configuration);
        var resources = await monitor.ReadAsync(CancellationToken.None);
        check(resources.VCores == 8 && resources.MinVCoresPerDatabase == 0 && resources.MaxVCoresPerDatabase == 8
            && resources.State == "Ready" && resources.Location == "eastus2"
            && resources.Tier == "Hyperscale" && resources.Hardware == "Gen5",
            "Network resource details use actual pool capacity, limits, state, region, tier, and hardware from ARM");
        check(resources.Databases.Count == 3 && resources.Databases.All(db => db.Status == "Online"
            && db.Pool == resources.Pool && db.Objective == "ElasticPool"),
            "Each provider database has independently verified pool membership, state, and service objective");
        check(handler.Requests.Count == 4 && handler.Requests.All(uri => uri.Host == "management.azure.com"
            && uri.Query == "?api-version=2023-08-01"),
            "Network resources use only four read-only ARM requests, with no SQL access");
        check(!JsonSerializer.Serialize(resources).Contains("/subscriptions/", StringComparison.OrdinalIgnoreCase),
            "Display models do not expose subscription-bearing resource IDs");
        handler.Capacity = 16;
        handler.Standalone = true;
        resources = await monitor.ReadAsync(CancellationToken.None);
        check(resources.VCores == 16 && resources.Databases[2].Pool is null
            && resources.Databases[2].Objective == "HS_Gen5_4",
            "A refresh reflects changed pool capacity and does not claim standalone providers are pooled");
        foreach (var failure in new[] { "Denied", "WrongId", "OtherPool", "Malformed" })
        {
            handler.Failure = failure;
            var failed = false;
            try { await monitor.ReadAsync(CancellationToken.None); }
            catch (Exception ex) when (ex is HttpRequestException or InvalidOperationException or JsonException)
            {
                failed = true;
                check(!ex.Message.Contains("/subscriptions/", StringComparison.OrdinalIgnoreCase),
                    $"{failure} resource error does not expose a subscription-bearing ID");
            }
            check(failed, $"{failure} resource response fails explicitly instead of returning success-shaped details");
        }
    }

    internal sealed class ResourceHandler(string source) : HttpMessageHandler
    {
        public List<Uri> Requests { get; } = [];
        public int Capacity { get; set; } = 8;
        public int MaxPerDatabase { get; set; } = 8;
        public bool Standalone { get; set; }
        public string? Failure { get; set; }
        public Task? WaitForResponse { get; set; }

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            if (WaitForResponse is { } pending) await pending.WaitAsync(cancellationToken);
            if (request.Method != HttpMethod.Get || request.Headers.Authorization?.Scheme != "Bearer")
                throw new Exception("Resource inspection must use authenticated GET requests.");
            var uri = request.RequestUri!;
            Requests.Add(uri);
            var server = source[..source.LastIndexOf("/databases/", StringComparison.Ordinal)];
            var pool = $"{server}/elasticPools/caldova-network-pool";
            var id = Failure == "WrongId" ? $"{server}/databases/unrelated" : uri.AbsolutePath;
            object body;
            if (uri.AbsolutePath == pool)
            {
                body = new
                {
                    id, location = "eastus2",
                    sku = new { tier = "Hyperscale", family = "Gen5", capacity = Capacity },
                    properties = new { state = "Ready", perDatabaseSettings = new { minCapacity = 0, maxCapacity = MaxPerDatabase } }
                };
            }
            else
            {
                var standalone = Standalone && uri.AbsolutePath.EndsWith("/ridgeview-scheduling", StringComparison.Ordinal);
                body = new
                {
                    id,
                    properties = new
                    {
                        status = "Online",
                        currentServiceObjectiveName = standalone ? "HS_Gen5_4" : "ElasticPool",
                        elasticPoolId = Failure == "OtherPool" ? $"{server}/elasticPools/other" : standalone ? null : pool
                    }
                };
            }
            return new HttpResponseMessage(Failure == "Denied" ? HttpStatusCode.Forbidden : HttpStatusCode.OK)
            {
                Content = new StringContent(Failure == "Malformed" ? "invalid JSON" : JsonSerializer.Serialize(body))
            };
        }
    }
}
