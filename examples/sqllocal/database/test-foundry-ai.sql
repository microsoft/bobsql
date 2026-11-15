/* ============================================================================
   Caldova Regional Care Transfer Center
   test-foundry-ai.sql : live Foundry skill invocation smoke test
   ============================================================================ */

USE [CaldovaRegionalCare];
GO

SET NOCOUNT ON;

DECLARE @TransferPacketId bigint;
DECLARE @BriefingId bigint;

SELECT TOP (1) @TransferPacketId = packet.TransferPacketId
FROM ai.TransferPacket AS packet
JOIN ops.Transfer AS transfer ON transfer.TransferId = packet.TransferId
WHERE transfer.TransferNumber = 'TR-2026-0147'
ORDER BY packet.PacketVersion DESC;

IF @TransferPacketId IS NULL
    EXEC ai.usp_CreateTransferPacket
        @TransferNumber = 'TR-2026-0147',
        @TransferPacketId = @TransferPacketId OUTPUT;

EXEC ai.usp_InvokeTransferSkill
    @TransferPacketId = @TransferPacketId,
    @SkillName = N'ReceivingBriefing',
    @SkillVersion = '2.0',
    @BriefingId = @BriefingId OUTPUT;

IF @BriefingId IS NULL
    THROW 50030, 'The live invocation did not create a briefing.', 1;

IF (SELECT COUNT(*) FROM ai.BriefingSource WHERE BriefingId = @BriefingId) <> 7
    THROW 50031, 'The briefing does not retain all seven grounding sources.', 1;

SELECT
    @BriefingId AS BriefingId,
    endpoint.ModelId,
    invocation.HttpStatusCode,
    invocation.DurationMs,
    briefing.Summary,
    (SELECT COUNT(*) FROM ai.BriefingItem WHERE BriefingId = @BriefingId) AS BriefingItemCount,
    (SELECT COUNT(*) FROM ai.BriefingSource WHERE BriefingId = @BriefingId) AS GroundingSourceCount
FROM ai.Briefing AS briefing
JOIN ai.ModelInvocation AS invocation
  ON invocation.ModelInvocationId = briefing.ModelInvocationId
JOIN ai.ModelEndpoint AS endpoint
  ON endpoint.ModelEndpointId = invocation.ModelEndpointId
WHERE briefing.BriefingId = @BriefingId;
GO