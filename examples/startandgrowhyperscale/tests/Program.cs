using CaldovaNetworkScheduling.Components.Layout;
using CaldovaNetworkScheduling.Components.Pages;
using CaldovaNetworkScheduling.Services;
using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.Web;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Azure.Core;
using Azure.Identity;
using System.Text.Json;
using System.Net;

var checks = 0;
void Check(bool condition, string description)
{
    if (!condition) throw new InvalidOperationException($"FAIL: {description}");
    checks++;
}

var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
{
    ["ServerlessMonitor:ResourceId"] = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/caldova-network-rg/providers/Microsoft.Sql/servers/sql-caldova-network-test/databases/caldova-scheduling",
    ["ServerlessMonitor:EnableWorkload"] = "false"
}).AddEnvironmentVariables().Build();
var privateConfig = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
{
    ["ServerlessMonitor:ResourceId"] = "/subscriptions/{subscription-id}/resourceGroups/caldova-test-rg/providers/Microsoft.Sql/servers/sql-caldova-start-test/databases/caldova-scheduling",
    ["Azure:SubscriptionId"] = "33333333-3333-3333-3333-333333333333"
}).Build();
Check(ServerlessMonitor.ResolveConfiguredResourceId(privateConfig).Contains("/subscriptions/33333333-3333-3333-3333-333333333333/")
    && ServerlessMonitor.ResolveConfiguredResourceId(privateConfig).Contains("/servers/sql-caldova-start-test/"),
    "Private subscription configuration resolves the public placeholder without changing the selected server");
privateConfig["Azure:SubscriptionId"] = null;
privateConfig["AZURE_SUBSCRIPTION_ID"] = "44444444-4444-4444-4444-444444444444";
Check(ServerlessMonitor.ResolveConfiguredResourceId(privateConfig).Contains("/subscriptions/44444444-4444-4444-4444-444444444444/"),
    "Environment subscription configuration also resolves the public placeholder");
privateConfig["AZURE_SUBSCRIPTION_ID"] = null;
Check(ServerlessMonitor.ResolveConfiguredResourceId(privateConfig, offline: true).Contains($"/subscriptions/{Guid.Empty:D}/"),
    "Offline replay and synthetic playback do not require private Azure identifiers");
foreach (var invalid in new[] { "", "invalid", Guid.Empty.ToString("D") })
{
    privateConfig["Azure:SubscriptionId"] = invalid;
    var rejected = false;
    try { ServerlessMonitor.ResolveConfiguredResourceId(privateConfig); }
    catch (InvalidOperationException) { rejected = true; }
    Check(rejected, "Live mode explicitly rejects missing or invalid private subscription configuration");
}
Check(ServerlessMonitor.ResolveConfiguredResourceId(configuration) == configuration["ServerlessMonitor:ResourceId"],
    "An explicitly configured complete resource target remains unchanged");
const string placeholderConnection = "Server=tcp:{network-server}.database.windows.net,1433;Initial Catalog=caldova-scheduling";
const string placeholderResource = "/subscriptions/{subscription-id}/resourceGroups/caldova-network-rg/providers/Microsoft.Sql/servers/{start-server}/databases/caldova-scheduling";
IConfiguration NamesConfig(Dictionary<string, string?> values) => new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
{
    ["ConnectionStrings:Scheduling"] = placeholderConnection,
    ["ServerlessMonitor:ResourceId"] = placeholderResource
}.Concat(values).ToDictionary()).Build();
var names = NamesConfig(new() { ["Azure:NetworkSqlServer"] = "sql-caldova-network-test", ["Azure:StartSqlServer"] = "sql-caldova-start-test" });
DemoResourceNames.Apply(names, offline: false);
Check(names["ConnectionStrings:Scheduling"] == "Server=tcp:sql-caldova-network-test.database.windows.net,1433;Initial Catalog=caldova-scheduling"
    && names["ServerlessMonitor:ResourceId"]!.Contains("/servers/sql-caldova-start-test/databases/")
    && names["ServerlessMonitor:ResourceId"]!.Contains("{subscription-id}"),
    "Private server names resolve public placeholders in the connection string and resource ID without touching the subscription placeholder");
names = NamesConfig(new() { ["CALDOVA_NETWORK_SQL_SERVER"] = "sql-caldova-network-env", ["CALDOVA_PART1_SQL_SERVER"] = "sql-caldova-start-env" });
DemoResourceNames.Apply(names, offline: false);
Check(names["ConnectionStrings:Scheduling"]!.Contains("tcp:sql-caldova-network-env.") && names["ServerlessMonitor:ResourceId"]!.Contains("/servers/sql-caldova-start-env/"),
    "Deployment-script environment names also resolve the server placeholders");
names = NamesConfig(new() { ["Azure:NetworkSqlServer"] = "sql-caldova-network-local", ["CALDOVA_NETWORK_SQL_SERVER"] = "sql-caldova-network-env",
    ["Azure:StartSqlServer"] = "sql-caldova-start-local" });
DemoResourceNames.Apply(names, offline: false);
Check(names["ConnectionStrings:Scheduling"]!.Contains("tcp:sql-caldova-network-local."), "Azure:NetworkSqlServer takes precedence over the deployment environment name");
names = NamesConfig(new());
DemoResourceNames.Apply(names, offline: true);
Check(names["ConnectionStrings:Scheduling"]!.Contains("tcp:sql-caldova-network-offline.")
    && names["ServerlessMonitor:ResourceId"]!.Contains("/servers/sql-caldova-start-offline/")
    && !names["ConnectionStrings:Scheduling"]!.Contains('{') && !names["ServerlessMonitor:ResourceId"]!.Contains("-server}"),
    "Offline replay and synthetic playback do not require private server names");
foreach (var (missing, invalid) in new[] { ("Azure:NetworkSqlServer", ""), ("Azure:NetworkSqlServer", "SQL_Bad;Server"), ("Azure:StartSqlServer", ""),
    ("Azure:StartSqlServer", "sql-caldova-start-test.database.windows.net") })
{
    var values = new Dictionary<string, string?> { ["Azure:NetworkSqlServer"] = "sql-caldova-network-test", ["Azure:StartSqlServer"] = "sql-caldova-start-test" };
    values[missing] = invalid;
    var unresolved = NamesConfig(values);
    string? message = null;
    try { DemoResourceNames.Apply(unresolved, offline: false); }
    catch (InvalidOperationException ex) { message = ex.Message; }
    Check(message is not null && message.Contains(missing) && message.Contains(DemoResourceNames.LocalSettingsFile),
        "Live mode fails clearly instead of targeting an unresolved or invalid server placeholder");
}
var completeNames = NamesConfig(new());
completeNames["ConnectionStrings:Scheduling"] = "Server=tcp:sql-explicit.database.windows.net,1433";
completeNames["ServerlessMonitor:ResourceId"] = configuration["ServerlessMonitor:ResourceId"];
DemoResourceNames.Apply(completeNames, offline: false);
Check(completeNames["ConnectionStrings:Scheduling"] == "Server=tcp:sql-explicit.database.windows.net,1433"
    && completeNames["ServerlessMonitor:ResourceId"] == configuration["ServerlessMonitor:ResourceId"],
    "Explicit complete server targets (deployed App Service settings) need no private names");
