using System.Collections.Concurrent;
using System.ComponentModel.DataAnnotations;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace MigrationStudio.Services;

public interface IMigrationWorkflow
{
    Task<MigrationPlan> CreateAsync(MigrationConfiguration configuration, CancellationToken token);
    MigrationPlan GetPlan(string id);
    MigrationRun GetRun(string id);
    Task<MigrationRun> StartAsync(string id, StartMigrationRequest approval, CancellationToken token);
    Task<MigrationRun> CancelAsync(string id, CancellationToken token);
    object AgentSummary();
}

public sealed class MigrationWorkflow : BackgroundService, IMigrationWorkflow
{
    public const string Confirmation = "CREATE FREE DATABASE AND MIGRATE";
    private readonly ConcurrentDictionary<string, MigrationPlan> plans = new();
    private readonly ConcurrentDictionary<string, MigrationRun> runs = new();
    private readonly ConcurrentDictionary<string, CancellationTokenSource> cancellations = new();
    private readonly System.Threading.Channels.Channel<string> queue =
        System.Threading.Channels.Channel.CreateBounded<string>(1);
    private readonly SemaphoreSlim admission = new(1, 1);
    private readonly IOperationRunner runner;
    private readonly IEventStream events;
    private readonly StudioPaths paths;
    private readonly ILogger<MigrationWorkflow> logger;

    public MigrationWorkflow(IOperationRunner runner, IEventStream events, StudioPaths paths, ILogger<MigrationWorkflow> logger)
    {
        this.runner = runner;
        this.events = events;
        this.paths = paths;
        this.logger = logger;
        var root = Path.Combine(paths.StateRoot, "runs");
        if (!Directory.Exists(root)) return;
        foreach (var directory in Directory.GetDirectories(root))
        {
            var file = Path.Combine(directory, "state.json");
            if (!File.Exists(file)) continue;
            var saved = JsonSerializer.Deserialize<SavedRun>(File.ReadAllText(file), StudioPaths.Json)
                ?? throw new InvalidOperationException("A saved migration state is invalid.");
            plans[saved.Plan.Id] = saved.Plan;
            runs[saved.Run.Id] = saved.Run.State is "running" or "queued" or "cancelling"
                ? saved.Run with { State = "interrupted", Error = "Host restarted. Inspect Azure and local state before creating a new plan; no operation was resumed." }
                : saved.Run;
        }
    }

    public async Task<MigrationPlan> CreateAsync(MigrationConfiguration configuration, CancellationToken token)
    {
        Validate(configuration);
        var id = Guid.NewGuid().ToString("N");
        var plan = new MigrationPlan(id, Fingerprint(configuration), configuration,
            [
                $"Source: {configuration.ContainerName} / {configuration.SourceDatabase}. Source data and schema are not modified.",
                $"Destination: {configuration.SubscriptionId} / {configuration.ResourceGroup} / {configuration.ServerName} / {configuration.TargetDatabase}.",
                configuration.CreateResourceGroup ? "Create the selected resource group." : "Reuse the selected resource group.",
                configuration.CreateServer ? "Create an Entra-only server with the confirmed operator as administrator." : "Reuse the server without replacing its administrator or authentication settings.",
                "Create a NEW empty free-offer General Purpose serverless database. Verify useFreeLimit=true and AutoPause; never enable paid overages.",
                "Source must pass the script's consistency gate before export. A writer checkbox alone is not evidence.",
                "Export actual unmasked schema/data, import into the empty target, and compare measured source/target evidence.",
                "SQL target connectivity must already be approved; no broad firewall rule or automatic public-IP lookup.",
                "No Service Desk switch, automatic cloud cleanup, paid-tier fallback, or source deletion."
            ], "review", DateTimeOffset.UtcNow, InitialSteps());
        plans[id] = plan;
        var run = new MigrationRun(id, "review", plan.Steps, DateTimeOffset.UtcNow);
        runs[id] = run;
        await PersistAsync(plan, run, token);
        events.Publish("review", "ready", "An immutable migration plan is ready for operator review. No resources were changed.", id);
        return plan;
    }

