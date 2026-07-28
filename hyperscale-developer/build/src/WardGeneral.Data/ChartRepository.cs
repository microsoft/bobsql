using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Options;
using WardGeneral.Data.Models;

namespace WardGeneral.Data;

/// <summary>
/// The app's data-access layer. Every call goes through a <b>stored procedure</b> — the
/// "procs-for-everything" contract — using raw ADO.NET (no ORM) so the call path
/// and result mapping stay fully visible. The same procedures are what Data API Builder
/// and the SQL MCP server expose later.
/// </summary>
public sealed class ChartRepository
{
    private readonly WardGeneralConnectionFactory _connections;
    private readonly RlsOptions _rls;
    private readonly AccessContext _access;

    public ChartRepository(WardGeneralConnectionFactory connections, IOptions<RlsOptions> rls, AccessContext access)
    {
        _connections = connections;
        _rls = rls.Value;
        _access = access;
    }

    /// <summary>
    /// <c>clinical.SearchEncounters</c> — every filter optional (OPPO). Reads can go to a
    /// read-scale-out replica (<paramref name="readOnly"/>), talk verb <b>Make it HA</b>.
    /// </summary>
    public async Task<IReadOnlyList<EncounterSummary>> SearchEncountersAsync(
        string? status = null,
        int? patientId = null,
        int? departmentId = null,
        int? attendingProviderId = null,
        DateTime? fromAdmit = null,
        DateTime? toAdmit = null,
        bool readOnly = true,
        CancellationToken ct = default)
    {
        await using var conn = _connections.Create(readOnly);
        await OpenWithContextAsync(conn, ct);

        await using var cmd = NewProc(conn, "clinical.SearchEncounters");
        AddParam(cmd, "@Status", SqlDbType.NVarChar, status, 20);
        AddParam(cmd, "@PatientId", SqlDbType.Int, patientId);
        AddParam(cmd, "@DepartmentId", SqlDbType.Int, departmentId);
        AddParam(cmd, "@AttendingProviderId", SqlDbType.Int, attendingProviderId);
        AddParam(cmd, "@FromAdmit", SqlDbType.DateTime2, fromAdmit);
        AddParam(cmd, "@ToAdmit", SqlDbType.DateTime2, toAdmit);

        var results = new List<EncounterSummary>();
        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            results.Add(new EncounterSummary(
                EncounterId: reader.GetInt32(reader.GetOrdinal("EncounterId")),
                PatientId: reader.GetInt32(reader.GetOrdinal("PatientId")),
                DepartmentId: reader.GetInt32(reader.GetOrdinal("DepartmentId")),
                AttendingProviderId: reader.GetInt32(reader.GetOrdinal("AttendingProviderId")),
                BedId: GetNullableInt(reader, "BedId"),
                EncounterType: reader.GetString(reader.GetOrdinal("EncounterType")),
                AdmitTime: reader.GetDateTime(reader.GetOrdinal("AdmitTime")),
                DischargeTime: GetNullableDateTime(reader, "DischargeTime"),
                Status: reader.GetString(reader.GetOrdinal("Status"))));
        }