Check(DemoResourceNames.ResolveAppName(NamesConfig(new() { ["Azure:AppName"] = "app-caldova-network-test" })) == "app-caldova-network-test"
    && DemoResourceNames.ResolveAppName(NamesConfig(new() { ["CALDOVA_NETWORK_APP_NAME"] = "app-caldova-network-env" })) == "app-caldova-network-env"
    && DemoResourceNames.ResolveAppName(NamesConfig(new() { ["WEBSITE_SITE_NAME"] = "app-caldova-network-site" })) == "app-caldova-network-site",
    "The app identity name comes from private configuration, the deployment environment, or App Service");
foreach (var invalid in new string?[] { null, "", "app'];DROP USER x;--", "-bad-" })
{
    var rejected = false;
    try { DemoResourceNames.ResolveAppName(NamesConfig(new() { ["Azure:AppName"] = invalid })); }
    catch (InvalidOperationException ex) { rejected = ex.Message.Contains("Azure:AppName"); }
    Check(rejected, "A missing or unsafe app identity name fails clearly before any storage SQL runs");
}
var storageSql = PoolStorage.SetupSql("GRANT SELECT ON OBJECT::demo.StorageSize TO [$(AppName)];",
    NamesConfig(new() { ["Azure:AppName"] = "app-caldova-network-test" }));
Check(storageSql == "GRANT SELECT ON OBJECT::demo.StorageSize TO [app-caldova-network-test];",
    "Storage setup SQL receives the configured app identity instead of a tracked literal");
var appSettingsPath = Path.Combine(AppContext.BaseDirectory, "appsettings.json");
if (File.Exists(appSettingsPath))
{
    var tracked = File.ReadAllText(appSettingsPath);
    Check(tracked.Contains(DemoResourceNames.NetworkServerPlaceholder) && tracked.Contains("{subscription-id}"),
        "Tracked app settings keep public server and subscription placeholders");
}
var localRoot = Path.Combine(AppContext.BaseDirectory, "local-settings-check");
Directory.CreateDirectory(localRoot);
try
{
    File.WriteAllText(Path.Combine(localRoot, "appsettings.json"), """{ "Azure": { "NetworkSqlServer": "sql-public-default", "AppName": "app-public" } }""");
    File.WriteAllText(Path.Combine(localRoot, DemoResourceNames.LocalSettingsFile), """{ "Azure": { "NetworkSqlServer": "sql-caldova-network-local", "AppName": "app-local" } }""");
    using var fileProvider = new Microsoft.Extensions.FileProviders.PhysicalFileProvider(localRoot);
    var layered = new ConfigurationManager();
    layered.AddJsonFile(fileProvider, "appsettings.json", optional: false, reloadOnChange: false);
    layered.AddInMemoryCollection(new Dictionary<string, string?> { ["Azure:AppName"] = "app-environment-override" });
    DemoResourceNames.AddLocalSettings(layered, new LocalSettingsEnvironment(fileProvider, localRoot));
    Check(layered["Azure:NetworkSqlServer"] == "sql-caldova-network-local" && layered["Azure:AppName"] == "app-environment-override",
        "The git-ignored local file overrides tracked app settings while later sources such as environment still win");
    var withoutLocal = new ConfigurationManager();
    DemoResourceNames.AddLocalSettings(withoutLocal, new LocalSettingsEnvironment(
        new Microsoft.Extensions.FileProviders.NullFileProvider(), localRoot));
    Check(withoutLocal["Azure:NetworkSqlServer"] is null, "The local settings file is optional for public clones");
}
finally { Directory.Delete(localRoot, recursive: true); }
if (args.Contains("--pool-cli-check"))
{
    var currentName = await new AzureCliRunner().RunAsync(
        ["account", "show", "--query", "name", "--output", "tsv"], CancellationToken.None);
    if (string.IsNullOrWhiteSpace(currentName)) throw new InvalidOperationException("Azure CLI did not report a current subscription.");
    Console.WriteLine($"PASS: app CLI runner uses the current subscription ({currentName}); no mutation submitted.");
    return;
}
if (args.Contains("--serverless-live"))
{
    var ramped = args.Contains("--serverless-ramp");
    var workers = ramped ? 8 : 4;
    var workerIndex = Array.IndexOf(args, "--serverless-workers");
    if (workerIndex >= 0 && (workerIndex + 1 >= args.Length
        || !int.TryParse(args[workerIndex + 1], out workers) || workers is < 1 or > 16))
        throw new ArgumentException("--serverless-workers must be an integer from 1 to 16.");
    int Seconds(string name, int fallback)
    {
        var index = Array.IndexOf(args, name);
        if (index < 0) return fallback;
        if (!ramped || index + 1 >= args.Length || !int.TryParse(args[index + 1], out var value))
            throw new ArgumentException($"{name} requires --serverless-ramp and an integer number of seconds.");
        return value;
    }
    var liveRamp = ramped ? new WorkloadRamp(workers,
        TimeSpan.FromSeconds(Seconds("--serverless-ramp-step-seconds", 30)),
        TimeSpan.FromSeconds(Seconds("--serverless-ramp-hold-seconds", 60)),
        TimeSpan.FromSeconds(Seconds("--serverless-ramp-down-step-seconds", Seconds("--serverless-ramp-step-seconds", 30)))) : null;
    await ServerlessLiveCheck.RunAsync(configuration, workers, liveRamp);
    return;
}
var observeIndex = Array.IndexOf(args, "--serverless-observe-from");
var sqlObserveIndex = Array.IndexOf(args, "--serverless-dmv-observe-from");
if (sqlObserveIndex >= 0)
{
    if (sqlObserveIndex + 1 >= args.Length
        || !DateTimeOffset.TryParse(args[sqlObserveIndex + 1], out var sqlFrom))
        throw new ArgumentException("--serverless-dmv-observe-from requires a UTC timestamp.");
    await ServerlessLiveCheck.ObserveSqlAsync(configuration, sqlFrom);
    return;
}
if (observeIndex >= 0)
{
    await ServerlessLiveCheck.CaptureAsync(configuration, DateTimeOffset.Parse(args[observeIndex + 1]));
    return;
}
var sql = new SqlAppointmentAvailabilityService(configuration);
Check(new ServerlessCpuSample(DateTimeOffset.UtcNow, 50, 8).UsedVCores == 4,
    "DMV CPU uses the sample's own vCore limit");
Check(new ServerlessCpuSample(DateTimeOffset.UtcNow, 0, 8).UsedVCores == 0,
    "DMV CPU preserves a real zero");
try
{
    _ = new ServerlessCpuSample(DateTimeOffset.UtcNow, 50, 0).UsedVCores;
    throw new InvalidOperationException("Invalid DMV limit was accepted");
}
catch (InvalidOperationException ex) when (ex.Message.StartsWith("SQL returned")) { checks++; }
foreach (var invalid in new[] { new ServerlessCpuSample(DateTimeOffset.UtcNow, 101, 8),
    new ServerlessCpuSample(DateTimeOffset.UtcNow, double.NaN, 8),
    new ServerlessCpuSample(DateTimeOffset.UtcNow, 50, double.PositiveInfinity) })
{
    try
    {
        _ = invalid.UsedVCores;
        throw new Exception("Invalid SQL CPU sample was accepted");
    }
    catch (InvalidOperationException) { checks++; }
}
var sessionTracker = new SessionCpuTracker();
var sessionAt = new DateTime(2026, 10, 22, 18, 0, 0, DateTimeKind.Utc);
var sessionLogin = sessionAt.AddMinutes(-1);
Check(sessionTracker.Observe(sessionAt, [new(100, sessionLogin, 1000)]) is null,
    "Session CPU needs a baseline");
