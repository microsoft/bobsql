using System.Text.Json;
using System.Text.Json.Serialization;

namespace WardGeneral.Data.Models;

/// <summary>
/// Summary row returned by <c>clinical.SearchEncounters</c>.
/// </summary>
public sealed record EncounterSummary(
    int EncounterId,
    int PatientId,
    int DepartmentId,
    int AttendingProviderId,
    int? BedId,
    string EncounterType,
    DateTime AdmitTime,
    DateTime? DischargeTime,
    string Status);

/// <summary>
/// The digital patient chart returned by <c>clinical.GetPatientChart</c> /
/// <c>clinical.GetPatientChartByBed</c> (projection of <c>clinical.vPatientChart</c>).
///
/// Talk verb: <b>Modernize it — JSON</b>. Five sections come back as the native <c>json</c>
/// type and are parsed here into strongly-typed collections: <see cref="Diagnoses"/>,
/// <see cref="Medications"/>, <see cref="Allergies"/>, <see cref="LatestVitals"/>,
/// <see cref="RecentLabs"/>.
/// </summary>
public sealed record PatientChart(
    int EncounterId,
    string EncounterStatus,
    string EncounterType,
    DateTime AdmitTime,
    DateTime? DischargeTime,
    string? IntakeJson,
    int PatientId,
    string Mrn,
    string PatientName,
    DateTime? DateOfBirth,
    string? Sex,
    int? AgeYears,
    int DepartmentId,
    string DepartmentName,
    int? UnitId,
    string? UnitName,
    int? BedId,
    string? BedNumber,
    int AttendingProviderId,
    string AttendingProviderName,
    string AttendingProviderRole,
    IReadOnlyList<Diagnosis> Diagnoses,
    IReadOnlyList<Medication> Medications,
    IReadOnlyList<Allergy> Allergies,
    IReadOnlyDictionary<string, VitalReading> LatestVitals,
    IReadOnlyList<LabResult> RecentLabs,
    IReadOnlyList<Symptom> Symptoms,
    IReadOnlyList<CareTeamMember> CareTeam,
    IReadOnlyList<ImagingStudy> Imaging,
    IReadOnlyList<NoteEntry> RecentNotes,
    NoteSignals? NoteSignals);

public sealed record Diagnosis(
    [property: JsonPropertyName("code")] string? Code,
    [property: JsonPropertyName("description")] string? Description,
    [property: JsonPropertyName("byProviderId")] int? ByProviderId);

public sealed record Medication(
    [property: JsonPropertyName("medication")] string? Name,
    [property: JsonPropertyName("dose")] string? Dose,
    [property: JsonPropertyName("route")] string? Route,
    [property: JsonPropertyName("orderedById")] int? OrderedById,
    [property: JsonPropertyName("orderedAt")] DateTime? OrderedAt);

public sealed record Allergy(
    [property: JsonPropertyName("substance")] string? Substance,
    [property: JsonPropertyName("reaction")] string? Reaction,
    [property: JsonPropertyName("severity")] string? Severity,
    [property: JsonPropertyName("recordedAt")] DateTime? RecordedAt);

public sealed record VitalReading(
    [property: JsonPropertyName("value")] decimal? Value,
    [property: JsonPropertyName("unit")] string? Unit,
    [property: JsonPropertyName("at")] DateTime? At);

public sealed record LabResult(
    [property: JsonPropertyName("test")] string? Test,
    [property: JsonPropertyName("collectedAt")] DateTime? CollectedAt,
    [property: JsonPropertyName("resultedAt")] DateTime? ResultedAt,
    // The lab payload itself is nested JSON — keep it raw for display / further parsing.
    [property: JsonPropertyName("result")] JsonElement Result);

public sealed record Symptom(
    [property: JsonPropertyName("description")] string? Description,
    [property: JsonPropertyName("severity")] string? Severity,
    [property: JsonPropertyName("notedAt")] DateTime? NotedAt);

