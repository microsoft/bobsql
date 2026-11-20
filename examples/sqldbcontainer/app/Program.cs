using CustomerServiceDesk.Data;
using Microsoft.Data.SqlClient;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddRazorPages(options =>
    options.Conventions.ConfigureFilter(new Microsoft.AspNetCore.Mvc.ResponseCacheAttribute
    {
        NoStore = true,
        Location = Microsoft.AspNetCore.Mvc.ResponseCacheLocation.None
    }));
builder.Services.AddScoped<DeskRepository>();
builder.Services.AddHttpClient<OllamaEmbeddings>(client =>
{
    client.BaseAddress = new Uri("http://localhost:11434/");
    client.Timeout = TimeSpan.FromSeconds(60);
});

var app = builder.Build();
app.UseExceptionHandler("/Error");
app.Use(async (context, next) =>
{
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    context.Response.Headers["Content-Security-Policy"] =
        "default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; frame-ancestors 'none'; form-action 'self'; base-uri 'self'";
    await next();
});
app.UseRouting();
app.UseAuthorization();
app.MapStaticAssets();
app.MapRazorPages().WithStaticAssets();
app.MapGet("/health", async (DeskRepository desk, ILogger<Program> logger, CancellationToken token) =>
{
    try
    {
        var state = await desk.GetEnvironmentAsync(token);
        return Results.Ok(new { database = "reachable", cases = state.TotalCases,
            searchReady = state.SearchReady, pendingEmbeddings = state.PendingEmbeddings });
    }
    catch (SqlException exception)
    {
        logger.LogError(exception, "Database health check failed.");
        return Results.Json(new { database = "unavailable" }, statusCode: 503);
    }
});
app.Run();