Check(sessionTracker.Observe(sessionAt.AddSeconds(15), [new(100, sessionLogin, 61000)]) == 4,
    "Session CPU delta divides CPU milliseconds by elapsed milliseconds");
Check(sessionTracker.Observe(sessionAt.AddSeconds(30), []) is null,
    "Disappeared session counters are not zero CPU");
Check(sessionTracker.Observe(sessionAt.AddSeconds(45), [new(100, sessionAt.AddSeconds(35), 30000)]) == 2,
    "Reused session IDs use login time and count only the new session's CPU");
Check(sql.Mode == "SQL", "Appointments must not silently fall back to scripted data");
Check(sql.ViewDefinition.Contains("JOIN [northbrook-scheduling].dbo.AppointmentSlot"), "View joins Northbrook");
Check(sql.ViewDefinition.Contains("JOIN [ridgeview-scheduling].dbo.AppointmentSlot"), "View joins Ridgeview");
Check(sql.ViewDefinition.Split("FROM network.ProviderClinic").Length == 2, "All providers join one central directory source");
Check(sql.ViewDefinition.Contains("p.IsNetworkMember = 1") && sql.ViewDefinition.Split(".IsBooked = 0").Length == 4,
    "The directory filters membership and all three joins exclude booked slots");
Check(!sql.ViewDefinition.Contains("UNION", StringComparison.OrdinalIgnoreCase), "The view uses only joins, not a union");
foreach (var (providerKey, alias) in new[] { ("caldova", "c"), ("northbrook", "n"), ("ridgeview", "r") })
    Check(sql.ViewDefinition.Contains($"ON p.ProviderKey = N'{providerKey}' AND {alias}.ClinicId = p.ClinicId"),
        $"{providerKey} join selects only that provider's schedule even when clinic and slot IDs overlap");
Check(sql.ViewDefinition.Contains("COALESCE(c.SlotId, n.SlotId, r.SlotId) IS NOT NULL"),
    "Directory rows with no matching unbooked schedule are excluded");
Check(new[] { "SlotId", "Clinician", "Specialty", "SlotStart", "DurationMinutes" }.All(column =>
    sql.ViewDefinition.Contains($"COALESCE(c.{column}, n.{column}, r.{column}) AS {column}")),
    "Every appointment field comes from the matching provider's schedule");
foreach (var key in new[] { "caldova", "northbrook", "ridgeview" })
{
    var query = SqlAppointmentAvailabilityService.GetBookingQuery(key);
    var database = SqlAppointmentAvailabilityService.GetDatabase(key);
    Check(query.Split("UPDATE ").Length == 2 && query.Split("INSERT ").Length == 2, $"{key} booking has one UPDATE and one INSERT");
    Check(query.Contains($"FROM {SqlAppointmentAvailabilityService.GetSourceObject(key)} AS s")
        && query.Contains($"INSERT [{database}].dbo.Appointment"), $"{key} writes only the allowlisted provider database");
    Check(new[] { "caldova-scheduling", "northbrook-scheduling", "ridgeview-scheduling" }.Where(d => d != database).All(d => !query.Contains($"[{d}]")),
        $"{key} transaction writes to exactly one database");
    Check(query.Contains("s.IsBooked = 0") && query.Contains("s.SlotId = @SlotId") && query.Contains("IF @@ROWCOUNT = 1"), $"{key} conditional slot claim");
    Check(query.Contains("BEGIN TRANSACTION") && query.Contains("COMMIT TRANSACTION") && query.Contains("SET XACT_ABORT ON")
        && !query.Contains("SAVE TRAN"), $"{key} one atomic transaction without savepoints");
    Check(query.Contains("p.ProviderKey = @ProviderKey") && query.Contains("p.IsNetworkMember = 1"), $"{key} membership guard");
}
try
{
    SqlAppointmentAvailabilityService.GetBookingQuery("ridgeview]; DROP TABLE dbo.AppointmentSlot;--");
    throw new InvalidOperationException("Untrusted provider was accepted");
}
catch (ArgumentException) { checks++; }
try
{
    await sql.BookAsync("caldova", 0);
    throw new InvalidOperationException("Invalid slot was accepted");
}
catch (ArgumentOutOfRangeException) { checks++; }
try
{
    await sql.FindNextAsync("unrecognized", true);
    throw new InvalidOperationException("Invalid specialty was accepted");
}
catch (ArgumentException) { checks++; }

var services = new ServiceCollection();
services.AddLogging();
services.AddSingleton<IConfiguration>(configuration);
services.AddSingleton<TokenCredential>(new DefaultAzureCredential());
services.AddHttpClient<ServerlessMonitor>();
services.AddScoped<ServerlessSqlWorkload>();
services.AddScoped<ServerlessSqlTelemetry>();
services.AddScoped<ServerlessResume>();
services.AddSingleton(TimeProvider.System);
services.AddSingleton(new ServerlessRecordingSettings("Live", null, 2));
services.AddScoped<ServerlessRunRecording>();
services.AddScoped<PoolPresentation>();
services.AddOptions<ServerlessScriptOptions>();
services.AddScoped<IScaleWorkload, ScriptedScaleWorkload>();
services.AddSingleton<IAppointmentAvailabilityService>(sql);
var (networkMonitor, networkResourceHandler) = NetworkResourceChecks.Create(configuration);
services.AddSingleton(networkMonitor);
services.AddSingleton(new PoolScaler(new AzureCliRunner(), networkMonitor, configuration,
    new PoolScaleChecks.Lifetime(), Microsoft.Extensions.Logging.Abstractions.NullLogger<PoolScaler>.Instance));
services.AddSingleton(new PoolScheduling(networkMonitor,
    new PoolClinicClientFactory(configuration, Microsoft.Extensions.Logging.Abstractions.NullLoggerFactory.Instance, new StorageChecks.Fake(configuration)),
    configuration, new PoolScaleChecks.Lifetime(), Microsoft.Extensions.Logging.Abstractions.NullLogger<PoolScheduling>.Instance,
    new StorageChecks.Fake(configuration)));
services.AddSingleton<PoolStorage>(new StorageChecks.Fake(configuration));
services.AddSingleton<NavigationManager>(new CheckNavigation());
await using var provider = services.BuildServiceProvider();
await using var renderer = new HtmlRenderer(provider, provider.GetRequiredService<ILoggerFactory>());
async Task<string> RenderAsync<T>() where T : IComponent =>
    await renderer.Dispatcher.InvokeAsync(async () =>
        (await renderer.RenderComponentAsync<T>()).ToHtmlString());

var layout = await RenderAsync<MainLayout>();
foreach (var route in new[] { "/network", "/verify", "/scale", "/appointments" })
    Check(layout.Contains($"href=\"{route}\""), $"Navigation includes {route}");
