USE CaldovaRegionalCare;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @PacketId bigint, @BriefingId bigint, @Notes nvarchar(max), @WrongPatient nvarchar(max);
DECLARE @OriginalPackets int = (SELECT COUNT(*) FROM ai.TransferPacket);
SET @WrongPatient = (
    SELECT HistoricalNoteId AS historicalNoteId, CONVERT(varchar(18), CONVERT(binary(8), NoteVersion), 1) AS sourceVersion
    FROM care.HistoricalNote WHERE SourceCode = 'DEMO-JAMES-ALLERGY' FOR JSON PATH);
BEGIN TRY
    EXEC ai.usp_CreateTransferPacketWithHistory 'TR-2026-0147', @WrongPatient, @PacketId OUTPUT;
    THROW 50055, 'Cross-patient history selection was not rejected.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 50050 THROW;
END CATCH;
IF (SELECT COUNT(*) FROM ai.TransferPacket) <> @OriginalPackets
    THROW 50055, 'Rejected history selection persisted a packet.', 1;

SET @Notes = (
    SELECT HistoricalNoteId AS historicalNoteId, '0x0000000000000000' AS sourceVersion
    FROM care.HistoricalNote WHERE SourceCode = 'DEMO-MARIA-ALLERGY' FOR JSON PATH);
BEGIN TRY
    EXEC ai.usp_CreateTransferPacketWithHistory 'TR-2026-0147', @Notes, @PacketId OUTPUT;
    THROW 50055, 'Stale selection was not rejected.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 50051 THROW;
END CATCH;
BEGIN TRY
    EXEC ai.usp_CreateTransferPacketWithHistory 'TR-2026-0147', N'[1]', @PacketId OUTPUT;
    THROW 50055, 'Invalid selection shape was not rejected.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 50050 THROW;
END CATCH;

EXEC ai.usp_CreateTransferPacket 'TR-2026-0147', @PacketId OUTPUT, @ReturnPacket = 0;
IF (SELECT COUNT(*) FROM ai.PacketSource WHERE TransferPacketId = @PacketId) <> 7
    OR EXISTS (SELECT 1 FROM ai.TransferPacket AS p
               CROSS APPLY OPENJSON(CONVERT(nvarchar(max), p.PacketJson), '$.historicalContext') AS h
               WHERE TransferPacketId = @PacketId)
    THROW 50055, 'Original seven-source packet behavior changed.', 1;

SET @Notes = (
    SELECT HistoricalNoteId AS historicalNoteId, CONVERT(varchar(18), CONVERT(binary(8), NoteVersion), 1) AS sourceVersion
    FROM care.HistoricalNote WHERE SourceCode = 'DEMO-MARIA-ALLERGY' FOR JSON PATH);
EXEC ai.usp_CreateTransferPacketWithHistory 'TR-2026-0147', @Notes, @PacketId OUTPUT;
IF (SELECT COUNT(*) FROM ai.PacketSource WHERE TransferPacketId = @PacketId) <> 8
    THROW 50055, 'Expected seven original source groups plus one historical source.', 1;
DECLARE @PacketJson nvarchar(max) = (
    SELECT CONVERT(nvarchar(max), PacketJson) FROM ai.TransferPacket WHERE TransferPacketId = @PacketId);
IF JSON_VALUE(@PacketJson, '$.historicalContext[0].sourceCode') <> 'DEMO-MARIA-ALLERGY'
    OR JSON_VALUE(@PacketJson, '$.historicalContext[0].recordedAt') NOT LIKE '2025-11-03%'
    OR JSON_VALUE(@PacketJson, '$.historicalContext[0].noteText') NOT LIKE '%hives and facial swelling%'
    THROW 50055, 'Expanded packet lacks the selected note text, date, or provenance.', 1;
DECLARE @InvalidResponse nvarchar(max) =
    N'{"result":{"choices":[{"message":{"content":"{\"summary\":\"Test\",\"keyContext\":[],\"confirmOnArrival\":[]}"},"finish_reason":"stop"}]}}';
DECLARE @ValidationStartedAt datetime2(3) = SYSUTCDATETIME();
BEGIN TRY
    EXEC ai.usp_SaveTransferBriefing
        @ModelInvocationId = NULL, @TransferPacketId = @PacketId,
        @SkillName = N'ReceivingBriefing', @SkillVersion = '2.0',
        @ModelId = N'gpt-oss-20b', @CompletionUrl = N'https://validation.invalid',
        @PacketJson = @PacketJson, @ResponseJson = @InvalidResponse,
        @ReturnCode = 0, @HttpStatusCode = 200, @StartedAt = @ValidationStartedAt,
        @BriefingId = @BriefingId OUTPUT;
    THROW 50055, 'Empty receiving recommendations must fail before persistence.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 50026 THROW;
END CATCH;

DECLARE @MalformedRecommendations TABLE (Recommendations nvarchar(max));
INSERT @MalformedRecommendations VALUES
    (N'["1. Verify the current handoff. 2. Clarify the reported history.", "historicalContext"]'),
    (N'["1. Verify the current handoff. 2. Clarify the reported history.", "Verify the recorded allergy."]'),
    (N'["Verify the current handoff.", "historicalContext"]');
