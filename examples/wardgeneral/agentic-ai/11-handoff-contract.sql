/* ============================================================================
    11-handoff-contract.sql  —  the Agentic AI task contract

   WHAT THIS ADDS
   --------------------------------------------------------------------------
   The Agentic AI agent does one real piece of WORK: it prepares a shift handoff
   for a patient and asks the clinician to save it. That task needs somewhere to
   land, and Getting Started did not ship one:

     1. clinical.AgentRecommendation      what the agent proposed, and its fate
     2. UQ_AgentRec_RequestKey            a UNIQUE index over the request key
     3. clinical.SaveShiftHandoff         the only sanctioned write path

   WHY SBAR AS FOUR COLUMNS, NOT ONE BLOB
   --------------------------------------------------------------------------
   Situation, Background, Assessment, Recommendation is a fixed, standardized
   structure that clinicians already use out loud at every shift change. Storing
   it as four named columns rather than one JSON document means the shape is
   enforced by the table instead of by the model, and it gives Security four
   distinct things to classify and mask. A blob would have taught nothing.

    WHY REQUESTKEY IS NOT NULL
    --------------------------------------------------------------------------
    This table is new and empty. Every row in it is agent-proposed, so every row
    must carry the caller's idempotency key. The unique index turns that key into
    an engine-enforced guarantee rather than a prompt convention.

   WHY Status IS MUTABLE — AND WHY THIS IS NOT A LEDGER TABLE
   --------------------------------------------------------------------------
   Status moves Proposed -> Approved / Rejected -> Executed. That is workflow
   state, and workflow state changes. An append-only ledger table would block
   the UPDATE by design, which is exactly why Security uses this table as its
   counter-example: ledger fits immutable facts, not decisions that evolve.
   Agentic AI only ever writes 'Proposed'; the transitions are Security's.

   WHY THE PROCEDURE, NOT A TABLE GRANT
   --------------------------------------------------------------------------
   Same rule as the imaging contract. The procedure takes an EncounterId and
   DERIVES PatientId from it, so patient identity is never a model-supplied
    value. Agentic AI has no authenticated clinician, so the procedure attributes
    every handoff to the system provider seeded below. Security owns replacing
    that with authenticated identity and row-level authorization.

   RERUNNABLE. Safe to execute more than once.
   All data is synthetic — no real PHI.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

/* ---- Upgrade cleanup ----------------------------------------------------- */
/* Earlier Agentic AI iterations configured unused DAB entities behind wrapper
   procedures. They are not part of the final area contract.

   NOTE: clinical.PlaceImagingOrder is deliberately NOT dropped here. Script 14
   deploys it on purpose as ordering plumbing the application never calls. An
   earlier revision of this file removed it, which made 11 and 14 fight over the
   same objects depending on run order. */
DROP PROCEDURE IF EXISTS clinical.SetAgentAccessContext;
DROP PROCEDURE IF EXISTS clinical.GetPatientChartApi;
DROP PROCEDURE IF EXISTS clinical.GetPatientChartByBedApi;
DROP PROCEDURE IF EXISTS clinical.SearchEncountersApi;
DROP PROCEDURE IF EXISTS clinical.AdmitPatientApi;
DROP PROCEDURE IF EXISTS clinical.FileLabResultApi;
GO

/* ---- 1. The table -------------------------------------------------------- */
IF OBJECT_ID('clinical.AgentRecommendation', 'U') IS NULL
BEGIN
    CREATE TABLE clinical.AgentRecommendation
    (
        RecommendationId INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_AgentRecommendation PRIMARY KEY,
        EncounterId      INT              NOT NULL
            CONSTRAINT FK_AgentRec_Encounter REFERENCES clinical.Encounter (EncounterId),
        PatientId        INT              NOT NULL
            CONSTRAINT FK_AgentRec_Patient   REFERENCES clinical.Patient (PatientId),
        Kind             NVARCHAR(30)     NOT NULL
            CONSTRAINT CK_AgentRec_Kind CHECK (Kind IN (N'ShiftHandoff')),
        Situation        NVARCHAR(MAX)    NULL,
        Background       NVARCHAR(MAX)    NULL,
        Assessment       NVARCHAR(MAX)    NULL,
        Recommendation   NVARCHAR(MAX)    NULL,
        Status           NVARCHAR(20)     NOT NULL
            CONSTRAINT DF_AgentRec_Status DEFAULT (N'Proposed')
            CONSTRAINT CK_AgentRec_Status CHECK (Status IN (N'Proposed', N'Approved', N'Rejected', N'Executed')),
        ProposedById     INT              NOT NULL
            CONSTRAINT FK_AgentRec_Provider REFERENCES ops.Provider (ProviderId),
        ProposedAt       DATETIME2(3)     NOT NULL
            CONSTRAINT DF_AgentRec_ProposedAt DEFAULT (SYSUTCDATETIME()),
        DecidedAt        DATETIME2(3)     NULL,
        RequestKey       UNIQUEIDENTIFIER NOT NULL
    );