    public MigrationPlan GetPlan(string id) => plans.TryGetValue(id, out var plan)
        ? plan : throw new StudioException(404, "Migration plan not found.");

    public MigrationRun GetRun(string id) => runs.TryGetValue(id, out var run)
        ? run : throw new StudioException(404, "Migration run not found.");

    public async Task<MigrationRun> StartAsync(string id, StartMigrationRequest approval, CancellationToken token)
    {
        var plan = GetPlan(id);
        if (approval.Confirmation != Confirmation || !approval.WritersStopped)
            throw new StudioException(400, "The exact approval phrase and offline-writer acknowledgement are required.");
        await admission.WaitAsync(token);
        try
        {
            if (runs.Values.Any(run => run.State is "running" or "queued" or "cancelling"))
                throw new StudioException(409, "Another migration is active.");
            if (GetRun(id).State != "review")
                throw new StudioException(409, "This approval cannot be reused. Create a fresh reviewed plan.");
            var run = GetRun(id) with { State = "queued", UpdatedAt = DateTimeOffset.UtcNow };
            await PersistAsync(plan, run, token);
            runs[id] = run;
            cancellations[id] = new CancellationTokenSource();
            if (!queue.Writer.TryWrite(id)) throw new InvalidOperationException("Migration admission queue is unavailable.");
            events.Publish("approval", "approved", "Operator approved this exact destination and offline migration. The consistency gate still applies.", id);
            return run;
        }
        finally { admission.Release(); }
    }

    public async Task<MigrationRun> CancelAsync(string id, CancellationToken token)
    {
        var run = GetRun(id);
        if (!cancellations.TryGetValue(id, out var cancellation))
            throw new StudioException(409, "This run has no active process to cancel.");
        var changed = run with { State = "cancelling", UpdatedAt = DateTimeOffset.UtcNow };
        runs[id] = changed;
        await PersistAsync(GetPlan(id), changed, token);
        await cancellation.CancelAsync();
        events.Publish("cancellation", "cancelling", "Cancellation requested. Partial Azure resources are retained for inspection.", id);
        return changed;
    }

