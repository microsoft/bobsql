using System.Diagnostics;
using System.Text.Json;
using Microsoft.Extensions.AI;

namespace WardGeneral.Agent;

/// <summary>
/// Agentic AI. Wraps one MCP tool so every invocation is recorded before the call
/// leaves the application.
/// </summary>
/// <remarks>
/// Composes with the approval gate rather than competing with it:
/// <c>ApprovalRequiredAIFunction</c> is itself a <see cref="DelegatingAIFunction"/>,
/// so a gated write is wrapped twice and the trace records the call at the moment
/// it is finally allowed to run.
/// </remarks>
internal sealed class TracedAIFunction(AIFunction inner) : DelegatingAIFunction(inner)
{
    protected override async ValueTask<object?> InvokeCoreAsync(
        AIFunctionArguments arguments,
        CancellationToken cancellationToken)
    {
        var trace = AgentTrace.Current;
        if (trace is null)
            return await base.InvokeCoreAsync(arguments, cancellationToken);

        var sw = Stopwatch.StartNew();
        try
        {
            var result = await base.InvokeCoreAsync(arguments, cancellationToken);
            sw.Stop();
            trace.Add(new AgentTraceStep(
                Name, Describe(arguments), sw.ElapsedMilliseconds,
                result?.ToString()?.Length ?? 0, null));
            return result;
        }
        catch (Exception ex)
        {
            sw.Stop();
            trace.Add(new AgentTraceStep(
                Name, Describe(arguments), sw.ElapsedMilliseconds, 0, ex.Message));
            throw;
        }
    }

    private static string Describe(AIFunctionArguments arguments)
    {
        try
        {
            return JsonSerializer.Serialize(arguments);
        }
        catch (Exception ex)
        {
            return $"<arguments could not be serialized: {ex.Message}>";
        }
    }
}
