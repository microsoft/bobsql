namespace WardGeneral.Web.Options;

/// <summary>
/// Toggles for progressively-revealed chart features, bound from the "Features"
/// section of configuration.
///
/// Every flag defaults <b>OFF</b>. The reader turns each one on in the area that
/// teaches it — <b>without editing source</b>: deploy that area's <c>.sql</c>,
/// flip the flag, and the panel lights up. This is why the app never needs
/// per-area code deltas: the <i>database</i> evolves (CREATE OR ALTER), the app
/// stays put.
///
/// Ward General App features are <b>not</b> flags. The base chart — including the in-engine
/// <c>REGEXP_*</c> note-signal card — is simply part of the app.
///
/// A flagged surface is <b>greyed out, not hidden</b>. The reader can see that the app
/// has more in it and which area unlocks each piece; the area that teaches it
/// lights it up. Hiding would make the progressive reveal invisible.
///
/// The panels also self-hide when their backing SQL isn't deployed — the chart DAL
/// reads the backing columns column-tolerantly (see <c>GetOptionalJson</c>), so a
/// <c>false</c> flag and a not-yet-created view both degrade gracefully.
/// </summary>
public sealed class FeatureFlags
{
    /// <summary>
    /// AI assistance card <i>and</i> the Research page (AI-Ready SQL). Backing:
    /// <c>clinical.GenerateClinicalAssistance</c> and <c>clinical.SearchSimilarNotes</c>.
    /// One flag for both because both ship in the same area and the same deploy set.
    /// The <c>wardgeneral-research</c> named replica the Research page reads already
    /// exists — it is provisioned in Architecture — so the proc is the only missing piece.
    /// </summary>
    public bool AiAssistance { get; set; }

    /// <summary>In-app clinical assistant dock — the chat icon (Agentic AI — Microsoft Agent Framework + DAB SQL MCP). Requires DAB running + an Azure OpenAI endpoint.</summary>
    public bool AiAgent { get; set; }
}
