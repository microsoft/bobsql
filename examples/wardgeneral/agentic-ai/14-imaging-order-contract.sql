/* ============================================================================
   14-imaging-order-contract.sql  —  ordering plumbing the app does not use

   WHAT THIS ADDS, AND WHY IT IS NOT WIRED UP
   --------------------------------------------------------------------------
   This script deploys a complete, production-shaped write path for imaging
   orders — and Agentic AI then deliberately never calls it. Nothing in the
   application, the DAB configuration, or the agent's tool inventory reaches
   it. The reader can run every Agentic AI demo start to finish and this
   procedure will execute zero times.

   That is the point. Agentic AI's argument is about the distance between a
   capability existing in the database and an agent being allowed to invoke
   it. Those are separate decisions, made in separate places, and an area
   that only ever shows tools the agent *can* call cannot make that argument.
   The one write the agent does perform is clinical.SaveShiftHandoff, which
   writes a DOCUMENT ABOUT care (script 11). This one would write an
   INSTRUCTION TO DELIVER care. Same approval mechanism, categorically
   different consequence — which is exactly why the second one stays behind
   glass.

   Three objects, none of which Getting Started shipped:

     1. clinical.ImagingOrder.RequestKey   a caller-supplied idempotency key
     2. UQ_Imaging_RequestKey              a FILTERED unique index over it
     3. clinical.PlaceImagingOrder         the only sanctioned write path

   WHERE THIS GOES NEXT
   --------------------------------------------------------------------------
   Agentic AI discusses — without building — what exposing this would take: a
   DAB entity publishing it as an MCP tool, registration in the agent's
   approval-required list, and a runtime Agent Skill describing when an order
   is warranted. Area 11 picks up the other end, and shows how new rows in
   clinical.ImagingOrder could be consumed with Change Event Streaming to feed
   a hospital imaging system. Neither the tool nor that system is built in
   this project. An INSERT here is a record of an intent; it does not perform an
   X-ray, and nothing downstream is listening yet.

   WHY A NULLABLE COLUMN AND A FILTERED INDEX
   --------------------------------------------------------------------------
   Getting Started seeded thousands of ImagingOrder rows and they have no request key.
   A plain NOT NULL column would require a backfill, and a plain UNIQUE index
   would treat every one of those NULLs as a duplicate. So the column is
   nullable and the uniqueness is scoped:

       WHERE RequestKey IS NOT NULL

   Seed rows keep a NULL key and never collide. Agent-placed rows must be
   distinct. The index is what makes the idempotency real — not the procedure's
   NOT EXISTS check, which alone would still race under concurrency.

   Contrast this deliberately with clinical.AgentRecommendation in script 11,
   whose request key is NOT NULL with a plain unique index. That table is new,
   so it could demand a key from the first row; this one had to stay backward
   compatible with data that already existed. Both designs are correct for
   their circumstances. Do not harmonize them.

   A filtered index requires SET QUOTED_IDENTIFIER ON and ANSI_NULLS ON at
   creation time. sqlcmd does NOT default those on, which is why the preamble
   below is not optional (Msg 1934 without it).

   WHY THE PROCEDURE, NOT A TABLE GRANT
   --------------------------------------------------------------------------
   If this were ever exposed, the agent would reach the database through DAB's
   MCP endpoint. If DAB could INSERT into the table directly, the model would
   choose the PatientId, and a confused or manipulated model could write an
   order for the wrong patient. This procedure takes an EncounterId and DERIVES
   PatientId from the encounter, so patient identity is never a model-supplied
   value. Later, when Security turns on Row-Level Security, the same
   derivation runs through the security policy on clinical.Encounter: an
   encounter the acting clinician cannot see yields no row, and therefore no
   order.

   Idempotency lives HERE, in the engine, not in the runtime skill. A skill is
   instruction text the model may ignore; a filtered unique index is not.

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

/* ---- 1. The idempotency key --------------------------------------------- */
IF COL_LENGTH('clinical.ImagingOrder', 'RequestKey') IS NULL
BEGIN
    ALTER TABLE clinical.ImagingOrder ADD RequestKey UNIQUEIDENTIFIER NULL;
    PRINT 'Added clinical.ImagingOrder.RequestKey.';