Check(!layout.Contains("SQL DMV") && !layout.Contains("mode-chip"), "Header has no data-source or mode labels");
var originalPlayback = configuration["Demo:Playback"];
configuration["Demo:Playback"] = "true";
var playbackLayout = await RenderAsync<MainLayout>();
configuration["Demo:Playback"] = originalPlayback;
Check(playbackLayout == layout && !playbackLayout.Contains("3b") && !playbackLayout.Contains("href=\"/pool\"")
    && System.Text.RegularExpressions.Regex.Matches(playbackLayout, "class=\"nav-step\"").Count == 5,
    "Playback renders exactly the live header and five-step navigation, without a playback-only Scale & Grow tab");
var acquisition = await RenderAsync<Overview>();
Check(acquisition.Contains("page-header acquisitions-header"),
    "Acquisitions uses its own full-width subtitle styling without changing other page headers");
var patientAccess = await RenderAsync<Scale>();
Check(!patientAccess.Contains("id=\"billing\"") && !patientAccess.Contains("Open Caldova database in Azure portal")
    && !patientAccess.Contains("End of Part 1") && !patientAccess.Contains("Presenter setup"), "Patient Access has no presenter or portal instructions");
Check(patientAccess.Contains("Behind the chart") && patientAccess.Contains("HASHBYTES"), "Patient Access shows the SQL workload behind the chart");
Check(patientAccess.Contains("avg_cpu_percent × cpu_limit / 100") && patientAccess.Contains("sys.dm_db_resource_stats")
    && patientAccess.Contains("15-second"), "CPU calculation, source, and interval are shown");
Check(patientAccess.Contains("▶ Run") && patientAccess.Contains("vCores in use") && !patientAccess.Contains("scripted vCores"), "Patient Access uses the live scene");
Check(patientAccess.Contains("Configured compute: 1 - 8 vCores")
    && !patientAccess.Contains("<span>0</span><span>min"),
    "Patient Access labels the configured 1 - 8 range without presenting zero as its configured minimum");
Check(!patientAccess.Contains("gauge-min"),
    "The configured minimum has no solid marker through the CPU gauge");
Check(patientAccess.Contains("data-vcores=\"1\" style=\"left:12.5%\"")
    && patientAccess.Contains("data-vcores=\"2\" style=\"left:25%\"")
    && patientAccess.Contains("data-vcores=\"6\" style=\"left:75%\"")
    && patientAccess.Contains("data-vcores=\"8\" style=\"left:100%\""),
    "CPU gauge hash marks 1, 2, 6 and 8 are positioned by their numeric values rather than evenly spaced");
Check(!patientAccess.Contains("class=\"app-clock\"") && !patientAccess.Contains("<small>Elapsed</small>")
    && patientAccess.Contains("Elapsed at interval end") && !patientAccess.Contains("UTC"),
    "Measured page omits the header elapsed clock while retaining elapsed sample timestamps");
foreach (var label in new[] { "MEASURED", "measured vCores", "Measured.", "illustrative", "synthetic", "Azure status", "SQL DMV", "not allocated", "Gaps are not" })
    Check(!patientAccess.Contains(label), $"Patient Access shows no '{label}' label");
Check(!patientAccess.Contains("Next · Step 2"), "Serverless chapter ends independently");
Check(patientAccess.Contains("staff online") && patientAccess.Contains("Each staff member runs this batch")
    && !patientAccess.Contains("Press Play"), "Staff map to SQL connections");
await ResumeActivityChecks.CheckRenderingAsync(Check, renderer);
Check(patientAccess.Contains("Load generation is disabled"), "SQL load is opt-in");
var illustration = await renderer.Dispatcher.InvokeAsync(async () => (await renderer.RenderComponentAsync<Scale>(
    ParameterView.FromDictionary(new Dictionary<string, object?> { ["ForceScripted"] = true }))).ToHtmlString());
Check(illustration.Contains("class=\"app-clock\"") && illustration.Contains("<small>Today</small>"),
    "The separate illustration retains its existing simulated time-of-day clock");
Check(!illustration.Contains("scripted", StringComparison.OrdinalIgnoreCase)
    && !illustration.Contains("illustration", StringComparison.OrdinalIgnoreCase), "The recording screen has no scripted or illustration notices");
Check(!illustration.Contains("not measured") && !illustration.Contains("Not Azure telemetry")
    && !illustration.Contains("runs no SQL workload"), "The recording screen omits realism disclaimers without adding live measurement claims");
Check(illustration.Contains("<small>Today</small>") && !illustration.Contains("<small>Elapsed</small>"),
    "The recording retains its clinic-day clock");
Check(illustration.Contains("app_cpu_percent") && illustration.Contains("app_cpu_billed")
    && illustration.Contains("Open Caldova database in Azure portal"), "Fallback still requires real portal metrics");
Check(!patientAccess.Contains("href=\"/serverless-illustration\"") && !illustration.Contains(">Measured<")
    && illustration.Contains("vCores in use (CPU)") && !illustration.Contains("measured vCores"), "The recording uses neutral CPU labels without mode buttons");
var scriptOptions = new ServerlessScriptOptions();
Check(scriptOptions.MinVCores + scriptOptions.PeakUsers * scriptOptions.VCoresPerUser == 4
    && scriptOptions.MaxVCores == 8, "Illustration peaks at 4 used vCores without changing the 8-vCore maximum");
Check(patientAccess.Contains("Sign in (resume)") && !illustration.Contains("Sign in (resume)"), "Measured mode offers an explicit first sign-in to resume");
Check(ServerlessResume.Transient.Contains(40613) && ServerlessResume.Transient.Contains(40197) && !ServerlessResume.Transient.Contains(18456)
    && ServerlessResume.Backoff(1) == TimeSpan.FromSeconds(1) && ServerlessResume.Backoff(10) == TimeSpan.FromSeconds(10),
    "Resume retries only transient errors (not login failures) with capped backoff");
Check(illustration.Contains("without hovering") && illustration.Contains("no compute charge during confirmed auto-pause"),
    "Portal beat is a visual billed-compute story, not a hover-number comparison");
Check(acquisition.Contains("northbrook-scheduling") && acquisition.Contains("ridgeview-scheduling"), "Acquisition shows the three provider databases");
foreach (var key in new[] { "caldova", "northbrook", "ridgeview" })
    Check(acquisition.Contains($"provider-card acquisition-card provider-{key}"),
        $"Acquisitions uses the existing {key} color identity for its card and header");
Check(acquisition.Contains("Three providers. Three separate databases.")
    && acquisition.Contains("schedule separately") && !acquisition.Contains("staff search and book across all three"),
    "Acquisitions describes separate scheduling as the starting point rather than claiming the future network already exists");
Check(!acquisition.Contains("Fictional demo figures")
    && System.Text.RegularExpressions.Regex.Matches(acquisition, "Care capabilities").Count == 3
    && acquisition.Contains("24,000") && acquisition.Contains("12,000") && acquisition.Contains("6,000")
    && acquisition.Contains("Patients") && acquisition.Contains("Staff") && acquisition.Contains("Departments"),
    "Each acquisition card retains patient, staff, department, and care-capability figures without a fictional-data notice");