DECLARE @Recommendations nvarchar(max);
WHILE EXISTS (SELECT 1 FROM @MalformedRecommendations)
BEGIN
    SELECT TOP (1) @Recommendations = Recommendations FROM @MalformedRecommendations;
    SET @InvalidResponse = N'{"summary":"Test","keyContext":[],"confirmOnArrival":[]}';
    SET @InvalidResponse = JSON_MODIFY(@InvalidResponse, '$.confirmOnArrival', JSON_QUERY(@Recommendations));
    SET @InvalidResponse = (
        SELECT JSON_QUERY((
            SELECT JSON_QUERY((SELECT @InvalidResponse AS content FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS message,
                   N'stop' AS finish_reason
            FOR JSON PATH)) AS [result.choices]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    BEGIN TRY
        EXEC ai.usp_SaveTransferBriefing
            @ModelInvocationId = NULL, @TransferPacketId = @PacketId,
            @SkillName = N'ReceivingBriefing', @SkillVersion = '2.0',
            @ModelId = N'gpt-oss-20b', @CompletionUrl = N'https://validation.invalid',
            @PacketJson = @PacketJson, @ResponseJson = @InvalidResponse,
            @ReturnCode = 0, @HttpStatusCode = 200, @StartedAt = @ValidationStartedAt,
            @BriefingId = @BriefingId OUTPUT;
        THROW 50055, 'Combined recommendations or field-name filler must fail before persistence.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() <> 50026 THROW;
    END CATCH;
    DELETE FROM @MalformedRecommendations WHERE Recommendations = @Recommendations;
END;

EXEC ai.usp_InvokeTransferSkill @PacketId, N'ReceivingBriefing', '2.0', @BriefingId OUTPUT;
IF EXISTS (
    SELECT 1 FROM ai.ModelInvocationAudit
    WHERE BriefingId = @BriefingId AND ModelId = N'gpt-oss-20b'
      AND ISNULL(JSON_VALUE(RequestJson, '$.response_format.type'), '') <> 'json_schema'
)
    THROW 50055, 'Historical GPT briefing requests must enforce structured JSON output.', 1;
IF (SELECT COUNT(*) FROM ai.BriefingSource WHERE BriefingId = @BriefingId) <> 8
    OR (SELECT COUNT(*) FROM ai.BriefingItem WHERE BriefingId = @BriefingId AND SectionName = 'HistoricalContext') <> 1
    THROW 50055, 'Historical briefing did not persist eight sources and one historical context item.', 1;
IF EXISTS (
    SELECT 1 FROM ai.ModelInvocationAudit
    WHERE BriefingId = @BriefingId AND ModelId = N'gpt-oss-20b'
      AND (ISNULL(JSON_VALUE(RequestJson, '$.response_format.json_schema.strict'), '') <> 'true'
        OR ISNULL(JSON_VALUE(RequestJson, '$.response_format.json_schema.schema.properties.confirmOnArrival.minItems'), '') <> '2'
        OR ISNULL(JSON_VALUE(RequestJson, '$.response_format.json_schema.schema.properties.confirmOnArrival.maxItems'), '') <> '4'
        OR ISNULL(JSON_VALUE(RequestJson, '$.response_format.json_schema.schema.properties.historicalContext.minItems'), '') <> '1'
        OR ISNULL(JSON_VALUE(RequestJson, '$.response_format.json_schema.schema.properties.historicalContext.maxItems'), '') <> '1'))
    THROW 50055, 'Historical GPT requests must constrain recommendations and require exactly the supplied history count.', 1;
IF EXISTS (
    SELECT 1 FROM ai.BriefingItem AS i
    LEFT JOIN ai.PacketSource AS s ON s.PacketSourceId = i.PacketSourceId
    WHERE i.BriefingId = @BriefingId AND i.SectionName = 'HistoricalContext'
      AND (s.PacketSourceId IS NULL OR s.SourceType <> 'HistoricalNote'
           OR s.TransferPacketId <> @PacketId OR s.SourceRecordKey <> JSON_VALUE(@PacketJson, '$.historicalContext[0].noteId')))
    THROW 50055, 'Historical context item cites an incorrect source.', 1;
IF EXISTS (SELECT 1 FROM ai.BriefingItem WHERE BriefingId = @BriefingId AND SectionName = 'HistoricalContext'
           AND ItemText NOT LIKE '%2025%')
    THROW 50055, 'Generated historical context omitted its recorded year.', 1;
SELECT N'Historical RAG tests passed' AS Result, @BriefingId AS BriefingId,
       @PacketId AS PacketId, 8 AS Sources, N'ReceivingBriefing 2.0' AS Skill;

DECLARE @SkillVersion varchar(30);
DECLARE @Expected TABLE (
    HistoricalNoteId bigint, SourceCode varchar(60), PersonId bigint,
    RecordedAt datetime2(3), Title nvarchar(200), AuthoredBy nvarchar(200),
    NoteText nvarchar(4000), IsSynthetic bit, ModelId varchar(100),
    CosineDistance float, SourceVersion varchar(18));
DECLARE @Query nvarchar(4000) = (SELECT ChiefConcern FROM ops.Transfer WHERE TransferNumber = 'TR-2026-0147');
INSERT @Expected EXEC ai.usp_SearchTransferHistory 'TR-2026-0147', @Query, 3;
IF (SELECT COUNT(*) FROM @Expected) <> 1
    OR NOT EXISTS (SELECT 1 FROM @Expected WHERE SourceCode = 'DEMO-MARIA-CHEST')
    THROW 50055, 'The demo transfer concern must retrieve only the relevant chest history.', 1;

EXEC ai.usp_GenerateTransferBriefing 'TR-2026-0147', @BriefingId OUTPUT,
    @IncludeHistory = 1, @SkillVersion = @SkillVersion OUTPUT;
IF @SkillVersion <> '2.0'
    OR (SELECT COUNT(*) FROM ai.BriefingSource WHERE BriefingId = @BriefingId) <> 8
    OR (SELECT COUNT(*) FROM ai.BriefingItem WHERE BriefingId = @BriefingId AND SectionName = 'HistoricalContext') <> 1
    THROW 50055, 'Integrated RAG must persist seven regional groups and only the relevant historical citation using skill 2.0.', 1;
IF (SELECT COUNT(*) FROM ai.BriefingItem
    WHERE BriefingId = @BriefingId AND SectionName = 'ConfirmOnArrival') NOT BETWEEN 2 AND 4
    THROW 50055, 'Historical receiving briefing must include 2 to 4 receiving recommendations.', 1;
IF EXISTS (
    SELECT CONVERT(nvarchar(100), HistoricalNoteId) FROM @Expected
    EXCEPT
    SELECT s.SourceRecordKey
    FROM ai.BriefingSource AS b JOIN ai.PacketSource AS s ON s.PacketSourceId = b.PacketSourceId
    WHERE b.BriefingId = @BriefingId AND s.SourceType = 'HistoricalNote')
    THROW 50055, 'Integrated RAG did not ground the briefing in the relevance-filtered notes.', 1;
IF NOT EXISTS (SELECT 1 FROM ai.ModelInvocationAudit
               WHERE BriefingId = @BriefingId AND InvocationStatus = 'Succeeded' AND HttpStatusCode = 200)
    THROW 50055, 'Integrated RAG did not commit its successful ledger audit.', 1;
SELECT N'Integrated relevance-filtered RAG passed' AS Result, @BriefingId AS BriefingId, 8 AS Sources;

EXEC ai.usp_GenerateTransferBriefing 'TR-2026-0147', @BriefingId OUTPUT,
    @IncludeHistory = 0, @SkillVersion = @SkillVersion OUTPUT;
IF @SkillVersion <> '2.0'
    OR (SELECT COUNT(*) FROM ai.BriefingSource WHERE BriefingId = @BriefingId) <> 7
    OR EXISTS (SELECT 1 FROM ai.BriefingItem WHERE BriefingId = @BriefingId AND SectionName = 'HistoricalContext')
    THROW 50055, 'Disabling history must preserve the original seven-source briefing.', 1;
IF EXISTS (
    SELECT 1 FROM ai.ModelInvocationAudit
    WHERE BriefingId = @BriefingId AND ModelId = N'gpt-oss-20b'
      AND (ISNULL(JSON_VALUE(RequestJson, '$.response_format.json_schema.schema.properties.historicalContext.minItems'), '') <> '0'
        OR ISNULL(JSON_VALUE(RequestJson, '$.response_format.json_schema.schema.properties.historicalContext.maxItems'), '') <> '0'))
    THROW 50055, 'Current-facts GPT requests must constrain historical context to an empty array.', 1;
SELECT N'Current-facts-only generation passed' AS Result, @BriefingId AS BriefingId, 7 AS Sources;
IF (SELECT COUNT(*) FROM ai.BriefingItem
    WHERE BriefingId = @BriefingId AND SectionName = 'ConfirmOnArrival') NOT BETWEEN 2 AND 4
    THROW 50055, 'Current-facts receiving briefing must include 2 to 4 receiving recommendations.', 1;

BEGIN TRY
    EXEC ai.usp_GenerateTransferBriefing 'TR-2026-0147', @BriefingId OUTPUT,
        @IncludeHistory = 1, @HistoricalNotes = @Notes;
    THROW 50055, 'Conflicting automatic and explicit history options were not rejected.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 50050 THROW;
END CATCH;

BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE care.HistoricalNote SET NoteText = N'[Stale-source test] ' + NoteText
    WHERE SourceCode = 'DEMO-MARIA-ALLERGY';
    EXEC ai.usp_GenerateTransferBriefing 'TR-2026-0147', @BriefingId OUTPUT, @IncludeHistory = 1;
    THROW 50055, 'Integrated RAG must reject stale embeddings rather than omit history.', 1;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    IF ERROR_NUMBER() <> 50047 THROW;
END CATCH;
SELECT N'Integrated RAG validation passed' AS Result;
GO
