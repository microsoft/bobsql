/* ============================================================================
   Ward General Hospital — Hyperscale developer demo
   02-tables.sql   : the Ward General schema (tables only)
   Run order       : 2 of 5

   Features layered on later by the demo (NOT created here):
     * vector embeddings for clinical.ClinicalNote — built by 06-ai-embeddings.sql
       as a companion table (clinical.ClinicalNoteEmbeddings) so this OLTP note
       table stays lean; a DiskANN index powers AI search over the notes.
     * a JSON index on clinical.Encounter.IntakeJson as data grows
       (CREATE JSON INDEX requires a clustered key and is an offline build).
     * RLS predicates (ops.Provider.EntraObjectId,
       clinical.Encounter.AttendingProviderId) and dynamic data masking.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

/* ---- Drop in reverse dependency order (idempotent re-run) ---------------- */
DROP TABLE IF EXISTS clinical.ImagingOrder;
DROP TABLE IF EXISTS clinical.CareTeamMember;
DROP TABLE IF EXISTS clinical.Symptom;
DROP TABLE IF EXISTS clinical.LabResult;
DROP TABLE IF EXISTS clinical.Allergy;
DROP TABLE IF EXISTS clinical.MedicationOrder;
DROP TABLE IF EXISTS clinical.Observation;
DROP TABLE IF EXISTS clinical.ClinicalNote;
DROP TABLE IF EXISTS clinical.Diagnosis;
DROP TABLE IF EXISTS ops.Appointment;
DROP TABLE IF EXISTS clinical.Encounter;
DROP TABLE IF EXISTS ops.Bed;
DROP TABLE IF EXISTS ops.Unit;
DROP TABLE IF EXISTS clinical.Patient;
DROP TABLE IF EXISTS ops.Provider;
DROP TABLE IF EXISTS ops.Department;
GO

/* ---- ops.Department ------------------------------------------------------ */
CREATE TABLE ops.Department
(
    DepartmentId  INT            NOT NULL IDENTITY(1, 1),
    Name          NVARCHAR(100)  NOT NULL,
    Specialty     NVARCHAR(100)  NULL,
    CONSTRAINT PK_Department PRIMARY KEY CLUSTERED (DepartmentId),
    CONSTRAINT UQ_Department_Name UNIQUE (Name)
);
GO

/* ---- ops.Unit ------------------------------------------------------------ */
/* Nursing unit / physical location (3 West, ICU). Second RLS axis.           */
CREATE TABLE ops.Unit
(
    UnitId        INT            NOT NULL IDENTITY(1, 1),
    Name          NVARCHAR(100)  NOT NULL,
    UnitType      NVARCHAR(30)   NOT NULL,   -- ICU | Med-Surg | ED | Telemetry | OR | L&D
    DepartmentId  INT            NULL,       -- a unit may align with a department
    CONSTRAINT PK_Unit PRIMARY KEY CLUSTERED (UnitId),
    CONSTRAINT UQ_Unit_Name UNIQUE (Name),
    CONSTRAINT FK_Unit_Department
        FOREIGN KEY (DepartmentId) REFERENCES ops.Department (DepartmentId),
    CONSTRAINT CK_Unit_Type
        CHECK (UnitType IN (N'ICU', N'Med-Surg', N'ED', N'Telemetry', N'OR', N'L&D'))
);
GO

/* ---- ops.Bed ------------------------------------------------------------- */
/* A bed within a Unit; the bedside chart is opened by bed (the app).         */
CREATE TABLE ops.Bed
(
    BedId         INT            NOT NULL IDENTITY(1, 1),
    UnitId        INT            NOT NULL,
    BedNumber     NVARCHAR(20)   NOT NULL,   -- e.g. '3W-12A'
    BedStatus     NVARCHAR(20)   NOT NULL CONSTRAINT DF_Bed_BedStatus DEFAULT N'Available',
                                             -- Available | Occupied | Cleaning | OutOfService
    CONSTRAINT PK_Bed PRIMARY KEY CLUSTERED (BedId),
    CONSTRAINT UQ_Bed_UnitNumber UNIQUE (UnitId, BedNumber),
    CONSTRAINT FK_Bed_Unit
        FOREIGN KEY (UnitId) REFERENCES ops.Unit (UnitId),
    CONSTRAINT CK_Bed_Status
        CHECK (BedStatus IN (N'Available', N'Occupied', N'Cleaning', N'OutOfService'))
);
GO

