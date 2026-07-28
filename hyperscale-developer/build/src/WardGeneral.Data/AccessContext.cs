namespace WardGeneral.Data;

/// <summary>
/// The acting clinician for the current Blazor circuit (per-user, scoped). The
/// "Viewing as" selector on the unit board writes here; the data-access layer
/// reads it and stamps <c>SESSION_CONTEXT</c> on every connection open, so
/// Row-Level Security filters the board and charts to this identity.
///
/// Default = <b>Admin</b> with no provider — the "see everything" starting point.
/// Selecting a provider sets <see cref="ProviderId"/> and flips <see cref="Role"/>
/// to <c>Attending</c>. Because the data layer re-stamps on each pooled connection
/// (and <c>sp_reset_connection</c> clears context between reuses), switching
/// providers needs no app restart and no explicit disconnect — the next query
/// simply opens a connection and stamps the new identity.
/// </summary>
public sealed class AccessContext
{
    /// <summary>The acting provider, or null for Admin / all-patients.</summary>
    public int? ProviderId { get; set; }

    /// <summary><c>Admin</c> sees the whole hospital; anything else is scoped to <see cref="ProviderId"/>.</summary>
    public string Role { get; set; } = "Admin";

    /// <summary>Display name of the acting provider (for the "Viewing as" badge).</summary>
    public string? ProviderName { get; set; }
}
