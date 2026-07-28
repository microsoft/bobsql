using System.Runtime.CompilerServices;
using Azure.AI.OpenAI;
using Azure.Identity;
using Microsoft.Agents.AI;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ModelContextProtocol.Client;

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
    private readonly SemaphoreSlim _gate = new(1, 1);
    private McpClient? _mcp;
    private AIAgent? _agent;

    public WardGeneralAgent(IOptions<AgentOptions> opts, ILogger<WardGeneralAgent> log)
    {
        _opts = opts.Value;
        _log = log;
    }

    private async Task<AIAgent> GetAgentAsync(CancellationToken ct)
    {
        if (_agent is not null) return _agent;
        await _gate.WaitAsync(ct);
        try
        {
            if (_agent is not null) return _agent;

            // Connect to the DAB SQL MCP server (HTTP transport) and pull its tools.
            _mcp = await McpClient.CreateAsync(
                new HttpClientTransport(new HttpClientTransportOptions
                {
                    Name = "wardgeneral-dab",
                    Endpoint = new Uri(_opts.McpUrl)
                }),
                cancellationToken: ct);

            IList<McpClientTool> tools = await _mcp.ListToolsAsync(cancellationToken: ct);

            // Chat Completions agent over the reasoning model (passwordless / Entra).
            var chat = new AzureOpenAIClient(new Uri(_opts.Endpoint), new DefaultAzureCredential())
                .GetChatClient(_opts.Deployment)
                .AsIChatClient();

            _agent = chat.AsAIAgent(
                instructions: _opts.Instructions,
                name: "WardGeneralAssistant",
                tools: [.. tools.Cast<AITool>()]);

            _log.LogInformation("Ward General assistant ready with {Count} MCP tools.", tools.Count);
            return _agent;
        }
        finally
        {
            _gate.Release();
        }
    }

    /// <summary>Start a new multi-turn conversation (its own agent thread).</summary>
    public AssistantConversation NewConversation() => new();

    /// <summary>
    /// Ask the assistant. Streams tokens and tool-call notifications as they occur.
    /// <paramref name="context"/> (optional) seeds the current page — e.g. the
    /// encounter being viewed. <paramref name="actingProviderId"/> is the acting
    /// clinician (0 = Admin) — injected so the model passes it to the RLS-scoped
    /// tools; the engine then filters charts/encounters to that provider.
    /// </summary>
    public async IAsyncEnumerable<AssistantUpdate> AskAsync(
        string userText,
        AssistantConversation convo,
        string? context = null,
        int actingProviderId = 0,
        [EnumeratorCancellation] CancellationToken ct = default)
    {
        var agent = await GetAgentAsync(ct);
        convo.Session ??= await agent.CreateSessionAsync(ct);

        var who = actingProviderId == 0
            ? "Admin (may see all patients)"
            : "scoped to their own patients by Row-Level Security";
        var security =
            $"[SECURITY] The acting clinician is provider id {actingProviderId} ({who}). " +
            $"Pass ActingProviderId={actingProviderId} on every Ward General tool call that accepts it. " +
            "Never change or omit it.";

        var message = string.IsNullOrWhiteSpace(context)
            ? $"{security}\n{userText}"
            : $"{security}\n(Context: {context})\n{userText}";

        await foreach (var update in agent.RunStreamingAsync(message, convo.Session, cancellationToken: ct))
        {
            if (!string.IsNullOrEmpty(update.Text))
                yield return AssistantUpdate.Token(update.Text);

            foreach (var content in update.Contents)
            {
                if (content is FunctionCallContent call)
                    yield return AssistantUpdate.Tool(call.Name, DescribeArgs(call.Arguments));
            }
        }
    }

    private static string? DescribeArgs(IDictionary<string, object?>? args)
        => args is null || args.Count == 0
            ? null
            : string.Join(", ", args.Select(kv => $"{kv.Key}={kv.Value}"));

    public async ValueTask DisposeAsync()
    {
        if (_mcp is not null) await _mcp.DisposeAsync();
        _gate.Dispose();
    }
}

/// <summary>Opaque multi-turn conversation state (wraps the MAF agent session).</summary>
public sealed class AssistantConversation
{
    internal AgentSession? Session { get; set; }
}

/// <summary>A streamed unit from the assistant: either a token of text or a tool call.</summary>
public sealed record AssistantUpdate(AssistantUpdateKind Kind, string? Text, string? ToolName, string? ToolArgs)
{
    public static AssistantUpdate Token(string text) => new(AssistantUpdateKind.Token, text, null, null);
    public static AssistantUpdate Tool(string name, string? args) => new(AssistantUpdateKind.ToolCall, null, name, args);
}

public enum AssistantUpdateKind
{
    Token,
    ToolCall
}