/* ---- ops.Provider -------------------------------------------------------- */
CREATE TABLE ops.Provider
(
    ProviderId    INT              NOT NULL IDENTITY(1, 1),
    FullName      NVARCHAR(200)    NOT NULL,
    DepartmentId  INT              NOT NULL,
    Role          NVARCHAR(50)     NOT NULL,
    EntraObjectId UNIQUEIDENTIFIER NULL,   -- maps to Microsoft Entra for RLS
    CONSTRAINT PK_Provider PRIMARY KEY CLUSTERED (ProviderId),
    CONSTRAINT FK_Provider_Department
        FOREIGN KEY (DepartmentId) REFERENCES ops.Department (DepartmentId)
);
GO

/* ---- clinical.Patient ---------------------------------------------------- */
/* Email / Phone / MRN are the regex-validation targets (REGEXP_LIKE).         */
/* InsuranceJson is the native json showcase.                                  */
CREATE TABLE clinical.Patient
(
    PatientId     INT            NOT NULL IDENTITY(1, 1),
    MRN           VARCHAR(12)    NOT NULL,        -- format WG-#######
    FullName      NVARCHAR(200)  NOT NULL,
    DateOfBirth   DATE           NOT NULL,
    Sex           NVARCHAR(20)   NOT NULL,
    Email         NVARCHAR(256)  NULL,
    Phone         VARCHAR(32)    NULL,
    City          NVARCHAR(100)  NULL,
    PostalCode    VARCHAR(12)    NULL,
    InsuranceJson JSON           NULL,            -- native JSON (GA on Azure SQL DB)
    CreatedAt     DATETIME2(3)   NOT NULL CONSTRAINT DF_Patient_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Patient PRIMARY KEY CLUSTERED (PatientId),
    CONSTRAINT UQ_Patient_MRN UNIQUE (MRN)
);
GO

/* ---- clinical.Encounter -------------------------------------------------- */
/* The chart's spine. BedId is set while the patient is admitted; the filtered  */
/* unique index below enforces "a bed has ≤1 active encounter" (outline §3).  */
/* IntakeJson is the json column that earns a JSON index at scale.             */
CREATE TABLE clinical.Encounter
(
    EncounterId         INT          NOT NULL IDENTITY(1, 1),
    PatientId           INT          NOT NULL,
    DepartmentId        INT          NOT NULL,
    AttendingProviderId INT          NOT NULL,
    BedId               INT          NULL,    -- nullable: outpatient / pre-bed-assignment
    EncounterType       NVARCHAR(20) NOT NULL,   -- ED | Inpatient | Outpatient
    AdmitTime           DATETIME2(3) NOT NULL,
    DischargeTime       DATETIME2(3) NULL,
    Status              NVARCHAR(20) NOT NULL,   -- Active | Discharged
    IntakeJson          JSON         NULL,
    CONSTRAINT PK_Encounter PRIMARY KEY CLUSTERED (EncounterId),
    CONSTRAINT FK_Encounter_Patient
        FOREIGN KEY (PatientId) REFERENCES clinical.Patient (PatientId),
    CONSTRAINT FK_Encounter_Department
        FOREIGN KEY (DepartmentId) REFERENCES ops.Department (DepartmentId),
    CONSTRAINT FK_Encounter_Provider
        FOREIGN KEY (AttendingProviderId) REFERENCES ops.Provider (ProviderId),
    CONSTRAINT FK_Encounter_Bed
        FOREIGN KEY (BedId) REFERENCES ops.Bed (BedId),
    CONSTRAINT CK_Encounter_Type
        CHECK (EncounterType IN (N'ED', N'Inpatient', N'Outpatient')),
    CONSTRAINT CK_Encounter_Status
        CHECK (Status IN (N'Active', N'Discharged')),
    CONSTRAINT CK_Encounter_Discharge
        CHECK (DischargeTime IS NULL OR DischargeTime >= AdmitTime)
);
GO

