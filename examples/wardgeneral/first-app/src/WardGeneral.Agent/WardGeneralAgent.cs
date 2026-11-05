using System.Runtime.CompilerServices;
using Azure.AI.OpenAI;
using Azure.Identity;
using Microsoft.Agents.AI;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ModelContextProtocol.Client;
using WardGeneral.Data;

namespace WardGeneral.Agent;

/// <summary>
/// The in-app clinical assistant. A single <see cref="AIAgent"/> (Microsoft Agent
/// Framework, Chat Completions over Azure OpenAI) whose tools are the DAB
/// <b>SQL MCP</b> server — the SAME stored-procedure contract the app's DAL and
/// VS Code Copilot use. Built once (singleton), streamed per conversation.
///
/// The agent decides which tools to call from the user's natural-language question;
/// this class just surfaces the streamed tokens and tool calls to the UI.
/// </summary>
public sealed class WardGeneralAgent : IAsyncDisposable
{
    private readonly AgentOptions _opts;
    private readonly ILogger<WardGeneralAgent> _log;
    private readonly AccessContext _access;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly List<McpClient> _mcpClients = [];
    private McpClient? _mcp;
    private AIAgent? _agent;

    public WardGeneralAgent(
        IOptions<AgentOptions> opts,
        ILogger<WardGeneralAgent> log,
        AccessContext access)
    {
        _opts = opts.Value;
        _log = log;
        _access = access;
    }

    private async Task<IList<McpClientTool>> ConnectAsync(string name, string url, CancellationToken ct)
    {
        var httpClient = new HttpClient(new ActingProviderHandler(_access));
        var client = await McpClient.CreateAsync(
            new HttpClientTransport(new HttpClientTransportOptions
            {
                Name = name,
                Endpoint = new Uri(url)
            }, httpClient, ownsHttpClient: true),
            cancellationToken: ct);

        _mcpClients.Add(client);
        var tools = await client.ListToolsAsync(cancellationToken: ct);
        _log.LogInformation("Connected to MCP endpoint {Name} at {Url} with {Count} tools.", name, url, tools.Count);
        return tools;
    }

    private async Task<AIAgent> GetAgentAsync(CancellationToken ct)
    {
        if (_agent is not null) return _agent;
        await _gate.WaitAsync(ct);
        try
        {
            if (_agent is not null) return _agent;

            // Connect to the DAB SQL MCP server (HTTP transport) and pull its tools.
            var mcpTools = await ConnectAsync("wardgeneral-dab", _opts.McpUrl, ct);
            _mcp = _mcpClients[0];

            // Agentic AI: the approval gate. The two writes are wrapped so the
            // framework raises a request instead of executing. Everything else
            // stays a plain call, because a prompt the reader has to click
            // through on every read is a prompt they stop reading. Tracing wraps
            // everything, and composes inside the gate so an approved write is
            // traced too.
            List<AITool> tools = [];
            var gated = 0;
            foreach (var tool in mcpTools)
            {
                AIFunction traced = new TracedAIFunction(tool);
                if (RequiresApproval(tool.Name))
                {
                    tools.Add(new ApprovalRequiredAIFunction(traced));
                    gated++;
                }
                else
                {
                    tools.Add(traced);
                }
            }

            if (gated == 0 && _opts.ApprovalRequiredToolFragments.Count > 0)
            {
                _log.LogWarning(
                    "No MCP tool name matched {Fragments}, so NOTHING is approval-gated. " +
                    "Check that the primary DAB config exposes the write procedures.",
                    string.Join(", ", _opts.ApprovalRequiredToolFragments));
            }

            // Chat Completions agent over the reasoning model (passwordless / Entra).
            var chat = new AzureOpenAIClient(new Uri(_opts.Endpoint), new DefaultAzureCredential())
                .GetChatClient(_opts.Deployment)
                .AsIChatClient();

            var agentOptions = new ChatClientAgentOptions
            {
                Name = "WardGeneralAssistant",
                ChatOptions = new ChatOptions
                {
                    Instructions = _opts.Instructions,
                    Tools = tools
                }
            };

            // Agentic AI: the runtime Agent Skill. A context provider, not a tool -
            // the model asks for the skill when it decides the question calls for
            // it, and the framework loads the prose then. Loading and reading a
            // skill would ALSO require approval by default; both are turned off
            // here so the single prompt the reader sees is the saved handoff.
            var skills = CreateSkillsProvider();
            if (skills is not null)
            {
                agentOptions.AIContextProviders = [skills];
            }

            _agent = chat.AsAIAgent(agentOptions);

            _log.LogInformation(
                "Ward General assistant ready with {Count} MCP tools ({Gated} approval-gated).",
                tools.Count, gated);
            return _agent;
        }
        finally
        {
            _gate.Release();
        }
    }

    private bool RequiresApproval(string toolName)
        => _opts.ApprovalRequiredToolFragments.Any(
               f => toolName.Contains(f, StringComparison.OrdinalIgnoreCase));

    private AgentSkillsProvider? CreateSkillsProvider()
    {
        if (string.IsNullOrWhiteSpace(_opts.SkillPath)) return null;

        var path = Path.IsPathRooted(_opts.SkillPath)
            ? _opts.SkillPath
            : Path.Combine(AppContext.BaseDirectory, _opts.SkillPath);

        if (!Directory.Exists(path))
        {
            _log.LogWarning("Agent skill folder {Path} was not found; running without a skill.", path);
            return null;
        }

        _log.LogInformation("Loading agent skill from {Path}.", path);
        return new AgentSkillsProvider(path, options: new AgentSkillsProviderOptions
        {
            DisableLoadSkillApproval = true,
            DisableReadSkillResourceApproval = true
        });
    }

