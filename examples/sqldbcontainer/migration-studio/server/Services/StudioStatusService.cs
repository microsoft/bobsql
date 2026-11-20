using System.Text.Json;

namespace MigrationStudio.Services;

public interface IStudioStatusService
{
    Task<StudioStatus> GetAsync(CancellationToken token);
}

public sealed class StudioStatusService(
    IOperationRunner runner, ICopilotGuide copilot, ISkillCatalog skills) : IStudioStatusService
{
    public async Task<StudioStatus> GetAsync(CancellationToken token)
    {
        var copilotTask = copilot.StatusAsync(token);
        Capability[] capabilities;
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
        timeout.CancelAfter(TimeSpan.FromSeconds(60));
        try
        {
            var result = await runner.RunAsync("Preflight", new { }, null, timeout.Token);
            capabilities = result.GetProperty("capabilities").Deserialize<Capability[]>(StudioPaths.Json)
                ?? throw new StudioException(502, "Preflight did not return capability results.");
        }
        catch (StudioException exception)
        {
            capabilities = [new("Migration preflight", "blocked", exception.Message)];
        }
        catch (OperationCanceledException) when (!token.IsCancellationRequested)
        {
            capabilities = [new("Migration preflight", "blocked", "Preflight exceeded 60 seconds. Check local CLI readiness before retrying.")];
        }
        var copilotStatus = await copilotTask;
        return new("http://localhost:5187", capabilities, skills.All, copilotStatus);
    }
}