        return results;
    }

    /// <summary><c>clinical.GetPatientChart</c> — full chart for one encounter.</summary>
    public Task<PatientChart?> GetPatientChartAsync(int encounterId, bool readOnly = true, CancellationToken ct = default) =>
        ReadChartAsync("clinical.GetPatientChart", ("@EncounterId", SqlDbType.Int, (object)encounterId), readOnly, ct);

    /// <summary><c>clinical.GetPatientChartByBed</c> — active encounter on a bed.</summary>
    public Task<PatientChart?> GetPatientChartByBedAsync(int bedId, bool readOnly = true, CancellationToken ct = default) =>
        ReadChartAsync("clinical.GetPatientChartByBed", ("@BedId", SqlDbType.Int, (object)bedId), readOnly, ct);

    /// <summary><c>clinical.RecordVitals</c> — append one observation (write → primary).</summary>
    public async Task RecordVitalsAsync(
        int encounterId, string observationType, decimal valueNumeric, string? unit = null, CancellationToken ct = default)
    {
        await using var conn = _connections.Create(readOnly: false);
        await OpenWithContextAsync(conn, ct);

        await using var cmd = NewProc(conn, "clinical.RecordVitals");
        AddParam(cmd, "@EncounterId", SqlDbType.Int, encounterId);
        AddParam(cmd, "@ObservationType", SqlDbType.NVarChar, observationType, 20);
        AddParam(cmd, "@ValueNumeric", SqlDbType.Decimal, valueNumeric);
        AddParam(cmd, "@Unit", SqlDbType.NVarChar, unit, 20);

        await cmd.ExecuteNonQueryAsync(ct);
    }

    /// <summary><c>clinical.AddClinicalNote</c> — append a free-text note (write → primary).</summary>
    public async Task AddClinicalNoteAsync(
        int encounterId, int authorProviderId, string noteType, string noteText, CancellationToken ct = default)
    {
        await using var conn = _connections.Create(readOnly: false);
        await OpenWithContextAsync(conn, ct);

        await using var cmd = NewProc(conn, "clinical.AddClinicalNote");
        AddParam(cmd, "@EncounterId", SqlDbType.Int, encounterId);
        AddParam(cmd, "@AuthorProviderId", SqlDbType.Int, authorProviderId);
        AddParam(cmd, "@NoteType", SqlDbType.NVarChar, noteType, 20);
        AddParam(cmd, "@NoteText", SqlDbType.NVarChar, noteText, -1);

        await cmd.ExecuteNonQueryAsync(ct);
    }

    /// <summary>
    /// <c>clinical.GenerateClinicalAssistance</c> — advisory AI for the attending: a
    /// <b>suggested</b> triage flag (to confirm/override) plus a grounded summary. Vector
    /// search (RAG) over similar prior notes + gpt-5, all in-engine; every call is audited
    /// server-side (<c>clinical.AIAssistanceLog</c>). Routed to the <b>primary</b> — it needs
    /// the embeddings, the Foundry credential, and writes the audit row. On-demand only
    /// (a gpt-5 call costs tokens and takes seconds), so give it a generous command timeout.
    /// </summary>
    public async Task<AssistanceResult?> GetClinicalAssistanceAsync(
        int encounterId, CancellationToken ct = default)
    {
        await using var conn = _connections.Create(readOnly: false);
        await OpenWithContextAsync(conn, ct);

        await using var cmd = NewProc(conn, "clinical.GenerateClinicalAssistance");
        cmd.CommandTimeout = 130; // the proc waits up to 120s on gpt-5
        AddParam(cmd, "@EncounterId", SqlDbType.Int, encounterId);

        await using var reader = await cmd.ExecuteReaderAsync(ct);
        if (!await reader.ReadAsync(ct))
            return null;

        return new AssistanceResult(
            EncounterId: reader.GetInt32(reader.GetOrdinal("EncounterId")),
            PatientName: GetNullableString(reader, "PatientName"),
            SuggestedTriageFlag: GetNullableString(reader, "SuggestedTriageFlag"),
            Summary: GetNullableString(reader, "Summary"),
            GroundedOnNoteIds: GetNullableString(reader, "GroundedOnNoteIds"),
            Path: GetOptionalString(reader, "Path"),
            ProcessingTimeMs: reader.GetInt32(reader.GetOrdinal("ProcessingTimeMs")));
    }

    // ---- helpers ---------------------------------------------------------

    private async Task<PatientChart?> ReadChartAsync(
        string proc, (string Name, SqlDbType Type, object Value) key, bool readOnly, CancellationToken ct)
    {
        await using var conn = _connections.Create(readOnly);
        await OpenWithContextAsync(conn, ct);

        await using var cmd = NewProc(conn, proc);
        AddParam(cmd, key.Name, key.Type, key.Value);

        await using var reader = await cmd.ExecuteReaderAsync(ct);
        if (!await reader.ReadAsync(ct))
            return null;

        return new PatientChart(
            EncounterId: reader.GetInt32(reader.GetOrdinal("EncounterId")),
            EncounterStatus: reader.GetString(reader.GetOrdinal("EncounterStatus")),
            EncounterType: reader.GetString(reader.GetOrdinal("EncounterType")),
            AdmitTime: reader.GetDateTime(reader.GetOrdinal("AdmitTime")),
            DischargeTime: GetNullableDateTime(reader, "DischargeTime"),
            IntakeJson: GetJson(reader, "IntakeJson"),
            PatientId: reader.GetInt32(reader.GetOrdinal("PatientId")),
            Mrn: reader.GetString(reader.GetOrdinal("MRN")),
            PatientName: reader.GetString(reader.GetOrdinal("PatientName")),
            DateOfBirth: GetNullableDateTime(reader, "DateOfBirth"),
            Sex: GetNullableString(reader, "Sex"),
            AgeYears: GetNullableInt(reader, "AgeYears"),
            DepartmentId: reader.GetInt32(reader.GetOrdinal("DepartmentId")),
            DepartmentName: reader.GetString(reader.GetOrdinal("DepartmentName")),
            UnitId: GetNullableInt(reader, "UnitId"),
            UnitName: GetNullableString(reader, "UnitName"),
            BedId: GetNullableInt(reader, "BedId"),
            BedNumber: GetNullableString(reader, "BedNumber"),
            AttendingProviderId: reader.GetInt32(reader.GetOrdinal("AttendingProviderId")),
            AttendingProviderName: reader.GetString(reader.GetOrdinal("AttendingProviderName")),
            AttendingProviderRole: reader.GetString(reader.GetOrdinal("AttendingProviderRole")),
            Diagnoses: DeserializeList<Diagnosis>(GetJson(reader, "Diagnoses")),
            Medications: DeserializeList<Medication>(GetJson(reader, "Medications")),
            Allergies: DeserializeList<Allergy>(GetJson(reader, "Allergies")),
            LatestVitals: DeserializeDictionary<VitalReading>(GetJson(reader, "LatestVitals")),
            RecentLabs: DeserializeList<LabResult>(GetJson(reader, "RecentLabs")),
            Symptoms: DeserializeList<Symptom>(GetJson(reader, "Symptoms")),
            CareTeam: DeserializeList<CareTeamMember>(GetJson(reader, "CareTeam")),
            Imaging: DeserializeList<ImagingStudy>(GetJson(reader, "Imaging")),
            RecentNotes: DeserializeList<NoteEntry>(GetJson(reader, "RecentNotes")),
            NoteSignals: DeserializeObject<NoteSignals>(GetOptionalJson(reader, "NoteSignals")));
    }

    /// <summary>Distinct unit names for the Unit-board selector (reads <c>ops.vBedCensus</c>).</summary>
    public async Task<IReadOnlyList<string>> GetUnitsAsync(bool readOnly = true, CancellationToken ct = default)
    {
        await using var conn = _connections.Create(readOnly);
        await OpenWithContextAsync(conn, ct);

        await using var cmd = new SqlCommand(
            "SELECT DISTINCT UnitName FROM ops.vBedCensus ORDER BY UnitName", conn)
        {
            RetryLogicProvider = RetryPolicy.CreateProvider()
        };

        var units = new List<string>();
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct))
            if (!r.IsDBNull(0)) units.Add(r.GetString(0));
        return units;
    }

    /// <summary>
    /// The Unit board — beds for a unit from <c>ops.vBedCensus</c> (read directly, no proc).
    /// Occupied beds carry patient info; empty beds have nulls. Reads can go to a
    /// read-scale-out replica (talk verb <b>Make it HA</b>).
    /// </summary>
    public async Task<IReadOnlyList<BedCensusRow>> GetUnitBoardAsync(
        string? unitName = null, bool occupiedOnly = true, bool readOnly = true, CancellationToken ct = default)
    {
        await using var conn = _connections.Create(readOnly);
        await OpenWithContextAsync(conn, ct);

        const string sql = @"
SELECT UnitName, BedNumber, BedStatus, EncounterId, PatientId, MRN, PatientName, AttendingProvider, AdmitTime
FROM ops.vBedCensus
WHERE (@Unit IS NULL OR UnitName = @Unit)
  AND (@OccupiedOnly = 0 OR EncounterId IS NOT NULL)
ORDER BY UnitName, BedNumber;";

        await using var cmd = new SqlCommand(sql, conn) { RetryLogicProvider = RetryPolicy.CreateProvider() };
        cmd.Parameters.Add("@Unit", SqlDbType.NVarChar, 100).Value = (object?)unitName ?? DBNull.Value;
        cmd.Parameters.Add("@OccupiedOnly", SqlDbType.Bit).Value = occupiedOnly;

        var rows = new List<BedCensusRow>();
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct))
        {
            rows.Add(new BedCensusRow(
                UnitName: r.GetString(r.GetOrdinal("UnitName")),
                BedNumber: r.GetString(r.GetOrdinal("BedNumber")),
                BedStatus: r.GetString(r.GetOrdinal("BedStatus")),
                EncounterId: GetNullableInt(r, "EncounterId"),
                PatientId: GetNullableInt(r, "PatientId"),
                Mrn: GetNullableString(r, "MRN"),
                PatientName: GetNullableString(r, "PatientName"),
                AttendingProvider: GetNullableString(r, "AttendingProvider"),
                AdmitTime: GetNullableDateTime(r, "AdmitTime")));
        }
        return rows;
    }

    /// <summary>
    /// Open the connection and, when Row-Level Security is enabled, stamp the acting
    /// clinician (from <see cref="AccessContext"/>) into <c>SESSION_CONTEXT</c>
    /// (read-only) on this pooled connection. The RLS predicate on
    /// <c>clinical.Encounter</c> reads it and filters rows in the engine.
    /// Connection-pool reuse (<c>sp_reset_connection</c>) clears the context, so every
    /// open re-stamps — switching "Viewing as" needs no restart or explicit reconnect.
    /// Default identity (nothing selected) is Admin → all patients.
    /// </summary>
    private async Task OpenWithContextAsync(SqlConnection conn, CancellationToken ct)
    {
        await conn.OpenAsync(ct);
        if (!_rls.Enabled)
            return;

        var role = string.IsNullOrWhiteSpace(_access.Role) ? "Admin" : _access.Role;

        await using var cmd = new SqlCommand(
            "EXEC sys.sp_set_session_context @k1, @v1, @ro; " +
            "EXEC sys.sp_set_session_context @k2, @v2, @ro;", conn);
        cmd.Parameters.AddWithValue("@k1", "ProviderId");
        cmd.Parameters.AddWithValue("@v1", (object?)_access.ProviderId ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@k2", "Role");
        cmd.Parameters.AddWithValue("@v2", role);
        cmd.Parameters.AddWithValue("@ro", true); // read-only: a query can't overwrite it this session
        await cmd.ExecuteNonQueryAsync(ct);
    }

    /// <summary>
    /// Attendings with active patients, for the "Viewing as" selector. Loaded once at
    /// Admin scope (so the full list appears); the RLS filter on this query is harmless
    /// there because Admin sees every encounter.
    /// </summary>
    public async Task<IReadOnlyList<ProviderOption>> GetProvidersAsync(bool readOnly = true, CancellationToken ct = default)
    {
        await using var conn = _connections.Create(readOnly);
        await OpenWithContextAsync(conn, ct);

        await using var cmd = new SqlCommand(@"
SELECT DISTINCT e.AttendingProviderId, pr.FullName, pr.Role
FROM clinical.Encounter AS e
JOIN ops.Provider AS pr ON pr.ProviderId = e.AttendingProviderId
WHERE e.Status = N'Active'
ORDER BY pr.FullName;", conn)
        {
            RetryLogicProvider = RetryPolicy.CreateProvider()
        };

        var list = new List<ProviderOption>();
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct))
            list.Add(new ProviderOption(r.GetInt32(0), r.GetString(1), r.GetString(2)));
        return list;
    }

    private static SqlCommand NewProc(SqlConnection conn, string name)
    {
        var cmd = new SqlCommand(name, conn)
        {
            CommandType = CommandType.StoredProcedure,
            // Retry the execute too (connection open is retried by the connection).
            RetryLogicProvider = RetryPolicy.CreateProvider()
        };
        return cmd;
    }

    private static void AddParam(SqlCommand cmd, string name, SqlDbType type, object? value, int size = 0)
    {
        var p = size != 0 ? cmd.Parameters.Add(name, type, size) : cmd.Parameters.Add(name, type);
        p.Value = value ?? DBNull.Value;
    }

    private static int? GetNullableInt(SqlDataReader r, string col)
    {
        var i = r.GetOrdinal(col);
        return r.IsDBNull(i) ? null : r.GetInt32(i);
    }

    private static string? GetNullableString(SqlDataReader r, string col)
    {
        var i = r.GetOrdinal(col);
        return r.IsDBNull(i) ? null : r.GetString(i);
    }

    /// <summary>
    /// Like <see cref="GetNullableString"/> but tolerant of a column that isn't in the
    /// result set. The direct assistance proc (07) omits <c>Path</c>; the gateway proc (09)
    /// adds it. Returns null when the column is absent instead of throwing.
    /// </summary>
    private static string? GetOptionalString(SqlDataReader r, string col)
    {
        for (var i = 0; i < r.FieldCount; i++)
            if (string.Equals(r.GetName(i), col, StringComparison.OrdinalIgnoreCase))
                return r.IsDBNull(i) ? null : r.GetString(i);
        return null;
    }

    private static DateTime? GetNullableDateTime(SqlDataReader r, string col)
    {
        var i = r.GetOrdinal(col);
        return r.IsDBNull(i) ? null : r.GetDateTime(i);
    }

    /// <summary>
    /// Read a native <c>json</c> column as text. Microsoft.Data.SqlClient may surface the
    /// <c>json</c> type as a string or a provider JSON value; ToString() gives the JSON text
    /// either way.
    /// </summary>
    private static string? GetJson(SqlDataReader r, string col)
    {
        var i = r.GetOrdinal(col);
        if (r.IsDBNull(i)) return null;
        var value = r.GetValue(i);
        return value?.ToString();
    }

    /// <summary>
    /// Like <see cref="GetJson"/> but tolerant of a column that isn't in the result set.
    /// A proc from an earlier chapter (before the regex / AI columns were added) simply
    /// won't return it, so the feature self-hides instead of throwing. Enables the one
    /// app codebase to serve every chapter as the schema evolves underneath it.
    /// </summary>
    private static string? GetOptionalJson(SqlDataReader r, string col)
    {
        for (var i = 0; i < r.FieldCount; i++)
            if (string.Equals(r.GetName(i), col, StringComparison.OrdinalIgnoreCase))
                return r.IsDBNull(i) ? null : r.GetValue(i)?.ToString();
        return null;
    }

    private static IReadOnlyList<T> DeserializeList<T>(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return Array.Empty<T>();
        return JsonSerializer.Deserialize<List<T>>(json, ChartJson.Options) ?? new List<T>();
    }

    private static IReadOnlyDictionary<string, T> DeserializeDictionary<T>(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new Dictionary<string, T>();
        return JsonSerializer.Deserialize<Dictionary<string, T>>(json, ChartJson.Options) ?? new Dictionary<string, T>();
    }

    private static T? DeserializeObject<T>(string? json) where T : class
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        return JsonSerializer.Deserialize<T>(json, ChartJson.Options);
    }
}