END
ELSE
    PRINT 'clinical.ImagingOrder.RequestKey already present.';
GO

/* ---- 2. Uniqueness, scoped to the rows that have a key ------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'UQ_Imaging_RequestKey'
                 AND object_id = OBJECT_ID('clinical.ImagingOrder'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UQ_Imaging_RequestKey
        ON clinical.ImagingOrder (RequestKey)
        WHERE RequestKey IS NOT NULL;
    PRINT 'Created UQ_Imaging_RequestKey.';
END
ELSE
    PRINT 'UQ_Imaging_RequestKey already present.';
GO

/* ---- 3. The only sanctioned write path ----------------------------------- */
CREATE OR ALTER PROCEDURE clinical.PlaceImagingOrder
    @EncounterId INT,
    @Modality    NVARCHAR(20),
    @BodySite    NVARCHAR(100) = NULL,
    @OrderedById INT,
    @RequestKey  UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @RequestKey IS NULL
        THROW 50061, 'A RequestKey is required. The caller supplies one key per approved order.', 1;

    /* Validate at the boundary. Every argument below arrived from a language
       model by way of an MCP tool call, so none of it is trusted. The foreign
       keys would catch these too, but a named error is far easier for the
       reader — and the agent — to act on than a constraint violation. */
    IF NOT EXISTS (SELECT 1 FROM ops.Provider WHERE ProviderId = @OrderedById)
        THROW 50062, 'The ordering provider does not exist.', 1;

    /* Note there is deliberately no equivalent existence check on the
       encounter. Under Security Row-Level Security, "the encounter is not
       there" and "the encounter is not yours" must look identical from the
       outside, and the INSERT below already yields nothing in both cases. A
       discharged encounter is folded into the same silence for the same
       reason. */

    DECLARE @inserted INT;

    /* One statement, therefore already atomic — no BEGIN TRAN needed. The
       SELECT is the security boundary: PatientId comes from the encounter row,
       and if that row is invisible (or absent) nothing is written. The
       NOT EXISTS makes a repeated approval a no-op; UQ_Imaging_RequestKey
       makes a CONCURRENT repeat a no-op as well. */
    INSERT INTO clinical.ImagingOrder
        (EncounterId, PatientId, Modality, BodySite, Status, OrderedById, RequestKey)
    SELECT e.EncounterId, e.PatientId, @Modality, @BodySite, N'Ordered', @OrderedById, @RequestKey
    FROM clinical.Encounter AS e
    WHERE e.EncounterId = @EncounterId
      AND e.Status = N'Active'
      AND NOT EXISTS (SELECT 1 FROM clinical.ImagingOrder AS x
                      WHERE x.RequestKey = @RequestKey);

    SET @inserted = @@ROWCOUNT;

    IF @inserted = 0 AND NOT EXISTS (SELECT 1 FROM clinical.ImagingOrder WHERE RequestKey = @RequestKey)
        THROW 50063, 'No order was placed. The encounter does not exist, is not active, or is not visible to the acting clinician.', 1;

    /* Return the order either way, with a flag saying whether this call is the
       one that created it. A caller that retries gets the same ImagingId. */
    SELECT
        o.ImagingId,
        o.EncounterId,
        o.PatientId,
        o.Modality,
        o.BodySite,
        o.Status,
        o.OrderedById,
        o.OrderedAt,
        o.RequestKey,
        CAST(@inserted AS BIT) AS Created
    FROM clinical.ImagingOrder AS o
    WHERE o.RequestKey = @RequestKey;
END;
GO

PRINT 'Agentic AI imaging-order contract is in place.';
GO
