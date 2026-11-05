/* =======================================================================
   Zava Health – Patient Chart Core (SQL Server 2025 + NVIDIA NIM)
   FULL DROP-and-CREATE (re-runnable)
   - Schemas: ref, core, clinical, sec
   - Providers & Roles with supervision chain support
   - DoctorNotes = APPEND_ONLY LEDGER table
   - RLS predicates added via ALTER statements for robust parsing
   - No explicit default/check constraint names (safe to re-run)
   ======================================================================= */

SET NOCOUNT ON;
GO

/* =========================
   Create database (SQL Server 2025)
   ========================= */
USE master;
GO
IF DB_ID(N'zavahospital') IS NULL
    CREATE DATABASE zavahospital;
GO
ALTER DATABASE zavahospital SET ACCELERATED_DATABASE_RECOVERY = ON;
ALTER DATABASE zavahospital SET OPTIMIZED_LOCKING = ON;
GO
USE zavahospital;
GO

/* =========================
   Database scoped settings
   ========================= */
ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SNIFFING = ON;
ALTER DATABASE SCOPED CONFIGURATION SET IDENTITY_CACHE = ON;
ALTER DATABASE SCOPED CONFIGURATION SET VERBOSE_TRUNCATION_WARNINGS = ON;
ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;
GO

/* ============================================================
   Ensure schemas exist FIRST so two-part names always parse
   ============================================================ */
IF SCHEMA_ID('ref')      IS NULL EXEC('CREATE SCHEMA ref AUTHORIZATION dbo;');
IF SCHEMA_ID('core')     IS NULL EXEC('CREATE SCHEMA core AUTHORIZATION dbo;');
IF SCHEMA_ID('clinical') IS NULL EXEC('CREATE SCHEMA clinical AUTHORIZATION dbo;');
IF SCHEMA_ID('sec')      IS NULL EXEC('CREATE SCHEMA sec AUTHORIZATION dbo;');
GO

/* =========================
   CLEAN DROP (if exists)
   ========================= */

-- Drop RLS security policy via dynamic SQL (schema-agnostic)
DECLARE @p SYSNAME, @s SYSNAME, @sql NVARCHAR(MAX);
SELECT TOP(1) @p = sp.name, @s = SCHEMA_NAME(sp.schema_id)
FROM sys.security_policies sp
WHERE sp.name = N'PatientScopePolicy';
IF @p IS NOT NULL
BEGIN
    SET @sql = N'DROP SECURITY POLICY ' + QUOTENAME(@s) + N'.' + QUOTENAME(@p) + N';';
    EXEC sys.sp_executesql @sql;
END
GO

-- Drop RLS functions (if present)
IF OBJECT_ID(N'sec.fn_BedAssignmentScopePredicate', N'IF') IS NOT NULL
    DROP FUNCTION sec.fn_BedAssignmentScopePredicate;
IF OBJECT_ID(N'sec.fn_PatientScopePredicate', N'IF') IS NOT NULL
    DROP FUNCTION sec.fn_PatientScopePredicate;
GO

-- Drop clinical tables (depend on core/ref)
IF OBJECT_ID(N'clinical.Alerts', N'U') IS NOT NULL           DROP TABLE clinical.Alerts;
IF OBJECT_ID(N'clinical.VitalsSnapshots', N'U') IS NOT NULL   DROP TABLE clinical.VitalsSnapshots;
IF OBJECT_ID(N'clinical.Orders', N'U') IS NOT NULL            DROP TABLE clinical.Orders;
IF OBJECT_ID(N'clinical.DoctorNotes', N'U') IS NOT NULL       DROP TABLE clinical.DoctorNotes; -- ledger: DROP is sufficient
IF OBJECT_ID(N'clinical.Symptoms', N'U') IS NOT NULL          DROP TABLE clinical.Symptoms;
GO

-- Drop core tables
IF OBJECT_ID(N'core.BedAssignments', N'U') IS NOT NULL DROP TABLE core.BedAssignments;
IF OBJECT_ID(N'core.Encounters', N'U') IS NOT NULL     DROP TABLE core.Encounters;
IF OBJECT_ID(N'core.Patients', N'U') IS NOT NULL       DROP TABLE core.Patients;

-- Drop providers after clinical (FK safety)
IF OBJECT_ID(N'core.Providers', N'U') IS NOT NULL      DROP TABLE core.Providers;
GO

