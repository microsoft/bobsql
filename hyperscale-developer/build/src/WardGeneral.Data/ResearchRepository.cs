using System.Data;
using Microsoft.Data.SqlClient;
using WardGeneral.Data.Models;

namespace WardGeneral.Data;

/// <summary>
/// Read-only semantic search over historical clinical notes, for the Research page.
///
/// Talk verb: <b>Scale it</b> (read scale-out). This connects to the <b>serverless
/// named replica</b> (<c>wardgeneral-research</c>) via
/// <see cref="WardGeneralConnectionFactory.CreateResearch"/> and calls
/// <c>clinical.SearchSimilarNotes</c>. The <i>entire</i> workload — embedding the
/// query with <c>AI_GENERATE_EMBEDDINGS</c> and the DiskANN vector search over the
/// 60k-note corpus — runs on the replica's own compute, so the OLTP primary serving
/// the ward is never touched. It is <b>retrieval only</b> (no chat / no generation):
/// a human reads the returned notes.
/// </summary>
public sealed class ResearchRepository
{
    private readonly WardGeneralConnectionFactory _connections;

    public ResearchRepository(WardGeneralConnectionFactory connections) => _connections = connections;

    /// <summary>The named replica this page targets (for the UI banner).</summary>
    public string Target => _connections.ResearchTarget;

    /// <summary>
    /// Semantic search: embed <paramref name="queryText"/> and return the top
    /// <paramref name="topK"/> most similar clinical notes, ranked by similarity.
    /// Runs entirely on the read-only named replica.
    /// </summary>
    public async Task<IReadOnlyList<NoteSearchResult>> SearchSimilarNotesAsync(
        string queryText, int topK = 10, CancellationToken ct = default)
    {
        await using var conn = _connections.CreateResearch();
        await conn.OpenAsync(ct);

        await using var cmd = new SqlCommand("clinical.SearchSimilarNotes", conn)
        {
            CommandType = CommandType.StoredProcedure,
            CommandTimeout = 60, // embed + vector search on a serverless replica warming up
            RetryLogicProvider = RetryPolicy.CreateProvider()
        };
        cmd.Parameters.Add("@QueryText", SqlDbType.NVarChar, -1).Value = queryText;
        cmd.Parameters.Add("@TopK", SqlDbType.Int).Value = topK;

        var results = new List<NoteSearchResult>();
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct))
        {
            results.Add(new NoteSearchResult(
                NoteId: r.GetInt32(r.GetOrdinal("NoteId")),
                EncounterId: r.GetInt32(r.GetOrdinal("EncounterId")),
                NoteType: r.GetString(r.GetOrdinal("NoteType")),
                CreatedAt: r.GetDateTime(r.GetOrdinal("CreatedAt")),
                Similarity: r.GetDecimal(r.GetOrdinal("Similarity")),
                NoteText: r.GetString(r.GetOrdinal("NoteText"))));
        }
        return results;
    }
}