public sealed record CareTeamMember(
    [property: JsonPropertyName("providerId")] int? ProviderId,
    [property: JsonPropertyName("name")] string? Name,
    [property: JsonPropertyName("role")] string? Role,
    [property: JsonPropertyName("isPrimary")] bool IsPrimary);

public sealed record ImagingStudy(
    [property: JsonPropertyName("modality")] string? Modality,
    [property: JsonPropertyName("bodySite")] string? BodySite,
    [property: JsonPropertyName("status")] string? Status,
    [property: JsonPropertyName("orderedAt")] DateTime? OrderedAt,
    [property: JsonPropertyName("resultedAt")] DateTime? ResultedAt);

public sealed record NoteEntry(
    [property: JsonPropertyName("type")] string? Type,
    [property: JsonPropertyName("text")] string? Text,
    [property: JsonPropertyName("byProviderId")] int? ByProviderId,
    [property: JsonPropertyName("at")] DateTime? At);

/// <summary>
/// Structured facts mined from the latest clinical note's free text with SQL Server 2025
/// REGEXP_* (see <c>clinical.vChartNoteSignals</c>). Talk verb: <b>Modernize it — Regex</b>.
/// Deterministic extraction over the SAME <c>NoteText</c> column the AI layer embeds for
/// semantic search. Pain score and follow-up exist only in the prose — no structured column.
/// </summary>
public sealed record NoteSignals(
    [property: JsonPropertyName("source")] string? Source,
    [property: JsonPropertyName("noteAt")] DateTime? NoteAt,
    [property: JsonPropertyName("bloodPressure")] string? BloodPressure,
    [property: JsonPropertyName("heartRate")] string? HeartRate,
    [property: JsonPropertyName("temperature")] string? Temperature,
    [property: JsonPropertyName("respRate")] string? RespRate,
    [property: JsonPropertyName("spo2")] string? Spo2,
    [property: JsonPropertyName("painScore")] string? PainScore,
    [property: JsonPropertyName("followUp")] string? FollowUp);

/// <summary>One bed from <c>ops.vBedCensus</c> — occupied rows carry patient info,
/// empty beds have nulls. Powers the room-centric Unit board.</summary>
public sealed record BedCensusRow(
    string UnitName,
    string BedNumber,
    string BedStatus,
    int? EncounterId,
    int? PatientId,
    string? Mrn,
    string? PatientName,
    string? AttendingProvider,
    DateTime? AdmitTime);

/// <summary>
/// Advisory AI result from <c>clinical.GenerateClinicalAssistance</c> — a <b>suggested</b>
/// triage flag for the attending to confirm/override, a grounded summary of considerations,
/// and the ids of the historical notes it was grounded on (so the clinician can check its
/// work). The engine assists; it does not decide. Every call is audited server-side
/// (<c>clinical.AIAssistanceLog</c>).
/// </summary>
public sealed record AssistanceResult(
    int EncounterId,
    string? PatientName,
    string? SuggestedTriageFlag,
    string? Summary,
    string? GroundedOnNoteIds,
    string? Path,
    int ProcessingTimeMs);

/// <summary>
/// An attending option for the "Viewing as" selector. Selecting one stamps its
/// <see cref="ProviderId"/> into <c>SESSION_CONTEXT</c> so Row-Level Security scopes
/// the board and charts to that clinician.
/// </summary>
public sealed record ProviderOption(int ProviderId, string FullName, string Role);

/// <summary>
/// One hit from the research vector search (<c>clinical.SearchSimilarNotes</c> on the
/// named replica): a clinical note ranked by semantic similarity to the query.
/// </summary>
public sealed record NoteSearchResult(
    int NoteId,
    int EncounterId,
    string NoteType,
    DateTime CreatedAt,
    decimal Similarity,
    string NoteText);


/// <summary>Shared JSON options for the chart's <c>json</c> sections.</summary>
public static class ChartJson
{
    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNameCaseInsensitive = true
    };
}
