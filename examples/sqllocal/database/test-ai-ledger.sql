USE [CaldovaRegionalCare];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.tables
    WHERE object_id = OBJECT_ID(N'ai.ModelInvocationAudit') AND ledger_type = 3
)
    THROW 50991, 'Expected an append-only AI audit ledger table.', 1;

BEGIN TRY
    EXEC ai.usp_WriteModelInvocationAudit
        @ModelInvocationId = -1, @PacketJson = N'{}',
        @SkillName = N'ReceivingBriefing', @SkillVersion = '2.0',
        @ModelId = N'gpt-oss-20b', @CompletionUrl = N'https://validation.invalid';
    THROW 50991, 'Ledger writer must reject a missing invocation.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 50054 THROW;
END CATCH;

DECLARE @PacketId bigint;
DECLARE @BriefingId bigint;
SELECT TOP (1) @PacketId = TransferPacketId
FROM ai.TransferPacket
WHERE JSON_VALUE(CONVERT(nvarchar(max), PacketJson), '$.transfer.transferNumber') = 'TR-2026-0147'
  AND NOT EXISTS (SELECT 1 FROM OPENJSON(CONVERT(nvarchar(max), PacketJson), '$.historicalContext'))
ORDER BY TransferPacketId DESC;
IF @PacketId IS NULL
    THROW 50991, 'Create a standard TR-2026-0147 transfer packet before running this test.', 1;

EXEC ai.usp_InvokeTransferSkill @TransferPacketId = @PacketId,
    @SkillName = N'ReceivingBriefing', @SkillVersion = '2.0', @BriefingId = @BriefingId OUTPUT;

IF NOT EXISTS (
    SELECT 1 FROM ai.ModelInvocationAudit AS a
    JOIN ai.ModelInvocation AS i ON i.ModelInvocationId = a.ModelInvocationId
    WHERE a.BriefingId = @BriefingId AND a.InvocationStatus = 'Succeeded'
      AND a.HttpStatusCode = 200 AND a.TransferNumber = 'TR-2026-0147'
      AND a.RequestJson = i.RequestJson AND a.ResponseJson = i.ResponseJson
      AND a.SkillJson = i.SkillJson AND a.ledger_start_transaction_id IS NOT NULL
)
    THROW 50991, 'The successful briefing was not snapshotted in the ledger.', 1;

IF EXISTS (
    SELECT 1 FROM ai.ModelInvocationAudit
    WHERE BriefingId = @BriefingId AND ModelId = N'gpt-oss-20b'
      AND ISNULL(JSON_VALUE(RequestJson, '$.response_format.type'), '') <> 'json_schema'
)
    THROW 50991, 'GPT briefing requests must enforce structured JSON output.', 1;

DECLARE @Rejected bit = 0;
BEGIN TRY
    EXEC sys.sp_executesql N'UPDATE ai.ModelInvocationAudit SET ModelId = ModelId WHERE BriefingId = @Id;',
        N'@Id bigint', @Id = @BriefingId;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 37359 THROW;
    SET @Rejected = 1;
END CATCH;
IF @Rejected = 0 THROW 50991, 'Ledger UPDATE unexpectedly succeeded.', 1;

SET @Rejected = 0;
BEGIN TRY
    EXEC sys.sp_executesql N'DELETE FROM ai.ModelInvocationAudit WHERE BriefingId = @Id;',
        N'@Id bigint', @Id = @BriefingId;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 37359 THROW;
    SET @Rejected = 1;
END CATCH;
IF @Rejected = 0 THROW 50991, 'Ledger DELETE unexpectedly succeeded.', 1;

-- Only this test session's briefing insert fails; other callers are unaffected.
IF OBJECT_ID(N'ai.trg_TestLedgerFailure', N'TR') IS NOT NULL
    THROW 50991, 'A ledger failure test is already installed. No replacement was made.', 1;
EXEC sys.sp_executesql N'
CREATE TRIGGER ai.trg_TestLedgerFailure ON ai.Briefing AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    IF CONTEXT_INFO() = 0x43414C444F56414C4544474552
        THROW 50990, ''Intentional session-scoped ledger failure test.'', 1;
END;';

DECLARE @BeforeFailure bigint = (SELECT MAX(ModelInvocationId) FROM ai.ModelInvocation);
DECLARE @PreviousContext varbinary(128) = COALESCE(CONTEXT_INFO(), 0x);
BEGIN TRY
    SET CONTEXT_INFO 0x43414C444F56414C4544474552;
    SET @Rejected = 0;
    BEGIN TRY
        EXEC ai.usp_InvokeTransferSkill @TransferPacketId = @PacketId,
            @SkillName = N'ReceivingBriefing', @SkillVersion = '2.0', @BriefingId = @BriefingId OUTPUT;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() <> 50990 THROW;
        SET @Rejected = 1;
    END CATCH;
    SET CONTEXT_INFO @PreviousContext;
    DROP TRIGGER ai.trg_TestLedgerFailure;

    IF @Rejected = 0 THROW 50991, 'Expected the test failure to propagate to the caller.', 1;
    IF NOT EXISTS (
        SELECT 1 FROM ai.ModelInvocationAudit AS a
        JOIN ai.ModelInvocation AS i ON i.ModelInvocationId = a.ModelInvocationId
        WHERE a.ModelInvocationId > @BeforeFailure AND a.TransferPacketId = @PacketId
          AND a.InvocationStatus = 'Failed' AND i.InvocationStatus = 'Failed'
          AND a.ErrorMessage = N'Intentional session-scoped ledger failure test.'
          AND a.BriefingId IS NULL AND a.HttpStatusCode = 200
          AND a.RequestJson = i.RequestJson AND a.ResponseJson = i.ResponseJson
          AND NOT EXISTS (SELECT 1 FROM ai.Briefing b WHERE b.ModelInvocationId = a.ModelInvocationId)
    )
        THROW 50991, 'The failed call was not preserved after briefing rollback.', 1;
END TRY
BEGIN CATCH
    SET CONTEXT_INFO @PreviousContext;
    IF OBJECT_ID(N'ai.trg_TestLedgerFailure', N'TR') IS NOT NULL
        DROP TRIGGER ai.trg_TestLedgerFailure;
    THROW;
END CATCH;

SELECT TOP (2) ModelInvocationId, TransferNumber, ModelId, InvocationStatus,
    HttpStatusCode, DurationMs, BriefingId, ErrorMessage, ledger_start_transaction_id
FROM ai.ModelInvocationAudit
WHERE TransferPacketId = @PacketId
ORDER BY ModelInvocationId DESC;
PRINT 'AI ledger success, failure, UPDATE rejection, and DELETE rejection tests passed.';
GO
