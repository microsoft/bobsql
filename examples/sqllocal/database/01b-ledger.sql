/* 01b-ledger.sql : append-only AI interaction ledger and its writer. */
USE CaldovaRegionalCare;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'ai.ModelInvocationAudit', N'U') IS NULL
BEGIN
    CREATE TABLE ai.ModelInvocationAudit
    (
        ModelInvocationId bigint NOT NULL,
        TransferPacketId  bigint NOT NULL,
        TransferNumber    varchar(30) NOT NULL,
        SkillName         sysname NOT NULL,
        SkillVersion      varchar(30) NOT NULL,
        ModelId           nvarchar(256) NOT NULL,
        CompletionUrl     nvarchar(4000) NOT NULL,
        SkillJson         nvarchar(max) NOT NULL,
        RequestJson       nvarchar(max) NOT NULL,
        ResponseJson      nvarchar(max) NULL,
        InvocationStatus  varchar(20) NOT NULL,
        StartedAt         datetime2(3) NOT NULL,
        CompletedAt       datetime2(3) NOT NULL,
        DurationMs        bigint NOT NULL,
        ReturnCode        int NULL,
        HttpStatusCode    int NULL,
        ErrorMessage      nvarchar(2000) NULL,
        BriefingId        bigint NULL,
        CONSTRAINT PK_ModelInvocationAudit PRIMARY KEY CLUSTERED (ModelInvocationId),
        CONSTRAINT CK_ModelInvocationAudit_Status CHECK (InvocationStatus IN ('Succeeded', 'Failed'))
    )
    WITH (LEDGER = ON (APPEND_ONLY = ON));

    CREATE INDEX IX_ModelInvocationAudit_Transfer
        ON ai.ModelInvocationAudit(TransferNumber, ModelInvocationId DESC);
END;
IF NOT EXISTS (
    SELECT 1 FROM sys.tables
    WHERE object_id = OBJECT_ID(N'ai.ModelInvocationAudit') AND ledger_type = 3
)
    THROW 50054, 'ai.ModelInvocationAudit must be an append-only ledger table.', 1;
GO

CREATE OR ALTER PROCEDURE ai.usp_WriteModelInvocationAudit
    @ModelInvocationId bigint,
    @PacketJson json,
    @SkillName sysname,
    @SkillVersion varchar(30),
    @ModelId nvarchar(256),
    @CompletionUrl nvarchar(4000),
    @BriefingId bigint = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT ai.ModelInvocationAudit
        (ModelInvocationId, TransferPacketId, TransferNumber, SkillName, SkillVersion,
         ModelId, CompletionUrl, SkillJson, RequestJson, ResponseJson, InvocationStatus,
         StartedAt, CompletedAt, DurationMs, ReturnCode, HttpStatusCode, ErrorMessage, BriefingId)
    SELECT ModelInvocationId, TransferPacketId,
           JSON_VALUE(CONVERT(nvarchar(max), @PacketJson), '$.transfer.transferNumber'),
           @SkillName, @SkillVersion, @ModelId, @CompletionUrl, SkillJson, RequestJson,
           ResponseJson, InvocationStatus, StartedAt, CompletedAt, DurationMs,
           ReturnCode, HttpStatusCode, ErrorMessage, @BriefingId
    FROM ai.ModelInvocation
    WHERE ModelInvocationId = @ModelInvocationId;

    IF @@ROWCOUNT <> 1
        THROW 50054, 'Expected one model invocation to write to the audit ledger.', 1;
END;
GO
