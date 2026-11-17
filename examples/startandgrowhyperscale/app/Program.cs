using CaldovaNetworkScheduling.Components;
using CaldovaNetworkScheduling.Services;
using CaldovaNetworkScheduling.Services.Playback;
using Azure.Core;
using Azure.Identity;

if (args is ["--fill-demo-storage"])
{
    try { await StorageFillCommand.RunAsync(); }
    catch (Exception ex)
    {
        Console.Error.WriteLine(AzureCliRunner.Redact(ex.ToString()));
        Environment.ExitCode = 1;
    }
    return;
}
if (args is ["--rehearse-pool"])
{
    try { await PoolRehearsalCommand.RunAsync(); }
    catch (Exception ex)
    {
        Console.Error.WriteLine(AzureCliRunner.Redact(ex.ToString()));
        Environment.ExitCode = 1;
    }
    return;
}
var builder = WebApplication.CreateBuilder(args);
DemoResourceNames.AddLocalSettings(builder.Configuration, builder.Environment);

var demoMode = builder.Configuration["Demo:Mode"] ?? "Measured";
var demoPlayback = builder.Configuration.GetValue<bool>("Demo:Playback");
var serverlessRecording = ServerlessRecordingSettings.Read(builder.Configuration, builder.Environment.ContentRootPath);
DemoResourceNames.Apply(builder.Configuration, serverlessRecording.IsReplay || demoPlayback);
builder.Configuration["ServerlessMonitor:ResourceId"] = ServerlessMonitor.ResolveConfiguredResourceId(
    builder.Configuration, serverlessRecording.IsReplay || demoPlayback);
PoolScaler.ValidateHost(builder.Configuration);
if (!string.Equals(demoMode, "Measured", StringComparison.OrdinalIgnoreCase))
{
    throw new InvalidOperationException($"Demo:Mode '{demoMode}' is not supported. Use 'Measured'; scripted playback is no longer the live demo.");
}

builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents();
builder.Services.AddOptions<ServerlessScriptOptions>();
builder.Services.AddScoped<IScaleWorkload, ScriptedScaleWorkload>();
builder.Services.AddSingleton<IAzureCliRunner, AzureCliRunner>();
builder.Services.AddSingleton<PoolScaler>();
builder.Services.AddSingleton<PoolClinicClientFactory>();
builder.Services.AddSingleton<PoolScheduling>();
builder.Services.AddSingleton<PoolStorage>();
builder.Services.AddSingleton<TimeProvider>(TimeProvider.System);
builder.Services.AddSingleton(serverlessRecording);
builder.Services.AddScoped<ServerlessRunRecording>();
builder.Services.AddScoped<PoolPresentation>();

// Playback replaces every Azure and SQL dependency with in-memory stand-ins for recording backup clips.
if (demoPlayback)
{
    builder.Services.AddSingleton<PlaybackDatabase>();
    builder.Services.AddSingleton<PlaybackPool>();
    builder.Services.AddSingleton<TokenCredential, PlaybackCredential>();
    builder.Services.AddHttpClient<ServerlessMonitor>(client => client.Timeout = TimeSpan.FromSeconds(30))
        .ConfigurePrimaryHttpMessageHandler(services => new PlaybackArmHandler(services.GetRequiredService<PlaybackDatabase>()));
    builder.Services.AddScoped<ServerlessSqlWorkload, PlaybackSqlWorkload>();
    builder.Services.AddScoped<ServerlessSqlTelemetry, PlaybackSqlTelemetry>();
    builder.Services.AddScoped<ServerlessResume, PlaybackResume>();
    builder.Services.AddSingleton<IAppointmentAvailabilityService, PlaybackAppointmentAvailabilityService>();
    builder.Services.AddSingleton<NetworkResourceMonitor>(services => new PlaybackNetworkResourceMonitor(
        new HttpClient(), services.GetRequiredService<TokenCredential>(), builder.Configuration,
        services.GetRequiredService<PlaybackPool>()));
}
else
{
    builder.Services.AddSingleton<TokenCredential>(new DefaultAzureCredential());
    builder.Services.AddHttpClient<ServerlessMonitor>(client => client.Timeout = TimeSpan.FromSeconds(30));
    builder.Services.AddHttpClient<NetworkResourceMonitor>(client => client.Timeout = TimeSpan.FromSeconds(30));
    builder.Services.AddScoped<ServerlessSqlWorkload>();
    builder.Services.AddScoped<ServerlessSqlTelemetry>();
    builder.Services.AddScoped<ServerlessResume>();
    builder.Services.AddSingleton<IAppointmentAvailabilityService, SqlAppointmentAvailabilityService>();
}

var app = builder.Build();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error", createScopeForErrors: true);
    app.UseHsts();
}

app.UseStaticFiles();
app.UseAntiforgery();

app.MapGet("/healthz", () => Results.Json(new { status = "ok", mode = demoPlayback ? "playback" : serverlessRecording.IsReplay ? "replay" : "measured",
    serverless = demoPlayback ? "in-memory" : serverlessRecording.IsReplay ? "saved-sql-dmv" : "sql-dmv",
    appointments = demoPlayback ? "in-memory" : "sql",
    serverlessCapture = serverlessRecording.CaptureEnabled,
    poolPresentation = builder.Configuration.GetValue<bool>("PoolPresentation:Enabled") ? "illustration" : "disabled" }));

app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode();

app.Run();
