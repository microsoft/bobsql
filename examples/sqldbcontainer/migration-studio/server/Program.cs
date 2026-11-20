using System.Net;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Antiforgery;
using Microsoft.Extensions.FileProviders;
using MigrationStudio;
using MigrationStudio.Middleware;
using MigrationStudio.Services;

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.UseKestrel(options => options.Listen(IPAddress.Loopback, 5188));
builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<ApiExceptionHandler>();
builder.Services.AddOpenApi();
builder.Services.AddValidation();
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.PropertyNameCaseInsensitive = false;
    options.SerializerOptions.AllowDuplicateProperties = false;
    options.SerializerOptions.Converters.Add(new JsonStringEnumConverter());
});
builder.Services.AddDistributedMemoryCache();
builder.Services.AddSession(options =>
{
    options.Cookie.Name = "MigrationStudio.Session";
    options.Cookie.HttpOnly = true;
    options.Cookie.SameSite = SameSiteMode.Strict;
    options.IdleTimeout = TimeSpan.FromHours(4);
});
builder.Services.AddAntiforgery(options =>
{
    options.HeaderName = "X-CSRF-TOKEN";
    options.Cookie.Name = "MigrationStudio.Csrf";
    options.Cookie.SameSite = SameSiteMode.Strict;
    options.Cookie.HttpOnly = true;
});
builder.Services.AddSingleton<StudioPaths>();
builder.Services.AddSingleton<IEventStream, EventStream>();
builder.Services.AddSingleton<IOperationRunner, OperationRunner>();
builder.Services.AddSingleton<ISkillCatalog, SkillCatalog>();
builder.Services.AddSingleton<MigrationWorkflow>();
builder.Services.AddSingleton<IMigrationWorkflow>(services => services.GetRequiredService<MigrationWorkflow>());
builder.Services.AddHostedService(services => services.GetRequiredService<MigrationWorkflow>());
builder.Services.AddSingleton<CopilotGuide>();
builder.Services.AddSingleton<ICopilotGuide>(services => services.GetRequiredService<CopilotGuide>());
builder.Services.AddHostedService(services => services.GetRequiredService<CopilotGuide>());
builder.Services.AddSingleton<IStudioStatusService, StudioStatusService>();
var app = builder.Build();
app.UseExceptionHandler();
app.Use(async (context, next) =>
{
    var host = context.Request.Host;
    if (host.Host is not ("localhost" or "127.0.0.1") || host.Port != 5188
        || context.Connection.RemoteIpAddress is not { } address || !IPAddress.IsLoopback(address))
    {
        context.Response.StatusCode = 403;
        return;
    }
    context.Response.Headers.XContentTypeOptions = "nosniff";
    context.Response.Headers["Content-Security-Policy"] =
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; form-action 'self'; base-uri 'self'";
    context.Response.Headers["Referrer-Policy"] = "no-referrer";
    if (context.Request.Path.StartsWithSegments("/api"))
        context.Response.Headers.CacheControl = "no-store";
    await next();
});
app.UseSession();
app.Use(async (context, next) =>
{
    if (context.Request.Path.StartsWithSegments("/api") && context.Request.Path != "/api/session")
    {
        if (context.Session.GetString("operator") != "local")
            throw new StudioException(401, "Establish a local browser session first.");
        if (!HttpMethods.IsGet(context.Request.Method) && !HttpMethods.IsHead(context.Request.Method))
        {
            var expectedOrigin = $"{context.Request.Scheme}://{context.Request.Host}";
            if (context.Request.Headers.Origin != expectedOrigin)
                throw new StudioException(403, "Mutating operations require the exact local application origin.");
            try { await context.RequestServices.GetRequiredService<IAntiforgery>().ValidateRequestAsync(context); }
            catch (AntiforgeryValidationException)
            {
                throw new StudioException(403, "The operation approval token is missing or invalid. Reload this local app.");
            }
        }
    }
    await next();
});
var paths = app.Services.GetRequiredService<StudioPaths>();
var frontend = Path.Combine(paths.Root, "client", "dist");
if (Directory.Exists(frontend))
{
    var files = new PhysicalFileProvider(frontend);
    app.UseDefaultFiles(new DefaultFilesOptions { FileProvider = files });
    app.UseStaticFiles(new StaticFileOptions { FileProvider = files });
    app.MapFallback(async context =>
    {
        if (context.Request.Path.StartsWithSegments("/api") || context.Request.Path.StartsWithSegments("/openapi"))
        {
            context.Response.StatusCode = 404;
            return;
        }
        context.Response.ContentType = "text/html";
        await context.Response.SendFileAsync(Path.Combine(frontend, "index.html"), context.RequestAborted);
    });
}
app.MapOpenApi();
app.MapStudio();
app.Run();

public partial class Program;
