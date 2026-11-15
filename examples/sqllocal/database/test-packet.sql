/* ============================================================================
   Caldova Regional Care Transfer Center
   test-packet.sql : regex and grounded packet behavior smoke test
   ============================================================================ */

USE [CaldovaRegionalCare];
GO

SET NOCOUNT ON;

EXEC ai.usp_ExtractSignals @TransferNumber = 'TR-2026-0147';

DECLARE @TransferPacketId bigint;

EXEC ai.usp_CreateTransferPacket
    @TransferNumber = 'TR-2026-0147',
    @TransferPacketId = @TransferPacketId OUTPUT;

DECLARE @ExtractedSignalCount int =
(
    SELECT COUNT(*)
    FROM ai.ExtractedSignal AS s
    JOIN ops.FieldNarrative AS n ON n.NarrativeId = s.NarrativeId
    JOIN ops.Transfer AS t ON t.EncounterId = n.EncounterId
    WHERE t.TransferNumber = 'TR-2026-0147'
);

DECLARE @PacketSourceCount int =
(
    SELECT COUNT(*)
    FROM ai.PacketSource
    WHERE TransferPacketId = @TransferPacketId
);

DECLARE @PacketJson json =
(
    SELECT PacketJson
    FROM ai.TransferPacket
    WHERE TransferPacketId = @TransferPacketId
);

DECLARE @VectorColumnCount int =
(
    SELECT COUNT(*)
    FROM sys.columns
    WHERE system_type_id = TYPE_ID(N'vector')
);

IF @ExtractedSignalCount <> 6
    THROW 50020, 'Expected six extracted signal matches for Maria.', 1;

IF @PacketSourceCount <> 7
    THROW 50021, 'Expected exactly seven grounding sources.', 1;

IF ISJSON(@PacketJson) <> 1
    THROW 50022, 'Transfer packet is not valid JSON.', 1;

IF JSON_VALUE(@PacketJson, '$.transfer.encounterNumber') <> 'RC-2026-09147'
    THROW 50023, 'Transfer packet contains the wrong encounter.', 1;

IF JSON_VALUE(@PacketJson, '$.person.regionalRecordNumber') <> 'CR-804921'
    THROW 50024, 'Transfer packet contains the wrong person.', 1;

IF @VectorColumnCount <> 0
    THROW 50025, 'Vector columns are not permitted in this database.', 1;

SELECT
    @TransferPacketId AS TransferPacketId,
    @ExtractedSignalCount AS ExtractedSignalCount,
    @PacketSourceCount AS PacketSourceCount,
    @VectorColumnCount AS VectorColumnCount,
    JSON_VALUE(@PacketJson, '$.transfer.encounterNumber') AS EncounterNumber,
    JSON_VALUE(@PacketJson, '$.person.regionalRecordNumber') AS RegionalRecordNumber;
GO