foreach (var (key, patients, staff, cores) in new[] { ("northbrook", "6,000", "45", 2), ("ridgeview", "12,000", "90", 4) })
{
    var card = WebUtility.HtmlDecode(System.Text.RegularExpressions.Regex.Match(acquisition,
        $"<article class=\"provider-card acquisition-card provider-{key}\">[\\s\\S]*?</article>").Value);
    Check(card.Contains($"<strong>{patients}</strong>") && card.Contains($"<strong>{staff}</strong>")
        && card.Contains($"Provisioned Hyperscale · {cores} vCores"),
        $"{key} retains its provisioned cores and the matching fictional provider-size profile");
}
Check(!acquisition.Contains("Add these databases to a pool") && !acquisition.Contains("Copilot") && !acquisition.Contains("Next ·"),
    "Acquisition has no presenter instructions or step buttons");
Check(!acquisition.Contains("Integrate into elastic pool") && !acquisition.Contains("Load history"), "No simulated Azure mutation buttons");
var verify = await RenderAsync<Verify>();
Check(!verify.Contains("Scale Pool")
    && !verify.Contains("Refresh resources") && !verify.Contains("Check network") && !verify.Contains("SQL access")
    && !verify.Contains("Open slots") && verify.Contains("caldova-network-pool"),
    "Network page shows resource membership without SQL checks");
var poolScale = await RenderAsync<PoolScale>();
Check(poolScale.Contains("class=\"pool-scale-page\"") && !verify.Contains("pool-scale-page"),
    "Compact Scale layout is scoped to Scale and leaves the Network cards unchanged");
Check(poolScale.Contains("Step 4") && poolScale.Contains("Scale Pool to 24") && poolScale.Contains("Scale Pool to 8")
    && poolScale.Contains("Run Scheduling") && !poolScale.Contains("Scale Pool to 32"),
    "Step four has the 24/8 scale controls and scheduling run");
Check(System.Text.RegularExpressions.Regex.Matches(poolScale, "CPU-used vCores</span>").Count == 3
    && System.Text.RegularExpressions.Regex.Matches(poolScale, "clinic-growth-space").Count == 3
    && !poolScale.Contains("Fictional demo figures") && poolScale.Contains("Scheduling does not book appointments"),
    "Each scale card shows its own measured activity and storage area without invented booking counts");
Check(!poolScale.Contains("pool-cpu-chart") && !poolScale.Contains("pool-cpu-panel")
    && !poolScale.Contains("clinic-cpu-chart"),
    "Scale shows larger database cards with measured values and storage bars, without CPU charts");
Check(!poolScale.Contains("Illustrative") && !poolScale.Contains("clinic-storage-chart")
    && System.Text.RegularExpressions.Regex.Matches(poolScale, "<progress ").Count == 3
    && poolScale.Contains("18.00 GiB used") && poolScale.Contains("12.00 GiB used") && poolScale.Contains("15.00 GiB used")
    && poolScale.Contains("30.00 GiB allocated")
    && poolScale.Contains("CPU-used across pool") && poolScale.Contains("space used versus currently allocated data-file space"),
    "Storage cards show a simple used-versus-allocated bar with no axes or history chart");
var storageBars = System.Text.RegularExpressions.Regex.Matches(poolScale, "<progress max=\"([0-9]+)\" value=\"([0-9]+)\"");
Check(storageBars.Count == 3 && storageBars.Select(bar =>
        (Max: long.Parse(bar.Groups[1].Value), Used: long.Parse(bar.Groups[2].Value))).SequenceEqual(
        new[] { (30L * DatabaseStorage.GiB, 18L * DatabaseStorage.GiB),
            (30L * DatabaseStorage.GiB, 12L * DatabaseStorage.GiB), (30L * DatabaseStorage.GiB, 15L * DatabaseStorage.GiB) }),
    "Each bar uses measured allocated bytes as its maximum, never a demo seed or growth target");
Check(!verify.Contains("portal.azure.com") && !verify.Contains("Open pool in Azure portal"), "Network page has no portal instructions");
Check(!verify.Contains("Pool resource details") && !verify.Contains("resource-details")
    && System.Text.RegularExpressions.Regex.Matches(verify, "Shared 8 vCores").Count == 3
    && verify.Contains("Online") && !verify.Contains("Service objective") && !verify.Contains("Read from Caldova as"),
    "Network page shows shared pool capacity on each database card without a top resource panel");
Check(!verify.Contains("/subscriptions/") && !verify.Contains("✓ Reachable"),
    "Resource inspection exposes no subscription IDs and does not claim SQL reachability");
Check(verify.Contains("<fieldset class=\"network-pool pool-verified\">")
    && WebUtility.HtmlDecode(verify).Contains("Hyperscale elastic pool · caldova-network-pool"),
    "One verified pool outline encloses all three provider cards");
Check(System.Text.RegularExpressions.Regex.Matches(verify, "class=\"shared-vcores\"").Count == 3,
    "All three verified shared-capacity readouts have matching outlined badges");
Check(System.Text.RegularExpressions.Regex.Matches(WebUtility.HtmlDecode(verify), "Min 0 / Max 8 vCores per database").Count == 3,
    "Real network cards display ARM minimum and maximum separately from the shared eight-core pool");
foreach (var key in new[] { "caldova", "northbrook", "ridgeview" })
{
    var cardPattern = $"<article class=\"provider-card acquisition-card provider-{key}\">[\\s\\S]*?</article>";
    var before = System.Text.RegularExpressions.Regex.Match(acquisition, cardPattern).Value;
    var after = System.Text.RegularExpressions.Regex.Match(verify, cardPattern).Value;
    var profilePattern = "<section class=\"provider-profile\">[\\s\\S]*?</section>";
    Check(after.Length > 0 && System.Text.RegularExpressions.Regex.Match(before, profilePattern).Value
        == System.Text.RegularExpressions.Regex.Match(after, profilePattern).Value,
        $"{key} keeps the same colored card and exact provider profile after moving into the pool");
    Check(!after.Contains("<details") && after.Contains("Shared 8 vCores") && after.Contains("Database state")
        && !after.Contains("SQL access") && !after.Contains("Fictional demo figures")
        && !after.Contains("Service objective") && !after.Contains("Read from Caldova as"),
        $"{key} shows database, shared capacity, state, and profile without technical Details");
}
Check(!acquisition.Contains("provider-details"),
    "Acquisitions keeps its full provider profiles visible while Network uses compact cards");
networkResourceHandler.Standalone = true;
var splitNetwork = await RenderAsync<Verify>();
Check(System.Text.RegularExpressions.Regex.Matches(splitNetwork, "Shared 8 vCores").Count == 2
    && splitNetwork.Contains("Not shared"),
    "Only pooled database cards show shared capacity");
Check(splitNetwork.Contains("network-pool pool-unverified") && !splitNetwork.Contains("network-pool pool-verified"),
    "A mixed standalone and pooled state cannot be drawn as one verified pool");
Check(System.Text.RegularExpressions.Regex.Matches(splitNetwork, "class=\"shared-vcores\"").Count == 2,
    "Only verified pooled databases receive shared-capacity badges");
networkResourceHandler.Failure = "Denied";
var unverifiedNetwork = await RenderAsync<Verify>();
Check(unverifiedNetwork.Contains("Resource details could not be verified")
    && unverifiedNetwork.Contains("Not verified") && !unverifiedNetwork.Contains("3 of 3")
    && !unverifiedNetwork.Contains("8 vCores"),
    "Failed resource inspection displays an explicit error without fabricated or stale membership details");
