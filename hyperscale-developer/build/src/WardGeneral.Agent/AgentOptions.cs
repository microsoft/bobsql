namespace WardGeneral.Agent;

/// <summary>
/// Configuration for the in-app clinical assistant (Microsoft Agent Framework +
/// the DAB SQL MCP server). Bound from the "Agent" section of configuration.
/// </summary>
public sealed class AgentOptions
{
    /// <summary>Azure OpenAI endpoint hosting the chat model (e.g. https://collierhealth-ai.openai.azure.com/).</summary>
    public string Endpoint { get; set; } = "";

    /// <summary>Chat-model deployment name (a reasoning model, e.g. gpt-5).</summary>
    public string Deployment { get; set; } = "gpt-5";

    /// <summary>The DAB SQL MCP endpoint whose tools the agent may call.</summary>
    public string McpUrl { get; set; } = "http://localhost:5000/mcp";

    /// <summary>System instructions for the assistant.</summary>
    public string Instructions { get; set; } =
        "You are the Ward General clinical assistant. Answer strictly from the Ward General " +
        "tools (search encounters, patient charts, similar clinical notes, and AI clinical " +
        "assistance). Never invent patients, encounters, values, or citations. When you use a " +
        "tool, ground your answer in what it returns. Any clinical suggestion is ADVISORY — a " +
        "licensed clinician confirms. Be concise and cite encounter/note ids you used. " +
        "SECURITY: tools that accept ActingProviderId enforce Row-Level Security in the database. " +
        "Always pass ActingProviderId EXACTLY as given in the [SECURITY] line of the user's " +
        "message; never invent, change, or omit it. If a chart or search returns nothing, tell " +
        "the user they may not have access to that patient — do not try to work around it.";
}