-- Drop reference tables
IF OBJECT_ID(N'ref.AlertSeverities', N'U') IS NOT NULL DROP TABLE ref.AlertSeverities;
IF OBJECT_ID(N'ref.OrderTypes', N'U') IS NOT NULL      DROP TABLE ref.OrderTypes;
IF OBJECT_ID(N'ref.Beds', N'U') IS NOT NULL            DROP TABLE ref.Beds;
IF OBJECT_ID(N'ref.Rooms', N'U') IS NOT NULL           DROP TABLE ref.Rooms;
IF OBJECT_ID(N'ref.Buildings', N'U') IS NOT NULL       DROP TABLE ref.Buildings;
IF OBJECT_ID(N'ref.ProviderRoles', N'U') IS NOT NULL   DROP TABLE ref.ProviderRoles;
GO

/* ==========================
   RECREATE: Reference tables
   ========================== */

-- Facilities
CREATE TABLE ref.Buildings (
    BuildingID      INT IDENTITY(1,1) PRIMARY KEY,
    Name            NVARCHAR(100) NOT NULL,
    AddressLine1    NVARCHAR(150) NULL,
    AddressLine2    NVARCHAR(150) NULL,
    City            NVARCHAR(80)  NULL,
    StateProvince   NVARCHAR(80)  NULL,
    PostalCode      NVARCHAR(20)  NULL,
    IsActive        BIT NOT NULL DEFAULT (1),
    CreatedAt       DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME())
);
CREATE UNIQUE INDEX UX_ref_Buildings_Name ON ref.Buildings(Name) WHERE IsActive = 1;

CREATE TABLE ref.Rooms (
    RoomID          INT IDENTITY(1,1) PRIMARY KEY,
    BuildingID      INT NOT NULL,
    RoomNumber      NVARCHAR(20) NOT NULL,
    Ward            NVARCHAR(50) NULL,
    IsActive        BIT NOT NULL DEFAULT (1),
    CreatedAt       DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_ref_Rooms_Building FOREIGN KEY (BuildingID) REFERENCES ref.Buildings(BuildingID)
);
CREATE UNIQUE INDEX UX_ref_Rooms_Building_RoomNumber ON ref.Rooms(BuildingID, RoomNumber) WHERE IsActive = 1;

CREATE TABLE ref.Beds (
    BedID           INT IDENTITY(1,1) PRIMARY KEY,
    RoomID          INT NOT NULL,
    BedNumber       NVARCHAR(20) NOT NULL,
    IsActive        BIT NOT NULL DEFAULT (1),
    CreatedAt       DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_ref_Beds_Room FOREIGN KEY (RoomID) REFERENCES ref.Rooms(RoomID)
);
CREATE UNIQUE INDEX UX_ref_Beds_Room_BedNumber ON ref.Beds(RoomID, BedNumber) WHERE IsActive = 1;

-- Orders & Alerts lookups
CREATE TABLE ref.OrderTypes (
    OrderTypeCode   NVARCHAR(40)  NOT NULL PRIMARY KEY,
    DisplayName     NVARCHAR(100) NOT NULL,
    IsActive        BIT NOT NULL DEFAULT (1)
);

CREATE TABLE ref.AlertSeverities (
    SeverityCode    NVARCHAR(20) NOT NULL PRIMARY KEY,
    Rank            TINYINT      NOT NULL CHECK (Rank BETWEEN 1 AND 10),
    DisplayName     NVARCHAR(50) NOT NULL
);

-- Provider roles
CREATE TABLE ref.ProviderRoles (
    RoleID          INT IDENTITY(1,1) PRIMARY KEY,
    RoleName        NVARCHAR(50) NOT NULL UNIQUE  -- Intern, Resident, Associate, Attending, Consultant
);
GO

/* =======================
   RECREATE: Core entities
   ======================= */

CREATE TABLE core.Patients (
    PatientID       INT IDENTITY(1,1) PRIMARY KEY,
    MRN             NVARCHAR(50) NOT NULL,
    FirstName       NVARCHAR(100) NOT NULL,
    LastName        NVARCHAR(100) NOT NULL,
    DOB             DATE NULL,
    Gender          NVARCHAR(20) NULL CHECK (Gender IN (N'Male',N'Female',N'Other')),
    ContactInfo     NVARCHAR(200) NULL,
    Allergies       NVARCHAR(500) NULL,
    CreatedAt       DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    ModifiedAt      DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME())
) WITH (DATA_COMPRESSION = ROW);
CREATE UNIQUE INDEX UX_core_Patients_MRN ON core.Patients(MRN);
ALTER TABLE core.Patients WITH CHECK 
ADD CONSTRAINT CHK_core_Patients_Name_NotEmpty
CHECK (LEN(LTRIM(RTRIM(ISNULL(FirstName,'')))) > 0
   AND LEN(LTRIM(RTRIM(ISNULL(LastName ,'')))) > 0);

