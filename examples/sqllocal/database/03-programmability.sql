/* ============================================================================
   Caldova Regional Care Transfer Center
   03-programmability.sql : app queries, regex extraction, grounded packet build
   ============================================================================ */

USE [CaldovaRegionalCare];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW app.vTransferQueue
AS
SELECT
    t.TransferId,
    t.TransferNumber,
    e.EncounterNumber,
    p.RegionalRecordNumber,
    p.GivenName,
    p.FamilyName,
    DATEDIFF(year, p.DateOfBirth, CAST(SYSUTCDATETIME() AS date))
        - CASE WHEN DATEADD(year, DATEDIFF(year, p.DateOfBirth, CAST(SYSUTCDATETIME() AS date)), p.DateOfBirth)
                    > CAST(SYSUTCDATETIME() AS date) THEN 1 ELSE 0 END AS Age,
    t.TransportUnit,
    destination.FacilityName AS DestinationName,
    t.ChiefConcern,
    t.PriorityCode,
    t.TransferStatus,
    t.EstimatedArrivalAt,
    CASE
        WHEN DATEDIFF(minute, SYSUTCDATETIME(), t.EstimatedArrivalAt) < 0 THEN 0
        ELSE DATEDIFF(minute, SYSUTCDATETIME(), t.EstimatedArrivalAt)
    END AS EtaMinutes,
    t.DestinationBay,
    t.ReceivingTeamNotifiedAt
FROM ops.Transfer AS t
JOIN care.Encounter AS e ON e.EncounterId = t.EncounterId
JOIN care.Person AS p ON p.PersonId = e.PersonId
JOIN ops.Facility AS destination ON destination.FacilityId = t.DestinationFacilityId
WHERE t.TransferStatus IN ('Requested', 'Accepted', 'InTransit');
GO

CREATE OR ALTER PROCEDURE app.usp_GetTransferDetail
    @TransferNumber varchar(30)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @EncounterId bigint;
    DECLARE @PersonId bigint;

    SELECT
        @EncounterId = t.EncounterId,
        @PersonId = e.PersonId
    FROM ops.Transfer AS t
    JOIN care.Encounter AS e ON e.EncounterId = t.EncounterId
    WHERE t.TransferNumber = @TransferNumber;

    IF @EncounterId IS NULL
        THROW 50010, 'Transfer not found.', 1;

    SELECT *
    FROM app.vTransferQueue
    WHERE TransferNumber = @TransferNumber;

    SELECT ObservationCode, ObservationName, NumericValue, TextValue, Unit, IsAlert, ObservedAt
    FROM care.Observation
    WHERE EncounterId = @EncounterId
    ORDER BY ObservedAt DESC, ObservationId;

    SELECT n.NarrativeId, n.NarrativeText, n.AuthoredBy, n.RecordedAt
    FROM ops.FieldNarrative AS n
    WHERE n.EncounterId = @EncounterId
    ORDER BY n.RecordedAt DESC;

    SELECT a.AllergyName, pa.Reaction, pa.RecordedAt
    FROM care.PersonAllergy AS pa
    JOIN care.Allergy AS a ON a.AllergyId = pa.AllergyId
    WHERE pa.PersonId = @PersonId
      AND pa.AllergyStatus = 'Active'
    ORDER BY a.AllergyName;

    SELECT m.MedicationName, pm.Dose, pm.Frequency, pm.StartedAt
    FROM care.PersonMedication AS pm
    JOIN care.Medication AS m ON m.MedicationId = pm.MedicationId
    WHERE pm.PersonId = @PersonId
      AND pm.MedicationStatus = 'Active'
    ORDER BY m.MedicationName;

    SELECT TOP (5)
        e.EncounterNumber, e.EncounterType, e.StartedAt, e.EndedAt, f.FacilityName
    FROM care.Encounter AS e
    JOIN ops.Facility AS f ON f.FacilityId = e.FacilityId
    WHERE e.PersonId = @PersonId
      AND e.EncounterId <> @EncounterId
    ORDER BY e.StartedAt DESC;

        SELECT s.SignalType, s.SignalValue, s.MatchOrdinal
        FROM ai.ExtractedSignal AS s
        JOIN ops.FieldNarrative AS n ON n.NarrativeId = s.NarrativeId
        WHERE n.EncounterId = @EncounterId
        ORDER BY s.SignalType, s.MatchOrdinal;
