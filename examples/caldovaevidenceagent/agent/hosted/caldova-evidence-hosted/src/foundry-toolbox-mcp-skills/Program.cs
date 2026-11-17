// Copyright (c) Microsoft. All rights reserved.

/*
 * Caldova Evidence Agent - Agent Framework Responses agent for C#
 *
 * Hosted agent that downloads formal skills from the Foundry Skills API and exposes
 * governed DAB SQL MCP tools directly to the model.
 *
 * The AgentSkillsProvider implements the progressive-disclosure pattern from the
 * Agent Skills specification (https://agentskills.io/):
 *   1. Advertise - skill names and descriptions are injected into the system prompt.
 *   2. Load      - the model retrieves the full skill body on demand.
 *   3. Read      - supplementary skill resources (reference documents, assets) are
 *                  fetched on demand.
 *
 * Skill packages are downloaded at startup, then loaded into context only when the
 * model needs them. SQL tools are discovered from the MCP server at startup.
 *
 * Required environment variables (set by the deployment script):
 *   FOUNDRY_PROJECT_ENDPOINT       - Foundry project endpoint.
 *   AZURE_AI_MODEL_DEPLOYMENT_NAME - Model deployment name.
 *   SKILL_NAMES                    - Comma-separated Foundry skill names.
 *   SQL_MCP_ENDPOINT               - Streamable HTTP endpoint for DAB SQL MCP.
 */

using System.ClientModel.Primitives;
using Azure.AI.Projects;
using Azure.AI.Projects.Agents;
using Azure.Core;
using Azure.Identity;
using DotNetEnv;
using Microsoft.Agents.AI;
using Microsoft.Agents.AI.Foundry.Hosting;
using Microsoft.Extensions.AI;
using ModelContextProtocol.Client;

// Load .env file if present (for local development).
Env.NoClobber().TraversePath().Load();

string projectEndpoint = Environment.GetEnvironmentVariable("FOUNDRY_PROJECT_ENDPOINT")
    ?? throw new InvalidOperationException("FOUNDRY_PROJECT_ENDPOINT environment variable is not set.");

string deployment = Environment.GetEnvironmentVariable("AZURE_AI_MODEL_DEPLOYMENT_NAME")
    ?? throw new InvalidOperationException("AZURE_AI_MODEL_DEPLOYMENT_NAME environment variable is not set.");

string[] skillNames = (Environment.GetEnvironmentVariable("SKILL_NAMES") ?? string.Empty)
    .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
if (skillNames.Length == 0)
{
    throw new InvalidOperationException("SKILL_NAMES environment variable is not set.");
}

string sqlMcpEndpoint = Environment.GetEnvironmentVariable("SQL_MCP_ENDPOINT")
    ?? throw new InvalidOperationException("SQL_MCP_ENDPOINT environment variable is not set.");

bool useLocalAzureCliCredential = string.Equals(
    Environment.GetEnvironmentVariable("CALDOVA_USE_LOCAL_AZURE_CLI_CREDENTIAL"),
    "true",
    StringComparison.OrdinalIgnoreCase);
TokenCredential credential = useLocalAzureCliCredential
    ? new AzureCliCredential()
    : new DefaultAzureCredential(new DefaultAzureCredentialOptions
    {
        ManagedIdentityClientId = Environment.GetEnvironmentVariable("AZURE_CLIENT_ID"),
    });

var adminOptions = new AgentAdministrationClientOptions();
adminOptions.AddPolicy(new FoundryFeaturesPolicy("Skills=V1Preview"), PipelinePosition.PerCall);
var adminClient = new AgentAdministrationClient(new Uri(projectEndpoint), credential, adminOptions);
ProjectAgentSkills skillsClient = adminClient.GetAgentSkills();

string downloadedSkillsDir = Path.Combine(Path.GetTempPath(), "caldova-evidence-skills");
if (Directory.Exists(downloadedSkillsDir))
{
    Directory.Delete(downloadedSkillsDir, recursive: true);
}
Directory.CreateDirectory(downloadedSkillsDir);