CREATE TABLE core.Encounters (
    EncounterID     BIGINT IDENTITY(1,1) PRIMARY KEY,
    PatientID       INT NOT NULL,
    AdmitDate       DATETIME2(3) NOT NULL,
    DischargeDate   DATETIME2(3) NULL,
    Reason          NVARCHAR(200) NULL,
    CreatedAt       DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_core_Encounters_Patient FOREIGN KEY (PatientID) REFERENCES core.Patients(PatientID)
);
CREATE INDEX IX_core_Encounters_Patient_Open ON core.Encounters(PatientID) INCLUDE (AdmitDate, DischargeDate);

CREATE TABLE core.BedAssignments (
    AssignmentID    BIGINT IDENTITY(1,1) PRIMARY KEY,
    BedID           INT NOT NULL,
    PatientID       INT NOT NULL,
    EncounterID     BIGINT NULL,
    AdmitDate       DATETIME2(3) NOT NULL,
    DischargeDate   DATETIME2(3) NULL,
    CreatedAt       DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_core_BedAssignments_Bed       FOREIGN KEY (BedID)     REFERENCES ref.Beds(BedID),
    CONSTRAINT FK_core_BedAssignments_Patient   FOREIGN KEY (PatientID) REFERENCES core.Patients(PatientID),
    CONSTRAINT FK_core_BedAssignments_Encounter FOREIGN KEY (EncounterID) REFERENCES core.Encounters(EncounterID),
    CONSTRAINT CHK_core_BedAssignments_Dates CHECK (DischargeDate IS NULL OR DischargeDate >= AdmitDate)
);
CREATE UNIQUE INDEX UX_core_BedAssignments_Bed_Open
    ON core.BedAssignments(BedID) WHERE DischargeDate IS NULL;
CREATE UNIQUE INDEX UX_core_BedAssignments_Patient_Open
    ON core.BedAssignments(PatientID) WHERE DischargeDate IS NULL;
CREATE INDEX IX_core_BedAssignments_Patient ON core.BedAssignments(PatientID, AdmitDate DESC) INCLUDE (BedID, DischargeDate);

-- Providers (with Role and optional Supervisor chain)
CREATE TABLE core.Providers (
    ProviderID      INT IDENTITY(1,1) PRIMARY KEY,
    FullName        NVARCHAR(100) NOT NULL,
    RoleID          INT NOT NULL,
    SupervisorProviderID INT NULL,   -- self-FK for supervision chain
    ContactInfo     NVARCHAR(200) NULL,
    IsActive        BIT NOT NULL DEFAULT (1),
    CreatedAt       DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_core_Providers_Role       FOREIGN KEY (RoleID) REFERENCES ref.ProviderRoles(RoleID),
    CONSTRAINT FK_core_Providers_Supervisor FOREIGN KEY (SupervisorProviderID) REFERENCES core.Providers(ProviderID)
);
CREATE UNIQUE INDEX UX_core_Providers_FullName ON core.Providers(FullName) WHERE IsActive = 1;
GO

/* ===========================
   RECREATE: Clinical tables
   =========================== */

-- Doctor Notes: APPEND_ONLY Ledger; authored by ProviderID
CREATE TABLE clinical.DoctorNotes (
    NoteID          BIGINT IDENTITY(1,1) PRIMARY KEY,
    PatientID       INT NOT NULL,
    EncounterID     BIGINT NULL,
    ProviderID      INT NOT NULL,
    NoteText        NVARCHAR(MAX) NOT NULL,
    CreatedAt       DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_clinical_DoctorNotes_Patient   FOREIGN KEY (PatientID)   REFERENCES core.Patients(PatientID),
    CONSTRAINT FK_clinical_DoctorNotes_Encounter FOREIGN KEY (EncounterID) REFERENCES core.Encounters(EncounterID),
    CONSTRAINT FK_clinical_DoctorNotes_Provider  FOREIGN KEY (ProviderID)  REFERENCES core.Providers(ProviderID)
) WITH (LEDGER = ON (APPEND_ONLY = ON));
CREATE INDEX IX_clinical_DoctorNotes_Patient_Time ON clinical.DoctorNotes(PatientID, CreatedAt DESC) INCLUDE (ProviderID);

