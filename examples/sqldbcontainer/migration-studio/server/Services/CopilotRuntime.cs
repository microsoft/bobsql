using GitHub.Copilot;
using GitHub.Copilot.Rpc;

namespace MigrationStudio.Services;

#pragma warning disable GHCP001
public static class CopilotRuntime
{
    public static CopilotClientOptions ClientOptions(string workspace)
    {
        var environment = new Dictionary<string, string>();
        foreach (var name in new[] { "PATH", "SystemRoot", "WINDIR", "USERPROFILE", "APPDATA",
            "LOCALAPPDATA", "TEMP", "TMP", "HOME", "ProgramFiles", "ProgramFiles(x86)", "COMSPEC" })
            if (Environment.GetEnvironmentVariable(name) is { } value) environment[name] = value;
        environment["COPILOT_TELEMETRY_DISABLED"] = "true";
        var connection = RuntimeConnection.ForStdio();
        connection.Environment = environment;
        return new CopilotClientOptions
        {
            // Empty mode forces COPILOT_DISABLE_KEYTAR=1. This local, single-user host
            // needs the Windows secure store; session capabilities are closed below.
            Mode = CopilotClientMode.CopilotCli,
            Connection = connection,
            UseLoggedInUser = true,
            BaseDirectory = workspace,
            WorkingDirectory = workspace,
            BuiltinPluginDirectories = [],
            Telemetry = new TelemetryConfig { ExporterType = "none", CaptureContent = false }
        };
    }

    public static SessionConfig RestrictedSession(string workspace, IList<string> allowedTools) => new()
    {
        ConfigDirectory = workspace,
        WorkingDirectory = workspace,
        AvailableTools = allowedTools,
        IncludedBuiltInAgents = [],
        IncludedBuiltinSkills = [],
        EnableConfigDiscovery = false,
        EnableSessionStore = false,
        EnableSkills = false,
        EnableFileHooks = false,
        EnableOnDemandInstructionDiscovery = false,
        EnableHostGitOperations = false,
        EnableExperimentalMode = false,
        EnableSessionTelemetry = false,
        SkipCustomInstructions = true,
        SkipEmbeddingRetrieval = true,
        EmbeddingCacheStorage = EmbeddingCacheStorageMode.InMemory,
        McpOAuthTokenStorage = McpOAuthTokenStorageMode.InMemory,
        Memory = new GitHub.Copilot.MemoryConfiguration { Enabled = false },
        CustomAgentsLocalOnly = true,
        CoauthorEnabled = false,
        ManageScheduleEnabled = false,
        PluginDirectories = [],
        InstructionDirectories = [],
        AgentDirectories = [],
        HookDirectories = [],
        SkillDirectories = [],
        McpServers = new Dictionary<string, McpServerConfig>(),
        SystemMessage = new SystemMessageConfig
        {
            Mode = SystemMessageMode.Replace,
            Content = "This is a restricted local SQL Migration Studio session. No inference is authorized by sign-in."
        },
        OnPermissionRequest = (_, _) => Task.FromResult(PermissionDecision.Reject(
            "Only explicitly allowlisted, read-only host tools are permitted."))
    };
}
#pragma warning restore GHCP001
