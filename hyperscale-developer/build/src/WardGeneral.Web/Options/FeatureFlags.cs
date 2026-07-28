namespace WardGeneral.Web.Options;

/// <summary>
/// Toggles for progressively-revealed chart features, bound from the "Features"
/// section of configuration.
///
/// All default <b>ON</b> so the talk shows the finished app. The <i>book</i> flips
/// them per chapter — base app in Ch 4, the REGEXP_* panel in Ch 5, AI assistance
/// alongside — <b>without editing source</b>: deploy the chapter's <c>.sql</c>, flip
/// the flag, and the panel lights up. This is why the app never needs per-chapter
/// code deltas: the <i>database</i> evolves (CREATE OR ALTER), the app stays put.
///
/// The panels also self-hide when their backing SQL isn't deployed — the chart DAL
/// reads the backing columns column-tolerantly (see <c>GetOptionalJson</c>), so a
/// <c>false</c> flag and a not-yet-created view both degrade gracefully.
/// </summary>
public sealed class FeatureFlags
{
    /// <summary>REGEXP_* note-signal extraction card (Ch 5). Backing: <c>clinical.vChartNoteSignals</c>.</summary>
    public bool NoteSignals { get; set; } = true;

    /// <summary>AI assistance card — vector search + gpt-5 (Ch 5 / AI). Backing: <c>clinical.GenerateClinicalAssistance</c>.</summary>
    public bool AiAssistance { get; set; } = true;

    /// <summary>In-app clinical assistant dock (Microsoft Agent Framework + DAB SQL MCP). Requires DAB running + an Azure OpenAI endpoint.</summary>
    public bool Assistant { get; set; } = true;
}