    /// <summary>Start a new multi-turn conversation (its own agent thread).</summary>
    public AssistantConversation NewConversation() => new();

    /// <summary>
    /// Ask the assistant. Streams tokens and tool-call notifications as they occur.
    /// <paramref name="context"/> (optional) seeds the current page — e.g. the
    /// encounter being viewed.
    /// </summary>
    public async IAsyncEnumerable<AssistantUpdate> AskAsync(
        string userText,
        AssistantConversation convo,
        string? context = null,
        [EnumeratorCancellation] CancellationToken ct = default)
    {
        var agent = await GetAgentAsync(ct);
        convo.Session ??= await agent.CreateSessionAsync(ct);

        // Each answer shows only its own work, so the previous turn's steps go.
        convo.Trace.Clear();
        AgentTrace.Current = convo.Trace;

        var message = string.IsNullOrWhiteSpace(context)
            ? userText
            : $"(Context: {context})\n{userText}";

        await foreach (var update in StreamAsync(agent, convo, new ChatMessage(ChatRole.User, message), ct))
            yield return update;
    }

    /// <summary>
    /// Agentic AI. Answer the pending approval request and let the run continue.
    /// Approving executes the tool call the model already proposed — the app does
    /// not rebuild it, so what the clinician saw is exactly what runs. Declining
    /// hands the model a refusal and the write never reaches the database.
    /// </summary>
    public async IAsyncEnumerable<AssistantUpdate> RespondToApprovalAsync(
        AssistantConversation convo,
        bool approved,
        string? reason = null,
        [EnumeratorCancellation] CancellationToken ct = default)
    {
        if (convo.Session is null || convo.Pending.Count == 0)
            yield break;

        var agent = await GetAgentAsync(ct);

        // The approved write is a tool call like any other, so it is traced too.
        AgentTrace.Current = convo.Trace;

        List<AIContent> responses = [];
        foreach (var request in convo.Pending)
        {
            responses.Add(new ToolApprovalResponseContent(request.RequestId, approved, request.ToolCall)
            {
                Reason = reason
            });
        }
        convo.Pending.Clear();

        await foreach (var update in StreamAsync(agent, convo, new ChatMessage(ChatRole.User, responses), ct))
            yield return update;
    }

    private async IAsyncEnumerable<AssistantUpdate> StreamAsync(
        AIAgent agent,
        AssistantConversation convo,
        ChatMessage message,
        [EnumeratorCancellation] CancellationToken ct)
    {
        convo.Session ??= await agent.CreateSessionAsync(ct);

        await foreach (var update in agent.RunStreamingAsync(message, convo.Session, cancellationToken: ct))
        {
            if (!string.IsNullOrEmpty(update.Text))
                yield return AssistantUpdate.Token(update.Text);

            foreach (var content in update.Contents)
            {
                switch (content)
                {
                    // Order matters: an approval request also carries the tool
                    // call, and reporting it as a plain call would tell the
                    // reader something ran when nothing has.
                    case ToolApprovalRequestContent request:
                        convo.Pending.Add(request);
                        yield return AssistantUpdate.Approval(
                            request.ToolCall is FunctionCallContent fc ? fc.Name : "tool call",
                            request.ToolCall is FunctionCallContent f ? DescribeArgs(f.Arguments) : null);
                        break;

                    case FunctionCallContent call:
                        yield return AssistantUpdate.Tool(call.Name, DescribeArgs(call.Arguments));
                        break;
                }
            }
        }
    }

    private static string? DescribeArgs(IDictionary<string, object?>? args)
        => args is null || args.Count == 0
            ? null
            : string.Join(", ", args.Select(kv => $"{kv.Key}={kv.Value}"));

    public async ValueTask DisposeAsync()
    {
        foreach (var client in _mcpClients) await client.DisposeAsync();
        _mcpClients.Clear();
        _mcp = null;
        _gate.Dispose();
    }
}

/// <summary>Opaque multi-turn conversation state (wraps the MAF agent session).</summary>
public sealed class AssistantConversation
{
    internal AgentSession? Session { get; set; }

    /// <summary>
    /// Agentic AI. Tool calls the framework has held back pending human approval.
    /// Kept on the conversation, not on the agent, because the agent is a
    /// singleton shared by every user of the app.
    /// </summary>
    internal List<ToolApprovalRequestContent> Pending { get; } = [];

    /// <summary>Agentic AI. The tool calls made during the current turn.</summary>
    public AgentTrace Trace { get; } = new();

    /// <summary>True when the assistant is waiting on the clinician to decide.</summary>
    public bool AwaitingApproval => Pending.Count > 0;
}

/// <summary>A streamed unit from the assistant: text, a tool call, or a request to approve one.</summary>
public sealed record AssistantUpdate(AssistantUpdateKind Kind, string? Text, string? ToolName, string? ToolArgs)
{
    public static AssistantUpdate Token(string text) => new(AssistantUpdateKind.Token, text, null, null);
    public static AssistantUpdate Tool(string name, string? args) => new(AssistantUpdateKind.ToolCall, null, name, args);
    public static AssistantUpdate Approval(string name, string? args) => new(AssistantUpdateKind.ApprovalRequest, null, name, args);
}

public enum AssistantUpdateKind
{
    Token,
    ToolCall,
    ApprovalRequest
}