/* ---- ops.Appointment ----------------------------------------------------- */
CREATE TABLE ops.Appointment
(
    AppointmentId  INT          NOT NULL IDENTITY(1, 1),
    PatientId      INT          NOT NULL,
    ProviderId     INT          NOT NULL,
    DepartmentId   INT          NOT NULL,
    ScheduledStart DATETIME2(3) NOT NULL,
    ScheduledEnd   DATETIME2(3) NOT NULL,
    Status         NVARCHAR(20) NOT NULL,   -- Scheduled | Completed | Cancelled | NoShow
    CONSTRAINT PK_Appointment PRIMARY KEY CLUSTERED (AppointmentId),
    CONSTRAINT FK_Appointment_Patient
        FOREIGN KEY (PatientId) REFERENCES clinical.Patient (PatientId),
    CONSTRAINT FK_Appointment_Provider
        FOREIGN KEY (ProviderId) REFERENCES ops.Provider (ProviderId),
    CONSTRAINT FK_Appointment_Department
        FOREIGN KEY (DepartmentId) REFERENCES ops.Department (DepartmentId),
    CONSTRAINT CK_Appointment_Window CHECK (ScheduledEnd > ScheduledStart),
    CONSTRAINT CK_Appointment_Status
        CHECK (Status IN (N'Scheduled', N'Completed', N'Cancelled', N'NoShow'))
);
GO

/* ---- clinical.Diagnosis -------------------------------------------------- */
CREATE TABLE clinical.Diagnosis
(
    DiagnosisId   INT           NOT NULL IDENTITY(1, 1),
    EncounterId   INT           NOT NULL,
    IcdCode       VARCHAR(10)   NOT NULL,
    Description   NVARCHAR(300) NULL,
    DiagnosedById INT           NOT NULL,
    CONSTRAINT PK_Diagnosis PRIMARY KEY CLUSTERED (DiagnosisId),
    CONSTRAINT FK_Diagnosis_Encounter
        FOREIGN KEY (EncounterId) REFERENCES clinical.Encounter (EncounterId),
    CONSTRAINT FK_Diagnosis_Provider
        FOREIGN KEY (DiagnosedById) REFERENCES ops.Provider (ProviderId)
);
GO

/* ---- clinical.ClinicalNote ----------------------------------------------- */
/* NoteText is the free-text column embedded for AI search and regex-mined.     */
CREATE TABLE clinical.ClinicalNote
(
    NoteId           INT            NOT NULL IDENTITY(1, 1),
    EncounterId      INT            NOT NULL,
    AuthorProviderId INT            NOT NULL,
    NoteType         NVARCHAR(20)   NOT NULL,   -- Progress | Discharge | Consult
    NoteText         NVARCHAR(MAX)  NOT NULL,
    CreatedAt        DATETIME2(3)   NOT NULL CONSTRAINT DF_Note_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_ClinicalNote PRIMARY KEY CLUSTERED (NoteId),
    CONSTRAINT FK_Note_Encounter
        FOREIGN KEY (EncounterId) REFERENCES clinical.Encounter (EncounterId),
    CONSTRAINT FK_Note_Provider
        FOREIGN KEY (AuthorProviderId) REFERENCES ops.Provider (ProviderId),
    CONSTRAINT CK_Note_Type
        CHECK (NoteType IN (N'Progress', N'Discharge', N'Consult'))
);
GO