END;
GO

CREATE OR ALTER PROCEDURE ai.usp_ExtractSignals
    @TransferNumber varchar(30),
    @ReturnSignals bit = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @NarrativeId bigint;

    SELECT TOP (1) @NarrativeId = n.NarrativeId
    FROM ops.Transfer AS t
    JOIN ops.FieldNarrative AS n ON n.EncounterId = t.EncounterId
    WHERE t.TransferNumber = @TransferNumber
    ORDER BY n.RecordedAt DESC;

    IF @NarrativeId IS NULL
        THROW 50011, 'No field narrative was found for the transfer.', 1;

    BEGIN TRANSACTION;

    DELETE FROM ai.ExtractedSignal
    WHERE NarrativeId = @NarrativeId;

    INSERT ai.ExtractedSignal
        (NarrativeId, SignalRuleId, MatchOrdinal, SignalType, SignalValue,
         StartPosition, EndPosition)
    SELECT
        n.NarrativeId,
        r.SignalRuleId,
        matches.match_id,
        r.SignalType,
        CONVERT(nvarchar(1000), COALESCE(
            JSON_VALUE(CONVERT(nvarchar(max), matches.substring_matches), '$[0].value'),
            matches.match_value)),
        matches.start_position,
        matches.end_position
    FROM ops.FieldNarrative AS n
    CROSS JOIN ai.SignalRule AS r
    CROSS APPLY REGEXP_MATCHES(n.NarrativeText, r.Pattern, r.Flags) AS matches
    WHERE n.NarrativeId = @NarrativeId
      AND r.IsActive = 1;

    COMMIT TRANSACTION;

    IF @ReturnSignals = 1
    SELECT SignalType, SignalValue, MatchOrdinal, StartPosition, EndPosition
    FROM ai.ExtractedSignal
    WHERE NarrativeId = @NarrativeId
    ORDER BY SignalType, MatchOrdinal;
END;
GO

