using System.Collections.Concurrent;

namespace WardGeneral.Agent;

/// <summary>
/// Agentic AI. One tool invocation the agent chose to make, with the evidence a
/// reader needs to judge the decision: what it called, what it asked for, and
/// what came back.
/// </summary>
/// <param name="Tool">The MCP tool name the model selected.</param>
/// <param name="Arguments">The arguments the model chose, as JSON.</param>
/// <param name="ElapsedMs">Wall-clock duration of the call.</param>
/// <param name="ResultChars">Size of the returned payload, as a rough proxy for how much came back.</param>
/// <param name="Error">Set when the call failed; the agent's own recovery is then visible in the next step.</param>
public sealed record AgentTraceStep(
    string Tool,
    string Arguments,
    long ElapsedMs,
    int ResultChars,
    string? Error);

/// <summary>
/// Agentic AI. Collects the tool calls made during one assistant turn so the
/// application can show its work.
/// </summary>
/// <remarks>
/// Tools are built once and shared by every conversation, so the sink cannot be
/// a constructor argument — it is flowed through <see cref="AsyncLocal{T}"/>,
/// which follows the async call chain from the turn that started it down into
/// each function invocation the framework makes on its behalf.
/// </remarks>
public sealed class AgentTrace
{
    private static readonly AsyncLocal<AgentTrace?> _current = new();

    internal static AgentTrace? Current
    {
        get => _current.Value;
        set => _current.Value = value;
    }

    private readonly ConcurrentQueue<AgentTraceStep> _steps = new();

    /// <summary>Steps recorded so far, oldest first. Safe to read while a turn is still running.</summary>
    public IReadOnlyCollection<AgentTraceStep> Steps => _steps;

    internal void Add(AgentTraceStep step) => _steps.Enqueue(step);

    /// <summary>Drop the previous turn's steps so each answer shows only its own work.</summary>
    public void Clear() => _steps.Clear();
}
