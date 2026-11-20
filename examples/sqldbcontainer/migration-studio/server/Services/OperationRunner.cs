using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace MigrationStudio.Services;

public interface IOperationRunner
{
    Task<JsonElement> RunAsync(string operation, object input, Action<JsonElement>? progress, CancellationToken token);
}

public sealed class OperationRunner(StudioPaths paths, ILogger<OperationRunner> logger) : IOperationRunner
{
    private static readonly HashSet<string> Operations =
        ["Containers", "Databases", "Preflight", "Tenants", "Subscriptions", "Locations", "Groups", "Servers", "Identity", "Migrate"];

    public async Task<JsonElement> RunAsync(string operation, object input, Action<JsonElement>? progress, CancellationToken token)
    {
        if (!Operations.Contains(operation)) throw new StudioException(400, "Unsupported operation.");
        var script = Path.Combine(paths.Scripts, "Invoke-StudioOperation.ps1");
        if (!File.Exists(script)) throw new StudioException(503, "The operation scripts are not installed.");
        var requests = Path.Combine(paths.StateRoot, "requests");
        StudioPaths.ProtectDirectory(requests);
        var requestFile = Path.Combine(requests, $"{Guid.NewGuid():N}.json");
        await File.WriteAllTextAsync(requestFile, JsonSerializer.Serialize(input, StudioPaths.Json), token);
        var info = new ProcessStartInfo("pwsh")
        {
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true,
            WorkingDirectory = paths.Root
        };
        foreach (var argument in new[] { "-NoLogo", "-NoProfile", "-NonInteractive", "-File", script,
            "-Operation", operation, "-InputFile", requestFile })
            info.ArgumentList.Add(argument);
        info.Environment.Remove("SQLCMDPASSWORD");
        info.Environment.Remove("AZURE_CLIENT_SECRET");
        info.Environment.Remove("GITHUB_TOKEN");
        info.Environment.Remove("GH_TOKEN");
        using var process = new Process { StartInfo = info };
        var started = false;
        try
        {
            process.Start();
            started = true;
            using var registration = token.Register(() =>
            {
                try { if (!process.HasExited) process.Kill(entireProcessTree: true); }
                catch (InvalidOperationException) { }
            });
            var errorTask = process.StandardError.ReadToEndAsync(token);
            var output = new StringBuilder();
            while (await process.StandardOutput.ReadLineAsync(token) is { } line)
            {
                if (line.StartsWith("STUDIO_EVENT ", StringComparison.Ordinal))
                {
                    using var document = JsonDocument.Parse(line["STUDIO_EVENT ".Length..]);
                    progress?.Invoke(document.RootElement.Clone());
                }
                else
                {
                    if (output.Length + line.Length > 4_000_000)
                        throw new StudioException(502, "Operation response exceeded the safe size limit.");
                    output.AppendLine(line);
                }
            }
            await process.WaitForExitAsync(token);
            var error = await errorTask;
            if (process.ExitCode != 0)
            {
                logger.LogWarning("Operation {Operation} exited with code {Code}. Diagnostics withheld from model and HTTP response.",
                    operation, process.ExitCode);
                var safeMessage = ExtractSafeFailure(output.ToString());
                throw new StudioException(422, safeMessage ?? $"The {operation} operation failed. Check local prerequisites and the protected operation diagnostics.");
            }
            try
            {
                using var document = JsonDocument.Parse(output.ToString());
                return document.RootElement.Clone();
            }
            catch (JsonException)
            {
                logger.LogWarning("Operation {Operation} returned invalid JSON; stderr present: {HasError}", operation, error.Length > 0);
                throw new StudioException(502, "The operation did not return valid structured results.");
            }
        }
        finally
        {
            if (started && !process.HasExited) process.Kill(entireProcessTree: true);
            File.Delete(requestFile);
        }
    }

    private static string? ExtractSafeFailure(string output)
    {
        try
        {
            using var document = JsonDocument.Parse(output);
            return document.RootElement.TryGetProperty("safeError", out var message)
                ? message.GetString() : null;
        }
        catch (JsonException) { return null; }
    }
}
