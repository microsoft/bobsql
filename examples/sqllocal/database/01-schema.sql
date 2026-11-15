/* ============================================================================
   Caldova Regional Care Transfer Center
   01-schema.sql : operational, grounding, skill, and AI audit schema
   ============================================================================ */

USE [CaldovaRegionalCare];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE [name] = N'care')
    EXEC(N'CREATE SCHEMA care AUTHORIZATION dbo;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE [name] = N'ops')
    EXEC(N'CREATE SCHEMA ops AUTHORIZATION dbo;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE [name] = N'ai')
    EXEC(N'CREATE SCHEMA ai AUTHORIZATION dbo;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE [name] = N'app')
    EXEC(N'CREATE SCHEMA app AUTHORIZATION dbo;');
GO

CREATE TABLE ops.Facility
(
    FacilityId       int IDENTITY(1,1) NOT NULL,
    FacilityCode     varchar(20) NOT NULL,
    FacilityName     nvarchar(200) NOT NULL,
    FacilityType     varchar(30) NOT NULL,
    RegionName       nvarchar(100) NOT NULL,
    IsActive         bit NOT NULL CONSTRAINT DF_Facility_IsActive DEFAULT (1),
    CONSTRAINT PK_Facility PRIMARY KEY CLUSTERED (FacilityId),
    CONSTRAINT UQ_Facility_FacilityCode UNIQUE (FacilityCode),
    CONSTRAINT CK_Facility_FacilityType CHECK
        (FacilityType IN ('TransferCenter', 'EmergencyDepartment', 'AmbulanceService'))
);
GO

CREATE TABLE care.Person
(
    PersonId             bigint IDENTITY(1,1) NOT NULL,
    RegionalRecordNumber varchar(30) NOT NULL,
    GivenName            nvarchar(100) NOT NULL,
    FamilyName           nvarchar(100) NOT NULL,
    DateOfBirth          date NOT NULL,
    AdministrativeSex   varchar(20) NOT NULL,
    CreatedAt            datetime2(3) NOT NULL CONSTRAINT DF_Person_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Person PRIMARY KEY CLUSTERED (PersonId),
    CONSTRAINT UQ_Person_RegionalRecordNumber UNIQUE (RegionalRecordNumber),
    CONSTRAINT CK_Person_AdministrativeSex CHECK
        (AdministrativeSex IN ('Female', 'Male', 'Nonbinary', 'Unknown'))
);
GO

CREATE TABLE care.HistoricalNote
(
    HistoricalNoteId bigint IDENTITY PRIMARY KEY,
    SourceCode varchar(60) NOT NULL UNIQUE,
    PersonId bigint NOT NULL REFERENCES care.Person(PersonId),
    RecordedAt datetime2(3) NOT NULL,
    Title nvarchar(200) NOT NULL,
    AuthoredBy nvarchar(200) NOT NULL,
    NoteText nvarchar(4000) NOT NULL,
    IsSynthetic bit NOT NULL DEFAULT (1),
    NoteVersion rowversion NOT NULL,
    CONSTRAINT CK_HistoricalNote_Text CHECK (LEN(LTRIM(RTRIM(NoteText))) > 0)
);
GO

CREATE INDEX IX_HistoricalNote_Person_Date
    ON care.HistoricalNote(PersonId, RecordedAt DESC);
GO

CREATE TABLE care.Encounter
(
    EncounterId      bigint IDENTITY(1,1) NOT NULL,
    EncounterNumber  varchar(30) NOT NULL,
    PersonId         bigint NOT NULL,
    FacilityId       int NOT NULL,
    EncounterType    varchar(30) NOT NULL,
    EncounterStatus  varchar(20) NOT NULL,
    StartedAt        datetime2(3) NOT NULL,
    EndedAt          datetime2(3) NULL,
    CONSTRAINT PK_Encounter PRIMARY KEY CLUSTERED (EncounterId),
    CONSTRAINT UQ_Encounter_EncounterNumber UNIQUE (EncounterNumber),
    CONSTRAINT FK_Encounter_Person FOREIGN KEY (PersonId) REFERENCES care.Person(PersonId),
    CONSTRAINT FK_Encounter_Facility FOREIGN KEY (FacilityId) REFERENCES ops.Facility(FacilityId),
    CONSTRAINT CK_Encounter_Type CHECK
        (EncounterType IN ('Emergency', 'Outpatient', 'Inpatient', 'Transfer')),
    CONSTRAINT CK_Encounter_Status CHECK
        (EncounterStatus IN ('Planned', 'Active', 'Completed', 'Cancelled')),
    CONSTRAINT CK_Encounter_Times CHECK (EndedAt IS NULL OR EndedAt >= StartedAt)
);
GO

CREATE INDEX IX_Encounter_Person_StartedAt
    ON care.Encounter(PersonId, StartedAt DESC)
    INCLUDE (EncounterNumber, FacilityId, EncounterType, EncounterStatus, EndedAt);
GO

CREATE TABLE care.Observation
(
    ObservationId    bigint IDENTITY(1,1) NOT NULL,
    EncounterId      bigint NOT NULL,
    ObservationCode  varchar(30) NOT NULL,
    ObservationName  nvarchar(100) NOT NULL,
    NumericValue     decimal(12,3) NULL,
    TextValue        nvarchar(200) NULL,
    Unit             nvarchar(30) NULL,
    IsAlert          bit NOT NULL CONSTRAINT DF_Observation_IsAlert DEFAULT (0),
    ObservedAt       datetime2(3) NOT NULL,
    CONSTRAINT PK_Observation PRIMARY KEY CLUSTERED (ObservationId),
    CONSTRAINT FK_Observation_Encounter FOREIGN KEY (EncounterId) REFERENCES care.Encounter(EncounterId),
    CONSTRAINT CK_Observation_Value CHECK
        ((NumericValue IS NOT NULL AND TextValue IS NULL) OR
         (NumericValue IS NULL AND TextValue IS NOT NULL))
);
GO

CREATE INDEX IX_Observation_Encounter_ObservedAt
    ON care.Observation(EncounterId, ObservedAt DESC)
    INCLUDE (ObservationCode, ObservationName, NumericValue, TextValue, Unit, IsAlert);
GO

CREATE TABLE care.Allergy
(
    AllergyId    int IDENTITY(1,1) NOT NULL,
    AllergyCode  varchar(30) NOT NULL,
    AllergyName  nvarchar(200) NOT NULL,
    CONSTRAINT PK_Allergy PRIMARY KEY CLUSTERED (AllergyId),
    CONSTRAINT UQ_Allergy_AllergyCode UNIQUE (AllergyCode)
);
GO

CREATE TABLE care.PersonAllergy
(
    PersonAllergyId  bigint IDENTITY(1,1) NOT NULL,
    PersonId         bigint NOT NULL,
    AllergyId        int NOT NULL,
    Reaction         nvarchar(300) NULL,
    AllergyStatus    varchar(20) NOT NULL,
    RecordedAt       datetime2(3) NOT NULL,
    CONSTRAINT PK_PersonAllergy PRIMARY KEY CLUSTERED (PersonAllergyId),
    CONSTRAINT FK_PersonAllergy_Person FOREIGN KEY (PersonId) REFERENCES care.Person(PersonId),
    CONSTRAINT FK_PersonAllergy_Allergy FOREIGN KEY (AllergyId) REFERENCES care.Allergy(AllergyId),
    CONSTRAINT UQ_PersonAllergy_Person_Allergy UNIQUE (PersonId, AllergyId),
    CONSTRAINT CK_PersonAllergy_Status CHECK (AllergyStatus IN ('Active', 'Inactive', 'EnteredInError'))
);
GO

CREATE INDEX IX_PersonAllergy_Active
    ON care.PersonAllergy(PersonId, AllergyStatus)
    INCLUDE (AllergyId, Reaction, RecordedAt);
GO

CREATE TABLE care.Medication
(
    MedicationId    int IDENTITY(1,1) NOT NULL,
    MedicationCode  varchar(30) NOT NULL,
    MedicationName  nvarchar(200) NOT NULL,
    CONSTRAINT PK_Medication PRIMARY KEY CLUSTERED (MedicationId),
    CONSTRAINT UQ_Medication_MedicationCode UNIQUE (MedicationCode)
);
GO

CREATE TABLE care.PersonMedication
(
    PersonMedicationId  bigint IDENTITY(1,1) NOT NULL,
    PersonId            bigint NOT NULL,
    MedicationId        int NOT NULL,
    Dose                nvarchar(100) NULL,
    Frequency           nvarchar(100) NULL,
    MedicationStatus    varchar(20) NOT NULL,
    StartedAt           date NULL,
    EndedAt             date NULL,
    CONSTRAINT PK_PersonMedication PRIMARY KEY CLUSTERED (PersonMedicationId),
    CONSTRAINT FK_PersonMedication_Person FOREIGN KEY (PersonId) REFERENCES care.Person(PersonId),
    CONSTRAINT FK_PersonMedication_Medication FOREIGN KEY (MedicationId) REFERENCES care.Medication(MedicationId),
    CONSTRAINT CK_PersonMedication_Status CHECK
        (MedicationStatus IN ('Active', 'Completed', 'Stopped', 'EnteredInError')),
    CONSTRAINT CK_PersonMedication_Dates CHECK (EndedAt IS NULL OR StartedAt IS NULL OR EndedAt >= StartedAt)
);
GO

CREATE INDEX IX_PersonMedication_Active
    ON care.PersonMedication(PersonId, MedicationStatus)
    INCLUDE (MedicationId, Dose, Frequency, StartedAt, EndedAt);
GO

CREATE TABLE ops.Transfer
(
    TransferId              bigint IDENTITY(1,1) NOT NULL,
    TransferNumber          varchar(30) NOT NULL,
    EncounterId             bigint NOT NULL,
    OriginFacilityId        int NOT NULL,
    DestinationFacilityId   int NOT NULL,
    TransportUnit           nvarchar(100) NOT NULL,
    ChiefConcern            nvarchar(200) NOT NULL,
    PriorityCode            tinyint NOT NULL,
    TransferStatus          varchar(30) NOT NULL,
    EstimatedArrivalAt      datetime2(3) NOT NULL,
    DestinationBay          nvarchar(30) NULL,
    ReceivingTeamNotifiedAt datetime2(3) NULL,
    CreatedAt               datetime2(3) NOT NULL CONSTRAINT DF_Transfer_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Transfer PRIMARY KEY CLUSTERED (TransferId),
    CONSTRAINT UQ_Transfer_TransferNumber UNIQUE (TransferNumber),
    CONSTRAINT UQ_Transfer_EncounterId UNIQUE (EncounterId),
    CONSTRAINT FK_Transfer_Encounter FOREIGN KEY (EncounterId) REFERENCES care.Encounter(EncounterId),
    CONSTRAINT FK_Transfer_OriginFacility FOREIGN KEY (OriginFacilityId) REFERENCES ops.Facility(FacilityId),
    CONSTRAINT FK_Transfer_DestinationFacility FOREIGN KEY (DestinationFacilityId) REFERENCES ops.Facility(FacilityId),
    CONSTRAINT CK_Transfer_Priority CHECK (PriorityCode BETWEEN 1 AND 5),
    CONSTRAINT CK_Transfer_Status CHECK
        (TransferStatus IN ('Requested', 'Accepted', 'InTransit', 'Arrived', 'Cancelled')),
    CONSTRAINT CK_Transfer_Facilities CHECK (OriginFacilityId <> DestinationFacilityId)
);
GO

CREATE INDEX IX_Transfer_Queue
    ON ops.Transfer(TransferStatus, EstimatedArrivalAt)
    INCLUDE (TransferNumber, EncounterId, DestinationFacilityId, TransportUnit, ChiefConcern,
             PriorityCode, DestinationBay, ReceivingTeamNotifiedAt);
GO

CREATE TABLE ops.TransferStatusHistory
(
    TransferStatusHistoryId  bigint IDENTITY(1,1) NOT NULL,
    TransferId               bigint NOT NULL,
    TransferStatus           varchar(30) NOT NULL,
    ChangedAt                datetime2(3) NOT NULL CONSTRAINT DF_TransferStatusHistory_ChangedAt DEFAULT (SYSUTCDATETIME()),
    ChangedBy                nvarchar(200) NOT NULL,
    StatusNote               nvarchar(500) NULL,
    CONSTRAINT PK_TransferStatusHistory PRIMARY KEY CLUSTERED (TransferStatusHistoryId),
    CONSTRAINT FK_TransferStatusHistory_Transfer FOREIGN KEY (TransferId) REFERENCES ops.Transfer(TransferId),
    CONSTRAINT CK_TransferStatusHistory_Status CHECK
        (TransferStatus IN ('Requested', 'Accepted', 'InTransit', 'Arrived', 'Cancelled'))
);
GO

CREATE INDEX IX_TransferStatusHistory_Transfer_ChangedAt
    ON ops.TransferStatusHistory(TransferId, ChangedAt DESC)
    INCLUDE (TransferStatus, ChangedBy, StatusNote);
GO

CREATE TABLE ops.FieldNarrative
(
    NarrativeId   bigint IDENTITY(1,1) NOT NULL,
    EncounterId   bigint NOT NULL,
    NarrativeText nvarchar(max) NOT NULL,
    AuthoredBy    nvarchar(200) NOT NULL,
    RecordedAt    datetime2(3) NOT NULL,
    CONSTRAINT PK_FieldNarrative PRIMARY KEY CLUSTERED (NarrativeId),
    CONSTRAINT FK_FieldNarrative_Encounter FOREIGN KEY (EncounterId) REFERENCES care.Encounter(EncounterId)
);
GO

CREATE INDEX IX_FieldNarrative_Encounter_RecordedAt
    ON ops.FieldNarrative(EncounterId, RecordedAt DESC)
    INCLUDE (AuthoredBy);
GO

CREATE TABLE ai.SignalRule
(
    SignalRuleId  int IDENTITY(1,1) NOT NULL,
    SignalType    varchar(30) NOT NULL,
    Pattern       nvarchar(4000) NOT NULL,
    Flags         varchar(10) NOT NULL CONSTRAINT DF_SignalRule_Flags DEFAULT ('i'),
    RuleVersion   int NOT NULL,
    IsActive      bit NOT NULL CONSTRAINT DF_SignalRule_IsActive DEFAULT (1),
    CreatedAt     datetime2(3) NOT NULL CONSTRAINT DF_SignalRule_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_SignalRule PRIMARY KEY CLUSTERED (SignalRuleId),
    CONSTRAINT UQ_SignalRule_Type_Version UNIQUE (SignalType, RuleVersion),
    CONSTRAINT CK_SignalRule_Type CHECK
        (SignalType IN ('Symptom', 'Onset', 'Pain', 'Medication', 'Allergy')),
    CONSTRAINT CK_SignalRule_Version CHECK (RuleVersion > 0)
);
GO

CREATE TABLE ai.ExtractedSignal
(
    ExtractedSignalId  bigint IDENTITY(1,1) NOT NULL,
    NarrativeId       bigint NOT NULL,
    SignalRuleId      int NOT NULL,
    MatchOrdinal      bigint NOT NULL,
    SignalType        varchar(30) NOT NULL,
    SignalValue       nvarchar(1000) NOT NULL,
    StartPosition     int NOT NULL,
    EndPosition       int NOT NULL,
    ExtractedAt       datetime2(3) NOT NULL CONSTRAINT DF_ExtractedSignal_ExtractedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_ExtractedSignal PRIMARY KEY CLUSTERED (ExtractedSignalId),
    CONSTRAINT FK_ExtractedSignal_Narrative FOREIGN KEY (NarrativeId) REFERENCES ops.FieldNarrative(NarrativeId),
    CONSTRAINT FK_ExtractedSignal_Rule FOREIGN KEY (SignalRuleId) REFERENCES ai.SignalRule(SignalRuleId),
    CONSTRAINT UQ_ExtractedSignal_Match UNIQUE (NarrativeId, SignalRuleId, MatchOrdinal),
    CONSTRAINT CK_ExtractedSignal_Positions CHECK (StartPosition > 0 AND EndPosition >= StartPosition)
);
GO

CREATE INDEX IX_ExtractedSignal_Narrative
    ON ai.ExtractedSignal(NarrativeId, SignalType, MatchOrdinal)
    INCLUDE (SignalValue, StartPosition, EndPosition, SignalRuleId);
GO

CREATE TABLE ai.Skill
(
    SkillId       int IDENTITY(1,1) NOT NULL,
    SkillName     sysname NOT NULL,
    SkillVersion  varchar(30) NOT NULL,
    SkillJson     json NOT NULL,
    SkillHash     binary(32) NOT NULL,
    IsApproved    bit NOT NULL CONSTRAINT DF_Skill_IsApproved DEFAULT (0),
    IsActive      bit NOT NULL CONSTRAINT DF_Skill_IsActive DEFAULT (1),
    CreatedAt     datetime2(3) NOT NULL CONSTRAINT DF_Skill_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Skill PRIMARY KEY CLUSTERED (SkillId),
    CONSTRAINT UQ_Skill_Name_Version UNIQUE (SkillName, SkillVersion)
);
GO

CREATE TABLE ai.TransferPacket
(
    TransferPacketId  bigint IDENTITY(1,1) NOT NULL,
    TransferId        bigint NOT NULL,
    PacketVersion     int NOT NULL,
    PacketJson        json NOT NULL,
    PacketHash        binary(32) NOT NULL,
    CreatedAt         datetime2(3) NOT NULL CONSTRAINT DF_TransferPacket_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_TransferPacket PRIMARY KEY CLUSTERED (TransferPacketId),
    CONSTRAINT FK_TransferPacket_Transfer FOREIGN KEY (TransferId) REFERENCES ops.Transfer(TransferId),
    CONSTRAINT UQ_TransferPacket_Transfer_Version UNIQUE (TransferId, PacketVersion),
    CONSTRAINT CK_TransferPacket_Version CHECK (PacketVersion > 0)
);
GO

CREATE TABLE ai.PacketSource
(
    PacketSourceId     bigint IDENTITY(1,1) NOT NULL,
    TransferPacketId   bigint NOT NULL,
    SourceType         varchar(40) NOT NULL,
    SourceRecordKey    nvarchar(100) NOT NULL,
    SourceVersion      nvarchar(50) NULL,
    SourceSummary      nvarchar(1000) NOT NULL,
    SourceHash         binary(32) NOT NULL,
    CONSTRAINT PK_PacketSource PRIMARY KEY CLUSTERED (PacketSourceId),
    CONSTRAINT FK_PacketSource_Packet FOREIGN KEY (TransferPacketId) REFERENCES ai.TransferPacket(TransferPacketId),
    CONSTRAINT UQ_PacketSource_Record UNIQUE (TransferPacketId, SourceType, SourceRecordKey)
);
GO

CREATE TABLE ai.ModelEndpoint
(
    ModelEndpointId  int IDENTITY(1,1) NOT NULL,
    EndpointName     sysname NOT NULL,
    BaseUrl          nvarchar(2000) NOT NULL,
    ModelId          nvarchar(256) NOT NULL,
    CredentialName   sysname NULL,
    TimeoutSeconds   int NOT NULL CONSTRAINT DF_ModelEndpoint_Timeout DEFAULT (120),
    IsActive         bit NOT NULL CONSTRAINT DF_ModelEndpoint_IsActive DEFAULT (1),
    CONSTRAINT PK_ModelEndpoint PRIMARY KEY CLUSTERED (ModelEndpointId),
    CONSTRAINT UQ_ModelEndpoint_Name UNIQUE (EndpointName),
    CONSTRAINT CK_ModelEndpoint_Url CHECK (BaseUrl LIKE N'https://%'),
    CONSTRAINT CK_ModelEndpoint_Timeout CHECK (TimeoutSeconds BETWEEN 1 AND 230)
);
GO

CREATE TABLE ai.ModelInvocation
(
    ModelInvocationId  bigint IDENTITY(1,1) NOT NULL,
    TransferPacketId   bigint NOT NULL,
    SkillId            int NOT NULL,
    ModelEndpointId    int NOT NULL,
    SkillJson          nvarchar(max) NOT NULL,
    RequestJson        nvarchar(max) NOT NULL,
    ResponseJson       nvarchar(max) NULL,
    ReturnCode         int NULL,
    HttpStatusCode     int NULL,
    InvocationStatus   varchar(20) NOT NULL,
    StartedAt          datetime2(3) NOT NULL,
    CompletedAt        datetime2(3) NULL,
    DurationMs         bigint NULL,
    ErrorMessage       nvarchar(2000) NULL,
    CONSTRAINT PK_ModelInvocation PRIMARY KEY CLUSTERED (ModelInvocationId),
    CONSTRAINT FK_ModelInvocation_Packet FOREIGN KEY (TransferPacketId) REFERENCES ai.TransferPacket(TransferPacketId),
    CONSTRAINT FK_ModelInvocation_Skill FOREIGN KEY (SkillId) REFERENCES ai.Skill(SkillId),
    CONSTRAINT FK_ModelInvocation_Endpoint FOREIGN KEY (ModelEndpointId) REFERENCES ai.ModelEndpoint(ModelEndpointId),
    CONSTRAINT CK_ModelInvocation_SkillJson CHECK (ISJSON(SkillJson) = 1),
    CONSTRAINT CK_ModelInvocation_RequestJson CHECK (ISJSON(RequestJson) = 1),
    CONSTRAINT CK_ModelInvocation_ResponseJson CHECK (ResponseJson IS NULL OR ISJSON(ResponseJson) = 1),
    CONSTRAINT CK_ModelInvocation_Status CHECK
        (InvocationStatus IN ('Pending', 'Succeeded', 'Failed')),
    CONSTRAINT CK_ModelInvocation_Times CHECK (CompletedAt IS NULL OR CompletedAt >= StartedAt)
);
GO

CREATE INDEX IX_ModelInvocation_Packet_StartedAt
    ON ai.ModelInvocation(TransferPacketId, StartedAt DESC)
    INCLUDE (SkillId, ModelEndpointId, InvocationStatus, ReturnCode, HttpStatusCode, DurationMs);
GO

CREATE TABLE ai.Briefing
(
    BriefingId         bigint IDENTITY(1,1) NOT NULL,
    ModelInvocationId  bigint NOT NULL,
    Summary            nvarchar(2000) NOT NULL,
    ReviewStatus       varchar(20) NOT NULL CONSTRAINT DF_Briefing_ReviewStatus DEFAULT ('Pending'),
    GeneratedAt        datetime2(3) NOT NULL CONSTRAINT DF_Briefing_GeneratedAt DEFAULT (SYSUTCDATETIME()),
    ReviewedAt         datetime2(3) NULL,
    ReviewedBy         nvarchar(200) NULL,
    CONSTRAINT PK_Briefing PRIMARY KEY CLUSTERED (BriefingId),
    CONSTRAINT UQ_Briefing_ModelInvocation UNIQUE (ModelInvocationId),
    CONSTRAINT FK_Briefing_Invocation FOREIGN KEY (ModelInvocationId) REFERENCES ai.ModelInvocation(ModelInvocationId),
    CONSTRAINT CK_Briefing_ReviewStatus CHECK
        (ReviewStatus IN ('Pending', 'Approved', 'Rejected')),
    CONSTRAINT CK_Briefing_Review CHECK
        ((ReviewStatus = 'Pending' AND ReviewedAt IS NULL AND ReviewedBy IS NULL) OR
         (ReviewStatus IN ('Approved', 'Rejected') AND ReviewedAt IS NOT NULL AND ReviewedBy IS NOT NULL))
);
GO

CREATE TABLE ai.BriefingItem
(
    BriefingItemId  bigint IDENTITY(1,1) NOT NULL,
    BriefingId      bigint NOT NULL,
    SectionName     varchar(30) NOT NULL,
    DisplayOrder    smallint NOT NULL,
    ItemText        nvarchar(1000) NOT NULL,
    PacketSourceId  bigint NULL,
    CONSTRAINT PK_BriefingItem PRIMARY KEY CLUSTERED (BriefingItemId),
    CONSTRAINT FK_BriefingItem_Briefing FOREIGN KEY (BriefingId) REFERENCES ai.Briefing(BriefingId),
    CONSTRAINT FK_BriefingItem_PacketSource FOREIGN KEY (PacketSourceId) REFERENCES ai.PacketSource(PacketSourceId),
    CONSTRAINT UQ_BriefingItem_Order UNIQUE (BriefingId, SectionName, DisplayOrder),
    CONSTRAINT CK_BriefingItem_Section CHECK
        (SectionName IN ('KeyContext', 'ConfirmOnArrival', 'HistoricalContext')),
    CONSTRAINT CK_BriefingItem_Order CHECK (DisplayOrder > 0)
);
GO

CREATE TABLE ai.BriefingSource
(
    BriefingId      bigint NOT NULL,
    PacketSourceId  bigint NOT NULL,
    CitationOrder   smallint NOT NULL,
    CONSTRAINT PK_BriefingSource PRIMARY KEY CLUSTERED (BriefingId, PacketSourceId),
    CONSTRAINT FK_BriefingSource_Briefing FOREIGN KEY (BriefingId) REFERENCES ai.Briefing(BriefingId),
    CONSTRAINT FK_BriefingSource_PacketSource FOREIGN KEY (PacketSourceId) REFERENCES ai.PacketSource(PacketSourceId),
    CONSTRAINT UQ_BriefingSource_Order UNIQUE (BriefingId, CitationOrder),
    CONSTRAINT CK_BriefingSource_Order CHECK (CitationOrder > 0)
);
GO

SELECT
    COUNT(*) AS ApplicationTableCount,
    SUM(CASE WHEN c.system_type_id = TYPE_ID(N'vector') THEN 1 ELSE 0 END) AS VectorColumnCount
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.columns AS c ON c.object_id = t.object_id
WHERE s.[name] IN (N'care', N'ops', N'ai', N'app');
GO

IF COL_LENGTH(N'ai.BriefingItem', N'PacketSourceId') IS NULL
BEGIN
    ALTER TABLE ai.BriefingItem ADD PacketSourceId bigint NULL;
    ALTER TABLE ai.BriefingItem ADD CONSTRAINT FK_BriefingItem_PacketSource
        FOREIGN KEY (PacketSourceId) REFERENCES ai.PacketSource(PacketSourceId);
END;
IF EXISTS (SELECT 1 FROM sys.check_constraints
           WHERE parent_object_id = OBJECT_ID(N'ai.BriefingItem')
             AND name = N'CK_BriefingItem_Section' AND definition NOT LIKE '%HistoricalContext%')
BEGIN
    BEGIN TRANSACTION;
    ALTER TABLE ai.BriefingItem DROP CONSTRAINT CK_BriefingItem_Section;
    ALTER TABLE ai.BriefingItem ADD CONSTRAINT CK_BriefingItem_Section
        CHECK (SectionName IN ('KeyContext', 'ConfirmOnArrival', 'HistoricalContext'));
    COMMIT;
END;
GO
