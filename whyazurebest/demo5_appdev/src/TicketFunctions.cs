using System.Net;
using System.Text;
using System.Text.Json;
using Azure.Core;
using Azure.Identity;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace TicketStream;

public class TicketFunctions
{
    private const string Hub = "tickets";

    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(30) };

    // Azure.Identity caches the token internally, so this is cheap per call.
    private static readonly DefaultAzureCredential Credential = new();
    private static readonly string[] AgentScope = ["https://ai.azure.com/.default"];

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    /// <summary>
    /// Serverless SignalR clients call this first to get a service URL and a
    /// short-lived access token. The function app's managed identity mints it.
    /// </summary>
    [Function("negotiate")]
    public static HttpResponseData Negotiate(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", "post")] HttpRequestData req,
        [SignalRConnectionInfoInput(HubName = Hub)] string connectionInfo)
    {
        var response = req.CreateResponse(HttpStatusCode.OK);
        response.Headers.Add("Content-Type", "application/json");
        response.WriteString(connectionInfo);
        return response;
    }

    /// <summary>
    /// Fires once per change event that Azure SQL published to Event Hubs.
    /// This function never opens a connection to the database.
    /// </summary>
    [Function("TicketEvent")]
    [SignalROutput(HubName = Hub)]
    public static SignalRMessageAction Run(
        [EventHubTrigger("%EventHubName%", Connection = "EventHubConnection", IsBatched = false)] string cloudEvent,
        FunctionContext context)
    {
        var log = context.GetLogger<TicketFunctions>();
        log.LogInformation("Change event received ({Bytes} bytes)", cloudEvent.Length);

        // The raw CloudEvent goes straight to the browser on purpose: the page
        // renders exactly what the database emitted, with nothing reshaped here.
        return new SignalRMessageAction("ticketChanged")
        {
            Arguments = [cloudEvent]
        };
    }

    /// <summary>
    /// Reads the same stream on its own consumer group, so asking the agent what
    /// to do never delays the ticket card. The two functions race; they do not
    /// queue behind each other.
    /// </summary>
    [Function("TicketTriage")]
    [SignalROutput(HubName = Hub)]
    public static async Task<SignalRMessageAction?> Triage(
        [EventHubTrigger("%EventHubName%", Connection = "EventHubConnection",
            ConsumerGroup = "%TriageConsumerGroup%", IsBatched = false)] string cloudEvent,
        FunctionContext context)
    {
        var log = context.GetLogger<TicketFunctions>();

        if (!TryReadTicket(cloudEvent, out var logicalId, out var ticket))
        {
            return null;
        }

        var started = DateTimeOffset.UtcNow;
        string answer;
        try
        {
            answer = await AskAgentAsync(ticket);
        }
        catch (Exception ex)
        {
            // A failed triage must not take the ticket feed down with it.
            log.LogError(ex, "Triage failed for {LogicalId}", logicalId);
            return null;
        }

        var elapsed = (int)(DateTimeOffset.UtcNow - started).TotalMilliseconds;
        log.LogInformation("Triaged {LogicalId} in {Elapsed} ms", logicalId, elapsed);

        var payload = JsonSerializer.Serialize(new
        {
            logicalId,
            elapsedMs = elapsed,
            agent = Setting("AgentName"),
            verdict = ParseVerdict(answer)
        }, Json);

        return new SignalRMessageAction("ticketAction")
        {
            Arguments = [payload]
        };
    }

    /// <summary>
    /// Pulls the inserted row out of the CloudEvent. CES nests JSON inside JSON
    /// twice: envelope.data is a string, and eventrow.current is a string again.
    /// </summary>
    private static bool TryReadTicket(string cloudEvent, out string logicalId, out string ticket)
    {
        logicalId = string.Empty;
        ticket = string.Empty;

        using var envelope = JsonDocument.Parse(cloudEvent);
        var root = envelope.RootElement;

        if (!root.TryGetProperty("operation", out var op) || op.GetString() != "INS")
        {
            return false;
        }

        logicalId = root.TryGetProperty("logicalid", out var id) ? id.GetString() ?? "" : "";
        if (logicalId.Length == 0) { return false; }

        if (!root.TryGetProperty("data", out var dataText)) { return false; }
        using var data = JsonDocument.Parse(dataText.GetString() ?? "{}");

        if (!data.RootElement.TryGetProperty("eventrow", out var eventRow) ||
            !eventRow.TryGetProperty("current", out var currentText))
        {
            return false;
        }

        using var row = JsonDocument.Parse(currentText.GetString() ?? "{}");
        var fields = row.RootElement;

        string Field(string name) =>
            fields.TryGetProperty(name, out var v) ? v.GetString() ?? "" : "";

        ticket = $"""
            Customer: {Field("CustomerName")}
            Reported severity: {Field("Severity")}
            Subject: {Field("Subject")}
            Body: {Field("Body")}
            """;

        return true;
    }

    private static async Task<string> AskAgentAsync(string ticket)
    {
        var token = await Credential.GetTokenAsync(new TokenRequestContext(AgentScope), default);

        var url = $"{Setting("AgentEndpoint")}/agents/{Setting("AgentName")}" +
                  $"/endpoint/protocols/openai/responses?api-version={Setting("AgentApiVersion")}";

        var body = JsonSerializer.Serialize(new { input = ticket }, Json);

        using var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(body, Encoding.UTF8, "application/json")
        };
        request.Headers.Authorization = new("Bearer", token.Token);

        using var response = await Http.SendAsync(request);
        var text = await response.Content.ReadAsStringAsync();
        response.EnsureSuccessStatusCode();

        return ExtractText(text);
    }

    /// <summary>Walks the Responses payload down to the assistant's text.</summary>
    private static string ExtractText(string responseJson)
    {
        using var doc = JsonDocument.Parse(responseJson);
        if (!doc.RootElement.TryGetProperty("output", out var output)) { return ""; }

        foreach (var item in output.EnumerateArray())
        {
            if (!item.TryGetProperty("content", out var content)) { continue; }
            foreach (var part in content.EnumerateArray())
            {
                if (part.TryGetProperty("text", out var t)) { return t.GetString() ?? ""; }
            }
        }
        return "";
    }

    /// <summary>
    /// The agent is told to return JSON, but models sometimes wrap it in a code
    /// fence. Take the outermost braces rather than failing the whole beat.
    /// </summary>
    private static object ParseVerdict(string text)
    {
        var start = text.IndexOf('{');
        var end = text.LastIndexOf('}');
        if (start >= 0 && end > start)
        {
            try
            {
                return JsonSerializer.Deserialize<JsonElement>(text[start..(end + 1)]);
            }
            catch (JsonException)
            {
                // fall through to the raw text
            }
        }
        return new { action = "info", taken = text };
    }

    private static string Setting(string name) =>
        Environment.GetEnvironmentVariable(name) ?? "";
}