Check(unverifiedNetwork.Contains("network-pool pool-unverified") && !unverifiedNetwork.Contains("class=\"shared-vcores\""),
    "Failed resource inspection shows an unverified outline instead of confirmed pool membership");
networkResourceHandler.Failure = null;
networkResourceHandler.Standalone = false;
var resourceResponseReady = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
networkResourceHandler.WaitForResponse = resourceResponseReady.Task;
var loadingNetwork = await renderer.Dispatcher.InvokeAsync(async () =>
{
    var pending = renderer.BeginRenderingComponent<Verify>();
    var html = pending.ToHtmlString();
    resourceResponseReady.SetResult();
    await pending.QuiescenceTask;
    return html;
});
networkResourceHandler.WaitForResponse = null;
Check(loadingNetwork.Contains("Loading...") && !loadingNetwork.Contains("Not verified")
    && !loadingNetwork.Contains("Shared 8 vCores") && loadingNetwork.Contains("network-header"),
    "Network resource loading is explicit, never unverified or fabricated, and the header has dedicated card spacing");
Check(loadingNetwork.Contains("Checking pool membership...") && !loadingNetwork.Contains("network-pool pool-verified"),
    "The shared outline stays unverified while membership is loading");
var appointments = await RenderAsync<Appointments>();
Check(appointments.Contains("Find openings") && appointments.Contains("Search the entire network"), "Explicit local/network search");
Check(appointments.Contains("Step 5") && !appointments.Contains("synthetic") && !appointments.Contains("Real SQL"), "Search shows scenario step without data-source labels");
Check(!appointments.Contains("No openings"), "Initial render does not pretend SQL ran");
Check(!appointments.Contains("Search Caldova alone first") && !appointments.Contains("Back ·"), "Search page has no presenter hints");

var start = new DateTimeOffset(2026, 10, 22, 15, 0, 0, TimeSpan.Zero);
JsonDocument Metric(string name, string unit, string aggregation, params double?[] values) =>
    JsonDocument.Parse(JsonSerializer.Serialize(new
    {
        interval = "PT1M",
        value = new[]
        {
            new
            {
                name = new { value = name }, unit,
                timeseries = new[]
                {
                    new
                    {
                        data = values.Select((value, index) => new Dictionary<string, object?>
                        {
                            ["timeStamp"] = start.AddMinutes(index), [aggregation] = value
                        })
                    }
                }
            }
        }
    }));
using var cpuMetric = Metric("app_cpu_percent", "Percent", "average", 25, null, 0, 50);
using var billedMetric = Metric("app_cpu_billed", "Count", "total", 180, 60, 0, null);
using var memoryMetric = Metric("app_memory_percent", "Percent", "average", 8.5, null, 0, 9);
var withMemory = ServerlessMonitor.Combine(cpuMetric.RootElement, billedMetric.RootElement,
    start, start.AddMinutes(4), memoryMetric.RootElement);
Check(withMemory[0].MemoryPercent == 8.5 && withMemory[1].MemoryPercent is null && withMemory[2].MemoryPercent == 0,
    "Memory percentages retain real values, missing buckets, and actual zeros independently");
Check(ServerlessSqlWorkload.Query.Contains("varbinary(32)") && ServerlessSqlWorkload.Query.Contains("50000")
    && ServerlessSqlWorkload.Query.Contains("HASHBYTES('SHA2_256'")
    && !ServerlessSqlWorkload.Query.Contains(" FROM ") && !ServerlessSqlWorkload.Query.Contains(" JOIN ")
    && !ServerlessSqlWorkload.Query.Contains("INSERT") && !ServerlessSqlWorkload.Query.Contains("DBCC"),
    "CPU query uses bounded scalar computation without table reads, joins, data writes, or cache flushes");
try
{
    using var invalidMemory = Metric("app_memory_percent", "Percent", "average", 101);
    ServerlessMonitor.Combine(cpuMetric.RootElement, billedMetric.RootElement, start, start.AddMinutes(1), invalidMemory.RootElement);
    throw new Exception("Invalid memory percentage accepted");
}
catch (InvalidOperationException) { checks++; }
var measured = ServerlessMonitor.Combine(cpuMetric.RootElement, billedMetric.RootElement, start, start.AddMinutes(4));
Check(measured.Count == 4, "Every completed minute is represented");
Check(measured[0].UsedVCores(8) == 2 && measured[0].BilledVCores == 3, "25% of 8 is 2 used; 180 vCore-seconds is 3 billed");
Check(measured[1].UsedVCores(8) is null && measured[1].BilledVCores == 1, "Missing CPU stays missing independently of billed samples");
Check(measured[2].UsedVCores(8) == 0 && measured[2].BilledVCores == 0, "Actual zero samples remain zero");
Check(measured[3].BilledVCores is null, "Missing billed sample does not become zero");
var filtered = ServerlessMonitor.Combine(cpuMetric.RootElement, billedMetric.RootElement, start.AddMinutes(1), start.AddMinutes(3));
Check(filtered.Count == 2 && filtered[0].At == start.AddMinutes(1), "Only requested complete buckets are included");
Check(ServerlessMonitor.Minute(start.AddSeconds(59)) == start, "Bucket boundary excludes unfinished minute");
try
{
    using var invalidCpu = Metric("app_cpu_percent", "Percent", "average", 101);
    ServerlessMonitor.Combine(invalidCpu.RootElement, billedMetric.RootElement, start, start.AddMinutes(1));
    throw new Exception("Invalid CPU percentage accepted");
}
catch (InvalidOperationException) { checks++; }
try
{
    using var invalidUnit = Metric("app_cpu_billed", "Percent", "total", 180);
    ServerlessMonitor.Combine(cpuMetric.RootElement, invalidUnit.RootElement, start, start.AddMinutes(1));
    throw new Exception("Invalid billed unit accepted");
}
catch (InvalidOperationException) { checks++; }
using var metricHandler = new MonitorHandler(cpuMetric.RootElement.GetRawText(), billedMetric.RootElement.GetRawText(), memoryMetric.RootElement.GetRawText());
using var metricHttp = new HttpClient(metricHandler);
var monitor = new ServerlessMonitor(metricHttp, new TestCredential(), configuration);
var baseline = await monitor.ReadConfigurationAsync(CancellationToken.None);
Check(baseline.MinVCores == 1 && baseline.MaxVCores == 8, "Maximum/minimum come from ARM, not configured display constants");
var wrongSqlTarget = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
{
    ["ConnectionStrings:Scheduling"] = "Server=tcp:other.database.windows.net,1433;Initial Catalog=caldova-scheduling"
}).Build();
try
{
    await new ServerlessSqlTelemetry(wrongSqlTarget).ReadAsync(baseline, start, CancellationToken.None);
    throw new Exception("Mismatched SQL telemetry target was accepted");
}
catch (InvalidOperationException ex) when (ex.Message.StartsWith("SQL target")) { checks++; }
var throughApi = await monitor.ReadMetricsAsync(baseline, start, start.AddMinutes(4).AddSeconds(30), CancellationToken.None);
Check(throughApi.Count == 4, "HTTP metric flow omits the currently unfinished minute");
Check(metricHandler.Requests.Count == 5, "Read baseline/configuration then separate CPU, billed, and memory requests");
Check(throughApi[0].MemoryPercent == 8.5
    && metricHandler.Requests.Any(r => r.Contains("metricnames=app_memory_percent&aggregation=Average")), "HTTP flow captures actual app memory percentage");
