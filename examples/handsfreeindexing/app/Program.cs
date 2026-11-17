using CaldovaPatientAccessOps.Components;
using CaldovaPatientAccessOps.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents();
builder.Services.AddScoped<IOperationsDataService, SqlOperationsDataService>();
builder.Services.AddHostedService<IndexHealthCaptureService>();

var app = builder.Build();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error", createScopeForErrors: true);
    app.UseHsts();
}

app.UseStaticFiles();
app.UseAntiforgery();

app.MapGet("/healthz", () => Results.Json(new { status = "ok" }));

app.MapGet("/readyz", async (IOperationsDataService dataService, CancellationToken cancellationToken) =>
{
    var sqlReady = await dataService.IsReadyAsync(cancellationToken);
    var readiness = new
    {
        status = sqlReady ? "ready" : "not-ready",
        mode = "azure-sql",
        dependencies = new[] { new { name = "sql", status = sqlReady ? "ready" : "not-ready" } }
    };

    return sqlReady ? Results.Json(readiness) : Results.Json(readiness, statusCode: 503);
});

app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode();

app.Run();