/* ---- clinical.Observation  (the high-volume telemetry table) -------------- */
/* DESIGN DECISION — clustering key vs primary key.                              */
/* Primary key and clustering key are INDEPENDENT choices — a PK is clustered     */
/* only by default, not by rule. Real vitals arrive as a concurrent trickle from */
/* device-integration engines (HL7 ORU / FHIR Observation), so this table sits   */
/* on a high-concurrency INSERT path, and the two keys are split on purpose:      */
/*                                                                                */
/*   * PK = ObservationId (BIGINT IDENTITY), declared NONCLUSTERED. It is a       */
/*     surrogate for identity/uniqueness ONLY — nothing seeks Observation by      */
/*     ObservationId and no FK references it, so the nonclustered PK costs        */
/*     effectively nothing.                                                       */
/*   * CLUSTERED key = (EncounterId, RecordedAt, ObservationId). An ascending     */
/*     IDENTITY clustered key (the default) would drive every concurrent insert   */
/*     onto the same last page — a PAGELATCH_EX convoy. Leading with EncounterId  */
/*     instead spreads inserts across the hundreds of concurrently-active         */
/*     encounters (no global hot page) WITHOUT relying on                         */
/*     OPTIMIZE_FOR_SEQUENTIAL_KEY (a convoy-manager, not a cure), and the same   */
/*     key serves the "latest vitals per encounter" chart read as a seek.         */
/*     It meets narrow / unique / static and trades "ever-increasing" on purpose  */
/*     to distribute the write load. ObservationId is appended so the tuple is    */
/*     unique (see the UNIQUE CLUSTERED index below).                             */
/*                                                                                */
/* Modest seed here; a scale step adds a clustered-columnstore *history archive*  */
/* + the ~1 TB grow. The live table is never converted to columnstore.           */
CREATE TABLE clinical.Observation
(
    ObservationId   BIGINT        NOT NULL IDENTITY(1, 1),
    EncounterId     INT           NOT NULL,
    PatientId       INT           NOT NULL,
    RecordedAt      DATETIME2(3)  NOT NULL,
    ObservationType NVARCHAR(20)  NOT NULL,   -- HeartRate | SystolicBP | DiastolicBP | SpO2 | Temperature | RespRate
    ValueNumeric    DECIMAL(9, 3) NULL,
    Unit            NVARCHAR(20)  NULL,
    CONSTRAINT PK_Observation PRIMARY KEY NONCLUSTERED (ObservationId),
    CONSTRAINT FK_Observation_Encounter
        FOREIGN KEY (EncounterId) REFERENCES clinical.Encounter (EncounterId),
    CONSTRAINT FK_Observation_Patient
        FOREIGN KEY (PatientId) REFERENCES clinical.Patient (PatientId),
    CONSTRAINT CK_Observation_Type
        CHECK (ObservationType IN (N'HeartRate', N'SystolicBP', N'DiastolicBP', N'SpO2', N'Temperature', N'RespRate'))
);
GO

/* Clustered key — see the DESIGN DECISION note on the table above. Declared     */
/* UNIQUE (ObservationId makes the tuple unique) so SQL stores no 4-byte          */
/* uniquifier and the optimizer knows each row is uniquely keyed. This replaces   */
/* a separate nonclustered (EncounterId, RecordedAt) index — the clustered key    */
/* already is that index.                                                         */
CREATE UNIQUE CLUSTERED INDEX CIX_Observation_Encounter_RecordedAt
    ON clinical.Observation (EncounterId, RecordedAt, ObservationId);
GO

/* ---- clinical.MedicationOrder -------------------------------------------- */
CREATE TABLE clinical.MedicationOrder
(
    OrderId        INT           NOT NULL IDENTITY(1, 1),
    EncounterId    INT           NOT NULL,
    PatientId      INT           NOT NULL,
    MedicationName NVARCHAR(200) NOT NULL,
    Dose           NVARCHAR(50)  NULL,
    Route          NVARCHAR(50)  NULL,
    OrderedById    INT           NOT NULL,
    OrderedAt      DATETIME2(3)  NOT NULL CONSTRAINT DF_Order_OrderedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_MedicationOrder PRIMARY KEY CLUSTERED (OrderId),
    CONSTRAINT FK_Order_Encounter
        FOREIGN KEY (EncounterId) REFERENCES clinical.Encounter (EncounterId),
    CONSTRAINT FK_Order_Patient
        FOREIGN KEY (PatientId) REFERENCES clinical.Patient (PatientId),
    CONSTRAINT FK_Order_Provider
        FOREIGN KEY (OrderedById) REFERENCES ops.Provider (ProviderId)
);
GO

/* ---- clinical.Allergy ---------------------------------------------------- */
/* High-value bedside recall surface for the clinical-assistant agent.         */
CREATE TABLE clinical.Allergy
(
    AllergyId   INT           NOT NULL IDENTITY(1, 1),
    PatientId   INT           NOT NULL,
    Substance   NVARCHAR(200) NOT NULL,        -- e.g. 'Penicillin', 'Latex'
    Reaction    NVARCHAR(200) NULL,            -- e.g. 'Hives', 'Anaphylaxis'
    Severity    NVARCHAR(20)  NOT NULL,        -- Mild | Moderate | Severe
    RecordedAt  DATETIME2(3)  NOT NULL CONSTRAINT DF_Allergy_RecordedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Allergy PRIMARY KEY CLUSTERED (AllergyId),
    CONSTRAINT FK_Allergy_Patient
        FOREIGN KEY (PatientId) REFERENCES clinical.Patient (PatientId),
    CONSTRAINT CK_Allergy_Severity
        CHECK (Severity IN (N'Mild', N'Moderate', N'Severe'))
);
GO

