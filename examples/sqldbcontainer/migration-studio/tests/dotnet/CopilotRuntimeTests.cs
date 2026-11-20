using GitHub.Copilot;
using Microsoft.Extensions.AI;
using MigrationStudio;
using MigrationStudio.Services;
using Xunit;

namespace MigrationStudioTests;

#pragma warning disable GHCP001
public sealed class CopilotRuntimeTests
{
    [Fact]
    public async Task SecureStoreRuntimeKeepsNativeSessionsClosedWithoutInference()
    {
        var workspace = Path.Combine(Path.GetTempPath(), "migration-studio-runtime-" + Guid.NewGuid().ToString("N"));
        StudioPaths.ProtectDirectory(workspace);
        try
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(60));
            var options = CopilotRuntime.ClientOptions(workspace);
            Assert.NotEqual(CopilotClientMode.Empty, options.Mode);
            await using var client = new CopilotClient(options);
            await client.StartAsync(timeout.Token);
            await using var login = await client.CreateSessionAsync(
                CopilotRuntime.RestrictedSession(workspace, []), timeout.Token);
            await login.Rpc.Tools.InitializeAndValidateAsync(timeout.Token);
            var loginTools = (await login.Rpc.Tools.GetCurrentMetadataAsync(timeout.Token)).Tools;
            Assert.NotNull(loginTools);
            Assert.Empty(loginTools);

            var config = CopilotRuntime.RestrictedSession(workspace, ["inspect_readiness"]);
            config.Tools =
            [
                CopilotTool.DefineTool(() => new { ready = false },
                    factoryOptions: new AIFunctionFactoryOptions { Name = "inspect_readiness" })
            ];
            await using var guide = await client.CreateSessionAsync(config, timeout.Token);
            await guide.Rpc.Tools.InitializeAndValidateAsync(timeout.Token);
            var tools = (await guide.Rpc.Tools.GetCurrentMetadataAsync(timeout.Token)).Tools;
            Assert.NotNull(tools);
            Assert.Equal("inspect_readiness", Assert.Single(tools).Name);
        }
        finally { Directory.Delete(workspace, recursive: true); }
    }
}
#pragma warning restore GHCP001
