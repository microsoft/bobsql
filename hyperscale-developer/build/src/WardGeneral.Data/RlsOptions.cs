namespace WardGeneral.Data;

/// <summary>
/// Row-Level Security master switch, bound from the <c>RowLevelSecurity</c> config
/// section. Talk verb: <b>Secure it</b>.
///
/// The app connects as a single managed identity (trusted subsystem). When
/// <see cref="Enabled"/> is true, the data-access layer stamps the acting clinician
/// (from <see cref="AccessContext"/>, driven by the "Viewing as" selector) into
/// <c>SESSION_CONTEXT</c> on each pooled connection; the RLS predicate on
/// <c>clinical.Encounter</c> reads it and filters rows in the engine.
///
/// Default identity is Admin (all patients); selecting a provider narrows the board
/// to that provider with no restart. The database policy is fail-open when no
/// context is set, so a disabled app, diagnostics, and background jobs see all rows.
/// </summary>
public sealed class RlsOptions
{
    /// <summary>Stamp SESSION_CONTEXT on each connection (opt in to RLS filtering).</summary>
    public bool Enabled { get; set; }
}
