using System.ComponentModel.DataAnnotations;
using System.Text.Json;

namespace CustomerServiceDesk.Data;

public sealed record CaseRow(int CaseId, string Title, string Topic, string Status,
    string Priority, string DisplayName, string Channel, DateTime UpdatedAt);

public sealed record CustomerOption(int CustomerId, string DisplayName);
public sealed record PreparedSearch(int PreparedSearchId, string SearchText);
public sealed record SearchProfile(int ProfileId, string Provider, string ModelName,
    string ModelVersion, int Dimensions, string QueryPrefix);
public sealed record SearchHit(int CaseId, string Title, string Resolution, string Topic, double CosineDistance);

public sealed record CaseDetail(int CaseId, int CustomerId, string Title, string Description,
    string? Resolution, string Topic, string Status, string Priority, string Details,
    DateTime CreatedAt, DateTime UpdatedAt, byte[] Version, string DisplayName, string Email, string Phone);

public sealed record DeskEnvironment(string DatabaseName, string DatabaseUser, string Edition,
    int EngineEdition, string EngineVersion, int TotalCases, int OpenCases, int InProgressCases,
    int ResolvedCases, int PendingEmbeddings, string? ProfileName, string? ModelName,
    string? ModelVersion, int? Dimensions, int ReadyQueries, int TotalQueries,
    bool JsonIndexPresent, string? VectorIndexVersion, int PreviewFeatures, int CanUnmask,
    int CanReadCustomers)
{
    public bool SearchReady => ProfileName is not null && PendingEmbeddings == 0
        && TotalQueries > 0 && ReadyQueries == TotalQueries && VectorIndexVersion is not null;
}

public sealed class CaseInput : IValidatableObject
{
    [Required, StringLength(200)]
    public string Title { get; set; } = "";

    [Required, StringLength(2000)]
    public string Description { get; set; } = "";

    [StringLength(2000)]
    public string? Resolution { get; set; }

    [Required, RegularExpression("^[a-z0-9][a-z0-9-]{0,39}$",
        ErrorMessage = "Use a topic of up to 40 lowercase letters, digits, or hyphens.")]
    public string Topic { get; set; } = "general";

    [Required, AllowedValues("Open", "InProgress", "Resolved")]
    public string Status { get; set; } = "Open";

    [Required, AllowedValues("Low", "Normal", "High")]
    public string Priority { get; set; } = "Normal";

    [Required, StringLength(8000)]
    public string Details { get; set; } = """
        {
          "product": "Service Desk",
          "channel": "web",
          "device": "Windows 11",
          "region": "West"
        }
        """;

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (Status == "Resolved" && string.IsNullOrWhiteSpace(Resolution))
            yield return new ValidationResult("A resolved case requires a resolution.", [nameof(Resolution)]);

        string? error = null;
        try
        {
            using var json = JsonDocument.Parse(Details ?? "");
            if (json.RootElement.ValueKind != JsonValueKind.Object)
                error = "Details must be a JSON object.";
            else if (!json.RootElement.TryGetProperty("channel", out var channel)
                || channel.ValueKind != JsonValueKind.String
                || channel.GetString() is not ("web" or "phone" or "chat"))
                error = "Include a channel of web, phone, or chat in JSON details.";
        }
        catch (JsonException)
        {
            error = "Details must contain valid JSON.";
        }
        if (error is not null)
            yield return new ValidationResult(error, [nameof(Details)]);
    }
}
