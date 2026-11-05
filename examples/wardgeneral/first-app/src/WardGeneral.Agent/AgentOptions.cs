namespace WardGeneral.Agent;

/// <summary>
/// Configuration for the in-app clinical assistant (Microsoft Agent Framework +
/// the DAB SQL MCP server). Bound from the "Agent" section of configuration.
/// </summary>
public sealed class AgentOptions
{
    /// <summary>Azure OpenAI endpoint hosting the chat model (e.g. https://your-foundry.openai.azure.com/).</summary>
    public string Endpoint { get; set; } = "";

    /// <summary>Chat-model deployment name (a reasoning model, e.g. gpt-5).</summary>
    public string Deployment { get; set; } = "gpt-5";

    /// <summary>The DAB SQL MCP endpoint whose tools the agent may call.</summary>
    public string McpUrl { get; set; } = "http://localhost:5000/mcp";

    /// <summary>
    /// Agentic AI. Folder holding the runtime Agent Skill (the folder that
    /// contains SKILL.md). Relative paths resolve against the app's base
    /// directory. Leave empty to run with no skill attached.
    /// </summary>
    public string SkillPath { get; set; } = "skills/shift-handoff";

    /// <summary>
    /// Agentic AI. Any MCP tool whose name contains one of these fragments is
    /// wrapped so that it CANNOT execute without explicit human approval.
    /// Matched on fragments because DAB decorates entity names when it publishes
    /// them as MCP tools. This is the only write the assistant is offered and
    /// the only tool that pauses.
    /// </summary>
    public IList<string> ApprovalRequiredToolFragments { get; set; } =
        new List<string> { "save_handoff" };

    /// <summary>System instructions for the assistant.</summary>
    public string Instructions { get; set; } =
        "You are the Ward General clinical assistant. Answer strictly from the Ward General " +
        "tools (search encounters, patient charts, similar clinical notes, and AI clinical " +
        "assistance). Never invent patients, encounters, values, or citations. When you use a " +
        "tool, ground your answer in what it returns. Any clinical suggestion is ADVISORY — a " +
        "licensed clinician confirms. Be concise and cite encounter/note ids you used. " +
        // Kept here rather than in the skill: the skill body is not in context until
        // the model has already decided to load it.
        "SKILLS: for any question about shift handoff — which patients need one, or preparing " +
        "one for a named patient — call load_skill for 'shift-handoff' BEFORE calling any data " +
        "tool, and follow it.";
}