    public object AgentSummary()
    {
        var latest = runs.Values.OrderByDescending(run => run.UpdatedAt).FirstOrDefault();
        return latest is null ? new { state = "not-started", stages = Array.Empty<string>() }
            : new { state = latest.State, stages = latest.Steps.Select(step => $"{step.Id}: {step.State}").ToArray() };
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var id in queue.Reader.ReadAllAsync(stoppingToken))
        {
            var plan = GetPlan(id);
            using var linked = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken, cancellations[id].Token);
            try
            {
                Update(id, "running");
                var input = JsonSerializer.SerializeToElement(plan.Configuration, StudioPaths.Json);
                var dictionary = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(input.GetRawText(), StudioPaths.Json)!;
                dictionary["runDirectory"] = JsonSerializer.SerializeToElement(paths.RunDirectory(id));
                dictionary["confirmation"] = JsonSerializer.SerializeToElement(Confirmation);
                dictionary["writersStopped"] = JsonSerializer.SerializeToElement(true);
                var result = await runner.RunAsync("Migrate", dictionary, progress => ApplyProgress(id, progress), linked.Token);
                var passed = result.ValueKind == JsonValueKind.Object
                    && result.TryGetProperty("verified", out var verified) && verified.ValueKind == JsonValueKind.True;
                Update(id, passed ? "succeeded" : "needs-review", validation: result,
                    error: passed ? null : "Operation completed without a verified=true validation verdict. Review the evidence before cutover.");
            }
            catch (OperationCanceledException) when (linked.IsCancellationRequested)
            {
                Update(id, "cancelled", error: "Operation cancelled. Inspect partial target state; no automatic deletion or app switch occurred.");
            }
            catch (StudioException exception)
            {
                Update(id, "failed", error: exception.Message);
            }
            catch (Exception exception)
            {
                logger.LogError("Migration failed with {ExceptionType}. Sensitive details are withheld.", exception.GetType().Name);
                Update(id, "failed", error: "An unexpected host error stopped this migration. No success or cutover was assumed.");
            }
            finally
            {
                if (cancellations.TryRemove(id, out var cancellation)) cancellation.Dispose();
                await PersistAsync(plan, GetRun(id), CancellationToken.None);
            }
        }
    }

    private void ApplyProgress(string id, JsonElement progress)
    {
        var stage = progress.GetProperty("stage").GetString() ?? "operation";
        var state = progress.GetProperty("state").GetString() ?? "running";
        var message = progress.GetProperty("message").GetString() ?? "Operation update.";
        runs.AddOrUpdate(id, _ => throw new InvalidOperationException(), (_, current) =>
            current with { Steps = current.Steps.Select(step => step.Id == stage
                ? step with { State = state, Message = message } : step).ToArray(), UpdatedAt = DateTimeOffset.UtcNow });
        var entry = events.Publish(stage, state, message, id);
        File.AppendAllText(Path.Combine(paths.RunDirectory(id), "events.jsonl"),
            JsonSerializer.Serialize(entry, StudioPaths.Json) + Environment.NewLine);
        PersistAsync(GetPlan(id), GetRun(id), CancellationToken.None).GetAwaiter().GetResult();
    }

    private void Update(string id, string state, JsonElement? validation = null, string? error = null)
    {
        runs.AddOrUpdate(id, _ => throw new InvalidOperationException(), (_, current) =>
            current with { State = state, Validation = validation, Error = error, UpdatedAt = DateTimeOffset.UtcNow });
        events.Publish("migration", state, error ?? (state == "succeeded"
            ? "Source and target validation passed. Application cutover remains a separate approved step."
            : "Migration state updated."), id);
    }

    private async Task PersistAsync(MigrationPlan plan, MigrationRun run, CancellationToken token)
    {
        var file = Path.Combine(paths.RunDirectory(plan.Id), "state.json");
        var temporary = file + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            await File.WriteAllTextAsync(temporary, JsonSerializer.Serialize(new SavedRun(plan, run), StudioPaths.Json), token);
            File.Move(temporary, file, overwrite: true);
        }
        finally { File.Delete(temporary); }
    }

    public static string Fingerprint(MigrationConfiguration configuration) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(configuration, StudioPaths.Json))));

    public static void Validate(MigrationConfiguration configuration)
    {
        Validator.ValidateObject(configuration, new ValidationContext(configuration), validateAllProperties: true);
        if (!Guid.TryParse(configuration.TenantId, out _) || !Guid.TryParse(configuration.SubscriptionId, out _))
            throw new StudioException(400, "Tenant and subscription must be valid identifiers.");
        if (configuration.SourceDatabase.Equals("master", StringComparison.OrdinalIgnoreCase)
            || configuration.SourceDatabase.Equals("tempdb", StringComparison.OrdinalIgnoreCase)
            || configuration.SourceDatabase.Equals("model", StringComparison.OrdinalIgnoreCase)
            || configuration.SourceDatabase.Equals("msdb", StringComparison.OrdinalIgnoreCase))
            throw new StudioException(400, "Select a user database, not a system database.");
        if (configuration.SourceDatabase.Any(char.IsControl) || configuration.TargetDatabase.Any(char.IsControl))
            throw new StudioException(400, "Database names cannot contain control characters.");
    }

    private static MigrationStep[] InitialSteps() =>
    [
        new("preflight", "Verify prerequisites and consistency", "pending", "Not started."),
        new("provision", "Create protected free destination", "pending", "No resources created."),
        new("export", "Export actual schema and data", "pending", "No export started."),
        new("import", "Import into empty Azure database", "pending", "No import started."),
        new("verify", "Compare source and target evidence", "pending", "Cloud behavior not tested.")
    ];

    private sealed record SavedRun(MigrationPlan Plan, MigrationRun Run);
}