/* ---- clinical.LabResult -------------------------------------------------- */
/* ResultJson is the second native-json home (with Patient.InsuranceJson and  */
/* Encounter.IntakeJson). Lab result panels vary by test type, so the payload */
/* is naturally semi-structured.                                              */
CREATE TABLE clinical.LabResult
(
    LabResultId   BIGINT        NOT NULL IDENTITY(1, 1),
    EncounterId   INT           NOT NULL,
    PatientId     INT           NOT NULL,
    OrderedById   INT           NOT NULL,
    TestName      NVARCHAR(100) NOT NULL,       -- e.g. 'CBC', 'BMP', 'Troponin'
    CollectedAt   DATETIME2(3)  NOT NULL,
    ResultedAt    DATETIME2(3)  NULL,
    ResultJson    JSON          NULL,           -- panel values + reference ranges
    Status        NVARCHAR(20)  NOT NULL CONSTRAINT DF_Lab_Status DEFAULT N'Resulted',
                                                -- Ordered | Collected | Resulted | Cancelled
    CONSTRAINT PK_LabResult PRIMARY KEY CLUSTERED (LabResultId),
    CONSTRAINT FK_Lab_Encounter
        FOREIGN KEY (EncounterId) REFERENCES clinical.Encounter (EncounterId),
    CONSTRAINT FK_Lab_Patient
        FOREIGN KEY (PatientId) REFERENCES clinical.Patient (PatientId),
    CONSTRAINT FK_Lab_Provider
        FOREIGN KEY (OrderedById) REFERENCES ops.Provider (ProviderId),
    CONSTRAINT CK_Lab_Status
        CHECK (Status IN (N'Ordered', N'Collected', N'Resulted', N'Cancelled'))
);
GO

/* ---- clinical.Symptom  (presenting complaints per encounter) ------------- */
/* Surfaced in the bedside chart alongside diagnoses and vitals.               */
CREATE TABLE clinical.Symptom
(
    SymptomId   INT           NOT NULL IDENTITY(1, 1),
    EncounterId INT           NOT NULL,
    Description NVARCHAR(200) NOT NULL,
    Severity    NVARCHAR(20)  NULL,          -- Mild | Moderate | Severe
    NotedAt     DATETIME2(3)  NOT NULL CONSTRAINT DF_Symptom_NotedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Symptom PRIMARY KEY CLUSTERED (SymptomId),
    CONSTRAINT FK_Symptom_Encounter
        FOREIGN KEY (EncounterId) REFERENCES clinical.Encounter (EncounterId),
    CONSTRAINT CK_Symptom_Severity
        CHECK (Severity IS NULL OR Severity IN (N'Mild', N'Moderate', N'Severe'))
);
CREATE NONCLUSTERED INDEX IX_Symptom_Encounter ON clinical.Symptom (EncounterId);
GO

/* ---- clinical.CareTeamMember  (many providers per encounter) ------------- */
/* Encounter.AttendingProviderId is also the IsPrimary=1 Attending here; this   */
/* table adds the rest of the team, each with an encounter-scoped role.         */
CREATE TABLE clinical.CareTeamMember
(
    CareTeamMemberId INT          NOT NULL IDENTITY(1, 1),
    EncounterId      INT          NOT NULL,
    ProviderId       INT          NOT NULL,
    TeamRole         NVARCHAR(20) NOT NULL,  -- Intern|Resident|Associate|Attending|Consultant
    IsPrimary        BIT          NOT NULL CONSTRAINT DF_CareTeam_IsPrimary DEFAULT 0,
    CONSTRAINT PK_CareTeamMember PRIMARY KEY CLUSTERED (CareTeamMemberId),
    CONSTRAINT FK_CareTeam_Encounter
        FOREIGN KEY (EncounterId) REFERENCES clinical.Encounter (EncounterId),
    CONSTRAINT FK_CareTeam_Provider
        FOREIGN KEY (ProviderId) REFERENCES ops.Provider (ProviderId),
    CONSTRAINT UQ_CareTeam UNIQUE (EncounterId, ProviderId),
    CONSTRAINT CK_CareTeam_Role
        CHECK (TeamRole IN (N'Intern', N'Resident', N'Associate', N'Attending', N'Consultant'))
);
CREATE NONCLUSTERED INDEX IX_CareTeam_Encounter ON clinical.CareTeamMember (EncounterId);
GO

