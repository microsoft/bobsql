using System.Text.RegularExpressions;
using System.Threading.Channels;
using GitHub.Copilot;
using GitHub.Copilot.Rpc;
using Microsoft.Extensions.AI;

namespace MigrationStudio.Services;

public interface ICopilotGuide
{
    Task<CopilotStatus> StatusAsync(CancellationToken token);
    Task<CopilotSignInState> BeginSignInAsync(string owner, CancellationToken token);
    Task<CopilotSignInState> SignInStateAsync(string owner, CancellationToken token);
    Task<CopilotSignInState> CancelSignInAsync(string owner, string id, CancellationToken token);
    Task QueueAsync(CopilotMessageRequest request, CancellationToken token);
}

#pragma warning disable GHCP001
public sealed partial class CopilotGuide(
    StudioPaths paths, ISkillCatalog skills, IEventStream events,
    IMigrationWorkflow workflow, ILogger<CopilotGuide> logger) : BackgroundService, ICopilotGuide
{
    private readonly SemaphoreSlim connectionGate = new(1, 1);
    private readonly Channel<CopilotMessageRequest> requests = Channel.CreateBounded<CopilotMessageRequest>(1);
    private CopilotClient? client;
    private CopilotSession? session;
    private IDisposable? subscription;
    private CopilotStatus? lastStatus;
    private DateTimeOffset checkedAt;
    private string? sessionModel;
    private int busy;

    public async Task<CopilotStatus> StatusAsync(CancellationToken token)
    {
        await connectionGate.WaitAsync(token);
        try
        {
            if (lastStatus is not null && DateTimeOffset.UtcNow - checkedAt < TimeSpan.FromSeconds(30))
                return lastStatus;
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
            timeout.CancelAfter(TimeSpan.FromSeconds(45));
            try
            {
                if (client is null)
                {
                    client = new CopilotClient(CopilotRuntime.ClientOptions(paths.AgentWorkspace));
                    await client.StartAsync(timeout.Token);
                }
                var auth = await client.GetAuthStatusAsync(timeout.Token);
                if (!auth.IsAuthenticated)
                    return SetStatus(new(false, "Sign in to GitHub using Connect Copilot in this pane. Azure sign-in is separate.", []));
                var models = await client.ListModelsAsync(timeout.Token);
                return SetStatus(new(true, "Copilot SDK authenticated. Sending a message uses your Copilot allowance; inference has not been tested by this readiness check.",
                    models.Select(model => new CopilotModel(model.Id, model.Name)).ToArray()));
            }
            catch (Exception exception) when (!token.IsCancellationRequested)
            {
                logger.LogWarning("Copilot readiness failed with {ExceptionType}; credentials and transport details withheld.", exception.GetType().Name);
                if (client is not null)
                {
                    await client.DisposeAsync();
                    client = null;
                }
                return SetStatus(new(false, "Copilot runtime connection could not be verified. Check the installed SDK runtime and Copilot sign-in, then retry.", []));
            }
        }
        finally { connectionGate.Release(); }
    }

    private CopilotStatus SetStatus(CopilotStatus status)
    {
        lastStatus = status;
        checkedAt = DateTimeOffset.UtcNow;
        return status;
    }

    public async Task QueueAsync(CopilotMessageRequest request, CancellationToken token)
    {
        if (string.IsNullOrWhiteSpace(request.Text) || request.Text.Length > 2000)
            throw new StudioException(400, "Enter a question of 1 to 2,000 characters.");
        if (SecretPattern().IsMatch(request.Text))
            throw new StudioException(400, "Do not send credentials, tokens, or connection strings to Copilot. Use the protected local configuration.");
        var status = await StatusAsync(token);
        if (!status.Authenticated) throw new StudioException(503, status.Status);
        if (request.Model is { Length: > 0 } model && model != "auto" && !status.Models.Any(item => item.Id == model))
            throw new StudioException(400, "Choose a model reported by the authenticated Copilot runtime.");
        await connectionGate.WaitAsync(token);
        try
        {
            if (signInTask is { IsCompleted: false })
                throw new StudioException(409, "Finish or cancel Copilot sign-in before sending a message.");
            if (Interlocked.CompareExchange(ref busy, 1, 0) != 0)
                throw new StudioException(409, "Copilot is still responding to the previous message.");
            if (!requests.Writer.TryWrite(request))
            {
                Interlocked.Exchange(ref busy, 0);
                throw new StudioException(409, "The Copilot request queue is busy.");
            }
        }
        finally { connectionGate.Release(); }
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var request in requests.Reader.ReadAllAsync(stoppingToken))
        {
            try
            {
                var model = string.IsNullOrWhiteSpace(request.Model) ? "auto" : request.Model;
                if (session is null || sessionModel != model)
                {
                    subscription?.Dispose();
                    if (session is not null) await session.DisposeAsync();
                    var tools = new[]
                    {
                        CopilotTool.DefineTool(() => Trace("tool", "inspect_readiness", () =>
                            new { authenticated = lastStatus?.Authenticated == true, migrationTooling = "Use wizard preflight for measured SQL and Azure readiness.", sourceDataIncluded = false }),
                            factoryOptions: new AIFunctionFactoryOptions { Name = "inspect_readiness", Description = "Read sanitized application readiness, without credentials or database content." },
                            toolOptions: new CopilotToolOptions { SkipPermission = true }),
                        CopilotTool.DefineTool(() => Trace("tool", "get_migration_status", () => workflow.AgentSummary()),
                            factoryOptions: new AIFunctionFactoryOptions { Name = "get_migration_status", Description = "Read actual migration stage states; never assume any operation has run." },
                            toolOptions: new CopilotToolOptions { SkipPermission = true }),
                        CopilotTool.DefineTool((string name) => Trace("tool", "read_skill_instructions", () =>
                        {
                            if (!skills.All.Any(skill => skill.Name == name))
                                throw new StudioException(400, "The requested skill is not allowlisted.");
                            return Trace("skill", name, () => skills.Read(name));
                        }), factoryOptions: new AIFunctionFactoryOptions { Name = "read_skill_instructions", Description = "Read one of the three named, allowlisted public skill adaptations." },
                            toolOptions: new CopilotToolOptions { SkipPermission = true })
                    };
                    var toolNames = new[] { "inspect_readiness", "get_migration_status", "read_skill_instructions" };
                    var config = CopilotRuntime.RestrictedSession(paths.AgentWorkspace, toolNames.ToList());
                    config.Model = model;
                    config.Streaming = true;
                    config.EnableSkills = true;
                    config.SkillDirectories = skills.Directories.ToList();
                    config.Tools = tools;
                    config.Agent = "migration-guide";
                    config.CustomAgents =
                    [
                        new CustomAgentConfig
                        {
                            Name = "migration-guide",
                            DisplayName = "SQL Migration Copilot",
                            Description = "Explains and guides an approved, policy-enforced SQL migration.",
                            Prompt = Instructions,
                            Skills = skills.All.Select(skill => skill.Name).ToList(),
                            Tools = toolNames.ToList()
                        }
                    ];
                    config.SystemMessage = new SystemMessageConfig { Mode = SystemMessageMode.Replace, Content = Instructions };
                    session = await client!.CreateSessionAsync(config, stoppingToken);
                    sessionModel = model;
                    events.Publish("copilot", "ready", "Copilot session created with three adapted skills and only three read-only custom tools. Shell and file tools are unavailable.");
                    foreach (var skill in skills.All)
                        events.Publish("skill", "available", "Skill instructions supplied to the session. This is not a tool invocation.", subject: skill.Name);
                    subscription = session.On<SessionEvent>(entry =>
                    {
                        if (entry is AssistantMessageDeltaEvent delta)
                            events.Copilot("delta", delta.Data.DeltaContent);
                    });
                }
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
                timeout.CancelAfter(TimeSpan.FromMinutes(3));
                events.Publish("copilot", "started", "Copilot response requested. Waiting for actual tool and skill events.");
                await session.SendAndWaitAsync(new MessageOptions { Prompt = request.Text }, cancellationToken: timeout.Token);
                events.Publish("copilot", "completed", "Copilot response completed. Only recorded reads demonstrate skill access.");
                events.Copilot("done", "");
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                events.Copilot("error", "The local host stopped before Copilot completed.");
                events.Publish("copilot", "failed", "The local host stopped before Copilot completed.");
            }
            catch (Exception exception)
            {
                logger.LogWarning("Copilot request failed with {ExceptionType}; prompt and transport details withheld.", exception.GetType().Name);
                events.Copilot("error", "Copilot could not complete this request. No migration operation or fallback model was executed.");
                events.Publish("copilot", "failed", "Copilot request failed. No migration operation or fallback model was executed.");
                subscription?.Dispose();
                subscription = null;
                if (session is not null) await session.DisposeAsync();
                session = null;
            }
            finally { Interlocked.Exchange(ref busy, 0); }
        }
    }

    private T Trace<T>(string stage, string subject, Func<T> action)
    {
        events.Publish(stage, "started", stage == "skill" ? "Reading adapted skill instructions." : "Invoking a read-only host tool.", subject: subject);
        try
        {
            var result = action();
            events.Publish(stage, "completed", stage == "skill" ? "Skill instructions returned to Copilot; not a migration execution." : "Read-only tool returned. Arguments and results are withheld.", subject: subject);
            return result;
        }
        catch
        {
            events.Publish(stage, "failed", "The invocation failed. Sensitive diagnostics are withheld.", subject: subject);
            throw;
        }
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        signInAttempt?.Cancellation.Cancel();
        if (signInTask is not null) await signInTask;
        signInAttempt?.Cancellation.Dispose();
        await base.StopAsync(cancellationToken);
        subscription?.Dispose();
        if (session is not null) await session.DisposeAsync();
        if (client is not null) await client.DisposeAsync();
    }

    private const string Instructions = """
        You are SQL Migration Copilot inside a LOCAL demonstration application.
        Use the three adapted migration skills supplied to this session.
        Before explaining execution readiness, invoke inspect_readiness and
        get_migration_status. For skill-based guidance, call read_skill_instructions
        for each relevant named skill so the operator can observe the actual reads.
        Be concise, accurate, and grounded in actual tool evidence.
        You have ONLY read-only guidance tools. You cannot provision, export,
        import, stop apps, change SQL, or approve any operation.
        The wizard's independent policy layer executes reviewed fixed operations.
        Explain that division honestly: agent-assisted, host-executed migration.
        Never claim that a stage ran unless get_migration_status confirms it.
        Never invent progress, data counts, identities, target feature support,
        successful cloud validation, or a connection switch.
        Do not ask for or repeat credentials, connection strings, SQL rows,
        embedding vectors, source code, or raw diagnostics. Do not fetch URLs.
        Copilot sign-in and Azure tenant sign-in are separate.
        No paid-overage fallback, no automatic source writes, no automatic cloud
        cleanup, and no administrator identity for the runtime web application.
        If the user asks for an action, direct them to the relevant wizard stage.
        Free-offer eligibility and preview feature fidelity must be verified.
        """;

    [GeneratedRegex(@"(?i)(password\s*=|pwd\s*=|bearer\s+[a-z0-9._-]+|gh[pousr]_[a-z0-9]+|github_pat_|server\s*=|data\s+source\s*=)")]
    private static partial Regex SecretPattern();
}
#pragma warning restore GHCP001
