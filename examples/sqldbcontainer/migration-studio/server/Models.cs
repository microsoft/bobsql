using System.ComponentModel.DataAnnotations;
using System.Text.Json;

namespace MigrationStudio;

/// <summary>Source and Azure destination explicitly selected by the operator.</summary>
public sealed record MigrationConfiguration
{
    [Required, RegularExpression(@"^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$")]
    public required string ContainerName { get; init; }
    [Required, StringLength(128, MinimumLength = 1)]
    public required string SourceDatabase { get; init; }
    [Required, RegularExpression(@"^[0-9a-fA-F-]{36}$")]
    public required string TenantId { get; init; }
    [Required, RegularExpression(@"^[0-9a-fA-F-]{36}$")]
    public required string SubscriptionId { get; init; }
    [Required, RegularExpression(@"^[a-z0-9]{2,40}$")]
    public required string Region { get; init; }
    [Required, RegularExpression(@"^[a-zA-Z0-9_().-]{1,90}$")]
    public required string ResourceGroup { get; init; }
    public bool CreateResourceGroup { get; init; }
    [Required, RegularExpression(@"^[a-z][a-z0-9-]{1,61}[a-z0-9]$")]
    public required string ServerName { get; init; }
    public bool CreateServer { get; init; }
    [Required, StringLength(128, MinimumLength = 1)]
    public required string TargetDatabase { get; init; }
    [Required, RegularExpression("^Entra$")]
    public required string Authentication { get; init; }
}

/// <summary>Selected local source for privileged metadata discovery.</summary>
public sealed record DiscoverDatabasesRequest(
    [property: Required, RegularExpression(@"^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$")] string ContainerName);

/// <summary>One-time approval of this exact reviewed configuration and offline window.</summary>
public sealed record StartMigrationRequest(
    [property: Required] string Confirmation, bool WritersStopped);

/// <summary>A bounded operator message sent to Copilot; credentials and data are prohibited.</summary>
public sealed record CopilotMessageRequest(
    [property: Required, StringLength(2000, MinimumLength = 1)] string Text, string? Model);

/// <summary>One measured workflow stage, never a simulated percentage.</summary>
public sealed record MigrationStep(string Id, string Title, string State, string Message);

/// <summary>Immutable configuration proposed for approval.</summary>
public sealed record MigrationPlan(
    string Id, string Fingerprint, MigrationConfiguration Configuration,
    string[] Summary, string State, DateTimeOffset CreatedAt, MigrationStep[] Steps);

/// <summary>Durable execution snapshot for reconnecting clients.</summary>
public sealed record MigrationRun(
    string Id, string State, MigrationStep[] Steps, DateTimeOffset UpdatedAt,
    JsonElement? Validation = null, string? Error = null);

/// <summary>A sanitized operation event in the migration activity stream.</summary>
public sealed record StudioEvent(
    long Id, DateTimeOffset Time, string Stage, string State, string Message, string? RunId = null, string? Subject = null);

/// <summary>Readiness of one independently checked dependency.</summary>
public sealed record Capability(string Name, string State, string Detail);

/// <summary>Attribution for the exact adapted instructions available to the agent.</summary>
public sealed record SkillInfo(string Name, string Title, string SourceUrl, string Revision, string Adaptation);

/// <summary>A model actually reported by the authenticated Copilot runtime.</summary>
public sealed record CopilotModel(string Id, string Name);

/// <summary>SDK authentication status; this does not assert inference was tested.</summary>
public sealed record CopilotStatus(bool Authenticated, string Status, CopilotModel[] Models);

/// <summary>Device authorization UI state; no access token or SDK flow identifier is exposed.</summary>
public sealed record CopilotSignInState(
    string? Id, string State, string Message, string? UserCode = null,
    string? VerificationUri = null, DateTimeOffset? ExpiresAt = null);

/// <summary>Application and dependency readiness, separate from a migration result.</summary>
public sealed record StudioStatus(string ServiceDeskUrl, Capability[] Capabilities, SkillInfo[] Skills, CopilotStatus Copilot);

public sealed class StudioException(int statusCode, string safeMessage) : Exception(safeMessage)
{
    public int StatusCode { get; } = statusCode;
}