/* ---- clinical.ImagingOrder  (third order type; FindingsJson native json) - */
/* Joins Medication + Lab as the third order type. FindingsJson is another      */
/* native json home, like LabResult.ResultJson.                                 */
CREATE TABLE clinical.ImagingOrder
(
    ImagingId    BIGINT        NOT NULL IDENTITY(1, 1),
    EncounterId  INT           NOT NULL,
    PatientId    INT           NOT NULL,
    Modality     NVARCHAR(20)  NOT NULL,     -- XR | CT | MRI | US | Nuclear
    BodySite     NVARCHAR(100) NULL,
    Status       NVARCHAR(20)  NOT NULL CONSTRAINT DF_Imaging_Status DEFAULT N'Ordered',
    OrderedById  INT           NOT NULL,
    OrderedAt    DATETIME2(3)  NOT NULL CONSTRAINT DF_Imaging_OrderedAt DEFAULT SYSUTCDATETIME(),
    ResultedAt   DATETIME2(3)  NULL,
    FindingsJson JSON          NULL,
    CONSTRAINT PK_ImagingOrder PRIMARY KEY CLUSTERED (ImagingId),
    CONSTRAINT FK_Imaging_Encounter
        FOREIGN KEY (EncounterId) REFERENCES clinical.Encounter (EncounterId),
    CONSTRAINT FK_Imaging_Patient
        FOREIGN KEY (PatientId) REFERENCES clinical.Patient (PatientId),
    CONSTRAINT FK_Imaging_Provider
        FOREIGN KEY (OrderedById) REFERENCES ops.Provider (ProviderId),
    CONSTRAINT CK_Imaging_Modality
        CHECK (Modality IN (N'XR', N'CT', N'MRI', N'US', N'Nuclear')),
    CONSTRAINT CK_Imaging_Status
        CHECK (Status IN (N'Ordered', N'InProgress', N'Completed', N'Cancelled'))
);
CREATE NONCLUSTERED INDEX IX_Imaging_Encounter ON clinical.ImagingOrder (EncounterId);
GO

/* ---- Supporting nonclustered indexes (the joins every chart read uses) ---- */
/* Each chart section in 03-views.sql joins/groups on EncounterId (or          */
/* PatientId for allergies). These indexes turn each section into a seek so a   */
/* single-encounter chart read never scans a child table.                      */
CREATE NONCLUSTERED INDEX IX_Encounter_PatientId
    ON clinical.Encounter (PatientId) INCLUDE (DepartmentId, AdmitTime, Status);
CREATE NONCLUSTERED INDEX IX_Note_Encounter
    ON clinical.ClinicalNote (EncounterId);
CREATE NONCLUSTERED INDEX IX_Diagnosis_Encounter
    ON clinical.Diagnosis (EncounterId);         -- vChartDiagnoses
CREATE NONCLUSTERED INDEX IX_MedicationOrder_Encounter
    ON clinical.MedicationOrder (EncounterId);   -- vChartMedications
CREATE NONCLUSTERED INDEX IX_Appointment_Provider_Start
    ON ops.Appointment (ProviderId, ScheduledStart);
CREATE NONCLUSTERED INDEX IX_Bed_UnitId
    ON ops.Bed (UnitId);
CREATE NONCLUSTERED INDEX IX_Allergy_PatientId
    ON clinical.Allergy (PatientId);
CREATE NONCLUSTERED INDEX IX_Lab_Encounter_CollectedAt
    ON clinical.LabResult (EncounterId, CollectedAt);
GO

/* ---- Bedside invariant: a bed has ≤1 active encounter --------------------- */
/* Filtered unique index. Filtered indexes require QUOTED_IDENTIFIER ON and    */
/* ANSI_NULLS ON (both set at the top of this file).                           */
CREATE UNIQUE NONCLUSTERED INDEX UX_Encounter_ActiveBed
    ON clinical.Encounter (BedId)
    WHERE BedId IS NOT NULL AND Status = N'Active';
GO
