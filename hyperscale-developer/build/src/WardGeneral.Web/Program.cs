using WardGeneral.Web.Components;
using WardGeneral.Data;
using WardGeneral.Agent;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents();

// Data-access layer (talk verb: Secure it — Entra auth, no secrets).
// The connection factory reads WardGeneral:Server / WardGeneral:Database from config.
builder.Services.AddSingleton<WardGeneralConnectionFactory>();
builder.Services.AddScoped<ChartRepository>();
builder.Services.AddScoped<ResearchRepository>();

// Progressive-reveal feature flags — talk runs with all ON; the book flips them
// per chapter (deploy the chapter's SQL, flip the flag) with no source edits.
// See Options/FeatureFlags.cs.
builder.Services.Configure<WardGeneral.Web.Options.FeatureFlags>(
    builder.Configuration.GetSection("Features"));

// Row-Level Security "acting user" — talk verb: Secure it. On by default; the
// default identity is Admin (all patients). The "Viewing as" selector on the unit
// board picks a provider and the engine filters the board/charts to them — no
// restart. See RlsOptions.cs / AccessContext.cs.
builder.Services.Configure<RlsOptions>(
    builder.Configuration.GetSection("RowLevelSecurity"));
builder.Services.AddScoped<AccessContext>();

// In-app clinical assistant — talk verb: Modernize it. Microsoft Agent Framework
// agent whose tools are the DAB SQL MCP server (the same clinical.* procs the DAL
// and VS Code Copilot use). Singleton (one agent, built once); per-circuit page
// context grounds answers on the current view. See WardGeneral.Agent + AssistantDock.
builder.Services.Configure<AgentOptions>(builder.Configuration.GetSection("Agent"));
builder.Services.AddSingleton<WardGeneralAgent>();
builder.Services.AddScoped<WardGeneral.Web.Services.PageContext>();

var app = builder.Build();

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error", createScopeForErrors: true);
    // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
    app.UseHsts();
}
app.UseStatusCodePagesWithReExecute("/not-found", createScopeForStatusCodePages: true);
app.UseHttpsRedirection();

app.UseAntiforgery();

app.MapStaticAssets();
app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode();

app.Run();
