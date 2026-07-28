/* ============================================================================
   Ward General Hospital — Hyperscale developer demo
   04-procedures.sql : foundational read/write procedures for the chart.
   Run order         : 4 of 5  (after 03-views.sql)

   Surface area kept intentionally small:
     * clinical.GetPatientChart       — read by encounter id
     * clinical.GetPatientChartByBed  — read the active encounter on a bed
     * clinical.SearchEncounters      — search encounters by optional filters (OPPO)
     * clinical.AdmitPatient          — open an encounter and occupy a bed
     * clinical.DischargePatient      — close the encounter and free the bed
     * clinical.RecordVitals          — append an observation
     * clinical.PlaceMedicationOrder  — append a medication order
     * clinical.FileLabResult         — append a lab result (JSON payload)
     * clinical.AddClinicalNote       — append a free-text note
     * clinical.AddDiagnosis          — append a coded diagnosis
     * clinical.RecordAllergy         — record a patient allergy (survives discharge)
   The admit/discharge procedures are the only multi-statement transactions
   in this schema: each touches two tables (Encounter + Bed)
   and the pair must be atomic to keep the bedside invariant
   "at most one active encounter per bed" honest. Single-statement DML is
   already atomic on its own and stays that way (no surplus BEGIN TRAN).
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

/* ---- Read: chart for a specific encounter ------------------------------ */
/* Explicit column list (not SELECT *) so the result shape is a stable contract */
/* for the app / DAB / MCP even if vPatientChart gains columns later.           */
CREATE OR ALTER PROCEDURE clinical.GetPatientChart
    @EncounterId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        EncounterId, EncounterStatus, EncounterType, AdmitTime, DischargeTime, IntakeJson,
        PatientId, MRN, PatientName, DateOfBirth, Sex, AgeYears,
        DepartmentId, DepartmentName, UnitId, UnitName, BedId, BedNumber,
        AttendingProviderId, AttendingProviderName, AttendingProviderRole,
        Diagnoses, Medications, Allergies, LatestVitals, RecentLabs,
        Symptoms, CareTeam, Imaging, RecentNotes, NoteSignals
    FROM clinical.vPatientChart
    WHERE EncounterId = @EncounterId;
END;
GO

/* ---- Read: chart for whoever is currently in a bed --------------------- */
/* Same explicit-column contract as GetPatientChart.                            */
CREATE OR ALTER PROCEDURE clinical.GetPatientChartByBed
    @BedId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        EncounterId, EncounterStatus, EncounterType, AdmitTime, DischargeTime, IntakeJson,
        PatientId, MRN, PatientName, DateOfBirth, Sex, AgeYears,
        DepartmentId, DepartmentName, UnitId, UnitName, BedId, BedNumber,
        AttendingProviderId, AttendingProviderName, AttendingProviderRole,
        Diagnoses, Medications, Allergies, LatestVitals, RecentLabs,
        Symptoms, CareTeam, Imaging, RecentNotes, NoteSignals
    FROM clinical.vPatientChart
    WHERE BedId = @BedId
      AND EncounterStatus = N'Active';
END;
GO

/* ---- Read: search encounters with optional filters --------------------- */
/* The DAB / MCP "search" surface: every filter is optional. The              */
/* (col = @p OR @p IS NULL) shape is exactly what SQL Server 2025's Optional   */
/* Parameter Plan Optimization (OPPO) targets — on by default at database       */
/* compatibility level 170 (the Hyperscale default). OPPO picks a seek when a  */
/* filter is supplied and a scan when it is NULL, per execution, instead of    */
/* one compromise plan for all — an IQP feature (OPPO). Returns                  */
/* encounter summary rows; the caller opens a full chart via GetPatientChart.  */
CREATE OR ALTER PROCEDURE clinical.SearchEncounters
    @PatientId           INT          = NULL,
    @DepartmentId        INT          = NULL,
    @AttendingProviderId INT          = NULL,
    @Status              NVARCHAR(20) = NULL,
    @FromAdmit           DATETIME2(3) = NULL,
    @ToAdmit             DATETIME2(3) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        e.EncounterId,
        e.PatientId,
        e.DepartmentId,
        e.AttendingProviderId,
        e.BedId,
        e.EncounterType,
        e.AdmitTime,
        e.DischargeTime,
        e.Status
    FROM clinical.Encounter AS e
    WHERE (@PatientId           IS NULL OR e.PatientId           = @PatientId)
      AND (@DepartmentId        IS NULL OR e.DepartmentId        = @DepartmentId)
      AND (@AttendingProviderId IS NULL OR e.AttendingProviderId = @AttendingProviderId)
      AND (@Status              IS NULL OR e.Status              = @Status)
      AND (@FromAdmit           IS NULL OR e.AdmitTime          >= @FromAdmit)
      AND (@ToAdmit             IS NULL OR e.AdmitTime          <= @ToAdmit)
    ORDER BY e.AdmitTime DESC;