-- Symptoms / Observations
CREATE TABLE clinical.Symptoms (
    SymptomID       BIGINT IDENTITY(1,1) PRIMARY KEY,
    PatientID       INT NOT NULL,
    EncounterID     BIGINT NULL,
    Code            NVARCHAR(50) NULL,
    Description     NVARCHAR(500) NOT NULL,
    RecordedAt      DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_clinical_Symptoms_Patient   FOREIGN KEY (PatientID)   REFERENCES core.Patients(PatientID),
    CONSTRAINT FK_clinical_Symptoms_Encounter FOREIGN KEY (EncounterID) REFERENCES core.Encounters(EncounterID)
);
CREATE INDEX IX_clinical_Symptoms_Patient_Time ON clinical.Symptoms(PatientID, RecordedAt DESC);

-- Orders: authored by ProviderID
CREATE TABLE clinical.Orders (
    OrderID         BIGINT IDENTITY(1,1) PRIMARY KEY,
    PatientID       INT NOT NULL,
    EncounterID     BIGINT NULL,
    OrderTypeCode   NVARCHAR(40) NOT NULL,
    Details         NVARCHAR(MAX) NULL,
    ProviderID      INT NOT NULL,
    OrderedAt       DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    Status          NVARCHAR(30) NOT NULL DEFAULT (N'Pending'),
    CONSTRAINT CHK_clinical_Orders_Status CHECK (Status IN (N'Pending',N'InProgress',N'Completed',N'Cancelled')),
    CONSTRAINT FK_clinical_Orders_Patient   FOREIGN KEY (PatientID)   REFERENCES core.Patients(PatientID),
    CONSTRAINT FK_clinical_Orders_Encounter FOREIGN KEY (EncounterID) REFERENCES core.Encounters(EncounterID),
    CONSTRAINT FK_clinical_Orders_Type      FOREIGN KEY (OrderTypeCode) REFERENCES ref.OrderTypes(OrderTypeCode),
    CONSTRAINT FK_clinical_Orders_Provider  FOREIGN KEY (ProviderID)  REFERENCES core.Providers(ProviderID)
);
CREATE INDEX IX_clinical_Orders_Patient_Time   ON clinical.Orders(PatientID, OrderedAt DESC) INCLUDE (OrderTypeCode, Status, ProviderID);
CREATE INDEX IX_clinical_Orders_Status_Type    ON clinical.Orders(Status, OrderTypeCode);

-- Periodic Vitals
CREATE TABLE clinical.VitalsSnapshots (
    SnapshotID      BIGINT IDENTITY(1,1) PRIMARY KEY,
    PatientID       INT NOT NULL,
    EncounterID     BIGINT NULL,
    HeartRate       SMALLINT NULL CHECK (HeartRate BETWEEN 0 AND 300),
    BloodPressure   NVARCHAR(20) NULL,
    SpO2            DECIMAL(5,2) NULL CHECK (SpO2 BETWEEN 0 AND 100),
    TemperatureC    DECIMAL(4,1) NULL CHECK (TemperatureC BETWEEN 25.0 AND 45.0),
    RespiratoryRate SMALLINT NULL CHECK (RespiratoryRate BETWEEN 0 AND 120),
    RecordedAt      DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    Source          NVARCHAR(40) NULL,
    CONSTRAINT FK_clinical_Vitals_Patient   FOREIGN KEY (PatientID)   REFERENCES core.Patients(PatientID),
    CONSTRAINT FK_clinical_Vitals_Encounter FOREIGN KEY (EncounterID) REFERENCES core.Encounters(EncounterID)
) WITH (DATA_COMPRESSION = ROW);
CREATE INDEX IX_clinical_Vitals_Patient_Time ON clinical.VitalsSnapshots(PatientID, RecordedAt DESC)
    INCLUDE (HeartRate, BloodPressure, SpO2, TemperatureC, RespiratoryRate, Source);
ALTER TABLE clinical.VitalsSnapshots WITH CHECK 
ADD CONSTRAINT CHK_clinical_Vitals_NotFuture CHECK (RecordedAt <= DATEADD(MINUTE, 5, SYSUTCDATETIME()));