CREATE OR ALTER PROCEDURE ai.usp_CreateTransferPacket
    @TransferNumber varchar(30),
    @TransferPacketId bigint OUTPUT,
    @ReturnPacket bit = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TransferId bigint;
    DECLARE @EncounterId bigint;
    DECLARE @PersonId bigint;
    DECLARE @PacketVersion int;
    DECLARE @TransferJson nvarchar(max);
    DECLARE @PersonJson nvarchar(max);
    DECLARE @ObservationsJson nvarchar(max);
    DECLARE @AllergiesJson nvarchar(max);
    DECLARE @MedicationsJson nvarchar(max);
    DECLARE @RecentEncountersJson nvarchar(max);
    DECLARE @NarrativeJson nvarchar(max);
    DECLARE @SignalsJson nvarchar(max);
    DECLARE @PacketJson nvarchar(max);

    SELECT
        @TransferId = t.TransferId,
        @EncounterId = t.EncounterId,
        @PersonId = e.PersonId
    FROM ops.Transfer AS t
    JOIN care.Encounter AS e ON e.EncounterId = t.EncounterId
    WHERE t.TransferNumber = @TransferNumber;

    IF @TransferId IS NULL
        THROW 50012, 'Transfer not found.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM ai.ExtractedSignal AS s
        JOIN ops.FieldNarrative AS n ON n.NarrativeId = s.NarrativeId
        WHERE n.EncounterId = @EncounterId
    )
        EXEC ai.usp_ExtractSignals @TransferNumber = @TransferNumber, @ReturnSignals = 0;

    SET @TransferJson =
    (
        SELECT
            t.TransferNumber AS transferNumber,
            e.EncounterNumber AS encounterNumber,
            origin.FacilityName AS origin,
            destination.FacilityName AS destination,
            t.TransportUnit AS transportUnit,
            t.ChiefConcern AS chiefConcern,
            t.PriorityCode AS priority,
            t.TransferStatus AS [status],
            t.EstimatedArrivalAt AS estimatedArrivalAt,
            t.DestinationBay AS destinationBay,
            t.ReceivingTeamNotifiedAt AS receivingTeamNotifiedAt
        FROM ops.Transfer AS t
        JOIN care.Encounter AS e ON e.EncounterId = t.EncounterId
        JOIN ops.Facility AS origin ON origin.FacilityId = t.OriginFacilityId
        JOIN ops.Facility AS destination ON destination.FacilityId = t.DestinationFacilityId
        WHERE t.TransferId = @TransferId
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    SET @PersonJson =
    (
        SELECT
            p.RegionalRecordNumber AS regionalRecordNumber,
            p.GivenName AS givenName,
            p.FamilyName AS familyName,
            p.DateOfBirth AS dateOfBirth,
            p.AdministrativeSex AS administrativeSex
        FROM care.Person AS p
        WHERE p.PersonId = @PersonId
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    SET @ObservationsJson =
    (
        SELECT ObservationCode AS code, ObservationName AS [name], NumericValue AS numericValue,
               TextValue AS textValue, Unit AS unit, IsAlert AS isAlert, ObservedAt AS observedAt
        FROM care.Observation
        WHERE EncounterId = @EncounterId
        ORDER BY ObservedAt, ObservationId
        FOR JSON PATH
    );

    SET @AllergiesJson =
    (
        SELECT a.AllergyName AS [name], pa.Reaction AS reaction, pa.RecordedAt AS recordedAt
        FROM care.PersonAllergy AS pa
        JOIN care.Allergy AS a ON a.AllergyId = pa.AllergyId
        WHERE pa.PersonId = @PersonId AND pa.AllergyStatus = 'Active'
        ORDER BY a.AllergyName
        FOR JSON PATH
    );

    SET @MedicationsJson =
    (
        SELECT m.MedicationName AS [name], pm.Dose AS dose, pm.Frequency AS frequency
        FROM care.PersonMedication AS pm
        JOIN care.Medication AS m ON m.MedicationId = pm.MedicationId
        WHERE pm.PersonId = @PersonId AND pm.MedicationStatus = 'Active'
        ORDER BY m.MedicationName
        FOR JSON PATH
    );

    SET @RecentEncountersJson =
    (
        SELECT TOP (5)
            e.EncounterNumber AS encounterNumber, e.EncounterType AS encounterType,
            e.StartedAt AS startedAt, f.FacilityName AS facilityName
        FROM care.Encounter AS e
        JOIN ops.Facility AS f ON f.FacilityId = e.FacilityId
        WHERE e.PersonId = @PersonId AND e.EncounterId <> @EncounterId
        ORDER BY e.StartedAt DESC
        FOR JSON PATH
    );

    SET @NarrativeJson =
    (
        SELECT TOP (1)
            n.NarrativeText AS narrative, n.AuthoredBy AS authoredBy, n.RecordedAt AS recordedAt
        FROM ops.FieldNarrative AS n
        WHERE n.EncounterId = @EncounterId
        ORDER BY n.RecordedAt DESC
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    SET @SignalsJson =
    (
        SELECT s.SignalType AS [type], s.SignalValue AS [value], s.MatchOrdinal AS matchOrdinal
        FROM ai.ExtractedSignal AS s
        JOIN ops.FieldNarrative AS n ON n.NarrativeId = s.NarrativeId
        WHERE n.EncounterId = @EncounterId
        ORDER BY s.SignalType, s.MatchOrdinal
        FOR JSON PATH
    );

    SET @PacketJson =
    (
        SELECT
            JSON_QUERY(@TransferJson) AS transfer,
            JSON_QUERY(@PersonJson) AS person,
            JSON_QUERY(@ObservationsJson) AS observations,
            JSON_QUERY(@AllergiesJson) AS allergies,
            JSON_QUERY(@MedicationsJson) AS medications,
            JSON_QUERY(@RecentEncountersJson) AS recentEncounters,
            JSON_QUERY(@NarrativeJson) AS fieldNarrative,
            JSON_QUERY(@SignalsJson) AS extractedSignals
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    IF ISJSON(@PacketJson) <> 1
        THROW 50013, 'Transfer packet construction did not produce valid JSON.', 1;

    BEGIN TRANSACTION;

    SELECT @PacketVersion = ISNULL(MAX(PacketVersion), 0) + 1
    FROM ai.TransferPacket WITH (UPDLOCK, HOLDLOCK)
    WHERE TransferId = @TransferId;

    INSERT ai.TransferPacket
        (TransferId, PacketVersion, PacketJson, PacketHash)
    VALUES
        (@TransferId, @PacketVersion, CAST(@PacketJson AS json),
         HASHBYTES('SHA2_256', CONVERT(varbinary(max), @PacketJson)));

    SET @TransferPacketId = SCOPE_IDENTITY();

    INSERT ai.PacketSource
        (TransferPacketId, SourceType, SourceRecordKey, SourceVersion, SourceSummary, SourceHash)
    SELECT
        @TransferPacketId,
        source.SourceType,
        source.SourceRecordKey,
        CONVERT(nvarchar(50), @PacketVersion),
        source.SourceSummary,
        HASHBYTES('SHA2_256', CONVERT(varbinary(max), source.SourceSummary))
    FROM (VALUES
        ('Transfer', @TransferNumber, @TransferJson),
        ('Person', CONVERT(nvarchar(100), @PersonId), @PersonJson),
        ('Observations', CONVERT(nvarchar(100), @EncounterId), @ObservationsJson),
        ('Allergies', CONVERT(nvarchar(100), @PersonId), @AllergiesJson),
        ('Medications', CONVERT(nvarchar(100), @PersonId), @MedicationsJson),
        ('RecentEncounters', CONVERT(nvarchar(100), @PersonId), @RecentEncountersJson),
        ('FieldNarrative', CONVERT(nvarchar(100), @EncounterId), @NarrativeJson)
    ) AS source(SourceType, SourceRecordKey, SourceSummary);

    COMMIT TRANSACTION;

    IF @ReturnPacket = 1
    SELECT @TransferPacketId AS TransferPacketId, @PacketVersion AS PacketVersion,
           PacketHash, PacketJson
    FROM ai.TransferPacket
    WHERE TransferPacketId = @TransferPacketId;
END;
GO

CREATE OR ALTER PROCEDURE ai.usp_CreateTransferPacketWithHistory
    @TransferNumber varchar(30),
    @HistoricalNotes nvarchar(max),
    @TransferPacketId bigint OUTPUT,
    @ReturnPacket bit = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @TransferPacketId = NULL;
    IF @HistoricalNotes IS NULL OR ISJSON(@HistoricalNotes) <> 1
        THROW 50050, 'Historical selection must be a JSON array of note IDs and source versions.', 1;
    IF LEFT(LTRIM(@HistoricalNotes), 1) <> N'['
        OR (SELECT COUNT(*) FROM OPENJSON(@HistoricalNotes)) NOT BETWEEN 1 AND 3
        THROW 50050, 'Select between one and three historical notes.', 1;
    IF EXISTS (SELECT 1 FROM OPENJSON(@HistoricalNotes) WHERE type <> 5)
        THROW 50050, 'Each historical selection must be an object containing a note ID and source version.', 1;
    DECLARE @Raw TABLE (NoteId nvarchar(100), SourceVersion nvarchar(100));
    INSERT @Raw
    SELECT JSON_VALUE(value, '$.historicalNoteId'), JSON_VALUE(value, '$.sourceVersion')
    FROM OPENJSON(@HistoricalNotes);
    IF EXISTS (SELECT 1 FROM @Raw
               WHERE COALESCE(TRY_CONVERT(bigint, NoteId), 0) <= 0
                  OR SourceVersion IS NULL OR LEN(SourceVersion) <> 18
                  OR TRY_CONVERT(binary(8), SourceVersion, 1) IS NULL)
        OR EXISTS (SELECT TRY_CONVERT(bigint, NoteId) FROM @Raw
                   GROUP BY TRY_CONVERT(bigint, NoteId) HAVING COUNT(*) > 1)
        THROW 50050, 'Historical selections require unique positive note IDs and valid source versions.', 1;

    DECLARE @Selected TABLE (NoteId bigint PRIMARY KEY, SourceVersion binary(8));
    INSERT @Selected SELECT CONVERT(bigint, NoteId), CONVERT(binary(8), SourceVersion, 1) FROM @Raw;
    DECLARE @PersonId bigint, @StartedAt datetime2(3), @PacketJson nvarchar(max), @HistoryJson nvarchar(max);
    DECLARE @Snapshot TABLE (NoteId bigint PRIMARY KEY, SourceJson nvarchar(max), Title nvarchar(200), RecordedAt datetime2(3));
    BEGIN TRY
        BEGIN TRANSACTION;
        SELECT @PersonId = e.PersonId, @StartedAt = e.StartedAt
        FROM ops.Transfer AS t WITH (HOLDLOCK)
        JOIN care.Encounter AS e WITH (HOLDLOCK) ON e.EncounterId = t.EncounterId
        WHERE t.TransferNumber = @TransferNumber;
        IF @PersonId IS NULL
            THROW 50046, 'Unknown transfer number.', 1;
        IF EXISTS (SELECT 1 FROM @Selected AS s
                   LEFT JOIN care.HistoricalNote AS n WITH (HOLDLOCK) ON n.HistoricalNoteId = s.NoteId
                   WHERE n.HistoricalNoteId IS NULL OR n.PersonId <> @PersonId OR n.RecordedAt >= @StartedAt)
            THROW 50050, 'Selected historical notes must belong to this patient and predate the transfer.', 1;
        IF EXISTS (SELECT 1 FROM @Selected AS s
                   JOIN care.HistoricalNote AS n WITH (HOLDLOCK) ON n.HistoricalNoteId = s.NoteId
                   LEFT JOIN ai.HistoricalNoteEmbedding AS e WITH (HOLDLOCK) ON e.HistoricalNoteId = n.HistoricalNoteId
                   WHERE n.NoteVersion <> s.SourceVersion OR e.HistoricalNoteId IS NULL
                      OR e.ModelId <> 'nemotron-3-embed-1b-bf16'
                      OR e.ContentHash <> HASHBYTES('SHA2_256', CONVERT(nvarchar(max), N'passage: ') + n.NoteText))
            THROW 50051, 'Selected history changed or its embedding is stale; refresh history and select again.', 1;

        INSERT @Snapshot
        SELECT n.HistoricalNoteId,
            (SELECT n.HistoricalNoteId AS noteId, n.SourceCode AS sourceCode,
                    CONVERT(varchar(18), CONVERT(binary(8), n.NoteVersion), 1) AS sourceVersion,
                    n.RecordedAt AS recordedAt, n.Title AS title, n.AuthoredBy AS authoredBy,
                    n.NoteText AS noteText, n.IsSynthetic AS isSynthetic
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            n.Title, n.RecordedAt
        FROM care.HistoricalNote AS n JOIN @Selected AS s ON s.NoteId = n.HistoricalNoteId;
        SET @HistoryJson = N'[' + (SELECT STRING_AGG(CONVERT(nvarchar(max), SourceJson), N',')
                                  WITHIN GROUP (ORDER BY NoteId) FROM @Snapshot) + N']';

        EXEC ai.usp_CreateTransferPacket @TransferNumber, @TransferPacketId OUTPUT, @ReturnPacket = 0;
        SELECT @PacketJson = CONVERT(nvarchar(max), PacketJson)
        FROM ai.TransferPacket WHERE TransferPacketId = @TransferPacketId;
        SET @PacketJson = JSON_MODIFY(@PacketJson, '$.historicalContext', JSON_QUERY(@HistoryJson));
        UPDATE ai.TransferPacket
        SET PacketJson = CAST(@PacketJson AS json),
            PacketHash = HASHBYTES('SHA2_256', CONVERT(varbinary(max), @PacketJson))
        WHERE TransferPacketId = @TransferPacketId;
        INSERT ai.PacketSource
            (TransferPacketId, SourceType, SourceRecordKey, SourceVersion, SourceSummary, SourceHash)
        SELECT @TransferPacketId, 'HistoricalNote', CONVERT(nvarchar(100), NoteId),
            JSON_VALUE(SourceJson, '$.sourceVersion'),
            CONVERT(nvarchar(30), RecordedAt, 126) + N' - ' + Title,
            HASHBYTES('SHA2_256', CONVERT(varbinary(max), SourceJson))
        FROM @Snapshot;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;
        SET @TransferPacketId = NULL;
        THROW;
    END CATCH;
    IF @ReturnPacket = 1
    SELECT TransferPacketId, PacketVersion, PacketHash, PacketJson
    FROM ai.TransferPacket WHERE TransferPacketId = @TransferPacketId;
END;
GO

CREATE OR ALTER PROCEDURE ai.usp_SaveTransferBriefing
    @ModelInvocationId bigint,
    @TransferPacketId bigint,
    @SkillName sysname,
    @SkillVersion varchar(30),
    @ModelId nvarchar(256),
    @CompletionUrl nvarchar(4000),
    @PacketJson json,
    @ResponseJson nvarchar(max),
    @ReturnCode int,
    @HttpStatusCode int,
    @StartedAt datetime2(3),
    @BriefingId bigint OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @AssistantContent nvarchar(max), @FinishReason nvarchar(30);
    DECLARE @HistoryCount int = (SELECT COUNT(*) FROM OPENJSON(CONVERT(nvarchar(max), @PacketJson), '$.historicalContext'));
        SELECT TOP (1) @AssistantContent = content, @FinishReason = finish_reason
        FROM OPENJSON(@ResponseJson, '$.result.choices')
        WITH (
            content nvarchar(max) '$.message.content',
            finish_reason nvarchar(30) '$.finish_reason'
        );

        IF @ReturnCode <> 0 OR @HttpStatusCode NOT BETWEEN 200 AND 299
            THROW 50024, 'Foundry Local returned an unsuccessful response.', 1;

        IF @FinishReason = N'length'
            THROW 50032, 'The model exhausted its token budget before completing the briefing JSON.', 1;

        IF ISJSON(@AssistantContent) <> 1
            THROW 50025, 'The model response was not valid JSON.', 1;

        IF NULLIF(JSON_VALUE(@AssistantContent, '$.summary'), N'') IS NULL
           OR JSON_QUERY(@AssistantContent, '$.keyContext') IS NULL
           OR JSON_QUERY(@AssistantContent, '$.confirmOnArrival') IS NULL
            THROW 50026, 'The model response does not match the skill output contract.', 1;

        IF @SkillName = N'ReceivingBriefing' AND @SkillVersion = '2.0'
           AND (LEFT(LTRIM(JSON_QUERY(@AssistantContent, '$.confirmOnArrival')), 1) <> N'['
                OR (SELECT COUNT(*) FROM OPENJSON(@AssistantContent, '$.confirmOnArrival')) NOT BETWEEN 2 AND 4
                OR EXISTS (
                    SELECT 1 FROM OPENJSON(@AssistantContent, '$.confirmOnArrival')
                    WHERE type <> 1 OR NULLIF(LTRIM(RTRIM([value])), N'') IS NULL
                       OR DATALENGTH([value]) > 2000))
            THROW 50026, 'Receiving briefing requires 2 to 4 nonempty receiving recommendations up to 1000 characters each.', 1;

        IF @SkillName = N'ReceivingBriefing' AND @SkillVersion = '2.0'
           AND EXISTS (
               SELECT 1 FROM OPENJSON(@AssistantContent, '$.confirmOnArrival')
               WHERE LTRIM(RTRIM([value])) IN (N'summary', N'keyContext', N'confirmOnArrival', N'historicalContext', N'string')
                  OR [value] LIKE N'%1.[ ]%2.[ ]%')
            THROW 50026, 'Return each receiving recommendation as a separate unnumbered item, not field names or a combined numbered list.', 1;

        DECLARE @HistoryItems TABLE (NoteId bigint, ItemText nvarchar(max));
        IF @HistoryCount > 0
        BEGIN
            DECLARE @HistoryOutput nvarchar(max) = JSON_QUERY(@AssistantContent, '$.historicalContext');
            IF @HistoryOutput IS NULL OR LEFT(LTRIM(@HistoryOutput), 1) <> N'['
                THROW 50053, 'Historical briefing response requires a historicalContext array.', 1;
            INSERT @HistoryItems
            SELECT NoteId, ItemText FROM OPENJSON(@HistoryOutput)
            WITH (NoteId bigint '$.noteId', ItemText nvarchar(max) '$.text');
            IF (SELECT COUNT(*) FROM @HistoryItems) <> @HistoryCount
                OR EXISTS (SELECT NoteId FROM @HistoryItems GROUP BY NoteId HAVING COUNT(*) <> 1)
                OR EXISTS (SELECT 1 FROM @HistoryItems AS h
                           WHERE h.NoteId IS NULL OR NULLIF(LTRIM(RTRIM(h.ItemText)), N'') IS NULL
                             OR DATALENGTH(h.ItemText) > 2000
                             OR NOT EXISTS (SELECT 1 FROM ai.PacketSource AS s
                                            WHERE s.TransferPacketId = @TransferPacketId
                                              AND s.SourceType = 'HistoricalNote'
                                              AND s.SourceRecordKey = CONVERT(nvarchar(100), h.NoteId)))
                THROW 50053, 'Historical response must cite each supplied note exactly once with nonempty text up to 1000 characters.', 1;
        END;

        BEGIN TRANSACTION;

        UPDATE ai.ModelInvocation
        SET ResponseJson = @ResponseJson,
            ReturnCode = @ReturnCode,
            HttpStatusCode = @HttpStatusCode,
            InvocationStatus = 'Succeeded',
            CompletedAt = SYSUTCDATETIME(),
            DurationMs = DATEDIFF_BIG(millisecond, @StartedAt, SYSUTCDATETIME())
        WHERE ModelInvocationId = @ModelInvocationId;

        INSERT ai.Briefing (ModelInvocationId, Summary)
        VALUES (@ModelInvocationId, JSON_VALUE(@AssistantContent, '$.summary'));

        SET @BriefingId = SCOPE_IDENTITY();

        INSERT ai.BriefingItem (BriefingId, SectionName, DisplayOrder, ItemText)
        SELECT @BriefingId, 'KeyContext', CONVERT(smallint, [key] + 1), CONVERT(nvarchar(1000), [value])
        FROM OPENJSON(@AssistantContent, '$.keyContext');

        INSERT ai.BriefingItem (BriefingId, SectionName, DisplayOrder, ItemText)
        SELECT @BriefingId, 'ConfirmOnArrival', CONVERT(smallint, [key] + 1), CONVERT(nvarchar(1000), [value])
        FROM OPENJSON(@AssistantContent, '$.confirmOnArrival');

        INSERT ai.BriefingItem (BriefingId, SectionName, DisplayOrder, ItemText, PacketSourceId)
        SELECT @BriefingId, 'HistoricalContext', CONVERT(smallint, ROW_NUMBER() OVER (ORDER BY h.NoteId)),
            h.ItemText, s.PacketSourceId
        FROM @HistoryItems AS h JOIN ai.PacketSource AS s
          ON s.TransferPacketId = @TransferPacketId AND s.SourceType = 'HistoricalNote'
         AND s.SourceRecordKey = CONVERT(nvarchar(100), h.NoteId);

        INSERT ai.BriefingSource (BriefingId, PacketSourceId, CitationOrder)
        SELECT @BriefingId, PacketSourceId,
               CONVERT(smallint, ROW_NUMBER() OVER (ORDER BY PacketSourceId))
        FROM ai.PacketSource
        WHERE TransferPacketId = @TransferPacketId;

        EXEC ai.usp_WriteModelInvocationAudit
            @ModelInvocationId, @PacketJson, @SkillName, @SkillVersion,
            @ModelId, @CompletionUrl, @BriefingId;

        COMMIT TRANSACTION;
END;
GO