Check(metricHandler.Requests.Any(r => r.Contains("metricnames=app_cpu_percent&aggregation=Average"))
    && metricHandler.Requests.Any(r => r.Contains("metricnames=app_cpu_billed&aggregation=Total"))
    && metricHandler.Requests.Where(r => r.Contains("/metrics?")).All(r => r.Contains("interval=PT1M")), "API uses the exact metric/aggregation/granularity contract");
Check(metricHandler.Requests.Where(r => r.Contains("/metrics?")).All(r => !r.Contains("%2B") && !r.Contains("+00")),
    "Metric request timestamps use UTC Z, not offsets Azure decodes as spaces");
metricHandler.Capacity = 4;
try
{
    await monitor.ReadMetricsAsync(baseline, start, start.AddMinutes(4), CancellationToken.None);
    throw new Exception("Configuration change accepted");
}
catch (InvalidOperationException) { checks++; }
metricHandler.Deny = true;
try
{
    await monitor.ReadConfigurationAsync(CancellationToken.None);
    throw new Exception("Monitoring permission error accepted");
}
catch (HttpRequestException ex) when (ex.StatusCode == HttpStatusCode.Forbidden) { checks++; }
await using (var disabledLoad = new ServerlessSqlWorkload(configuration, provider.GetRequiredService<ILogger<ServerlessSqlWorkload>>()))
{
    try
    {
        disabledLoad.Start(new("/subscriptions/test", "Online", 1, 8), 4, 3);
        throw new Exception("Disabled workload accepted");
    }
    catch (InvalidOperationException) { checks++; }
    try
    {
        disabledLoad.StartRamp(new("/subscriptions/test", "Online", 1, 8), new(8, TimeSpan.FromSeconds(30), TimeSpan.FromSeconds(60)));
        throw new Exception("Disabled ramp accepted");
    }
    catch (InvalidOperationException) { checks++; }
}
var ramp = new WorkloadRamp(8, TimeSpan.FromSeconds(30), TimeSpan.FromSeconds(60));
ramp.Validate();
Check(ramp.WorkersPerStep == 1 && ramp.WorkersPerStepDown is null && ramp.Total == TimeSpan.FromMinutes(8),
    "Default ramps still add and remove one worker per step; 8 workers with 30s steps and 60s hold last 8 minutes");
Check(Enumerable.Range(0, 16).Select(s => ramp.ActiveAt(TimeSpan.FromSeconds(s * 30 + 1)))
        .SequenceEqual([1, 2, 3, 4, 5, 6, 7, 8, 8, 7, 6, 5, 4, 3, 2, 1]) && ramp.ActiveAt(ramp.Total) == 0,
    "Ramp adds one worker per step, holds at peak, then removes one per step to zero");
Check(Enumerable.Range(0, 8).All(i => ramp.StopAt(i) > ramp.StartAt(i)) && ramp.StopAt(7) < ramp.StopAt(0),
    "Every ramp worker runs, and the last worker started stops first");
var demoPage = new Scale();
T DemoField<T>(string name, bool isStatic = false) =>
    (T)(typeof(Scale).GetField(name, System.Reflection.BindingFlags.NonPublic |
        (isStatic ? System.Reflection.BindingFlags.Static : System.Reflection.BindingFlags.Instance))?.GetValue(isStatic ? null : demoPage)
        ?? throw new Exception($"Missing demo timing field: {name}"));
var demoRamp = DemoField<WorkloadRamp>("RunRamp", true);
demoRamp.Validate();
Check(demoRamp.PeakAt == TimeSpan.FromSeconds(45) && demoRamp.Total == TimeSpan.FromSeconds(165)
    && demoRamp.Hold == TimeSpan.FromSeconds(60) && demoRamp.StepUp == demoRamp.StepDown
    && demoRamp.WorkersPerStepDown == 2
    && demoRamp.WorkerLevels.SequenceEqual([1, 2, 6, 10])
    && Enumerable.Range(0, 12).Select(i => demoRamp.ActiveAt(TimeSpan.FromSeconds(i * 15)))
        .SequenceEqual([1, 2, 6, 10, 10, 10, 10, 8, 6, 4, 2, 0]),
    "Serverless Run holds 10 workers for 60 seconds then removes two every 15 seconds");
Check(demoRamp.StartAt(0) == TimeSpan.Zero && demoRamp.ActiveAt(TimeSpan.Zero) == 1
    && demoRamp.Total + DemoField<TimeSpan>("RunCooldown", true) == TimeSpan.FromSeconds(195)
    && DemoField<TimeSpan>("planned") == TimeSpan.FromSeconds(195),
    "Serverless Run starts one worker immediately and plans 195 seconds including trailing telemetry");
Check(DemoField<TimeSpan>("RunCooldown", true) == TimeSpan.FromSeconds(30)
    && DemoField<TimeSpan>("ResumeActivity", true) == TimeSpan.FromMinutes(10)
    && typeof(Scale).GetField("Cooldown", System.Reflection.BindingFlags.NonPublic |
        System.Reflection.BindingFlags.Static) is null,
    "Run retains trailing observation while resume waits for manual Stop with a ten-minute workload safety limit");
Check(Enumerable.Range(0, 10).All(i => demoRamp.StopAt(i) > demoRamp.StartAt(i))
    && demoRamp.StartAt(1) == TimeSpan.FromSeconds(15)
    && demoRamp.StartAt(2) == TimeSpan.FromSeconds(30) && demoRamp.StartAt(5) == TimeSpan.FromSeconds(30)
    && demoRamp.StartAt(6) == TimeSpan.FromSeconds(45)
    && demoRamp.StartAt(9) == TimeSpan.FromSeconds(45)
    && demoRamp.StopAt(9) == TimeSpan.FromSeconds(105)
    && demoRamp.StopAt(8) == TimeSpan.FromSeconds(105)
    && demoRamp.StopAt(7) == TimeSpan.FromSeconds(120)
    && demoRamp.StopAt(6) == TimeSpan.FromSeconds(120)
    && demoRamp.StopAt(2) == TimeSpan.FromSeconds(150)
    && demoRamp.StopAt(1) == TimeSpan.FromSeconds(165) && demoRamp.StopAt(0) == TimeSpan.FromSeconds(165),
    "Explicit start levels and paired stops retain last-started-first stopping order");
var mirroredDemoRamp = demoRamp with { WorkersPerStepDown = null };
mirroredDemoRamp.Validate();
Check(Enumerable.Range(0, 11).Select(i => mirroredDemoRamp.ActiveAt(TimeSpan.FromSeconds(i * 15)))
        .SequenceEqual([1, 2, 6, 10, 10, 10, 10, 6, 2, 1, 0]),
    "Explicit levels still reverse unchanged when no ramp-down group override is supplied");
var oddGroupsRamp = demoRamp with { WorkersPerStepDown = 3 };
oddGroupsRamp.Validate();
Check(Enumerable.Range(0, 4).Select(i => oddGroupsRamp.ActiveAt(TimeSpan.FromSeconds(105 + i * 15)))
        .SequenceEqual([7, 4, 1, 0]),
    "An explicit-level ramp with an incomplete final stopping group stops the remaining worker");
