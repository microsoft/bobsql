// -----------------------------------------------------------------------------
// The SAME Adventure Works SQL MCP Server — but now an AGENT decides which tool
// to call, exactly like GitHub Copilot does. Built on Microsoft Agent Framework,
// with a Microsoft Foundry model doing the reasoning.
//
// This is the "how does Copilot decide?" loop, handled for you by AIAgent:
//   user prompt + tool catalog  ->  model picks describe_entities
//     ->  model picks read_records(filter: ProductModel eq 'Touring-1000')
//       ->  model composes the answer from the JSON rows.
// We never name a tool in code — the model chooses, by matching the prompt to the
// tool/entity DESCRIPTIONS the server published (the routing layer from Demo 3).
//
// Governance stays in the SERVER: RBAC per entity, the view, parameterized SQL.
// Only the CALLER changes vs. the plain client — a model instead of a fixed call.
//
// DATA BOUNDARY: the SQL query executes LOCALLY under RBAC, but the model runs in
// Foundry (cloud), so the returned rows are sent to the model to phrase the answer
// — the same trust boundary as any Copilot tool call.
// -----------------------------------------------------------------------------

using Azure.AI.Projects;
using Azure.Identity;
using Microsoft.Agents.AI;
using Microsoft.Extensions.AI;
using ModelContextProtocol.Client;

// Microsoft Foundry project endpoint + model deployment that will do the reasoning.
string foundryEndpoint = Environment.GetEnvironmentVariable("AZURE_AI_PROJECT_ENDPOINT")
    ?? throw new InvalidOperationException("Set AZURE_AI_PROJECT_ENDPOINT to your Foundry project endpoint.");
string deployment = Environment.GetEnvironmentVariable("AZURE_AI_MODEL_DEPLOYMENT_NAME") ?? "gpt-4o-mini";

// 1) Connect to the LOCAL SQL MCP Server over Streamable HTTP (same endpoint VS Code uses).
await using McpClient mcp = await McpClient.CreateAsync(new HttpClientTransport(new()
{
    Endpoint = new Uri("http://localhost:5001/mcp"),
    Name = "Adventure Works (SQL MCP)",
}));

// 2) Pull the governed tool catalog. Each McpClientTool implements AITool, so the
//    model sees each tool's name, description, and parameter schema — the routing signal.
IList<McpClientTool> mcpTools = await mcp.ListToolsAsync();

// 3) Build a Foundry-backed agent and hand it those tools. AIAgent runs the
//    decide -> call -> feed-back -> repeat loop for you (what Copilot does internally).
AIAgent agent = new AIProjectClient(new Uri(foundryEndpoint), new DefaultAzureCredential())
    .AsAIAgent(
        model: deployment,
        instructions: "Answer Adventure Works product and sales questions using the SQL MCP tools only.",
        tools: [.. mcpTools.Cast<AITool>()]);

// 4) Ask in plain English. The model picks describe_entities, then read_records,
//    then synthesizes the answer — no tool names hard-coded by us.
Console.WriteLine(await agent.RunAsync("What parts make up the Touring-1000 bike?"));