END;
GO

/* ---- Write: admit a patient (open encounter + occupy bed) -------------- */
CREATE OR ALTER PROCEDURE clinical.AdmitPatient
    @PatientId            INT,
    @DepartmentId         INT,
    @AttendingProviderId  INT,
    @BedId                INT,
    @EncounterType        NVARCHAR(20) = N'Inpatient',
    @IntakeJson           JSON         = NULL,
    @EncounterId          INT          OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* Bed must currently be Available — and free of any active encounter.
           The filtered unique index UX_Encounter_ActiveBed is the ultimate
           guard, but checking up front gives a clean error message. */
        IF NOT EXISTS (
            SELECT 1
            FROM ops.Bed
            WHERE BedId     = @BedId
              AND BedStatus = N'Available'
        )
        BEGIN
            THROW 50001, 'Bed is not Available.', 1;
        END;

        IF EXISTS (
            SELECT 1
            FROM clinical.Encounter
            WHERE BedId  = @BedId
              AND Status = N'Active'
        )
        BEGIN
            THROW 50002, 'Bed already has an active encounter.', 1;
        END;

        INSERT INTO clinical.Encounter
            (PatientId, DepartmentId, AttendingProviderId, BedId,
             EncounterType, AdmitTime, Status, IntakeJson)
        VALUES
            (@PatientId, @DepartmentId, @AttendingProviderId, @BedId,
             @EncounterType, SYSUTCDATETIME(), N'Active', @IntakeJson);

        SET @EncounterId = SCOPE_IDENTITY();

        UPDATE ops.Bed
        SET BedStatus = N'Occupied'
        WHERE BedId = @BedId;

        COMMIT TRANSACTION;

        /* Also return the new id as a single-row result set, so result-set-      */
        /* oriented consumers (Data API Builder, the SQL MCP server) get it        */
        /* without having to read an OUTPUT parameter. The @EncounterId OUTPUT     */
        /* parameter is kept for the ADO.NET app.                                  */
        SELECT @EncounterId AS EncounterId;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        /* A concurrent admit can win the race between the up-front check and
           our INSERT; the filtered unique index UX_Encounter_ActiveBed then
           rejects our INSERT (error 2627/2601). Translate that into the same
           clean error the up-front check raises, so callers see one message
           for the conflict regardless of which check detected it. Under the
           concurrent load, this keeps the error surface tidy. */
        IF ERROR_NUMBER() IN (2627, 2601)
            THROW 50002, 'Bed already has an active encounter.', 1;

        THROW;
    END CATCH;
END;
GO

/* ---- Write: discharge (close encounter + free bed) --------------------- */
CREATE OR ALTER PROCEDURE clinical.DischargePatient
    @EncounterId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @BedId INT;

        SELECT @BedId = BedId
        FROM clinical.Encounter
        WHERE EncounterId = @EncounterId
          AND Status      = N'Active';

        /* If no active encounter, nothing to discharge. */
        IF @@ROWCOUNT = 0
        BEGIN
            THROW 50010, 'No active encounter to discharge.', 1;
        END;

        UPDATE clinical.Encounter
        SET Status        = N'Discharged',
            DischargeTime = SYSUTCDATETIME()
            /* BedId is intentionally KEPT — it preserves which bed the patient
               occupied for this encounter. The bedside invariant
               (UX_Encounter_ActiveBed) is filtered to Status='Active', so a
               discharged encounter never conflicts when the bed is reused. */
        WHERE EncounterId = @EncounterId;

        IF @BedId IS NOT NULL
        BEGIN
            UPDATE ops.Bed
            SET BedStatus = N'Cleaning'   -- not Available until EVS turns it over
            WHERE BedId = @BedId;
        END;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

/* ---- Write: record a single vital -------------------------------------- */
/* Single-statement DML — atomic on its own; no explicit transaction.      */
CREATE OR ALTER PROCEDURE clinical.RecordVitals
    @EncounterId     INT,
    @ObservationType NVARCHAR(20),
    @ValueNumeric    DECIMAL(9, 3),
    @Unit            NVARCHAR(20) = NULL,
    @RecordedAt      DATETIME2(3) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO clinical.Observation
        (EncounterId, PatientId, RecordedAt, ObservationType, ValueNumeric, Unit)
    SELECT
        e.EncounterId,
        e.PatientId,
        COALESCE(@RecordedAt, SYSUTCDATETIME()),
        @ObservationType,
        @ValueNumeric,
        @Unit
    FROM clinical.Encounter AS e
    WHERE e.EncounterId = @EncounterId;

    IF @@ROWCOUNT = 0
    BEGIN
        THROW 50020, 'Unknown encounter.', 1;
    END;