using var bootstrapCts = new CancellationTokenSource(TimeSpan.FromSeconds(60));
foreach (string skillName in skillNames)
{
    if (skillName.Contains('.') || skillName.Contains('/') || skillName.Contains('\\'))
    {
        throw new InvalidOperationException($"Invalid skill name '{skillName}'.");
    }

    Console.WriteLine($"Downloading skill '{skillName}' from Foundry...");
    string skillDir = Path.Combine(downloadedSkillsDir, skillName);
    Directory.CreateDirectory(skillDir);
    await skillsClient.GetSkillContentAsync(skillName, skillDir, bootstrapCts.Token);
    if (!File.Exists(Path.Combine(skillDir, "SKILL.md")))
    {
        throw new InvalidOperationException($"Downloaded skill '{skillName}' did not contain SKILL.md.");
    }
}

Console.WriteLine("Connecting to Caldova SQL MCP server...");
await using var sqlMcpClient = await McpClient.CreateAsync(
    new HttpClientTransport(
        new HttpClientTransportOptions
        {
            Endpoint = new Uri(sqlMcpEndpoint),
            Name = "caldova-evidence-sql",
            TransportMode = HttpTransportMode.StreamableHttp,
        }));

var sqlTools = await sqlMcpClient.ListToolsAsync();
string[] expectedSqlTools = ["get_article_context", "get_corpus_status", "search_evidence"];
string[] actualSqlTools = [.. sqlTools.Select(tool => tool.Name).OrderBy(name => name)];
if (!actualSqlTools.SequenceEqual(expectedSqlTools))
{
    throw new InvalidOperationException(
        $"Expected SQL MCP tools {string.Join(", ", expectedSqlTools)}; received {string.Join(", ", actualSqlTools)}.");
}
Console.WriteLine($"SQL MCP tools: {string.Join(", ", actualSqlTools)}");

// AgentSkillsProvider implements progressive disclosure over the MCP-discovered skills:
// names and descriptions are advertised in the system prompt, and the full skill body
// (and any supplementary resources) is loaded on demand when the model decides it is
// relevant.
var skillsProvider = new AgentSkillsProvider(
    downloadedSkillsDir,
    options: new AgentSkillsProviderOptions
    {
        DisableLoadSkillApproval = true,
        DisableReadSkillResourceApproval = true,
    });

AIAgent agent = new AIProjectClient(new Uri(projectEndpoint), credential)
    .AsAIAgent(new ChatClientAgentOptions
    {
        Name = "caldova-evidence-hosted",
        Description = "Hosted biomedical evidence agent with a formal Foundry Agent Skill and governed SQL MCP tools.",
        ChatOptions = new ChatOptions
        {
            ModelId = deployment,
            Instructions = """
                You are the Caldova Evidence Agent, a conversational biomedical research assistant.
                For biomedical evidence requests, load the available biomedical evidence review skill before investigating.
                Use the governed SQL MCP tools directly. For an initial investigation, call search_evidence exactly three
                times with distinct focused questions and top_k 3. Synthesize rather than enumerate: compare evidence, identify
                disagreement, assess limitations and confidence, and keep the initial answer between 110 and 150 words.
                Use the skill's exact visual heading structure, exactly three compact evidence bullets, and exactly three
                source PMCIDs. Calibrate confidence to the claim: when sources converge on mechanistic plausibility, lead with
                "High for mechanistic plausibility" and separately qualify human clinical causality. Every response, including
                follow-ups, must use the skill's visual heading structure; never return a prose-only answer. Keep follow-ups
                concise and no longer than the initial briefing.
                Cite plain PMCIDs only; do not emit Markdown citation links or raw source URLs. Never expose SQL, vectors,
                credentials, hidden reasoning, or internal tool parameters. Do not diagnose individuals or provide
                personalized treatment.
                """,
            Tools = [.. sqlTools],
        },
        AIContextProviders = [skillsProvider],
    });

var builder = AgentHost.CreateBuilder(args);
builder.Services.AddFoundryResponses(agent);
builder.RegisterProtocol("responses", endpoints => endpoints.MapFoundryResponses());

var app = builder.Build();
app.Run();

internal sealed class FoundryFeaturesPolicy(string feature) : PipelinePolicy
{
    public override void Process(PipelineMessage message, IReadOnlyList<PipelinePolicy> pipeline, int currentIndex)
    {
        message.Request.Headers.Add("Foundry-Features", feature);
        ProcessNext(message, pipeline, currentIndex);
    }

    public override ValueTask ProcessAsync(PipelineMessage message, IReadOnlyList<PipelinePolicy> pipeline, int currentIndex)
    {
        message.Request.Headers.Add("Foundry-Features", feature);
        return ProcessNextAsync(message, pipeline, currentIndex);
    }
}
