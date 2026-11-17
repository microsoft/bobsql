using System.Diagnostics;
using System.Text.RegularExpressions;

namespace CaldovaNetworkScheduling.Services;

public interface IAzureCliRunner
{
    Task<string> RunAsync(IReadOnlyList<string> arguments, CancellationToken token);
}

public sealed class AzureCliRunner : IAzureCliRunner
{
    public async Task<string> RunAsync(IReadOnlyList<string> arguments, CancellationToken token)
    {
        var info = new ProcessStartInfo
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        if (OperatingSystem.IsWindows())
        {
            var launcher = (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator)
                .Select(directory => Path.Combine(directory.Trim('"'), "az.cmd")).FirstOrDefault(File.Exists)
                ?? throw new InvalidOperationException("Azure CLI is not installed on the app host.");
            var python = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(launcher)!, "..", "python.exe"));
            if (!File.Exists(python))
                throw new InvalidOperationException("The Azure CLI Python executable could not be found.");
            info.FileName = python;
            info.Environment["AZ_INSTALLER"] = "MSI";
            info.ArgumentList.Add("-IBm");
            info.ArgumentList.Add("azure.cli");
        }
        else
        {
            info.FileName = "az";
        }
        foreach (var argument in arguments) info.ArgumentList.Add(argument);
        using var process = new Process { StartInfo = info };
        if (!process.Start()) throw new InvalidOperationException("Azure CLI could not be started.");
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        try { await process.WaitForExitAsync(token); }
        catch (OperationCanceledException)
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            await process.WaitForExitAsync(CancellationToken.None);
            await Task.WhenAll(stdout, stderr);
            throw;
        }
        var output = await stdout;
        var errors = await stderr;
        if (process.ExitCode != 0)
            throw new InvalidOperationException($"Azure CLI failed (exit {process.ExitCode}): {Redact(errors.Length > 0 ? errors : output)}");
        return output.Trim();
    }

    internal static string Redact(string message) => Regex.Replace(message,
        @"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b", "[redacted]");
}