-- Alerts
CREATE TABLE clinical.Alerts (
    AlertID         BIGINT IDENTITY(1,1) PRIMARY KEY,
    PatientID       INT NOT NULL,
    EncounterID     BIGINT NULL,
    AlertType       NVARCHAR(80) NOT NULL,
    SeverityCode    NVARCHAR(20) NOT NULL,
    Message         NVARCHAR(500) NULL,
    CreatedAt       DATETIME2(3) NOT NULL DEFAULT (SYSUTCDATETIME()),
    Resolved        BIT NOT NULL DEFAULT (0),
    ResolvedAt      DATETIME2(3) NULL,
    ResolvedBy      NVARCHAR(100) NULL,
    CONSTRAINT FK_clinical_Alerts_Patient   FOREIGN KEY (PatientID)   REFERENCES core.Patients(PatientID),
    CONSTRAINT FK_clinical_Alerts_Encounter FOREIGN KEY (EncounterID) REFERENCES core.Encounters(EncounterID),
    CONSTRAINT FK_clinical_Alerts_Severity  FOREIGN KEY (SeverityCode) REFERENCES ref.AlertSeverities(SeverityCode),
    CONSTRAINT CHK_clinical_Alerts_Resolve  CHECK ((Resolved = 0 AND ResolvedAt IS NULL) OR (Resolved = 1 AND ResolvedAt IS NOT NULL))
);
CREATE INDEX IX_clinical_Alerts_Open_BySeverity ON clinical.Alerts(Resolved, SeverityCode DESC, CreatedAt DESC) INCLUDE (PatientID, AlertType);
CREATE INDEX IX_clinical_Alerts_Patient_Time    ON clinical.Alerts(PatientID, CreatedAt DESC) INCLUDE (SeverityCode, Resolved);
CREATE INDEX IX_clinical_Alerts_SeverityTime    ON clinical.Alerts(SeverityCode, CreatedAt DESC) INCLUDE (PatientID, Resolved);
GO

/* ===================
   Row‑Level Security
   =================== */

-- Predicates AFTER all referenced objects exist
CREATE FUNCTION sec.fn_PatientScopePredicate(@PatientID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
    SELECT 1 AS fn_result
    WHERE EXISTS (
        SELECT 1
        FROM core.BedAssignments AS ba
        JOIN ref.Beds  AS b ON b.BedID = ba.BedID
        JOIN ref.Rooms AS r ON r.RoomID = b.RoomID
        WHERE ba.PatientID = @PatientID
          AND ba.DischargeDate IS NULL
          AND (TRY_CONVERT(INT, SESSION_CONTEXT(N'AllowedBuildingId')) IS NULL 
               OR r.BuildingID = TRY_CONVERT(INT, SESSION_CONTEXT(N'AllowedBuildingId')))
          AND (SESSION_CONTEXT(N'AllowedWard') IS NULL OR r.Ward = SESSION_CONTEXT(N'AllowedWard'))
    )
);
GO

CREATE FUNCTION sec.fn_BedAssignmentScopePredicate(@BedID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
    SELECT 1 AS fn_result
    WHERE EXISTS (
        SELECT 1
        FROM ref.Beds  AS b
        JOIN ref.Rooms AS r ON r.RoomID = b.RoomID
        WHERE b.BedID = @BedID
          AND (TRY_CONVERT(INT, SESSION_CONTEXT(N'AllowedBuildingId')) IS NULL 
               OR r.BuildingID = TRY_CONVERT(INT, SESSION_CONTEXT(N'AllowedBuildingId')))
          AND (SESSION_CONTEXT(N'AllowedWard') IS NULL OR r.Ward = SESSION_CONTEXT(N'AllowedWard'))
    )
);
GO

/* Create policy in OFF state, then add predicates one-by-one, then turn ON */
CREATE SECURITY POLICY sec.PatientScopePolicy WITH (STATE = OFF);
GO
ALTER SECURITY POLICY sec.PatientScopePolicy
    ADD FILTER PREDICATE sec.fn_PatientScopePredicate(PatientID) ON clinical.VitalsSnapshots;
GO
ALTER SECURITY POLICY sec.PatientScopePolicy
    ADD FILTER PREDICATE sec.fn_PatientScopePredicate(PatientID) ON clinical.DoctorNotes;
GO
ALTER SECURITY POLICY sec.PatientScopePolicy
    ADD FILTER PREDICATE sec.fn_PatientScopePredicate(PatientID) ON clinical.Symptoms;
GO
ALTER SECURITY POLICY sec.PatientScopePolicy
    ADD FILTER PREDICATE sec.fn_PatientScopePredicate(PatientID) ON clinical.Orders;
GO
ALTER SECURITY POLICY sec.PatientScopePolicy
    ADD FILTER PREDICATE sec.fn_PatientScopePredicate(PatientID) ON clinical.Alerts;
GO
ALTER SECURITY POLICY sec.PatientScopePolicy
    ADD FILTER PREDICATE sec.fn_BedAssignmentScopePredicate(BedID) ON core.BedAssignments;
GO
ALTER SECURITY POLICY sec.PatientScopePolicy WITH (STATE = ON);