foreach (var invalid in new WorkloadRamp[] { new(0, TimeSpan.FromSeconds(30), TimeSpan.FromSeconds(60)),
    new(17, TimeSpan.FromSeconds(30), TimeSpan.FromSeconds(60)), new(8, TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(60)),
    new(8, TimeSpan.FromSeconds(30), TimeSpan.Zero), new(8, TimeSpan.FromSeconds(10), TimeSpan.FromSeconds(9)),
    new(16, TimeSpan.FromSeconds(30), TimeSpan.FromSeconds(60)),
    demoRamp with { WorkerLevels = [] }, demoRamp with { WorkerLevels = [1, 6, 2, 8] },
    demoRamp with { WorkerLevels = [0, 2, 6, 8] }, demoRamp with { WorkerLevels = [1, 2, 6, 7] },
    demoRamp with { WorkerLevels = [2, 6, 8] }, demoRamp with { WorkersPerStep = 2 },
    demoRamp with { WorkersPerStepDown = 0 }, demoRamp with { WorkersPerStepDown = 17 } })
{
    try
    {
        invalid.Validate();
        throw new Exception($"Invalid ramp accepted: {invalid}");
    }
    catch (ArgumentOutOfRangeException) { checks++; }
}

var playback = new CaldovaNetworkScheduling.Services.Playback.PlaybackAppointmentAvailabilityService();
var caldovaOnly = await playback.FindNextAsync("Cardiology", networkWide: false);
var network = await playback.FindNextAsync("Cardiology", networkWide: true);
Check(caldovaOnly.QueryText == SqlAppointmentAvailabilityService.LocalQuery && network.QueryText == SqlAppointmentAvailabilityService.NetworkQuery
    && playback.ViewDefinition == SqlAppointmentAvailabilityService.ViewSql, "Playback shows the live query and view SQL");
Check(caldovaOnly.Slots.All(s => s.ProviderKey == "caldova") && network.Slots[0].ProviderKey == "ridgeview"
    && network.Slots[0].SourceObject == "[ridgeview-scheduling].dbo.AppointmentSlot"
    && (network.Slots[0].SlotStart.Date - DateTime.UtcNow.Date).Days == 2
    && (caldovaOnly.Slots[0].SlotStart.Date - DateTime.UtcNow.Date).Days == 19,
    "Playback seeds match the schema script: Caldova Cardiology +19 days, Ridgeview +2 days");
var firstBooking = await playback.BookAsync("ridgeview", network.Slots[0].SlotId);
var secondBooking = await playback.BookAsync("ridgeview", network.Slots[0].SlotId);
Check(firstBooking.Booked && !secondBooking.Booked && firstBooking.QueryText == SqlAppointmentAvailabilityService.GetBookingQuery("ridgeview"),
    "Playback booking is conditional and shows the live booking SQL");
Check((await playback.FindNextAsync("Cardiology", true)).Slots.All(s => s.SlotId != network.Slots[0].SlotId || s.ProviderKey != "ridgeview"),
    "A booked playback slot leaves availability");

await ResumeActivityChecks.RunAsync(Check, configuration);
await SavedRunChecks.RunAsync(Check, configuration);
await NetworkResourceChecks.RunAsync(Check, configuration);
await PoolScaleChecks.RunAsync(Check, configuration);
await PoolSchedulingChecks.RunAsync(Check, configuration);
await PoolPresentationChecks.RunAsync(Check);
await AppointmentBookingChecks.RunAsync(Check);
StorageChecks.Run(Check);
await StorageChecks.CheckSeedCancellationAsync(Check, configuration);
await StorageChecks.CheckTokensAsync(Check, configuration);
Console.WriteLine($"PASS: {checks} query-contract and component-rendering checks (no SQL connections).");
if (args.Contains("--live"))
{
    Console.WriteLine("LIVE: will permanently book one synthetic remote slot; requires approved pooled test setup.");
    var networkCheck = await sql.CheckNetworkAsync();
    Console.WriteLine($"Network check from {networkCheck.SourceDatabase}: " + string.Join("; ", networkCheck.Providers.Select(p => $"{p.Database} {p.OpenSlots} open")));
    var before = await sql.FindNextAsync("Cardiology", true);
    var slot = before.Slots.FirstOrDefault(s => s.ProviderKey == "ridgeview")
        ?? throw new InvalidOperationException("Seed an available Ridgeview cardiology slot before the live test.");
    var attempts = await Task.WhenAll(sql.BookAsync(slot.ProviderKey, slot.SlotId), sql.BookAsync(slot.ProviderKey, slot.SlotId));
    Check(attempts.Count(r => r.Booked) == 1, "Exactly one concurrent booking wins");
    var after = await sql.FindNextAsync("Cardiology", true);
    Check(!after.Slots.Any(s => s.ProviderKey == slot.ProviderKey && s.SlotId == slot.SlotId), "Booked slot disappears from availability");
    Console.WriteLine($"PASS: live cross-db search/concurrent booking, {slot.ProviderKey} slot {slot.SlotId}. This slot remains booked.");
}

sealed class CheckNavigation : NavigationManager
{
    public CheckNavigation() => Initialize("http://localhost/", "http://localhost/");
    protected override void NavigateToCore(string uri, bool forceLoad) =>
        throw new NotSupportedException("Rendering checks do not navigate.");
}

sealed class TestCredential : TokenCredential
{
    public override AccessToken GetToken(TokenRequestContext context, CancellationToken cancellationToken) =>
        new("offline-test-token", DateTimeOffset.UtcNow.AddHours(1));
    public override ValueTask<AccessToken> GetTokenAsync(TokenRequestContext context, CancellationToken cancellationToken) =>
        ValueTask.FromResult(GetToken(context, cancellationToken));
}

sealed class MonitorHandler(string cpu, string billed, string memory) : HttpMessageHandler
{
    public int Capacity { get; set; } = 8;
    public bool Deny { get; set; }
    public List<string> Requests { get; } = [];
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var uri = request.RequestUri!.AbsoluteUri;
        Requests.Add(uri);
        if (request.Headers.Authorization?.Scheme != "Bearer") throw new Exception("Missing bearer authorization");
        var content = uri.Contains("metricnames=app_cpu_percent") ? cpu
            : uri.Contains("metricnames=app_cpu_billed") ? billed
            : uri.Contains("metricnames=app_memory_percent") ? memory
            : JsonSerializer.Serialize(new { sku = new { name = "HS_S_Gen5", capacity = Capacity },
                properties = new { status = "Online", minCapacity = 1, elasticPoolId = (string?)null } });
        return Task.FromResult(new HttpResponseMessage(Deny ? HttpStatusCode.Forbidden : HttpStatusCode.OK)
        {
            Content = new StringContent(Deny ? "Monitoring permission denied" : content)
        });
    }
}

sealed class LocalSettingsEnvironment(Microsoft.Extensions.FileProviders.IFileProvider provider, string root)
    : Microsoft.Extensions.Hosting.IHostEnvironment
{
    public string EnvironmentName { get; set; } = "Development";
    public string ApplicationName { get; set; } = "CaldovaNetworkScheduling";
    public string ContentRootPath { get; set; } = root;
    public Microsoft.Extensions.FileProviders.IFileProvider ContentRootFileProvider { get; set; } = provider;
}
