namespace WardGeneral.Web.Services;

/// <summary>
/// Per-circuit UI context the Assistant dock reads to ground answers on what the
/// user is currently looking at (e.g. the encounter open on the chart page).
/// Pages set it as they render; the dock passes it to the agent as context.
/// </summary>
public sealed class PageContext
{
    public int? EncounterId { get; set; }
    public string? UnitName { get; set; }

    /// <summary>A short natural-language description of the current view, or null.</summary>
    public string? Describe()
    {
        if (EncounterId is int e) return $"the user is viewing patient chart for encounter {e}";
        if (!string.IsNullOrWhiteSpace(UnitName)) return $"the user is viewing unit {UnitName}";
        return null;
    }
}
