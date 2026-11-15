using System.Data;
using System.Text.Json;
using Caldova.TransferCenter.Models;
using Microsoft.Data.SqlClient;

namespace Caldova.TransferCenter.Data;

public sealed class CaldovaRepository(IConfiguration configuration)
{
    private readonly string _connectionString = configuration.GetConnectionString("Caldova")
        ?? throw new InvalidOperationException("Connection string 'Caldova' is not configured.");

    public async Task<HealthResult> GetHealthAsync(CancellationToken cancellationToken)
    {
        await using var connection = await OpenConnectionAsync(cancellationToken);
        await using var command = new SqlCommand("SELECT DB_NAME(), SYSUTCDATETIME();", connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        await reader.ReadAsync(cancellationToken);
        return new HealthResult("Healthy", reader.GetString(0), reader.GetDateTime(1));
    }

    public async Task<IReadOnlyList<TransferQueueItem>> GetTransfersAsync(CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT TransferId, TransferNumber, EncounterNumber, RegionalRecordNumber,
                   GivenName, FamilyName, Age, TransportUnit, DestinationName, ChiefConcern,
                   PriorityCode, TransferStatus, EstimatedArrivalAt, EtaMinutes,
                   DestinationBay, ReceivingTeamNotifiedAt
            FROM app.vTransferQueue
            ORDER BY PriorityCode, EstimatedArrivalAt;
            """;

        await using var connection = await OpenConnectionAsync(cancellationToken);
        await using var command = new SqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var transfers = new List<TransferQueueItem>();
        while (await reader.ReadAsync(cancellationToken))
        {
            transfers.Add(ReadTransfer(reader));
        }

        return transfers;
    }

    public async Task<TransferDetail?> GetTransferDetailAsync(string transferNumber, CancellationToken cancellationToken)
    {
        await using var connection = await OpenConnectionAsync(cancellationToken);
        await using var command = new SqlCommand("app.usp_GetTransferDetail", connection)
        {
            CommandType = CommandType.StoredProcedure
        };
        command.Parameters.Add(new SqlParameter("@TransferNumber", SqlDbType.VarChar, 30) { Value = transferNumber });

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        var transfer = ReadTransfer(reader);
        var observations = new List<Observation>();
        var narratives = new List<Narrative>();
        var allergies = new List<Allergy>();
        var medications = new List<Medication>();
        var encounters = new List<RecentEncounter>();
        var signals = new List<ExtractedSignal>();

        await reader.NextResultAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            observations.Add(new Observation(
                reader.GetString(0), reader.GetString(1), GetNullable<decimal>(reader, 2),
                GetNullableString(reader, 3), GetNullableString(reader, 4), reader.GetBoolean(5), reader.GetDateTime(6)));
        }

        await reader.NextResultAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            narratives.Add(new Narrative(reader.GetInt64(0), reader.GetString(1), reader.GetString(2), reader.GetDateTime(3)));
        }

        await reader.NextResultAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            allergies.Add(new Allergy(reader.GetString(0), GetNullableString(reader, 1), reader.GetDateTime(2)));
        }

        await reader.NextResultAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            medications.Add(new Medication(
                reader.GetString(0), GetNullableString(reader, 1), GetNullableString(reader, 2), reader.GetDateTime(3)));
        }

        await reader.NextResultAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            encounters.Add(new RecentEncounter(
                reader.GetString(0), reader.GetString(1), reader.GetDateTime(2),
                GetNullable<DateTime>(reader, 3), reader.GetString(4)));
        }

        await reader.NextResultAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            signals.Add(new ExtractedSignal(reader.GetString(0), reader.GetString(1), reader.GetInt64(2)));
        }

        return new TransferDetail(transfer, observations, narratives, allergies, medications, encounters, signals);
    }

    public async Task<IReadOnlyList<HistoricalNoteResult>> SearchHistoryAsync(
        string transferNumber, HistorySearchRequest request, CancellationToken cancellationToken)
    {
        await using var connection = await OpenConnectionAsync(cancellationToken);
        await using var command = new SqlCommand("ai.usp_SearchTransferHistory", connection)
        {
            CommandType = CommandType.StoredProcedure,
            CommandTimeout = 240
        };
        command.Parameters.Add(new SqlParameter("@TransferNumber", SqlDbType.VarChar, 30) { Value = transferNumber });
        command.Parameters.Add(new SqlParameter("@Query", SqlDbType.NVarChar, -1) { Value = request.Query });
        command.Parameters.Add(new SqlParameter("@TopK", SqlDbType.Int) { Value = request.TopK });
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (reader.FieldCount != 11 || reader.GetName(0) != "HistoricalNoteId")
        {
            // REST diagnostics precede THROW; advance so the SQL error reaches the caller.
            while (await reader.NextResultAsync(cancellationToken)) { }
            throw new InvalidOperationException("History search returned an unexpected result shape.");
        }
        var notes = new List<HistoricalNoteResult>();
        while (await reader.ReadAsync(cancellationToken))
        {
            notes.Add(new HistoricalNoteResult(
                reader.GetInt64(0), reader.GetString(1), reader.GetInt64(2), reader.GetDateTime(3),
                reader.GetString(4), reader.GetString(5), reader.GetString(6), reader.GetBoolean(7),
                reader.GetString(8), reader.GetDouble(9), reader.GetString(10)));
        }
        return notes;
    }

    public async Task<BriefingResult> GenerateBriefingAsync(
        string transferNumber, BriefingRequest? request, CancellationToken cancellationToken)
    {
        await using var connection = await OpenConnectionAsync(cancellationToken);

        long briefingId;
        BriefingResult result;
        await using (var briefingCommand = new SqlCommand("ai.usp_GenerateTransferBriefing", connection)
        {
            CommandType = CommandType.StoredProcedure,
            CommandTimeout = 240
        })
        {
            briefingCommand.Parameters.Add(new SqlParameter("@TransferNumber", SqlDbType.VarChar, 30) { Value = transferNumber });
            briefingCommand.Parameters.Add(new SqlParameter("@IncludeHistory", SqlDbType.Bit) { Value = request?.IncludeHistory ?? false });
            if (request?.HistoricalNotes is { Count: > 0 } historicalNotes)
            {
                briefingCommand.Parameters.Add(new SqlParameter("@HistoricalNotes", SqlDbType.NVarChar, -1)
                {
                    Value = JsonSerializer.Serialize(historicalNotes, JsonSerializerOptions.Web)
                });
            }
            var skillParameter = briefingCommand.Parameters.Add("@SkillVersion", SqlDbType.VarChar, 30);
            skillParameter.Direction = ParameterDirection.Output;
            var briefingParameter = briefingCommand.Parameters.Add("@BriefingId", SqlDbType.BigInt);
            briefingParameter.Direction = ParameterDirection.Output;

            await using var reader = await briefingCommand.ExecuteReaderAsync(cancellationToken);
            await reader.ReadAsync(cancellationToken);
            var summary = reader.GetString(1);
            var reviewStatus = reader.GetString(2);
            var modelId = reader.GetString(3);
            var durationMs = reader.GetInt64(4);
            var httpStatusCode = reader.GetInt32(5);

            var items = new List<BriefingItem>();
            await reader.NextResultAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                items.Add(new BriefingItem(reader.GetString(0), reader.GetInt16(1), reader.GetString(2),
                    GetNullable<long>(reader, 3)));
            }

            await reader.CloseAsync();
            briefingId = (long)briefingParameter.Value;
            result = new BriefingResult(
                briefingId, summary, reviewStatus, modelId, durationMs, httpStatusCode, items, [], (string)skillParameter.Value);
        }

        const string sourceSql = """
            SELECT source.SourceType, source.SourceRecordKey, source.SourceSummary, source.PacketSourceId,
                   history.Title, history.RecordedAt, history.NoteText, history.AuthoredBy
            FROM ai.BriefingSource AS briefingSource
            JOIN ai.PacketSource AS source ON source.PacketSourceId = briefingSource.PacketSourceId
            JOIN ai.TransferPacket AS packet ON packet.TransferPacketId = source.TransferPacketId
            OUTER APPLY (
                SELECT h.Title, h.RecordedAt, h.NoteText, h.AuthoredBy
                FROM OPENJSON(CONVERT(nvarchar(max), packet.PacketJson), '$.historicalContext')
                WITH (NoteId bigint '$.noteId', Title nvarchar(200) '$.title',
                      RecordedAt datetime2(3) '$.recordedAt', NoteText nvarchar(max) '$.noteText',
                      AuthoredBy nvarchar(200) '$.authoredBy') AS h
                WHERE source.SourceType = 'HistoricalNote'
                  AND source.SourceRecordKey = CONVERT(nvarchar(100), h.NoteId)
            ) AS history
            WHERE briefingSource.BriefingId = @BriefingId
            ORDER BY briefingSource.CitationOrder;
            """;
        await using var sourceCommand = new SqlCommand(sourceSql, connection);
        sourceCommand.Parameters.Add(new SqlParameter("@BriefingId", SqlDbType.BigInt) { Value = briefingId });
        await using var sourceReader = await sourceCommand.ExecuteReaderAsync(cancellationToken);
        var sources = new List<BriefingSource>();
        while (await sourceReader.ReadAsync(cancellationToken))
        {
            sources.Add(new BriefingSource(
                sourceReader.GetString(0), sourceReader.GetString(1), sourceReader.GetString(2),
                sourceReader.GetInt64(3), GetNullableString(sourceReader, 4),
                GetNullable<DateTime>(sourceReader, 5), GetNullableString(sourceReader, 6),
                GetNullableString(sourceReader, 7)));
        }

        return result with { Sources = sources };
    }

    public async Task<IReadOnlyList<ModelInvocationAudit>> GetAuditHistoryAsync(
        string transferNumber, CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT TOP (20) ModelInvocationId, SkillName, SkillVersion, ModelId,
                   InvocationStatus, StartedAt, DurationMs, HttpStatusCode, ErrorMessage,
                   BriefingId, RequestJson, ResponseJson, ledger_start_transaction_id
            FROM ai.ModelInvocationAudit
            WHERE TransferNumber = @TransferNumber
            ORDER BY ModelInvocationId DESC;
            """;

        await using var connection = await OpenConnectionAsync(cancellationToken);
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.Add(new SqlParameter("@TransferNumber", SqlDbType.VarChar, 30) { Value = transferNumber });
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var entries = new List<ModelInvocationAudit>();
        while (await reader.ReadAsync(cancellationToken))
        {
            entries.Add(new ModelInvocationAudit(
                reader.GetInt64(0), reader.GetString(1), reader.GetString(2), reader.GetString(3),
                reader.GetString(4), DateTime.SpecifyKind(reader.GetDateTime(5), DateTimeKind.Utc),
                reader.GetInt64(6), GetNullable<int>(reader, 7), GetNullableString(reader, 8),
                GetNullable<long>(reader, 9), reader.GetString(10), GetNullableString(reader, 11),
                reader.GetInt64(12)));
        }

        return entries;
    }

    private async Task<SqlConnection> OpenConnectionAsync(CancellationToken cancellationToken)
    {
        var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        return connection;
    }

    private static TransferQueueItem ReadTransfer(SqlDataReader reader) => new(
        reader.GetInt64(0), reader.GetString(1), reader.GetString(2), reader.GetString(3),
        reader.GetString(4), reader.GetString(5), reader.GetInt32(6), reader.GetString(7),
        reader.GetString(8), reader.GetString(9), reader.GetByte(10), reader.GetString(11),
        reader.GetDateTime(12), reader.GetInt32(13), GetNullableString(reader, 14),
        GetNullable<DateTime>(reader, 15));

    private static string? GetNullableString(SqlDataReader reader, int ordinal) =>
        reader.IsDBNull(ordinal) ? null : reader.GetString(ordinal);

    private static T? GetNullable<T>(SqlDataReader reader, int ordinal) where T : struct =>
        reader.IsDBNull(ordinal) ? null : reader.GetFieldValue<T>(ordinal);
}