END;
GO

/* ---- 2. The idempotency guarantee ---------------------------------------- */
/* Not the procedure's NOT EXISTS check — that alone still races. This index
   is what makes a re-approved handoff impossible to duplicate.               */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'UQ_AgentRec_RequestKey'
                 AND object_id = OBJECT_ID('clinical.AgentRecommendation'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UQ_AgentRec_RequestKey
        ON clinical.AgentRecommendation (RequestKey);
END;
GO

/* ---- 3. Read path for the handoff the clinician just saved --------------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_AgentRec_Encounter'
                 AND object_id = OBJECT_ID('clinical.AgentRecommendation'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_AgentRec_Encounter
        ON clinical.AgentRecommendation (EncounterId, ProposedAt DESC);
END;
GO

/* ---- 4. The identity a handoff is attributed to when no human is signed in

   Agentic AI has no authentication. Anyone who can reach the application can use
    it, and there is no signed-in clinician to attribute a handoff to.

   ProposedById is NOT NULL with an FK, because a clinical handoff with no author
   is not a handoff. So the application needs *something* true to write. This row
   is it: a non-human provider standing for "the Ward General application
   proposed this on behalf of an unauthenticated session".

   That is a fact, not a placeholder. Naming a real clinician here would forge
   authorship on a clinical document, and leaving the column nullable would let
   the record claim nothing at all.

    Security adds authenticated transport and row-level authorization but keeps
    this system attribution for agent-proposed handoffs.

   Seeded here rather than in Getting Started so re-running the Getting Started seed and its
   row counts stay exactly as that area published them. The row carries
   Role = 'System' and no EntraObjectId, so Security's RLS predicate matches no
   encounter for it and the "Viewing as" list — which loads attendings holding
   active patients — never shows it.                                          */
IF NOT EXISTS (SELECT 1 FROM ops.Provider WHERE FullName = N'Ward General Assistant (system)')
BEGIN
    INSERT INTO ops.Provider (FullName, DepartmentId, Role, EntraObjectId)
    SELECT N'Ward General Assistant (system)', MIN(d.DepartmentId), N'System', NULL
    FROM ops.Department AS d;
END;
GO

/* ---- 5. The only sanctioned write path ----------------------------------- */
CREATE OR ALTER PROCEDURE clinical.SaveShiftHandoff
    @EncounterId      INT,
    @Situation        NVARCHAR(MAX),
    @Background       NVARCHAR(MAX),
    @Assessment       NVARCHAR(MAX),
    @Recommendation   NVARCHAR(MAX),
    @RequestKey       UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    /* The key is the whole idempotency story. Without one, a retried approval
       writes a second handoff, so this is a hard error rather than a default. */
    IF @RequestKey IS NULL
        THROW 50071, 'A request key is required. The caller must supply one GUID per handoff and reuse it on retry.', 1;

    DECLARE @ProposedById INT;

    SELECT @ProposedById = ProviderId
    FROM ops.Provider
    WHERE FullName = N'Ward General Assistant (system)';

    IF NOT EXISTS (SELECT 1 FROM ops.Provider WHERE ProviderId = @ProposedById)
        THROW 50072, 'The proposing provider does not exist.', 1;

    DECLARE @inserted INT;

    /* One statement, already atomic — no outer transaction. PatientId is read
       from the encounter, never accepted from the caller. Under Security's
       policy an invisible encounter simply produces no row here, so "not
       yours", "discharged" and "does not exist" are indistinguishable. */
    INSERT INTO clinical.AgentRecommendation
        (EncounterId, PatientId, Kind, Situation, Background, Assessment, Recommendation, ProposedById, RequestKey)
    SELECT
        e.EncounterId, e.PatientId, N'ShiftHandoff',
        @Situation, @Background, @Assessment, @Recommendation,
        @ProposedById, @RequestKey
    FROM clinical.Encounter AS e
    WHERE e.EncounterId = @EncounterId
      AND e.Status      = N'Active'
      AND NOT EXISTS (SELECT 1 FROM clinical.AgentRecommendation AS x
                      WHERE x.RequestKey = @RequestKey);

    SET @inserted = @@ROWCOUNT;

    IF @inserted = 0 AND NOT EXISTS (SELECT 1 FROM clinical.AgentRecommendation WHERE RequestKey = @RequestKey)
        THROW 50073, 'No handoff was saved. The encounter does not exist or is not active.', 1;

    SELECT
        r.RecommendationId, r.EncounterId, r.PatientId, r.Kind, r.Status,
        r.ProposedById, r.ProposedAt, r.RequestKey,
        CAST(@inserted AS BIT) AS Created
    FROM clinical.AgentRecommendation AS r
    WHERE r.RequestKey = @RequestKey;
END;
GO