END;
GO

/* ---- Write: place a medication order ----------------------------------- */
/* Single-statement DML — atomic on its own; no explicit transaction. */
CREATE OR ALTER PROCEDURE clinical.PlaceMedicationOrder
    @EncounterId    INT,
    @MedicationName NVARCHAR(200),
    @OrderedById    INT,
    @Dose           NVARCHAR(50)  = NULL,
    @Route          NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO clinical.MedicationOrder
        (EncounterId, PatientId, MedicationName, Dose, Route, OrderedById, OrderedAt)
    SELECT
        e.EncounterId,
        e.PatientId,
        @MedicationName,
        @Dose,
        @Route,
        @OrderedById,
        SYSUTCDATETIME()
    FROM clinical.Encounter AS e
    WHERE e.EncounterId = @EncounterId;

    IF @@ROWCOUNT = 0
    BEGIN
        THROW 50030, 'Unknown encounter.', 1;
    END;
END;
GO

/* ---- Write: file a lab result (semi-structured JSON payload) ------------ */
/* Single-statement DML — atomic on its own; no explicit transaction. The     */
/* JSON anchor that grows the LOB slice in the grow-to-1tb scale demo.        */
CREATE OR ALTER PROCEDURE clinical.FileLabResult
    @EncounterId INT,
    @OrderedById INT,
    @TestName    NVARCHAR(100),
    @ResultJson  JSON,
    @CollectedAt DATETIME2(3) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO clinical.LabResult
        (EncounterId, PatientId, OrderedById, TestName, CollectedAt, ResultedAt,
         ResultJson, Status)
    SELECT
        e.EncounterId,
        e.PatientId,
        @OrderedById,
        @TestName,
        COALESCE(@CollectedAt, SYSUTCDATETIME()),
        SYSUTCDATETIME(),
        @ResultJson,
        N'Resulted'
    FROM clinical.Encounter AS e
    WHERE e.EncounterId = @EncounterId;

    IF @@ROWCOUNT = 0
    BEGIN
        THROW 50040, 'Unknown encounter.', 1;
    END;
END;
GO

/* ---- Write: add a free-text clinical note ------------------------------- */
/* Single-statement DML — atomic on its own; no explicit transaction. The     */
/* free-text anchor that grows the LOB slice in the grow-to-1tb scale demo.   */
CREATE OR ALTER PROCEDURE clinical.AddClinicalNote
    @EncounterId      INT,
    @AuthorProviderId INT,
    @NoteType         NVARCHAR(20),
    @NoteText         NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO clinical.ClinicalNote
        (EncounterId, AuthorProviderId, NoteType, NoteText)
    SELECT
        e.EncounterId,
        @AuthorProviderId,
        @NoteType,
        @NoteText
    FROM clinical.Encounter AS e
    WHERE e.EncounterId = @EncounterId;

    IF @@ROWCOUNT = 0
    BEGIN
        THROW 50050, 'Unknown encounter.', 1;
    END;
END;
GO

/* ---- Write: add a coded diagnosis to an encounter ---------------------- */
/* Single-statement DML — atomic on its own; no explicit transaction. */
CREATE OR ALTER PROCEDURE clinical.AddDiagnosis
    @EncounterId   INT,
    @IcdCode       VARCHAR(10),
    @DiagnosedById INT,
    @Description    NVARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO clinical.Diagnosis
        (EncounterId, IcdCode, Description, DiagnosedById)
    SELECT
        e.EncounterId,
        @IcdCode,
        @Description,
        @DiagnosedById
    FROM clinical.Encounter AS e
    WHERE e.EncounterId = @EncounterId;

    IF @@ROWCOUNT = 0
    BEGIN
        THROW 50060, 'Unknown encounter.', 1;
    END;
END;
GO

/* ---- Write: record a patient allergy ----------------------------------- */
/* Allergies attach to the PATIENT (they survive discharge), so this proc     */
/* validates the patient, not an encounter. Single-statement DML — atomic.    */
CREATE OR ALTER PROCEDURE clinical.RecordAllergy
    @PatientId INT,
    @Substance NVARCHAR(200),
    @Severity  NVARCHAR(20),
    @Reaction  NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO clinical.Allergy
        (PatientId, Substance, Reaction, Severity)
    SELECT
        p.PatientId,
        @Substance,
        @Reaction,
        @Severity
    FROM clinical.Patient AS p
    WHERE p.PatientId = @PatientId;

    IF @@ROWCOUNT = 0
    BEGIN
        THROW 50070, 'Unknown patient.', 1;
    END;
END;
GO
