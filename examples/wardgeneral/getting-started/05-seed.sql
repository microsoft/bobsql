/* ============================================================================
   Ward General — Getting Started
   05-seed.sql      : reproducible synthetic seed for Ward General Hospital.
   Run order        : 5 of 5  (after 04-procedures.sql)

   What this script populates (volumes per the Getting Started outline §3):

       ops.Department      ~ 12   (explicit)
       ops.Unit            ~ 20   (explicit)
       ops.Bed             ~400   (explicit)
       ops.Provider        ~150   (34 named + generated)
       clinical.Patient    ~ 10,000          (30 named + generated)
       clinical.Allergy    ~ 15,000
       clinical.Encounter  ~ 40,000          (400 active, rest discharged)
       ops.Appointment     ~120,000
       clinical.Diagnosis  ~ 80,000
       clinical.ClinicalNote ~ 60,000        (~1-2 KB per NoteText)
       clinical.MedicationOrder ~100,000
       clinical.LabResult  ~200,000          (~0.5-1 KB per ResultJson)
       clinical.Observation ~108M            (the size anchor; essentially the
                                              whole database on its own)

   Anchor target: about 12 GB after this seed completes. Performance grows
   clinical.Observation to ~1 TB via a one-time author-run grow
   script — readers stay at the volumes seeded here.

   ----------------------------------------------------------------------------
   DISCLAIMER — PURELY FICTIONAL, FULLY SYNTHETIC DATA
   ----------------------------------------------------------------------------
   This is the through-line dataset for the project. Every value it produces is
   PURELY FICTIONAL and FULLY SYNTHETIC. It contains NO real protected health
   information (PHI) and does NOT represent any real person, patient, provider,
   event, place, diagnosis, medication, lab result, insurer, or organization.
   Any resemblance to a real individual or institution is coincidental.
   Recognisable names are *Seinfeld* supporting cast, used purely as memorable
   flavour to make the data easier to follow. Jerry does not appear.

   This data was GENERATED WITH AI ASSISTANCE. Although plausible in shape, it
   DOES NOT accurately represent real medical, clinical, laboratory,
   pharmacological, or billing data IN ANY WAY. It exists SOLELY to illustrate
   Azure SQL Hyperscale features in this project.

   IT MUST NOT BE USED for any clinical, diagnostic, treatment, or other medical
   purpose; nor to train, fine-tune, validate, or evaluate any machine-learning
   or AI model; nor for any real-world healthcare decision of any kind. It is
   provided for illustration and learning ONLY.
   ----------------------------------------------------------------------------

   Knob (@Scale): the bulky tables Encounter (discharged), Appointment, and
   Observation each declare a local `@Scale FLOAT = 1.0` at the top of their
   batch. To scale the seed up or down, edit those three values together.
   Default 1.0 produces the volumes documented above. Reference data
   (Department / Unit / Bed / named Providers / named Patients) is not
   scaled by @Scale — those are deterministic constants.

   Run time: at @Scale = 1.0 the Observation load dominates. Measured
   ~16 minutes on an HS_Gen5_8 primary (2026-07-08). The load is log-rate
   gated (~105 MiB/s), so a larger vCore size does NOT shorten it — see
   Performance §5 for why.

   Idempotence: re-runnable. The script TRUNCATEs the synthesised tables
   and reseeds Patient / Provider / Department / Unit / Bed. Identity
   counters are reset.

   Re-running after AI-Ready SQL has been deployed: AI-Ready SQL adds two tables that take a
   foreign key on data this script owns — clinical.ClinicalNoteEmbeddings on
   ClinicalNote, and clinical.AIAssistanceLog on Encounter. Either one blocks
   the reset below. The reset therefore DROPS both first; 06 and 08 recreate
   them. Dropping is not optional for the assistance log, which is an
   append-only ledger table and so cannot be emptied at all. See the note there.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
SET XACT_ABORT ON;
SET NOCOUNT ON;
GO

/* ---------- Knobs --------------------------------------------------------
   Default volumes target the anchor size quoted in the header above.
   Variables declared per-batch (the bulky tables Encounter / Appointment /
   Observation scale with @Scale); reference data does not scale.
   To scale the whole seed up or down, edit @Scale in each of the three
   batches below that declare it (search for `@Scale FLOAT`).
----------------------------------------------------------------------- */
GO

/* ============================================================================
   Reset (idempotent re-run)
   Leaf tables TRUNCATE (which also resets their IDENTITY to 1). The parent
   tables are FK-referenced, so they can't be TRUNCATEd — DELETE instead, in
   child-first order. We do NOT reseed identity: on the canonical 02 -> 05 run
   the tables are freshly created by 02-tables.sql, so identity naturally
   starts at 1. (Reseeding to 0 on a never-inserted table makes the first id 0;
   and the FK inserts below join to ACTUAL ids via ROW_NUMBER, so they don't
   depend on the id range anyway.) Re-running 05 alone continues the parents'
   identity sequence — still valid; run 02 -> 05 for 1-based ids.
   ============================================================================ */
PRINT N'--- Resetting tables ---';

/* AI-Ready SQL artefacts first, if they exist. Both take a foreign key into data this
   script owns, and a foreign key blocks TRUNCATE outright — TRUNCATE is refused
   on any table that is the target of one, whether or not the child holds a
   single row. So on a 02 -> 05 -> 06/07/08 -> 05 loop, neither clears without
   this.

   clinical.ClinicalNoteEmbeddings is DROPped rather than emptied because it is
   derived data with no meaning once the notes it was computed from are gone —
   06-ai-embeddings.sql recreates the table and regenerates it. The DiskANN
   index must go before its table.

   clinical.AIAssistanceLog is DROPped too, and that one is forced rather than
   chosen. 08-ai-assistance.sql creates it WITH (LEDGER = ON (APPEND_ONLY = ON)),
   and an append-only ledger table supports neither DELETE nor TRUNCATE — see
   Ledger considerations and limitations, items 3 and 4. This script used to
   carry a DELETE here, and it failed at COMPILE time, which aborts the whole
   batch before any statement in it runs: the embeddings DROP above never
   executed, the PRINT never printed, and the reset silently did nothing while
   the inserts below appended a second copy of the data on top of the first.
   DROP is the only route that works. 08 recreates the table.

   Dropping a ledger table is a soft delete BY DESIGN, and the shadow it leaves
   is meant to stay: the object is renamed to MSSQL_DroppedLedgerTable_* and
   physically retained so the ledger digest stays verifiable — see DROP TABLE,
   Remarks. Do not try to clean these up. Each reseed leaves one more, and that
   is the documented price of a tamper-evident trail, not a leak.

   Verified live on 2026-08-15 that the retained shadow does NOT keep its
   foreign key, so the DROP genuinely unblocks the DELETE of Encounter below:
   before the drop clinical.Encounter had nine referencing tables, after it
   eight, zero foreign keys were held by any shadow, and a DELETE against
   Encounter compiled and ran. Worth stating because the opposite would have
   been just as plausible and would have made this whole approach useless.

   BOTH DROPS ONLY FIRE ON A RE-RUN. On the normal reader path — 02 before 05 —
   neither table exists yet and both IF guards are no-ops. They matter only when
   the AI-Ready SQL scripts have already been deployed and this seed is being run a
   second time.

    AFTER A RE-RUN, AI-READY SQL MUST BE REDEPLOYED: 06-ai-embeddings.sql to rebuild
   the embeddings table and regenerate the vectors, 07-vector-index.sql for the
   DiskANN index, and 08-ai-assistance.sql to recreate the audit ledger. The
   Ward General App app runs fine without them as long as the AiAssistance flag is off. */
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'VIX_ClinicalNoteEmbeddings_Embedding')
    DROP INDEX VIX_ClinicalNoteEmbeddings_Embedding ON clinical.ClinicalNoteEmbeddings;
IF OBJECT_ID('clinical.ClinicalNoteEmbeddings', 'U') IS NOT NULL
    DROP TABLE clinical.ClinicalNoteEmbeddings;
IF OBJECT_ID('clinical.AIAssistanceLog', 'U') IS NOT NULL
    DROP TABLE clinical.AIAssistanceLog;
GO

/* Children before parents. Every table holding a foreign key into Encounter or
   Patient has to be emptied before those parents can be DELETEd, so this list
   must name all nine children of Encounter — including Symptom, CareTeamMember
   and ImagingOrder, which section 14 populates. */
TRUNCATE TABLE clinical.Observation;
TRUNCATE TABLE clinical.LabResult;
TRUNCATE TABLE clinical.MedicationOrder;
TRUNCATE TABLE clinical.ClinicalNote;
TRUNCATE TABLE clinical.Diagnosis;
TRUNCATE TABLE clinical.Allergy;
TRUNCATE TABLE clinical.Symptom;
TRUNCATE TABLE clinical.CareTeamMember;
TRUNCATE TABLE clinical.ImagingOrder;
DELETE FROM ops.Appointment;
DELETE FROM clinical.Encounter;
DELETE FROM clinical.Patient;
DELETE FROM ops.Provider;
DELETE FROM ops.Bed;
DELETE FROM ops.Unit;
DELETE FROM ops.Department;
GO

/* ============================================================================
   1.  ops.Department  (12 rows, explicit)
   ============================================================================ */
PRINT N'--- ops.Department ---';
INSERT INTO ops.Department (Name, Specialty) VALUES
    (N'Cardiology',           N'Cardiology'),
    (N'Oncology',              N'Hematology-Oncology'),
    (N'Emergency Medicine',    N'Emergency Medicine'),
    (N'Internal Medicine',     N'Internal Medicine'),
    (N'Surgery',               N'General Surgery'),
    (N'Pediatrics',            N'Pediatrics'),
    (N'Obstetrics-Gynecology', N'OB-GYN'),
    (N'Orthopedics',           N'Orthopedic Surgery'),
    (N'Neurology',             N'Neurology'),
    (N'Pulmonology',           N'Pulmonary Medicine'),
    (N'Psychiatry',            N'Psychiatry'),
    (N'Radiology',             N'Radiology');
GO

/* ============================================================================
   2.  ops.Unit  (20 rows, explicit)
   ============================================================================ */
PRINT N'--- ops.Unit ---';
INSERT INTO ops.Unit (Name, UnitType, DepartmentId)
SELECT u.Name, u.UnitType, d.DepartmentId
FROM (VALUES
    (N'ED Main',          N'ED',         N'Emergency Medicine'),
    (N'ED Fast Track',    N'ED',         N'Emergency Medicine'),
    (N'ICU A',            N'ICU',        N'Internal Medicine'),
    (N'ICU B',            N'ICU',        N'Internal Medicine'),
    (N'3 West',           N'Med-Surg',   N'Internal Medicine'),
    (N'3 East',           N'Med-Surg',   N'Internal Medicine'),
    (N'4 North',          N'Telemetry',  N'Cardiology'),
    (N'4 South',          N'Telemetry',  N'Cardiology'),
    (N'5 West',           N'Med-Surg',   N'Oncology'),
    (N'5 East',           N'Telemetry',  N'Cardiology'),
    (N'L and D',          N'L&D',        N'Obstetrics-Gynecology'),
    (N'Postpartum',       N'Med-Surg',   N'Obstetrics-Gynecology'),
    (N'NICU',             N'ICU',        N'Pediatrics'),
    (N'PICU',             N'ICU',        N'Pediatrics'),
    (N'OR Suite A',       N'OR',         N'Surgery'),
    (N'OR Suite B',       N'OR',         N'Surgery'),
    (N'PACU',             N'Med-Surg',   N'Surgery'),
    (N'Same-Day Surgery', N'Med-Surg',   N'Surgery'),
    (N'Adult Psych',      N'Med-Surg',   N'Psychiatry'),
    (N'Geriatric Psych',  N'Med-Surg',   N'Psychiatry')
) u(Name, UnitType, DeptName)
JOIN ops.Department d ON d.Name = u.DeptName;
GO

/* ============================================================================
   3.  ops.Bed  (~400 rows; 20 beds per unit)
   ============================================================================ */
PRINT N'--- ops.Bed ---';
INSERT INTO ops.Bed (UnitId, BedNumber, BedStatus)
SELECT
    u.UnitId,
    CONCAT(LEFT(REPLACE(u.Name, N' ', N''), 4), N'-',
           RIGHT(CONCAT(N'00', gs.value), 3))               AS BedNumber,
    N'Available'                                            AS BedStatus
FROM ops.Unit u
CROSS JOIN GENERATE_SERIES(1, 20) gs;
GO

/* ============================================================================
   4.  ops.Provider  (34 named Seinfeld cast + Ward family + ~116 generated = 150)
   ============================================================================ */
PRINT N'--- ops.Provider (named: Seinfeld cast + Ward family, Jerry excluded) ---';
INSERT INTO ops.Provider (FullName, DepartmentId, Role, EntraObjectId)
SELECT v.FullName, d.DepartmentId, v.Role, NEWID()
FROM (VALUES
    /* The recurring four — minus Jerry */
    (N'Dr. Cosmo Kramer',          N'Internal Medicine',     N'Resident'),
    (N'Dr. Elaine Benes',          N'Cardiology',            N'Attending'),
    (N'Dr. George Costanza',       N'Psychiatry',            N'Resident'),
    /* Costanzas + Seinfeld parents + Uncle Leo */
    (N'Dr. Frank Costanza',        N'Cardiology',            N'Attending'),
    (N'Dr. Estelle Costanza',      N'Internal Medicine',     N'Attending'),
    (N'Dr. Helen Seinfeld',        N'Internal Medicine',     N'Attending'),
    (N'Dr. Morty Seinfeld',        N'Internal Medicine',     N'Attending'),
    (N'Dr. Leo Gerard',            N'Internal Medicine',     N'Hospitalist'),
    /* Canonical "Dr." in the show */
    (N'Dr. Tim Whatley',           N'Pulmonology',           N'Attending'),
    /* Recurring supporting cast */
    (N'Dr. Susan Ross',            N'Surgery',               N'Attending'),
    (N'Dr. David Puddy',           N'Orthopedics',           N'Attending'),
    (N'Dr. Jackie Chiles',         N'Emergency Medicine',    N'Attending'),
    (N'Dr. Jacopo Peterman',       N'Oncology',              N'Attending'),
    (N'Dr. Justin Pitt',           N'Internal Medicine',     N'Attending'),
    (N'Dr. Mickey Abbott',         N'Pediatrics',            N'Attending'),
    (N'Dr. Sidra Holland',         N'Obstetrics-Gynecology', N'Attending'),
    (N'Dr. Sue Ellen Mischke',     N'Obstetrics-Gynecology', N'Attending'),
    (N'Dr. Lloyd Braun',           N'Psychiatry',            N'Attending'),
    (N'Dr. Kenny Bania',           N'Internal Medicine',     N'Resident'),
    (N'Dr. Donna Chang',           N'Internal Medicine',     N'Resident'),
    (N'Dr. Bob Cobb',              N'Neurology',             N'Attending'),     -- the Maestro
    (N'Dr. Norman Lippman',        N'Psychiatry',            N'Attending'),
    (N'Dr. Carl Wilhelm',          N'Radiology',             N'Attending'),
    (N'Dr. Reggie Singer',         N'Emergency Medicine',    N'Resident'),
    (N'Dr. Tor Eckman',            N'Internal Medicine',     N'Resident'),     -- "holistic healer"
    (N'Dr. Babs Kramer',           N'Internal Medicine',     N'Hospitalist'),  -- Kramer's mother
    (N'Dr. Sally Weaver',          N'Pediatrics',            N'Resident'),
    (N'Dr. Russell Dalrymple',     N'Surgery',               N'Attending'),
    /* The Ward family — namesakes of Ward General Hospital */
    (N'Dr. Claudia Ward',          N'Internal Medicine',     N'Chief of Staff'),
    (N'Dr. Ginger Ward',           N'Cardiology',            N'Attending'),
    (N'Dr. Ryan Ward',             N'Surgery',               N'Resident'),
    (N'Dr. Troy Ward',             N'Emergency Medicine',    N'Attending'),
    (N'Dr. Blair Ward',            N'Pediatrics',            N'Attending'),
    (N'Dr. Elizabeth Ward',        N'Oncology',              N'Attending')
) v(FullName, DeptName, Role)
JOIN ops.Department d ON d.Name = v.DeptName;
GO

/* Generated providers — fill out to ~150 across all departments.
   NAMING CONVENTION (all synthetic — see header disclaimer): the NAMED cast
   above is deliberately fictional (Seinfeld characters + the Ward family). These
   generated "filler" providers pair a common given name with an INVENTED,
   clearly-fictional surname so that no first+last combination maps to an
   identifiable, findable real clinician. Do NOT reintroduce common real surnames
   here (a realistic first+last cross-product will eventually collide with a real
   professional — e.g. "Taylor Brooks" is a real eye doctor).
   Random name/role indices are materialised ONCE per row in CROSS APPLY r.
   A NEWID() placed directly inside CHOOSE is re-evaluated per internal
   comparison, so the index isn't stable and CHOOSE can fall through to NULL. */
INSERT INTO ops.Provider (FullName, DepartmentId, Role, EntraObjectId)
SELECT
    CONCAT(N'Dr. ',
        CHOOSE(r.fi,
               N'Alex',N'Sam',N'Jordan',N'Taylor',N'Morgan',N'Casey',
               N'Riley',N'Jamie',N'Dakota',N'Avery',N'Rowan',N'Quinn',
               N'Logan',N'Hayden',N'Drew',N'Emerson',N'Skyler',N'Reese',
               N'Phoenix',N'Sage'),
        N' ',
        CHOOSE(r.li,
               N'Winterbourne',N'Ashdown',N'Thornevale',N'Brightwater',N'Ravenscroft',N'Hollowell',
               N'Fairholm',N'Ashcombe',N'Merrowdale',N'Larkmoor',N'Stormhaven',N'Oakmere',
               N'Frostbourne',N'Highwillow',N'Duskwood',N'Emberly',N'Glasswell',N'Nettlewood',
               N'Quillfield',N'Vesperton')),
    d.DepartmentId,
    CHOOSE(r.ri, N'Attending', N'Resident', N'Hospitalist', N'Fellow'),
    NEWID()
FROM GENERATE_SERIES(1, 116) gs
CROSS APPLY (SELECT
    ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % 20 + 1 AS fi,
    ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % 20 + 1 AS li,
    ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % 4  + 1 AS ri
) r
CROSS APPLY (
    SELECT TOP 1 DepartmentId
    FROM ops.Department
    ORDER BY (gs.value + DepartmentId) % 12
) d;
GO

/* ============================================================================
   5.  clinical.Patient  (30 named Seinfeld supporting cast + ~9,970 generated)
   ============================================================================ */
PRINT N'--- clinical.Patient (named: Seinfeld supporting cast) ---';

/* The named patients first — recognisable supporting cast, no Jerry. */
INSERT INTO clinical.Patient
    (MRN, FullName, DateOfBirth, Sex, Email, Phone, City, PostalCode, InsuranceJson)
SELECT
    CONCAT(N'WG-', RIGHT(CONCAT(N'000000', ROW_NUMBER() OVER (ORDER BY v.FullName)), 7)),
    v.FullName,
    v.DateOfBirth,
    v.Sex,
    v.Email,
    v.Phone,
    v.City,
    v.PostalCode,
    JSON_OBJECT(
        'insurer'           : v.Insurer,
        'memberId'          : CONCAT(LEFT(v.Insurer, 2), N'-7745-', ABS(CHECKSUM(v.FullName)) % 9999),
        'groupId'           : CONCAT(N'GRP-', ABS(CHECKSUM(v.Insurer)) % 999, N'-', ABS(CHECKSUM(v.City)) % 9999),
        'planName'          : CONCAT(v.Insurer, N' Premier PPO'),
        'planType'          : N'PPO',
        'effectiveFrom'     : N'2024-01-01',
        'effectiveTo'       : N'2026-12-31',
        'primarySubscriber' : N'Self',
        'copay'             : JSON_OBJECT('primary': 25, 'specialist': 50, 'ED': 250),
        'deductibleUsd'     : 1500,
        'outOfPocketMaxUsd' : 5000,
        'networkStatus'     : N'InNetwork',
        'phone'             : N'+1-555-201-7700',
        'claimsAddress'     : N'PO Box 9000, Madison WI'
    )
FROM (VALUES
    (N'Newman Postal',          '1959-08-14', N'Male',   N'newman@waship.example',    N'+1-212-555-0142', N'New York',    N'10025', N'Vandelay Mutual'),
    (N'Babu Bhatt',             '1957-03-22', N'Male',   N'babu@dreamcafe.example',   N'+1-212-555-0118', N'New York',    N'10009', N'PennyPacker Health'),
    (N'Yev Kassem',             '1944-11-02', N'Male',   N'soup@kassem.example',      N'+1-212-555-0177', N'New York',    N'10019', N'Vandelay Mutual'),
    (N'Marla Penny',            '1963-05-30', N'Female', N'marla@example.com',        N'+1-212-555-0123', N'New York',    N'10023', N'Varnsen Health'),
    (N'Joe Davola',             '1961-02-17', N'Male',   N'joe@davola.example',       N'+1-212-555-0156', N'New York',    N'10001', N'PennyPacker Health'),
    (N'Jean-Paul Jean-Paul',    '1968-09-09', N'Male',   N'jp@marathon.example',      N'+1-212-555-0188', N'New York',    N'10018', N'Vandelay Mutual'),
    (N'Bob Sacamano',           '1955-07-04', N'Male',   N'bob@sacamano.example',     N'+1-212-555-0119', N'New York',    N'10003', N'Varnsen Health'),
    (N'Russell Dalrymple',      '1949-12-01', N'Male',   N'russell@nbc.example',      N'+1-212-555-0144', N'New York',    N'10020', N'PennyPacker Health'),
    (N'Tina Robbins',           '1962-04-26', N'Female', N'tina@example.com',         N'+1-212-555-0167', N'New York',    N'10021', N'Vandelay Mutual'),
    (N'Drake Stevens',          N'1965-10-14', N'Male',   N'thedrake@example.com',     N'+1-212-555-0102', N'New York',    N'10024', N'Varnsen Health'),
    (N'Pamela Rosenstein',      N'1969-01-23', N'Female', N'pamela@example.com',       N'+1-212-555-0185', N'New York',    N'10128', N'PennyPacker Health'),
    (N'James Bookman',          N'1942-06-08', N'Male',   N'jbookman@library.example', N'+1-212-555-0150', N'New York',    N'10016', N'Vandelay Mutual'),
    (N'Corky Ramirez',          N'1958-07-04', N'Male',   N'corky@example.com',        N'+1-212-555-0110', N'New York',    N'10017', N'Varnsen Health'),
    (N'Wendy Penewipple',       N'1967-12-30', N'Female', N'wendy@example.com',        N'+1-212-555-0173', N'New York',    N'10025', N'PennyPacker Health'),
    (N'Gail Cunningham',         N'1964-03-15', N'Female', N'gail@example.com',         N'+1-212-555-0166', N'New York',    N'10011', N'Vandelay Mutual'),
    (N'Aaron Beriak',           N'1968-08-19', N'Male',   N'aaron@example.com',        N'+1-212-555-0181', N'New York',    N'10010', N'Varnsen Health'),
    (N'Art Vandelay',           N'1958-11-11', N'Male',   N'art@vandelay.example',     N'+1-212-555-0100', N'New York',    N'10003', N'PennyPacker Health'),
    (N'H. E. Pennypacker',      N'1956-04-04', N'Male',   N'hep@pennypacker.example',  N'+1-212-555-0101', N'New York',    N'10002', N'Vandelay Mutual'),
    (N'Kel Varnsen',            N'1959-05-05', N'Male',   N'kel@varnsen.example',      N'+1-212-555-0103', N'New York',    N'10004', N'Varnsen Health'),
    (N'Martin Van Nostrand',    N'1957-06-06', N'Male',   N'mvn@example.com',          N'+1-212-555-0104', N'New York',    N'10005', N'PennyPacker Health'),
    (N'Steven Snell',           N'1970-02-28', N'Male',   N'snell@example.com',        N'+1-212-555-0190', N'New York',    N'10128', N'Vandelay Mutual'),
    (N'Toby Bertini',           N'1965-09-12', N'Female', N'toby@example.com',         N'+1-212-555-0189', N'New York',    N'10006', N'Varnsen Health'),
    (N'Maureen Cain',           N'1968-07-21', N'Female', N'maureen@example.com',      N'+1-212-555-0175', N'New York',    N'10007', N'PennyPacker Health'),
    (N'Christie Maslo',         N'1971-01-17', N'Female', N'christie@example.com',     N'+1-212-555-0162', N'New York',    N'10008', N'Vandelay Mutual'),
    (N'Pierre Doucet',          N'1960-10-10', N'Male',   N'pierre@example.com',       N'+1-212-555-0152', N'New York',    N'10013', N'Varnsen Health'),
    (N'Earl Haffler',           N'1934-03-03', N'Male',   N'earl@example.com',         N'+1-212-555-0140', N'New York',    N'10026', N'PennyPacker Health'),
    (N'Jeffrey Fogel',          N'1962-08-08', N'Male',   N'jeffrey@parksdept.example', N'+1-212-555-0145', N'New York',   N'10027', N'Vandelay Mutual'),
    (N'Connie Pomerantz',       N'1966-11-19', N'Female', N'connie@example.com',       N'+1-212-555-0148', N'New York',    N'10028', N'Varnsen Health'),
    (N'Karen Hennigan',         N'1972-04-04', N'Female', N'karen@example.com',        N'+1-212-555-0163', N'New York',    N'10029', N'PennyPacker Health'),
    (N'Sandra Galbraith',       N'1969-12-24', N'Female', N'sandra@example.com',       N'+1-212-555-0192', N'New York',    N'10030', N'Vandelay Mutual')
) v(FullName, DateOfBirth, Sex, Email, Phone, City, PostalCode, Insurer);
GO

/* Generated bulk patients to reach @PatientCount total. */
DECLARE @Have INT = (SELECT COUNT(*) FROM clinical.Patient);
DECLARE @Need INT = 10000 - @Have;
PRINT CONCAT(N'--- clinical.Patient (generated bulk): need ', @Need, N' rows ---');

INSERT INTO clinical.Patient
    (MRN, FullName, DateOfBirth, Sex, Email, Phone, City, PostalCode, InsuranceJson)
SELECT
    CONCAT(N'WG-', RIGHT(CONCAT(N'000000', gs.value + @Have), 7)),
    CONCAT(
        CHOOSE(r.fi,
            N'Avery',N'Bailey',N'Cameron',N'Devon',N'Eden',N'Finley',
            N'Gray',N'Harper',N'Indigo',N'Jules',N'Kai',N'Lane',
            N'Micah',N'Noa',N'Oakley',N'Parker',N'Quinn',N'Reagan',
            N'Sage',N'Tate',N'Umber',N'Vail',N'Wren',N'Yael',
            N'Amara',N'Bodhi',N'Celeste',N'Dario',N'Esme',N'Frankie',
            N'Giselle',N'Hugo',N'Ivy',N'Jonah',N'Keira',N'Leon',
            N'Mira',N'Nero',N'Odette',N'Priya'),
        N' ',
        CHOOSE(r.li,
            N'Adler',N'Barker',N'Conroy',N'Doyle',N'Esposito',N'Finch',
            N'Garber',N'Holcomb',N'Ingram',N'Jansen',N'Kobayashi',N'Lassiter',
            N'Maldonado',N'Nguyen',N'Okafor',N'Petrov',N'Quintero',N'Reyes',
            N'Sokolov',N'Tanaka',N'Underwood',N'Vasquez',N'Whitaker',N'Xiang',
            N'Yousef',N'Zheng',N'Brennan',N'Caldwell',N'Donnelly',N'Eberhardt',
            N'Abara',N'Bianchi',N'Castellanos',N'Dubois',N'Eriksson',N'Fitzgerald',
            N'Goldberg',N'Haddad',N'Ishikawa',N'Johansson',N'Kowalski',N'Lindqvist',
            N'Moreau',N'Nakamura',N'Okonkwo',N'Rossi',N'Silva',N'Tremblay')),
    /* Age, not birth year. A hardcoded 1930 + (n % 96) window was fine on the
       day it was written and quietly rots afterwards: it fixes the YOUNGEST
       patient at a birth year that recedes as the calendar moves, so the
       roster ages by one year every year and eventually holds no infants at
       all. The NICU draws from patients under one year old, so an empty
       neonatal cohort would divide by zero and abort the seed -- for a reader
       running the project a year after it shipped, with nothing on screen to
       explain why. Counting backwards in DAYS from today keeps a uniform
       spread of ages from newborn to ninety-five whenever the seed is run,
       and cannot produce a birth date in the future. */
    DATEADD(DAY, -(ABS(CHECKSUM(NEWID())) % 35064), CAST(SYSUTCDATETIME() AS DATE)),
    CASE WHEN gs.value % 2 = 0 THEN N'Female' ELSE N'Male' END,
    CONCAT(N'patient', gs.value + @Have, N'@example.com'),
    CONCAT(N'+1-212-555-',
           RIGHT(CONCAT(N'0000', ABS(CHECKSUM(NEWID())) % 10000), 4)),
    CHOOSE(((gs.value * 31) % 6) + 1,
           N'New York', N'Brooklyn', N'Queens', N'Bronx', N'Hoboken', N'Yonkers'),
    CONCAT(N'1', RIGHT(CONCAT(N'0000', ABS(CHECKSUM(NEWID())) % 10000), 4)),
    JSON_OBJECT(
        'insurer'           : CHOOSE(((gs.value * 17) % 4) + 1,
                                     N'Vandelay Mutual', N'PennyPacker Health',
                                     N'Varnsen Health',  N'Collier Health Plan'),
        'memberId'          : CONCAT(N'M-', RIGHT(CONCAT(N'00000', gs.value), 6)),
        'groupId'           : CONCAT(N'GRP-', (gs.value % 999), N'-',
                                     RIGHT(CONCAT(N'0000', gs.value % 9999), 4)),
        'planName'          : CHOOSE(((gs.value * 23) % 3) + 1,
                                     N'Premier PPO', N'Essential HMO', N'Bronze HDHP'),
        'planType'          : CHOOSE(((gs.value * 23) % 3) + 1, N'PPO', N'HMO', N'HDHP'),
        'effectiveFrom'     : N'2024-01-01',
        'effectiveTo'       : N'2026-12-31',
        'primarySubscriber' : N'Self',
        'copay'             : JSON_OBJECT('primary': 25, 'specialist': 50, 'ED': 250),
        'deductibleUsd'     : 1500,
        'outOfPocketMaxUsd' : 5000,
        'networkStatus'     : N'InNetwork',
        'phone'             : N'+1-555-201-7700',
        'claimsAddress'     : N'PO Box 9000, Madison WI'
    )
FROM GENERATE_SERIES(1, 9970) gs
CROSS APPLY (SELECT
    ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % 40 + 1 AS fi,
    ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % 48 + 1 AS li) r
WHERE gs.value <= @Need;
GO

/* ============================================================================
   6.  clinical.Allergy  (~15,000 — random subset of patients)
   ============================================================================ */
PRINT N'--- clinical.Allergy ---';
INSERT INTO clinical.Allergy (PatientId, Substance, Reaction, Severity)
SELECT TOP (15000)
    p.PatientId,
    CHOOSE(((p.PatientId * 7 + gs.value) % 10) + 1,
        N'Penicillin', N'Sulfa', N'Latex', N'Peanuts', N'Shellfish',
        N'Iodine contrast', N'NSAIDs', N'Codeine', N'Bee venom', N'Aspirin'),
    CHOOSE(((p.PatientId * 11 + gs.value) % 6) + 1,
        N'Hives', N'Anaphylaxis', N'Rash', N'Nausea', N'Swelling', N'Bronchospasm'),
    CHOOSE(((p.PatientId * 13 + gs.value) % 3) + 1, N'Mild', N'Moderate', N'Severe')
FROM clinical.Patient p
CROSS JOIN GENERATE_SERIES(1, 2) gs
ORDER BY ((p.PatientId * 1009 + gs.value) % 9973);
GO

/* ============================================================================
   7.  clinical.Encounter
       (a) 400 ACTIVE: one per bed, BedId 1..400, Status='Active'.
       (b) The rest DISCHARGED: BedId NULL, Status='Discharged'.
   ============================================================================ */
PRINT N'--- clinical.Encounter (active) ---';

/* ONE age clock for the whole file, computed once and read by every block that
   cares how old a patient is: the three admission pools below, the discharged
   backfill, and #EncStory when it picks the clinical story.

   The expression is character-for-character the one vPatientChart uses for
   AgeYears (03-views.sql), and it has to be. DATEDIFF(YEAR, ...) on its own
   counts January boundaries crossed, not birthdays had, so it reads one year
   high for anyone whose birthday has not come round yet -- 3,744 of the 10,000
   patients, measured. Seeding against the boundary count while the chart
   displays the birthday count left 152 encounters sitting in an adult
   department, carrying an adult story, under a chart header reading "17". A
   temp table rather than a repeated expression because DECLARE does not
   survive GO and a formula copied into six predicates drifts in five of them. */
IF OBJECT_ID('tempdb..#PatAge') IS NOT NULL DROP TABLE #PatAge;
SELECT p.PatientId, p.Sex,
       Age = DATEDIFF(YEAR, p.DateOfBirth, SYSUTCDATETIME())
             - IIF((MONTH(p.DateOfBirth) > MONTH(SYSUTCDATETIME()))
                OR (MONTH(p.DateOfBirth) = MONTH(SYSUTCDATETIME())
                    AND DAY(p.DateOfBirth) > DAY(SYSUTCDATETIME())), 1, 0)
INTO #PatAge
FROM clinical.Patient AS p;
CREATE UNIQUE CLUSTERED INDEX IX_PatAge ON #PatAge (PatientId);
GO

DECLARE @BedCount   INT = (SELECT COUNT(*) FROM ops.Bed);
DECLARE @ProvCount  INT = (SELECT COUNT(*) FROM ops.Provider);
DECLARE @PatCount   INT = (SELECT COUNT(*) FROM clinical.Patient);

/* Radiology reads images; it does not admit patients. It appears in the twelve
   departments and in the appointment round-robin -- an imaging appointment in
   Radiology is exactly right -- but an inpatient stay attributed to it is not,
   and the old round-robin gave it 3,305 of them. Eleven admitting departments
   absorb its share. */
DECLARE @DeptCount  INT = (SELECT COUNT(*) FROM ops.Department WHERE Name <> N'Radiology');

/* Active encounters (one per bed).
   FK ids are picked from ACTUAL parent rows via dense ROW_NUMBER joins, not
   1 + (x % count). Parent identity values are NOT guaranteed to be 1-based or
   contiguous: DBCC CHECKIDENT(RESEED, 0) on a freshly-emptied table yields
   0-based ids (0..N-1), and Hyperscale can also gap identity — so assuming
   1..N breaks the FKs. Joining on dense row-numbers is correct regardless of
   the actual id range. */
/* Active encounters, made COHERENT:
   - Department comes from the bed's own unit (#1), so a Cardiology bed yields a
     Cardiology encounter — never a mismatch.
   - The attending is picked from that department (#5), falling back to any
     provider so all 400 beds are filled.
   - The patient fits the unit (#6): NICU gets neonates, PICU gets older
     children, OB units get reproductive-age women, everything else gets adults.
     The four pools are DISJOINT and matched to beds by row-number, so no
     patient occupies two beds.

   Pediatrics is split by UNIT, not just by department. Both of its units are
   intensive care, but a NICU is neonatal and a PICU is not, and lumping them
   put a sixteen-year-old in a NICU bed on the unit board -- measured at 5
   adolescents and 11 school-age children in NICU. The roster carries 34
   patients under one year against 20 NICU beds, so the neonatal pool fills. */
;WITH BedBucket AS (
    SELECT b.BedId, un.DepartmentId,
           CASE un.Name WHEN N'NICU' THEN 1
                        WHEN N'PICU' THEN 4
                        ELSE CASE dept.Name WHEN N'Obstetrics-Gynecology' THEN 2
                                            ELSE 3 END
           END AS bucket,
           ROW_NUMBER() OVER (
             PARTITION BY CASE un.Name WHEN N'NICU' THEN 1
                                       WHEN N'PICU' THEN 4
                                       ELSE CASE dept.Name WHEN N'Obstetrics-Gynecology' THEN 2
                                                           ELSE 3 END
                          END
             ORDER BY b.BedId) AS brn
    FROM ops.Bed b
    JOIN ops.Unit un         ON un.UnitId       = b.UnitId
    JOIN ops.Department dept ON dept.DepartmentId = un.DepartmentId
),
PoolNeonate AS (
    SELECT PatientId, ROW_NUMBER() OVER (ORDER BY PatientId) AS prn
    FROM #PatAge
    WHERE Age < 1
),
PoolChild AS (
    SELECT PatientId, ROW_NUMBER() OVER (ORDER BY PatientId) AS prn
    FROM #PatAge
    WHERE Age BETWEEN 1 AND 17
),
PoolOB AS (
    SELECT PatientId, ROW_NUMBER() OVER (ORDER BY PatientId) AS prn
    FROM #PatAge
    WHERE Sex = N'Female'
      AND Age BETWEEN 18 AND 50
),
PoolAdult AS (
    SELECT PatientId, ROW_NUMBER() OVER (ORDER BY PatientId) AS prn
    FROM #PatAge
    WHERE Age >= 18
      AND NOT (Sex = N'Female' AND Age BETWEEN 18 AND 50)
)
INSERT INTO clinical.Encounter
    (PatientId, DepartmentId, AttendingProviderId, BedId,
     EncounterType, AdmitTime, Status, IntakeJson)
SELECT
    pat.PatientId,
    b.DepartmentId,
    prov.ProviderId,
    b.BedId                                                         AS BedId,
    CHOOSE(((b.BedId * 17) % 3) + 1, N'Inpatient', N'ED', N'Inpatient') AS EncounterType,
    adm.AdmitTime                                                  AS AdmitTime,
    N'Active'                                                       AS Status,
    JSON_OBJECT(
        'chiefComplaint'    : CHOOSE(((b.BedId * 17) % 8) + 1,
            N'Chest tightness with intermittent radiation to left arm',
            N'Shortness of breath on exertion, 3-day onset',
            N'Acute right lower quadrant abdominal pain',
            N'Altered mental status, family-reported confusion x12h',
            N'Severe headache, photophobia, no trauma',
            N'Fever, productive cough, pleuritic chest pain',
            N'Lower extremity swelling and erythema, possible DVT',
            N'Persistent vomiting and dehydration, 24h'),
        'esiLevel'          : 1 + ((b.BedId * 7) % 4),
        'arrivalMode'       : CHOOSE(((b.BedId * 11) % 3) + 1,
                                     N'Walk-in', N'EMS', N'Transfer'),
        'triageVitals'      : JSON_OBJECT(
            'heartRate'      : 60 + ((b.BedId * 7) % 60),
            'bloodPressure'  : JSON_OBJECT(
                'systolic'  : 100 + ((b.BedId * 13) % 60),
                'diastolic' : 60  + ((b.BedId * 11) % 30)),
            'spO2'           : 90 + ((b.BedId * 5)  % 9),
            'temperatureC'   : 36.5 + (((b.BedId * 3) % 30) / 10.0),
            'respRate'       : 12 + ((b.BedId * 5)  % 12)),
        'painScore'         : ((b.BedId * 7) % 11),
        /* JSON_QUERY is required: CHOOSE/CASE resolve to nvarchar across their    */
        /* branches, which would embed these arrays as escaped strings (type 1).   */
        'allergiesAtIntake' : JSON_QUERY(CHOOSE(((b.BedId * 3) % 4) + 1,
                                  JSON_ARRAY(N'Penicillin', N'Latex'),
                                  JSON_ARRAY(N'NKDA'),
                                  JSON_ARRAY(N'Sulfa'),
                                  JSON_ARRAY(N'Shellfish', N'Iodine contrast'))),
        'currentMedications': JSON_QUERY(CHOOSE(((b.BedId * 5) % 4) + 1,
                                  JSON_ARRAY(N'Lisinopril 10mg daily', N'Atorvastatin 40mg nightly', N'Aspirin 81mg daily'),
                                  JSON_ARRAY(N'Metformin 1000mg twice daily', N'Insulin glargine 20 units nightly'),
                                  JSON_ARRAY(N'Metoprolol 25mg twice daily', N'Apixaban 5mg twice daily'),
                                  JSON_ARRAY(N'Albuterol inhaler as needed', N'Furosemide 40mg daily'))),
        'pastMedicalHistory': JSON_QUERY(CHOOSE(((b.BedId * 7) % 4) + 1,
                                  JSON_ARRAY(N'Hypertension', N'Hyperlipidemia', N'Type 2 Diabetes'),
                                  JSON_ARRAY(N'COPD', N'Chronic kidney disease'),
                                  JSON_ARRAY(N'Atrial fibrillation', N'Prior stroke'),
                                  JSON_ARRAY(N'Coronary artery disease', N'Heart failure'))),
        'socialHistory'     : JSON_OBJECT(
            'tobacco' : CHOOSE(((b.BedId * 7) % 3) + 1,
                                N'Never', N'Former, quit 2018', N'Current 1ppd'),
            'alcohol' : N'Social',
            'drugs'   : N'Denied'),
        'lastOralIntake'    : CONVERT(NVARCHAR(19), DATEADD(HOUR, -1 * (2 + ((b.BedId * 5) % 10)), adm.AdmitTime), 126) + N'Z',
        'advanceDirectives' : CHOOSE(((b.BedId * 7) % 3) + 1, N'Full code', N'DNR/DNI', N'DNR, will intubate'),
        'triageNurseId'     : 40 + ((b.BedId * 3) % 20),
        'triageNotes'       : CHOOSE(((b.BedId * 11) % 4) + 1,
            N'Patient ambulatory; cooperative. Cardiac monitor and ECG within 10 min per ED protocol.',
            N'Arrived via EMS on a stretcher; triaged directly to the treatment area.',
            N'Alert and oriented; vitals stable at triage, placed in a monitored bed.',
            N'Assisted to bed; reports moderate pain, analgesia ordered per protocol.')
    )
FROM BedBucket b
CROSS APPLY (SELECT DATEADD(HOUR, -1 * (1 + ((b.BedId * 13) % 95)), SYSUTCDATETIME()) AS AdmitTime) adm
CROSS APPLY (
    /* demographic-appropriate, DISTINCT patient per bed (disjoint pools). */
    SELECT PatientId FROM PoolNeonate
        WHERE b.bucket = 1 AND prn = ((b.brn - 1) % (SELECT COUNT(*) FROM PoolNeonate)) + 1
    UNION ALL
    SELECT PatientId FROM PoolChild
        WHERE b.bucket = 4 AND prn = ((b.brn - 1) % (SELECT COUNT(*) FROM PoolChild)) + 1
    UNION ALL
    SELECT PatientId FROM PoolOB
        WHERE b.bucket = 2 AND prn = ((b.brn - 1) % (SELECT COUNT(*) FROM PoolOB)) + 1
    UNION ALL
    SELECT PatientId FROM PoolAdult
        WHERE b.bucket = 3 AND prn = ((b.brn - 1) % (SELECT COUNT(*) FROM PoolAdult)) + 1
) pat
CROSS APPLY (
    /* attending in the encounter's department; fall back to any provider. */
    SELECT TOP 1 pr.ProviderId
    FROM ops.Provider pr
    ORDER BY IIF(pr.DepartmentId = b.DepartmentId, 0, 1),
             (b.BedId * 31 + pr.ProviderId) % 97
) prov
/* Leave ~15% of beds unoccupied so the hospital runs at a realistic ~85%
   census rather than a full house. (BedId*7)%20 is a uniform permutation;
   keeping >= 3 retains 17/20 = 85% of beds as active admissions. The skipped
   beds stay 'Available' (only beds with an active encounter are marked
   Occupied below), and the discharged backfill still lands the total at
   @EncounterCount. */
WHERE (b.BedId * 7) % 20 >= 3;

/* Feature the Ward family (namesakes of Ward General) so they actually appear on
   the unit board and charts: make each Ward doctor the attending on up to 10
   active encounters in their OWN department. Department-coherent and demo-friendly;
   the bulk of attendings still come from the assignment above. */
;WITH ward AS (
    SELECT pr.ProviderId, pr.DepartmentId
    FROM ops.Provider pr
    WHERE pr.FullName LIKE N'Dr. % Ward'
),
wardranked AS (
    SELECT e.EncounterId, w.ProviderId,
           ROW_NUMBER() OVER (PARTITION BY w.ProviderId ORDER BY e.BedId) AS rn
    FROM clinical.Encounter e
    JOIN ward w ON w.DepartmentId = e.DepartmentId
    WHERE e.Status = N'Active'
)
UPDATE e
SET e.AttendingProviderId = r.ProviderId
FROM clinical.Encounter e
JOIN wardranked r ON r.EncounterId = e.EncounterId
WHERE r.rn <= 10;

/* ----------------------------------------------------------------------------
   Anchor one recognizable chart on the board the reader lands on first.

   The unit board opens on the first unit alphabetically -- 3 East, an Internal
   Medicine ward -- so its top bed is the first chart most readers ever open.
   Left to the round-robin that bed holds a generated name, and the named
   patients all cluster into the lowest bed ids (ED Main, ED Fast Track, ICU A)
   because they are the lowest PatientIds. Art Vandelay drew a bed that the 85%
   census rule leaves empty, so he had no chart at all.

   This puts Art Vandelay in the first 3 East bed under Dr. Claudia Ward, the
   Internal Medicine chief of staff -- department-coherent, and a recognizable
   pairing on the landing page. It is a SWAP, not an overwrite: if Art already
   holds a bed elsewhere the current occupant of 3 East takes it, so no patient
   ends up in two beds and none of the pool guarantees are disturbed. Both are
   non-OB adults by construction -- 3 East draws from the adult pool -- so the
   exchange cannot put the wrong demographic in either bed.

   It runs BEFORE #EncStory, so the story, diagnosis and intake payload are all
   derived for the patient who ends up in the bed, not the one who left it. */
DECLARE @ArtId    INT = (SELECT PatientId  FROM clinical.Patient WHERE FullName = N'Art Vandelay');
DECLARE @ClaudiaId INT = (SELECT ProviderId FROM ops.Provider    WHERE FullName = N'Dr. Claudia Ward');
DECLARE @AnchorEnc INT = (SELECT MIN(e.EncounterId)
                          FROM clinical.Encounter AS e
                          JOIN ops.Bed  AS b ON b.BedId  = e.BedId
                          JOIN ops.Unit AS u ON u.UnitId = b.UnitId
                          WHERE u.Name = N'3 East' AND e.Status = N'Active');
DECLARE @AnchorPat INT = (SELECT PatientId FROM clinical.Encounter WHERE EncounterId = @AnchorEnc);
DECLARE @ArtEnc    INT = (SELECT MIN(EncounterId) FROM clinical.Encounter
                          WHERE PatientId = @ArtId AND Status = N'Active');

IF @ArtId IS NOT NULL AND @ClaudiaId IS NOT NULL AND @AnchorEnc IS NOT NULL
BEGIN
    /* Art's previous bed, if he held one, goes to the patient he displaces. */
    IF @ArtEnc IS NOT NULL
        UPDATE clinical.Encounter SET PatientId = @AnchorPat WHERE EncounterId = @ArtEnc;

    UPDATE clinical.Encounter
    SET PatientId = @ArtId, AttendingProviderId = @ClaudiaId
    WHERE EncounterId = @AnchorEnc;
END;

PRINT N'--- clinical.Encounter (discharged) ---';

/* Local scale knob — keep in sync with the other two @Scale declarations
   in this file (Appointment and Observation batches). */
DECLARE @Scale          FLOAT = 1.0;
DECLARE @EncounterCount INT   = CAST(40000 * @Scale AS INT);

/* Discharged encounters — backfill to @EncounterCount total. */
DECLARE @Active INT = (SELECT COUNT(*) FROM clinical.Encounter);
DECLARE @Discharged INT = @EncounterCount - @Active;
PRINT CONCAT(N'    active = ', @Active, N', discharged to add = ', @Discharged);

/* Adults only, matching the active-encounter block above. The roster spans
   newborn to ninety-five, so without this an eight-year-old is admitted
   with a hypertensive emergency and started on a thiazide. The modulo below
   must use @AdultCount rather than @PatCount or the join misses and the
   discharged encounter count silently falls short of 40,000. */
DECLARE @AdultCount INT = (SELECT COUNT(*) FROM #PatAge WHERE Age >= 18);

/* Two of the twelve departments cannot take an arbitrary adult. Pediatrics has
   nothing but a NICU and a PICU, and the old round-robin put a ninety-six-year
   old in it. Obstetrics-Gynecology is worse: it was handed 1,664 discharged men.
   The active block above already drew from demographic pools; the discharged
   backfill never did, so the same hospital was coherent on its 400 occupied beds
   and incoherent across its other 39,600 stays.

   The department decides which pool the patient comes from. All three pools are
   joined on every row and the CASE picks between them, so the join cardinality
   -- and the 40,000 encounter total -- is unchanged. */
DECLARE @KidCount INT = (SELECT COUNT(*) FROM #PatAge WHERE Age < 18);
DECLARE @ObCount  INT = (SELECT COUNT(*) FROM #PatAge
                         WHERE Sex = N'Female' AND Age BETWEEN 18 AND 50);
DECLARE @PedsDeptId INT = (SELECT DepartmentId FROM ops.Department
                           WHERE Name = N'Pediatrics');
DECLARE @ObDeptId   INT = (SELECT DepartmentId FROM ops.Department
                           WHERE Name = N'Obstetrics-Gynecology');

;WITH P AS (SELECT PatientId,    ROW_NUMBER() OVER (ORDER BY PatientId)    - 1 AS rn
            FROM #PatAge WHERE Age >= 18),
      K AS (SELECT PatientId,    ROW_NUMBER() OVER (ORDER BY PatientId)    - 1 AS rn
            FROM #PatAge WHERE Age < 18),
      O AS (SELECT PatientId,    ROW_NUMBER() OVER (ORDER BY PatientId)    - 1 AS rn
            FROM #PatAge WHERE Sex = N'Female' AND Age BETWEEN 18 AND 50),
      D AS (SELECT DepartmentId, ROW_NUMBER() OVER (ORDER BY DepartmentId) - 1 AS rn
            FROM ops.Department WHERE Name <> N'Radiology')
INSERT INTO clinical.Encounter
    (PatientId, DepartmentId, AttendingProviderId, BedId,
     EncounterType, AdmitTime, DischargeTime, Status, IntakeJson)
SELECT
    CASE WHEN D.DepartmentId = @PedsDeptId THEN K.PatientId
         WHEN D.DepartmentId = @ObDeptId   THEN O.PatientId
         ELSE P.PatientId END,
    D.DepartmentId,
    prov.ProviderId,
    NULL                                                               AS BedId,
    CHOOSE(((gs.value * 5) % 3) + 1, N'Inpatient', N'ED', N'Outpatient') AS EncounterType,
    /* Discharge 1-360 days ago (always past); admit is the stay length before
       that. Anchoring on the discharge keeps DischargeTime — and every derived
       Observation/Med/Lab timestamp — strictly in the past. */
    DATEADD(DAY,
            -1 * ((1 + ((gs.value * 7) % 360)) + (1 + ((gs.value * 3) % 6))),  -- stay = 1-7 days
            SYSUTCDATETIME())                                           AS AdmitTime,
    DATEADD(DAY,
            -1 * (1 + ((gs.value * 7) % 360)),
            SYSUTCDATETIME())                                           AS DischargeTime,
    N'Discharged'                                                       AS Status,
    JSON_OBJECT(
        'chiefComplaint': CHOOSE(((gs.value * 7) % 5) + 1,
            N'Routine follow-up', N'Post-operative check',
            N'Chronic back pain flare', N'Hypertension management',
            N'Diabetes follow-up'),
        'esiLevel'      : 1 + ((gs.value * 7) % 4),
        'arrivalMode'   : N'Walk-in',
        'triageVitals'  : JSON_OBJECT(
            'heartRate'      : 60 + ((gs.value * 7) % 40),
            'bloodPressure'  : JSON_OBJECT(
                'systolic' : 110 + ((gs.value * 13) % 40),
                'diastolic': 65  + ((gs.value * 11) % 25)),
            'spO2'           : 95 + ((gs.value * 5) % 5),
            'temperatureC'   : 36.5 + (((gs.value * 3) % 20) / 10.0),
            'respRate'       : 12 + ((gs.value * 5) % 8))
    )
FROM GENERATE_SERIES(1, 80000) gs
JOIN P ON P.rn = (gs.value * 4001) % @AdultCount
JOIN K ON K.rn = (gs.value * 4001) % @KidCount
JOIN O ON O.rn = (gs.value * 4001) % @ObCount
JOIN D ON D.rn = (gs.value * 17)   % @DeptCount
CROSS APPLY (
    SELECT TOP 1 pr.ProviderId
    FROM ops.Provider pr
    ORDER BY IIF(pr.DepartmentId = D.DepartmentId, 0, 1),
             (gs.value * 23 + pr.ProviderId) % 97
) prov
WHERE gs.value <= @Discharged;
GO

/* Mark beds with an active encounter as Occupied. */
PRINT N'--- ops.Bed mark Occupied for active encounters ---';
UPDATE b
SET BedStatus = N'Occupied'
FROM ops.Bed b
WHERE EXISTS (
    SELECT 1 FROM clinical.Encounter e
    WHERE e.BedId = b.BedId AND e.Status = N'Active'
);
GO

/* ============================================================================
   8.  ops.Appointment  (~120,000)
   ============================================================================ */
PRINT N'--- ops.Appointment ---';
DECLARE @Scale            FLOAT = 1.0;
DECLARE @AppointmentCount INT   = CAST(120000 * @Scale AS INT);
DECLARE @PatCount  INT = (SELECT COUNT(*) FROM clinical.Patient);
DECLARE @ProvCount INT = (SELECT COUNT(*) FROM ops.Provider);
DECLARE @DeptCount INT = (SELECT COUNT(*) FROM ops.Department);

;WITH P AS (SELECT PatientId,    ROW_NUMBER() OVER (ORDER BY PatientId)    - 1 AS rn FROM clinical.Patient),
      D AS (SELECT DepartmentId, ROW_NUMBER() OVER (ORDER BY DepartmentId) - 1 AS rn FROM ops.Department)
INSERT INTO ops.Appointment
    (PatientId, ProviderId, DepartmentId, ScheduledStart, ScheduledEnd, Status)
SELECT
    P.PatientId,
    prov.ProviderId,
    D.DepartmentId,
    DATEADD(MINUTE, rnd.minOffset,
        DATEADD(DAY, rnd.dayOffset, SYSUTCDATETIME())),
    DATEADD(MINUTE, rnd.minOffset + 30,
        DATEADD(DAY, rnd.dayOffset, SYSUTCDATETIME())),
    /* Date and status are rolled from NEWID() — INDEPENDENT of the provider
       assignment (which derives from gs.value). Decoupling them keeps the
       appointment outcome from correlating with provider role, which would
       otherwise be a synthetic-data artifact (both fields aliasing on gs.value
       produced a fake 52%->68% loss spread by role). Distribution: past ->
       ~75% Completed / ~13% Cancelled / ~12% NoShow; future -> ~85% Scheduled
       / ~15% Cancelled. */
    CASE
        WHEN rnd.dayOffset < 0
            THEN CASE WHEN rnd.statusRoll < 75 THEN N'Completed'
                      WHEN rnd.statusRoll < 88 THEN N'Cancelled'
                      ELSE                           N'NoShow'
                 END
        ELSE     CASE WHEN rnd.statusRoll < 85 THEN N'Scheduled'
                      ELSE                           N'Cancelled'
                 END
    END
FROM GENERATE_SERIES(1, 120000) gs
JOIN P ON P.rn = (gs.value * 1009) % @PatCount
JOIN D ON D.rn = (gs.value * 7)    % @DeptCount
CROSS APPLY (SELECT
    (ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % 730)  - 365 AS dayOffset,   -- -365..+364 days
    (ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % 1440) - 360 AS minOffset,   -- time-of-day spread
    ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % 100          AS statusRoll   -- 0..99
) rnd
CROSS APPLY (
    SELECT TOP 1 pr.ProviderId
    FROM ops.Provider pr
    ORDER BY IIF(pr.DepartmentId = D.DepartmentId, 0, 1),
             (gs.value * 41 + pr.ProviderId) % 97
) prov
WHERE gs.value <= @AppointmentCount;
GO

/* ============================================================================
   9.  clinical.ClinicalNote  (~60,000 — 1.5 per encounter; ~1-2 KB NoteText)
   ============================================================================ */
PRINT N'--- clinical.ClinicalNote ---';
/* ----------------------------------------------------------------------------
   The note corpus is generated from a STORY TABLE, not from independent
   fragment pools. That distinction is the whole point.

   An earlier version drew the subjective complaint, the assessment and the
   plan from three separate randomizers keyed only on the encounter's primary
   condition, which made every note internally CONTRADICTORY. Measured on the
   live corpus, the single opening line "a sudden severe headache with neck
   stiffness and vomiting" appeared under EIGHT different assessments across
   994 notes. A note that reads as a subarachnoid hemorrhage in one line and a
   diabetic foot ulcer in the next is worthless as a retrieval corpus, and the
   vector search built on it in AI-Ready SQL would be demonstrating nothing.

   Here each row of #Story is one COHERENT clinical picture: the complaint, the
   exam findings, the assessment, the plan, the hospital course, the follow-up
   sentence AND the vital-sign ranges all belong to each other. A note draws
   one story row and never mixes across rows.

   Diversity then comes only from axes that cannot contradict that story:
     · 144 stories — 11 adult conditions x 12 stories, plus 3 pediatric age
       bands x 4 stories, because the vital-sign ranges live on the story row
       and an infant's normal heart rate is not an adult's
     ·   5 trajectories, applied to BOTH the plan and the hospital course
     ·  4 x 4 x 4 x 4 x 3 framing phrases - history, home medications, family
        history, general appearance, comorbidity, follow-on orders
     · per-story vital-sign ranges, so an anxiety presentation is not handed
       the same tachycardia as a pulmonary embolism

   Three contracts this block must not break:
     1. 03-views.sql mines the text with REGEXP_*. The literal tokens
        "T nn.nC", "HR nnn", "BP nnn/nn", "RR nn", "SpO2 nn%", "Pain scored N
        out of 10" and a closing "... follow up ..." sentence containing no
        internal period must survive verbatim.
     2. Four sections separated by CRLF - exactly three CRLF pairs per note.
     3. A DISCHARGED encounter's LAST note is its discharge summary, and an
        ACTIVE encounter never carries one.

   This block is the part a clinician should skim: 144 stories, not 60,000
   notes. All of it is synthetic - there is no real PHI here.

     cond: 0 HTN · 1 T2DM · 2 HF · 3 Pneumonia · 4 UTI ·
           5 Appendicitis · 6 Chest pain · 7 Syncope · 8 Stroke · 9 COPD ·
           10 Infant · 11 Child · 12 Adolescent · 13 Psychiatric admission
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('tempdb..#Story') IS NOT NULL DROP TABLE #Story;
CREATE TABLE #Story
(
    cond     TINYINT       NOT NULL,
    sid      TINYINT       NOT NULL,
    Label    NVARCHAR(60)  NOT NULL,
    Subj     NVARCHAR(300) NOT NULL,
    Exam     NVARCHAR(300) NOT NULL,
    Assess   NVARCHAR(300) NOT NULL,
    PlanTxt  NVARCHAR(300) NOT NULL,
    Course   NVARCHAR(300) NOT NULL,
    FollowUp NVARCHAR(200) NOT NULL,
    TempI    SMALLINT      NOT NULL,
    HrLo     SMALLINT      NOT NULL, HrSp  SMALLINT NOT NULL,
    SysLo    SMALLINT      NOT NULL, SysSp SMALLINT NOT NULL,
    DiaLo    SMALLINT      NOT NULL, DiaSp SMALLINT NOT NULL,
    RrLo     SMALLINT      NOT NULL, RrSp  SMALLINT NOT NULL,
    SpLo     SMALLINT      NOT NULL, SpSp  SMALLINT NOT NULL,
    PainLo   SMALLINT      NOT NULL, PainSp SMALLINT NOT NULL,
    CONSTRAINT PK_Story PRIMARY KEY (cond, sid)
);

INSERT INTO #Story (cond, sid, Label, Subj, Exam, Assess, PlanTxt, Course, FollowUp,
                    TempI, HrLo, HrSp, SysLo, SysSp, DiaLo, DiaSp, RrLo, RrSp, SpLo, SpSp, PainLo, PainSp)
VALUES
/* ---------- cond 0 : Hypertension (I10) ---------- */
(0,1,N'Hypertensive emergency with pulmonary edema',N'a severe headache with breathlessness at rest after several days of very high home readings, ',N'Bibasilar crackles to the mid-zones with an elevated jugular venous pressure. ',N'Hypertensive emergency with acute pulmonary edema and end-organ involvement. ',N'Admit to a monitored bed for intravenous nitroglycerin titration and diuresis. ',N'Blood pressure was lowered by a quarter in the first hour with intravenous therapy, oxygenation improved, and the patient transitioned to oral agents by day two. ',N'Arrange cardiology follow up within one week.',36,96,24,196,34,112,20,24,8,88,7,2,3),
(0,2,N'Hypertensive emergency with acute kidney injury',N'reduced urine output and ankle swelling with markedly elevated pressures at triage, ',N'Mild periorbital and pedal edema without focal neurologic findings. ',N'Hypertensive emergency complicated by acute kidney injury. ',N'Admit for controlled intravenous blood-pressure reduction with hourly urine output and daily creatinine. ',N'Creatinine peaked on day two then improved with controlled pressure reduction and avoidance of nephrotoxic agents. ',N'Arrange nephrology follow up in two weeks.',36,88,22,192,32,108,20,18,6,94,5,1,3),
(0,3,N'Hypertensive encephalopathy',N'confusion and visual disturbance developing over hours with a very high pressure at triage, ',N'Drowsy but rousable with papilledema on fundoscopy and no lateralizing weakness. ',N'Hypertensive encephalopathy with posterior reversible encephalopathy on imaging. ',N'Admit to a monitored bed for intravenous agent titration with hourly neurologic checks. ',N'Mentation cleared over forty-eight hours as pressure was lowered gradually, and imaging changes were reversible on repeat study. ',N'Arrange neurology follow up in four weeks.',36,84,20,204,30,116,18,16,6,95,4,2,4),
(0,4,N'Hypertensive urgency, no end-organ damage',N'a throbbing headache with home readings persistently above goal and no chest or visual symptoms, ',N'Comfortable at rest with a normal cardiovascular and neurologic examination. ',N'Hypertensive urgency without end-organ damage. ',N'Up-titrate oral agents, observe for several hours, and avoid rapid pressure reduction. ',N'Pressure fell steadily over six hours of observation on oral therapy with no symptoms and no evidence of organ injury. ',N'Follow up with primary care within seven days.',36,74,20,176,26,100,18,14,4,96,4,1,3),
(0,5,N'Newly diagnosed stage 2 hypertension',N'an incidental severely elevated blood-pressure reading found at a routine visit, ',N'Well appearing with normal heart sounds and no retinal changes. ',N'Newly diagnosed stage 2 essential hypertension. ',N'Start a thiazide plus an angiotensin-converting-enzyme inhibitor and counsel on sodium restriction. ',N'The patient tolerated combination therapy without symptomatic hypotension and was taught home monitoring before discharge. ',N'Follow up with primary care in four weeks.',36,70,18,158,24,96,16,13,4,97,3,0,2),
(0,6,N'Uncontrolled hypertension from nonadherence',N'symptoms after running out of antihypertensive medications several weeks ago, ',N'No acute distress with an otherwise unremarkable examination. ',N'Uncontrolled hypertension from medication nonadherence rather than treatment failure. ',N'Reconcile medications, address cost and access barriers, and resume the prior regimen. ',N'Pressure improved promptly once the original regimen was restarted, confirming nonadherence rather than resistance. ',N'Follow up with primary care in two weeks.',36,72,20,168,28,98,18,14,4,97,3,0,3),
(0,7,N'White-coat hypertension',N'high readings recorded only in clinic with normal readings at home, ',N'Normotensive on repeat measurement after ten minutes of quiet rest. ',N'White-coat hypertension; ambulatory monitoring arranged without acute treatment. ',N'Arrange ambulatory monitoring and defer pharmacotherapy pending those results. ',N'Repeat measurements after rest were normal and no antihypertensive therapy was started. ',N'Follow up in clinic once ambulatory monitoring is complete.',36,68,16,142,20,88,14,12,4,98,2,0,2),
(0,8,N'Renovascular hypertension',N'difficult-to-control pressure despite three agents with a rising creatinine on the latest panel, ',N'An abdominal bruit is audible with otherwise unremarkable findings. ',N'Secondary hypertension from suspected renal artery stenosis. ',N'Order renal artery imaging and avoid renin-angiotensin blockade until anatomy is known. ',N'Imaging confirmed a significant unilateral stenosis and the case was referred for revascularization assessment. ',N'Arrange vascular follow up in three weeks.',36,74,18,182,28,104,18,14,4,97,3,0,2),
(0,9,N'Primary aldosteronism',N'persistent high pressure with muscle cramps and a low potassium on the outpatient panel, ',N'Well appearing with normal cardiac findings and no edema. ',N'Secondary hypertension from suspected primary aldosteronism. ',N'Send aldosterone-renin testing off interfering agents and replace potassium. ',N'Potassium was repleted and the aldosterone-renin ratio returned markedly elevated, prompting endocrine referral. ',N'Arrange endocrinology follow up in four weeks.',36,72,18,178,26,102,18,14,4,97,3,0,2),
(0,10,N'Resistant hypertension on three agents',N'blood pressure above goal despite three medications taken as prescribed, ',N'No acute distress with a normal examination and confirmed adherence on pharmacy review. ',N'Resistant hypertension despite a three-drug regimen including a diuretic. ',N'Add a mineralocorticoid receptor antagonist and screen for secondary causes and sleep apnea. ',N'Pressure improved after a fourth agent was added and a sleep study was arranged before discharge. ',N'Follow up in the hypertension clinic in six weeks.',36,74,18,172,26,100,18,14,4,97,3,0,2),
(0,11,N'Over-treated hypertension with orthostatic symptoms',N'dizziness on standing since the antihypertensive dose was increased last month, ',N'A twenty-point systolic drop on standing with reproduction of the symptoms. ',N'Symptomatic orthostatic hypotension from over-treatment of hypertension. ',N'Reduce the offending agent, liberalize salt and fluid, and recheck standing pressures. ',N'Standing pressures normalized after the dose reduction and the dizziness resolved before discharge. ',N'Follow up with primary care in two weeks.',36,76,18,104,20,62,14,14,4,97,3,0,2),
(0,12,N'Pheochromocytoma suspected',N'episodic pounding headache with sweating and palpitations alongside labile readings, ',N'Diaphoretic during an episode with a tremor and an otherwise normal examination. ',N'Paroxysmal hypertension concerning for a catecholamine-secreting tumor. ',N'Send plasma metanephrines and start alpha blockade before any beta blockade. ',N'Metanephrines returned elevated and cross-sectional imaging identified an adrenal lesion for surgical referral. ',N'Arrange endocrine surgery follow up in three weeks.',36,98,26,186,32,106,20,16,6,96,4,1,3),
/* ---------- cond 1 : Type 2 diabetes (E11.9) ---------- */
(1,1,N'Diabetic ketoacidosis',N'nausea, vomiting and abdominal pain with deep rapid breathing over the past day, ',N'Dry mucous membranes with deep sighing respirations and a fruity breath odor. ',N'Diabetic ketoacidosis with a high anion gap and ketonemia. ',N'Start an insulin infusion with hourly glucose and two-hourly electrolytes after fluid resuscitation. ',N'The anion gap closed within eighteen hours on an insulin infusion and the patient was transitioned to subcutaneous insulin with overlap. ',N'Arrange endocrinology follow up within one week.',37,112,24,102,22,60,16,26,8,96,4,3,4),
(1,2,N'Hyperosmolar hyperglycemic state',N'confusion and lethargy over several days with profoundly elevated blood glucose, ',N'Markedly dehydrated and drowsy without ketotic respirations. ',N'Hyperosmolar hyperglycemic state without significant ketosis. ',N'Give aggressive isotonic fluids first, then low-dose insulin with careful sodium correction. ',N'Osmolality corrected gradually over two days with fluids and low-dose insulin, and mentation returned to baseline. ',N'Arrange endocrinology follow up in ten days.',37,106,22,98,22,58,14,20,6,96,4,1,3),
(1,3,N'Uncontrolled type 2 diabetes without decompensation',N'increased thirst, polyuria and fatigue with very high home glucose readings, ',N'Well perfused and alert with no ketotic features. ',N'Type 2 diabetes, markedly uncontrolled, without acute metabolic decompensation. ',N'Adjust the insulin regimen and engage diabetes education for glycemic control. ',N'Glucose came under control on an adjusted basal-bolus regimen and the patient completed structured education before discharge. ',N'Arrange diabetes clinic follow up in three weeks.',36,84,18,128,24,74,16,15,4,97,3,0,2),
(1,4,N'Diabetic foot ulcer with infection',N'a painful, slow-healing foot ulcer with surrounding redness and a foul odor, ',N'A deep plantar ulcer with surrounding cellulitis and absent protective sensation. ',N'Infected diabetic foot ulcer with soft-tissue involvement. ',N'Offload the ulcer, obtain deep tissue cultures, and start empiric antibiotics. ',N'Cellulitis regressed on culture-directed antibiotics and podiatry provided offloading footwear before discharge. ',N'Arrange podiatry follow up within one week.',38,94,20,124,22,70,16,16,4,96,4,4,4),
(1,5,N'Recurrent hypoglycemia from insulin excess',N'recurrent shakiness and sweating relieved by eating since a recent insulin adjustment, ',N'Alert with no focal deficit and a documented low capillary glucose during an episode. ',N'Recurrent hypoglycemia from insulin excess rather than a new endocrine disorder. ',N'Reduce insulin dosing, review carbohydrate intake, and reinforce glucose monitoring. ',N'No further hypoglycemic episodes occurred after the regimen was reduced and meal timing was reviewed. ',N'Follow up with the diabetes nurse in one week.',36,80,18,120,20,70,14,14,4,98,2,0,2),
(1,6,N'Newly diagnosed type 2 diabetes',N'an incidentally elevated glucose found on routine screening without symptoms, ',N'Well appearing with an unremarkable examination and intact foot sensation. ',N'Newly diagnosed type 2 diabetes without complications. ',N'Start metformin, provide dietary counseling, and arrange structured education. ',N'Metformin was tolerated without gastrointestinal upset and baseline complication screening was completed. ',N'Follow up with primary care in three months.',36,74,16,126,22,74,14,14,4,98,2,0,2),
(1,7,N'Diabetic gastroparesis',N'early fullness with nausea and vomiting of undigested food after meals, ',N'A succussion splash is present with a soft, non-tender abdomen. ',N'Diabetic gastroparesis with delayed gastric emptying. ',N'Give small frequent low-fat meals with a prokinetic agent and correct glycemia. ',N'Oral intake improved on small frequent meals and a prokinetic agent, and weight stabilized before discharge. ',N'Arrange gastroenterology follow up in four weeks.',36,88,18,116,20,68,14,15,4,97,3,3,4),
(1,8,N'Progressive diabetic nephropathy',N'increasing leg swelling with frothy urine over several months, ',N'Pitting edema to the mid-shin with no crackles on auscultation. ',N'Progressive diabetic nephropathy with nephrotic-range proteinuria. ',N'Maximize renin-angiotensin blockade, add a sodium-glucose cotransporter inhibitor, and restrict sodium. ',N'Proteinuria fell modestly after therapy was maximized and renal function remained stable through discharge. ',N'Arrange nephrology follow up in four weeks.',36,78,16,148,24,86,16,16,4,97,3,1,3),
(1,9,N'Painful diabetic neuropathy',N'burning pain in both feet that is worse at night and disturbs sleep, ',N'Reduced pinprick and vibration sense in a stocking distribution with intact pulses. ',N'Painful diabetic peripheral neuropathy. ',N'Start a neuropathic agent at low dose and titrate, and reinforce glycemic control and foot care. ',N'Pain scores fell by half on a titrated neuropathic agent and foot-care education was completed. ',N'Follow up with primary care in six weeks.',36,76,16,132,22,76,14,14,4,98,2,4,4),
(1,10,N'Steroid-induced hyperglycemia',N'high glucose readings that began after starting a course of steroids for another condition, ',N'No ketotic features with an otherwise unchanged examination. ',N'Steroid-induced hyperglycemia superimposed on type 2 diabetes. ',N'Add prandial insulin matched to the steroid schedule and taper insulin as steroids reduce. ',N'Glucose tracked the steroid dose and insulin was tapered in step as the steroid course was reduced. ',N'Follow up with primary care in two weeks.',36,82,18,130,22,76,14,15,4,97,3,0,2),
(1,11,N'Diabetic retinopathy on screening',N'blurred vision noted at a routine screening appointment without pain or redness, ',N'Reduced visual acuity with dot haemorrhages and hard exudates on fundoscopy. ',N'Diabetic retinopathy identified on screening, with maculopathy on the right. ',N'Refer urgently to ophthalmology and tighten glycemic and blood-pressure control. ',N'Ophthalmology confirmed treatable maculopathy and laser therapy was scheduled as an outpatient. ',N'Arrange ophthalmology follow up in two weeks.',36,74,16,140,22,80,16,14,4,98,2,0,2),
(1,12,N'Hyperglycemia from medication nonadherence',N'very high readings after stopping diabetes medications when supplies ran out, ',N'Mildly dehydrated but alert with no ketotic features. ',N'Hyperglycemia from interrupted therapy rather than progression of disease. ',N'Restart the prior regimen, rehydrate, and resolve the supply problem before discharge. ',N'Glucose normalized within a day of restarting the prior regimen and a supply plan was arranged with pharmacy. ',N'Follow up with primary care in two weeks.',36,88,18,124,22,72,14,16,4,97,3,0,3),
/* ---------- cond 2 : Heart failure (I50.9) ---------- */
(2,1,N'Acute decompensated HFrEF',N'progressive dyspnea on exertion, orthopnea and bilateral leg swelling over two weeks, ',N'Elevated jugular venous pressure with bibasilar crackles and pitting edema to the knees. ',N'Acute decompensated heart failure with reduced ejection fraction, volume overloaded. ',N'Diurese with intravenous furosemide and monitor daily weights and electrolytes. ',N'The patient lost four kilograms over five days of intravenous diuresis with improving oxygenation and stable renal function. ',N'Arrange heart failure clinic follow up within seven days.',37,96,22,112,24,68,16,22,6,89,7,1,3),
(2,2,N'Flash pulmonary edema',N'acute severe breathlessness with pink frothy sputum at rest, ',N'Sitting upright and using accessory muscles with crackles to the apices. ',N'Flash pulmonary edema requiring noninvasive positive-pressure ventilation. ',N'Provide noninvasive ventilation, nitrates and aggressive diuresis in a monitored bed. ',N'Oxygenation improved within two hours of noninvasive ventilation and nitrates, and ventilation was weaned by the following morning. ',N'Arrange cardiology follow up within five days.',36,110,26,168,30,96,20,28,8,84,8,2,4),
(2,3,N'HFpEF congestion',N'fatigue and breathlessness on modest exertion with swelling despite preserved pump function on a prior scan, ',N'Raised jugular venous pressure with a loud fourth heart sound and peripheral edema. ',N'Heart failure with preserved ejection fraction, congested on examination. ',N'Diurese cautiously, control heart rate and blood pressure, and evaluate diastolic function. ',N'Congestion settled with cautious diuresis while renal function was watched closely, and rate control was optimized. ',N'Arrange cardiology follow up in two weeks.',37,88,20,142,26,80,18,20,6,91,6,1,3),
(2,4,N'Right heart failure with hepatic congestion',N'increasing abdominal distension with early satiety and marked leg swelling, ',N'Tense ascites with tender hepatomegaly and a raised jugular venous pressure. ',N'Right-sided heart failure with hepatic congestion and peripheral edema. ',N'Diurese, evaluate for pulmonary hypertension, and monitor liver and renal function. ',N'Abdominal girth and liver enzymes improved with diuresis and an echocardiogram quantified the pulmonary pressures. ',N'Arrange cardiology follow up in two weeks.',37,92,20,106,22,64,16,20,6,90,6,2,3),
(2,5,N'Cardiorenal syndrome',N'worsening swelling with reduced urine output despite increasing diuretic doses at home, ',N'Congested with a raised jugular venous pressure and cool peripheries. ',N'Cardiorenal syndrome with diuretic resistance and a rising creatinine. ',N'Switch to a continuous diuretic infusion, add sequential nephron blockade, and involve nephrology. ',N'Urine output responded to a continuous infusion with sequential blockade and creatinine plateaued rather than climbing. ',N'Arrange combined cardiology and nephrology follow up in one week.',36,94,20,102,20,60,14,20,6,91,5,1,3),
(2,6,N'Decompensation from dietary sodium and nonadherence',N'worsening swelling after dietary indiscretion and several missed diuretic doses, ',N'Congested with a raised jugular venous pressure and a three-kilogram weight gain. ',N'Heart failure exacerbation precipitated by nonadherence and dietary sodium. ',N'Diurese, reinforce fluid and sodium limits, and address the adherence barriers directly. ',N'Weight returned to the recorded dry weight with diuresis and the patient completed dietary education before discharge. ',N'Arrange heart failure nurse follow up within seven days.',36,90,20,124,24,72,16,20,6,92,5,1,3),
(2,7,N'Decompensation from new atrial fibrillation',N'sudden palpitations with breathlessness and swelling developing over two days, ',N'An irregularly irregular pulse at a rapid rate with raised venous pressure. ',N'Heart failure decompensation precipitated by new atrial fibrillation with rapid ventricular response. ',N'Control the rate, anticoagulate after scoring stroke risk, and diurese concurrently. ',N'Rate control and diuresis improved symptoms in parallel, and anticoagulation was started after risk scoring. ',N'Arrange cardiology follow up in ten days.',36,118,28,110,24,66,16,22,6,90,6,1,3),
(2,8,N'Newly diagnosed ischemic cardiomyopathy',N'months of reduced exercise tolerance with breathlessness and no prior cardiac diagnosis, ',N'A displaced apex beat with a third heart sound and bibasilar crackles. ',N'Newly diagnosed ischemic cardiomyopathy with severely reduced systolic function. ',N'Start guideline-directed therapy in sequence and arrange ischemia assessment. ',N'Guideline-directed therapy was introduced stepwise with good tolerance and ischemia testing was booked before discharge. ',N'Arrange cardiology follow up in two weeks.',36,92,20,116,22,70,16,20,6,92,5,1,3),
(2,9,N'Heart failure from severe aortic stenosis',N'breathlessness with exertional chest tightness and one near-fainting episode, ',N'A harsh ejection systolic murmur radiating to the carotids with a slow-rising pulse. ',N'Heart failure secondary to severe aortic stenosis. ',N'Diurese cautiously, avoid vasodilators, and refer for urgent valve intervention assessment. ',N'Cautious diuresis relieved congestion without hypotension and the case was accepted for valve intervention workup. ',N'Arrange structural heart clinic follow up in one week.',36,86,18,104,20,62,14,20,6,92,5,2,3),
(2,10,N'Cardiogenic shock',N'rapidly worsening breathlessness with confusion and cold extremities, ',N'Hypotensive with cool mottled peripheries and a thready pulse. ',N'Cardiogenic shock complicating acute decompensated heart failure. ',N'Admit to intensive care for inotropic support with invasive monitoring and urgent echocardiography. ',N'Perfusion improved on inotropic support with lactate clearance, and the patient was weaned to oral therapy over four days. ',N'Arrange advanced heart failure follow up within five days.',36,116,26,78,18,46,14,26,8,86,7,2,4),
(2,11,N'Decompensation after anti-inflammatory use',N'swelling and breathlessness that began after taking anti-inflammatory tablets for back pain, ',N'Congested with raised venous pressure and new pitting edema. ',N'Heart failure decompensation precipitated by nonsteroidal anti-inflammatory use. ',N'Stop the offending agent, diurese, and document the drug as one to avoid. ',N'Congestion resolved with diuresis once the anti-inflammatory was stopped, and the drug was added to the avoid list. ',N'Follow up with primary care in two weeks.',36,88,18,120,22,72,16,20,6,92,5,2,3),
(2,12,N'Chemotherapy-related cardiomyopathy',N'breathlessness and fatigue developing during a course of cancer treatment, ',N'A quiet precordium with a third heart sound and mild peripheral edema. ',N'Chemotherapy-related cardiomyopathy with a fall in ejection fraction from baseline. ',N'Hold the offending agent, start cardioprotective therapy, and coordinate with oncology. ',N'Ejection fraction stabilized after the agent was held and cardioprotective therapy was established with oncology agreement. ',N'Arrange cardio-oncology follow up in three weeks.',36,94,20,110,22,66,16,20,6,92,5,1,3),
/* ---------- cond 3 : Pneumonia (J18.9) ---------- */
(3,1,N'Community-acquired pneumonia, lower lobe',N'fevers, chills and a productive cough with green sputum for three days, ',N'Bronchial breathing with focal crackles at the right base. ',N'Community-acquired pneumonia of the right lower lobe. ',N'Start empiric antibiotics and supplemental oxygen after obtaining blood cultures. ',N'Fever settled within forty-eight hours of empiric antibiotics and oxygen requirement fell steadily to room air. ',N'Follow up with primary care in two weeks.',38,102,20,112,22,66,16,24,6,90,6,3,4),
(3,2,N'Pneumonia with parapneumonic effusion',N'pleuritic chest pain with breathlessness and fever that has not improved on oral antibiotics, ',N'Stony dullness at the right base with absent breath sounds. ',N'Community-acquired pneumonia with a parapneumonic effusion on imaging. ',N'Continue antibiotics, characterize the effusion with ultrasound, and consider drainage. ',N'Ultrasound-guided sampling showed a simple effusion that resolved on antibiotics without the need for a chest drain. ',N'Arrange respiratory follow up in three weeks.',38,104,20,108,22,64,16,26,6,89,6,4,4),
(3,3,N'Severe pneumonia with sepsis',N'sudden high fever and rigors with rapid breathing and confusion, ',N'Ill-appearing and tachypneic with widespread crackles and delayed capillary refill. ',N'Severe community-acquired pneumonia with sepsis and hypoxemia. ',N'Initiate the sepsis bundle with fluids, broad antibiotics and monitored admission. ',N'Lactate cleared after fluid resuscitation and broad antibiotics, and vasopressor support was not required. ',N'Arrange respiratory follow up in three weeks.',38,118,24,92,20,54,16,30,8,84,8,3,4),
(3,4,N'Aspiration pneumonia',N'a cough and fever that began after a witnessed choking episode during a meal, ',N'Coarse crackles at the right base with a wet-sounding voice and an impaired swallow. ',N'Aspiration pneumonia affecting the right lower lobe. ',N'Keep nil by mouth pending swallow assessment and start antibiotics with anaerobic cover. ',N'Swallow assessment permitted a modified diet by day three and the chest signs cleared on antibiotics. ',N'Arrange speech and language therapy follow up in two weeks.',38,100,20,110,22,66,16,24,6,90,6,2,4),
(3,5,N'Atypical pneumonia',N'a gradual dry cough with malaise, headache and reduced appetite over a week, ',N'Chest signs are sparse relative to the extent of change on imaging. ',N'Atypical pneumonia suspected on clinical and radiographic dissociation. ',N'Start a macrolide, treat as an outpatient if physiology allows, and send atypical serology. ',N'Symptoms improved on macrolide therapy and the patient was stepped down to oral treatment at home. ',N'Follow up with primary care in two weeks.',38,96,18,114,22,68,16,22,6,93,5,2,4),
(3,6,N'Hospital-acquired pneumonia',N'a new cough and fever developing on the fifth day of an admission for another problem, ',N'New focal crackles with a rising oxygen requirement from baseline. ',N'Hospital-acquired pneumonia with a rising oxygen requirement. ',N'Broaden antibiotic cover per local policy and de-escalate once cultures return. ',N'Cultures allowed de-escalation to a narrow agent by day four and the oxygen requirement returned to baseline. ',N'Arrange respiratory follow up in three weeks.',38,102,20,110,22,64,16,24,6,89,6,2,4),
(3,7,N'Influenza with bacterial superinfection',N'an influenza-like illness that improved then worsened with a new fever and purulent sputum, ',N'Focal crackles superimposed on diffuse wheeze with a fever. ',N'Secondary bacterial pneumonia following influenza. ',N'Start antibiotics alongside antiviral therapy and apply droplet precautions. ',N'The secondary fever settled on antibiotics with antiviral cover, and isolation precautions were lifted before discharge. ',N'Follow up with primary care in two weeks.',38,106,20,108,22,64,16,26,6,88,6,3,4),
(3,8,N'Empyema',N'ongoing fever with pleuritic pain despite a week of antibiotics for pneumonia, ',N'Dullness with absent breath sounds at the left base and a swinging fever. ',N'Empyema complicating community-acquired pneumonia. ',N'Insert a chest drain, send pleural fluid for culture, and continue prolonged antibiotics. ',N'Drainage yielded frank pus, the fever settled within seventy-two hours, and a prolonged antibiotic course was planned. ',N'Arrange thoracic surgery follow up in two weeks.',38,110,22,104,22,62,16,26,6,88,6,5,4),
(3,9,N'Multilobar pneumonia with respiratory failure',N'worsening breathlessness with confusion and a cough productive of rusty sputum, ',N'Tachypneic with widespread crackles and marked hypoxemia on room air. ',N'Multilobar pneumonia with acute hypoxemic respiratory failure. ',N'Escalate oxygen therapy, admit to a monitored bed, and start broad antibiotics promptly. ',N'Oxygenation improved on high-flow therapy over three days and invasive ventilation was avoided. ',N'Arrange respiratory follow up in three weeks.',38,116,24,98,20,58,16,30,8,82,8,3,4),
(3,10,N'Pneumonia complicating COPD',N'worsening cough and breathlessness beyond the usual pattern of chronic lung disease, ',N'Widespread wheeze with focal crackles at the left base. ',N'Community-acquired pneumonia superimposed on chronic obstructive pulmonary disease. ',N'Treat both processes with antibiotics, bronchodilators and controlled oxygen targets. ',N'Both the infection and the bronchospasm settled on parallel treatment with controlled oxygen targets maintained throughout. ',N'Arrange respiratory follow up in three weeks.',38,104,20,112,22,66,16,26,6,87,6,3,4),
(3,11,N'Lung abscess',N'weeks of fever, weight loss and a cough productive of foul-smelling sputum, ',N'Poor dentition with focal signs and finger clubbing. ',N'Lung abscess following aspiration, with a cavitating lesion on imaging. ',N'Give prolonged antibiotics with anaerobic cover and arrange interval imaging. ',N'The cavity reduced on interval imaging after four weeks of therapy and the patient gained weight. ',N'Arrange respiratory follow up in four weeks.',38,96,18,110,22,66,16,22,6,92,5,3,4),
(3,12,N'Resolving pneumonia, step-down to oral',N'a cough and fever that are improving after two days of intravenous antibiotics, ',N'Afebrile with reducing crackles and a normal respiratory rate at rest. ',N'Community-acquired pneumonia, resolving and suitable for oral step-down. ',N'Switch to oral antibiotics, confirm oxygenation on room air, and plan discharge. ',N'Oral step-down was tolerated with no rebound fever and oxygen saturation remained normal on room air. ',N'Follow up with primary care in two weeks.',37,86,16,118,22,70,16,18,4,94,4,1,3),
/* ---------- cond 4 : Urinary tract infection (N39.0) ---------- */
(4,1,N'Uncomplicated cystitis',N'dysuria, urinary frequency and suprapubic discomfort for two days, ',N'Suprapubic tenderness without flank tenderness and no fever. ',N'Uncomplicated cystitis with a urinalysis consistent with lower urinary tract infection. ',N'Start a short course of oral antibiotics and encourage hydration. ',N'Symptoms resolved within forty-eight hours on a short oral course with no systemic features at any point. ',N'Follow up with primary care if symptoms persist beyond one week.',36,80,16,118,20,70,14,14,4,98,2,3,3),
(4,2,N'Acute pyelonephritis',N'flank pain, fever and rigors with nausea for a day, ',N'Marked costovertebral angle tenderness with a fever and tachycardia. ',N'Acute pyelonephritis with systemic features. ',N'Give intravenous antibiotics, obtain cultures, and monitor renal function. ',N'Fever settled within forty-eight hours of intravenous therapy and treatment was narrowed once cultures returned. ',N'Follow up with primary care in two weeks.',38,104,20,108,22,64,16,20,4,96,4,5,4),
(4,3,N'Urosepsis',N'rigors and confusion with urinary symptoms that worsened rapidly overnight, ',N'Hypotensive and mottled with marked flank tenderness. ',N'Urinary tract infection with sepsis and hemodynamic compromise. ',N'Provide fluids, broad antibiotics and monitored observation with lactate clearance. ',N'Lactate cleared after fluid resuscitation and broad antibiotics, and blood pressure was restored without vasopressors. ',N'Arrange urology follow up in three weeks.',38,120,24,84,20,50,14,26,6,93,5,4,4),
(4,4,N'Complicated urinary infection with delirium',N'new confusion at home with foul-smelling urine and reduced oral intake, ',N'Disoriented with dry mucous membranes and mild suprapubic tenderness. ',N'Complicated urinary tract infection presenting as delirium in an older adult. ',N'Treat the infection, address the delirium with non-pharmacological measures, and review reversible causes. ',N'Cognition returned to the reported baseline over four days as the infection and dehydration were treated. ',N'Arrange care of the elderly follow up in three weeks.',38,96,18,110,22,64,16,18,4,96,4,2,3),
(4,5,N'Catheter-associated urinary infection',N'urinary symptoms with fever in the setting of a chronic indwelling catheter, ',N'A fever with cloudy catheter drainage and mild suprapubic tenderness. ',N'Catheter-associated urinary tract infection. ',N'Exchange the catheter, obtain cultures from the new device, and start targeted antibiotics. ',N'The fever settled after catheter exchange and targeted therapy, and a trial without catheter was planned. ',N'Arrange continence team follow up in two weeks.',38,98,18,114,22,68,16,18,4,96,4,3,4),
(4,6,N'Obstructed infected kidney',N'severe one-sided loin pain radiating to the groin with fever and vomiting, ',N'Unable to lie still with marked unilateral loin tenderness and a fever. ',N'Obstructing ureteric stone with an infected obstructed kidney. ',N'Arrange emergency decompression with urology alongside antibiotics and analgesia. ',N'Emergency decompression was performed the same day and the fever settled rapidly afterwards. ',N'Arrange urology follow up in two weeks.',38,112,22,104,22,62,16,22,4,96,4,7,3),
(4,7,N'Recurrent urinary tract infection',N'a fourth episode of urinary symptoms this year with the same pattern each time, ',N'Mild suprapubic tenderness with no fever and no flank signs. ',N'Recurrent uncomplicated urinary tract infection. ',N'Treat the acute episode, send a culture before starting, and discuss prevention strategies. ',N'The acute episode settled on culture-guided therapy and a prevention plan was agreed before discharge. ',N'Arrange urology follow up in six weeks.',36,82,16,120,20,72,14,14,4,98,2,3,3),
(4,8,N'Renal abscess',N'persistent fever and flank pain despite a week of appropriate antibiotics, ',N'A swinging fever with persistent unilateral loin tenderness. ',N'Renal abscess complicating pyelonephritis. ',N'Arrange image-guided drainage and continue prolonged antibiotics with interval imaging. ',N'Image-guided drainage yielded purulent material and the fever settled within seventy-two hours. ',N'Arrange urology follow up in three weeks.',38,106,20,106,22,62,16,20,4,95,4,5,4),
(4,9,N'Hemorrhagic cystitis',N'lower abdominal pain with visible blood in the urine and frequency, ',N'Suprapubic tenderness with frankly blood-stained urine in the collection bag. ',N'Hemorrhagic cystitis with an associated urinary tract infection. ',N'Treat the infection, ensure generous hydration, and monitor the hematuria and hemoglobin. ',N'Hematuria cleared over three days with hydration and treatment, and hemoglobin remained stable. ',N'Arrange urology follow up in four weeks.',37,92,18,116,22,68,16,16,4,97,3,4,4),
(4,10,N'Multidrug-resistant urinary infection',N'urinary symptoms that have not responded to two courses of oral antibiotics, ',N'Low-grade fever with suprapubic tenderness and no flank signs. ',N'Urinary tract infection with a multidrug-resistant organism on culture. ',N'Treat with a culture-directed intravenous agent and involve microbiology in the plan. ',N'A culture-directed intravenous agent cleared the infection where oral therapy had failed. ',N'Arrange infectious diseases follow up in three weeks.',37,90,18,118,22,68,16,16,4,97,3,3,4),
(4,11,N'Acute bacterial prostatitis',N'perineal pain with fever and difficulty passing urine, ',N'An exquisitely tender prostate on examination with a fever. ',N'Acute bacterial prostatitis with associated urinary retention. ',N'Start a prolonged course of a prostate-penetrating antibiotic and relieve the retention. ',N'Retention was relieved and symptoms improved on a prostate-penetrating agent, with a prolonged course planned. ',N'Arrange urology follow up in four weeks.',38,100,20,116,22,68,16,18,4,96,4,5,4),
(4,12,N'Asymptomatic bacteriuria, treatment withheld',N'no urinary symptoms, with bacteria reported on a urine sample sent for another reason, ',N'Afebrile and comfortable with no suprapubic or flank tenderness. ',N'Asymptomatic bacteriuria, which does not warrant antibiotic treatment in this setting. ',N'Withhold antibiotics, document the rationale, and treat only if symptoms develop. ',N'No antibiotics were given and the patient remained asymptomatic throughout the admission. ',N'Follow up with primary care if urinary symptoms develop.',36,74,14,124,20,74,14,14,4,98,2,0,2),
/* ---------- cond 5 : Appendicitis (K35.80) ---------- */
(5,1,N'Acute uncomplicated appendicitis',N'periumbilical pain migrating to the right lower quadrant with nausea and anorexia, ',N'Focal tenderness at the right iliac fossa with voluntary guarding and no rebound. ',N'Acute appendicitis without perforation, confirmed on imaging. ',N'Keep nil by mouth with intravenous fluids and analgesia while surgery plans the operation. ',N'Laparoscopic appendectomy was performed within twelve hours and the postoperative course was uncomplicated. ',N'Arrange surgical follow up in three weeks.',38,98,18,116,22,68,16,18,4,97,3,6,4),
(5,2,N'Perforated appendicitis with localized peritonitis',N'right lower quadrant pain that suddenly worsened then spread across the lower abdomen, ',N'Rebound tenderness and involuntary guarding localized to the right lower quadrant. ',N'Perforated appendicitis with localized peritonitis. ',N'Proceed to urgent appendectomy with broad antibiotics and fluid resuscitation. ',N'Urgent surgery confirmed perforation with localized contamination, and recovery was slower but uncomplicated. ',N'Arrange surgical follow up in three weeks.',38,110,22,106,22,62,16,22,4,96,4,8,3),
(5,3,N'Appendicitis with generalized peritonitis and sepsis',N'diffuse abdominal pain with high fever and rigidity over the past day, ',N'A rigid silent abdomen with generalized rebound and hemodynamic compromise. ',N'Appendicitis with generalized peritonitis and sepsis. ',N'Arrange emergent surgery with sepsis management and monitored-bed admission. ',N'Emergency laparotomy and washout were performed, and the patient required two days of monitored care before stepping down. ',N'Arrange surgical follow up in two weeks.',38,124,24,88,20,52,14,26,6,94,5,8,3),
(5,4,N'Appendiceal abscess managed by drainage',N'a week of right-sided abdominal pain with fever and a tender lump on examination, ',N'A tender palpable mass in the right iliac fossa without generalized peritonism. ',N'Appendiceal abscess with a walled-off collection on imaging. ',N'Arrange image-guided drainage with antibiotics and plan interval appendectomy. ',N'Image-guided drainage and antibiotics settled the sepsis, and interval appendectomy was booked for eight weeks. ',N'Arrange surgical follow up in six weeks.',38,102,20,110,22,66,16,20,4,96,4,6,4),
(5,5,N'Post-operative day one after appendectomy',N'improving abdominal pain on the first day after a laparoscopic appendectomy, ',N'Soft abdomen with clean port sites and audible bowel sounds. ',N'Acute appendicitis, first postoperative day, recovering after laparoscopic appendectomy. ',N'Continue postoperative analgesia, advance diet as tolerated, and mobilize early. ',N'Diet was advanced and the patient mobilized independently, with wounds clean and dry at review. ',N'Arrange surgical follow up in three weeks.',37,88,16,118,22,70,16,16,4,97,3,4,4),
(5,6,N'Suspected appendicitis under observation',N'intermittent right-sided abdominal pain over several days without fever, ',N'Equivocal right iliac fossa tenderness with no guarding or rebound. ',N'Suspected appendicitis with an equivocal examination and inconclusive imaging. ',N'Perform serial abdominal examinations with repeat imaging and surgical reassessment. ',N'Serial examination and repeat imaging clarified the diagnosis within twenty-four hours and surgery proceeded. ',N'Arrange surgical follow up in three weeks.',37,86,16,120,22,72,16,16,4,97,3,4,4),
(5,7,N'Retrocecal appendicitis',N'right-sided pain felt more in the flank than the front of the abdomen, ',N'Minimal anterior tenderness with pain reproduced on right hip extension. ',N'Retrocecal appendicitis, accounting for the atypical examination findings. ',N'Proceed to appendectomy and warn of the atypical position at operation. ',N'Operative findings confirmed a retrocecal appendix, which explained the sparse anterior signs. ',N'Arrange surgical follow up in three weeks.',38,94,18,116,22,68,16,18,4,97,3,5,4),
(5,8,N'Mesenteric adenitis',N'right lower quadrant pain following a recent sore throat and coryzal illness, ',N'Shifting tenderness with palpable tender nodes and no localized guarding. ',N'Mesenteric adenitis rather than appendicitis, supported by imaging. ',N'Give supportive care with analgesia and observe, avoiding an unnecessary operation. ',N'Pain settled with supportive care over two days and no operation was required. ',N'Follow up with primary care if pain recurs.',38,92,18,114,22,68,16,16,4,97,3,4,4),
(5,9,N'Ovarian cyst mimicking appendicitis',N'sudden right lower abdominal pain that began mid-cycle without fever, ',N'Right adnexal tenderness on examination with a soft abdomen elsewhere. ',N'Ruptured ovarian cyst mimicking appendicitis, with a normal appendix on imaging. ',N'Provide analgesia and observation, and involve gynecology rather than proceeding to surgery. ',N'Pain settled with analgesia and observation, and gynecology confirmed no intervention was needed. ',N'Arrange gynecology follow up in four weeks.',37,90,18,114,22,68,16,16,4,98,2,5,4),
(5,10,N'Appendicitis treated nonoperatively',N'right lower quadrant pain with imaging showing early uncomplicated appendicitis, ',N'Localized tenderness without guarding, rebound or systemic upset. ',N'Uncomplicated appendicitis suitable for a trial of antibiotic therapy. ',N'Treat with intravenous then oral antibiotics and counsel on the risk of recurrence. ',N'Symptoms resolved on antibiotics alone and the patient was counselled on the recurrence risk before discharge. ',N'Arrange surgical follow up in six weeks.',38,92,18,116,22,68,16,18,4,97,3,5,4),
(5,11,N'Surgical site infection after appendectomy',N'increasing redness and discharge from a port site a week after appendectomy, ',N'An erythematous port site with purulent discharge and surrounding induration. ',N'Surgical site infection following laparoscopic appendectomy. ',N'Open and drain the wound, send a swab, and start antibiotics with regular dressings. ',N'The wound was laid open and dressed daily, and cellulitis regressed on culture-directed antibiotics. ',N'Arrange surgical follow up in two weeks.',38,94,18,118,22,70,16,16,4,97,3,4,4),
(5,12,N'Postoperative ileus after appendectomy',N'abdominal distension with vomiting and no flatus on the second postoperative day, ',N'A distended tympanitic abdomen with absent bowel sounds and no peritonism. ',N'Postoperative ileus following appendectomy for perforated appendicitis. ',N'Rest the bowel, decompress with a nasogastric tube, and correct electrolytes. ',N'Bowel function returned on the fourth day with decompression and electrolyte correction, and diet was reintroduced. ',N'Arrange surgical follow up in three weeks.',37,96,18,112,22,66,16,18,4,97,3,4,4),
/* ---------- cond 6 : Chest pain (R07.9) ---------- */
(6,1,N'ST-elevation myocardial infarction',N'crushing substernal chest pressure radiating to the left arm and jaw with diaphoresis, ',N'Diaphoretic and distressed with clear lung fields and no murmur. ',N'ST-elevation myocardial infarction of the anterior territory. ',N'Activate the catheterization laboratory for emergent percutaneous coronary intervention. ',N'The vessel was opened within ninety minutes of arrival and the patient was established on secondary prevention before discharge. ',N'Arrange cardiology follow up within one week.',36,96,24,104,26,64,16,20,6,94,5,7,3),
(6,2,N'Non-ST-elevation myocardial infarction',N'chest tightness at rest lasting twenty minutes with breathlessness and nausea, ',N'Comfortable at rest with no murmur and clear lung fields. ',N'Non-ST-elevation myocardial infarction with a rising high-sensitivity troponin. ',N'Admit to telemetry, load antiplatelet and anticoagulant therapy, and plan inpatient angiography. ',N'Troponin peaked at twelve hours and angiography the following day identified a culprit lesion treated with a stent. ',N'Arrange cardiology follow up within one week.',36,88,22,118,26,70,16,18,6,95,4,5,4),
(6,3,N'Unstable angina',N'chest tightness now coming on at rest that previously occurred only with exertion, ',N'Pain free at the time of examination with normal heart sounds. ',N'Unstable angina with a crescendo pattern and negative serial troponins. ',N'Admit for serial troponins, antiplatelet therapy and inpatient risk stratification. ',N'Serial troponins remained negative and functional testing prompted outpatient angiography rather than an inpatient procedure. ',N'Arrange cardiology follow up in two weeks.',36,80,20,124,26,74,16,16,4,96,4,4,4),
(6,4,N'Stable angina',N'exertional chest tightness relieved within minutes by rest and unchanged for months, ',N'Normal cardiovascular examination with no signs of failure. ',N'Stable angina with a predictable exertional pattern and no acute coronary syndrome. ',N'Optimize antianginal therapy and arrange outpatient functional testing. ',N'The patient remained pain free at rest on optimized therapy and outpatient functional testing was arranged. ',N'Arrange cardiology follow up in four weeks.',36,74,18,132,24,78,16,14,4,97,3,3,4),
(6,5,N'Acute pericarditis',N'pleuritic, positional chest pain that improves markedly when leaning forward, ',N'A scratchy friction rub is audible at the left sternal edge. ',N'Acute pericarditis with widespread concave ST elevation and no effusion. ',N'Start high-dose anti-inflammatory therapy with colchicine and restrict strenuous activity. ',N'Pain settled within seventy-two hours on anti-inflammatory therapy and colchicine, and no effusion developed. ',N'Arrange cardiology follow up in three weeks.',37,94,20,118,24,70,16,18,4,96,4,5,4),
(6,6,N'Pulmonary embolism',N'sudden pleuritic chest pain with breathlessness after a long-haul flight, ',N'Tachycardic and tachypneic with a swollen tender calf and clear lung fields. ',N'Acute pulmonary embolism confirmed on computed tomography pulmonary angiography. ',N'Start therapeutic anticoagulation and risk stratify for right heart strain. ',N'Anticoagulation was started immediately, right heart strain was absent on echocardiography, and oxygenation normalized. ',N'Arrange anticoagulation clinic follow up in two weeks.',37,112,24,110,24,66,16,26,8,88,7,5,4),
(6,7,N'Spontaneous pneumothorax',N'sudden sharp one-sided chest pain with breathlessness that began at rest, ',N'Reduced expansion with absent breath sounds and hyperresonance on the right. ',N'Primary spontaneous pneumothorax on the right. ',N'Aspirate or place a small-bore chest drain and repeat imaging afterwards. ',N'The lung reinflated after small-bore drainage and the drain was removed on day two with no recurrence. ',N'Arrange respiratory follow up in two weeks.',36,102,22,118,24,70,16,24,6,91,6,5,4),
(6,8,N'Anxiety-related chest pain',N'sharp chest pain with palpitations, tingling in the fingers and a sense of dread, ',N'Anxious and hyperventilating with an entirely normal cardiovascular examination. ',N'Anxiety-related chest pain with a normal electrocardiogram and negative troponins. ',N'Provide reassurance and breathing techniques, and arrange psychological support. ',N'Symptoms settled with reassurance and breathing techniques, and no cardiac abnormality was found. ',N'Follow up with primary care in two weeks.',36,92,22,126,22,76,14,18,6,98,2,4,4),
(6,9,N'Takotsubo cardiomyopathy',N'crushing chest pain with breathlessness that began immediately after a severe emotional shock, ',N'Mildly distressed with a third heart sound and no murmur. ',N'Takotsubo cardiomyopathy with apical ballooning and unobstructed coronary arteries. ',N'Provide supportive heart failure therapy and repeat imaging to confirm recovery. ',N'Systolic function recovered substantially by the time of repeat imaging, consistent with a stress cardiomyopathy. ',N'Arrange cardiology follow up in four weeks.',36,98,22,108,24,66,16,20,6,94,5,6,4),
(6,10,N'Aortic dissection',N'sudden tearing chest pain radiating to the back between the shoulder blades, ',N'A twenty-point blood-pressure difference between arms with an early diastolic murmur. ',N'Acute aortic dissection with a widened mediastinum on imaging. ',N'Control heart rate and blood pressure urgently and refer immediately to cardiothoracic surgery. ',N'Rate and pressure were controlled while transfer was arranged, and the patient proceeded to emergency repair. ',N'Arrange cardiothoracic surgery follow up in two weeks.',36,88,22,168,32,96,20,22,6,95,4,8,3),
(6,11,N'Non-cardiac chest pain from reflux',N'burning retrosternal discomfort that is worse after meals and when lying flat, ',N'Comfortable with epigastric tenderness and a normal cardiovascular examination. ',N'Non-cardiac chest pain, likely gastroesophageal reflux, with a reassuring cardiac workup. ',N'Trial proton-pump inhibitor therapy and give dietary and positional advice. ',N'Symptoms improved on acid suppression and the cardiac workup was reassuring throughout. ',N'Arrange gastroenterology follow up in six weeks.',36,76,18,126,22,76,14,14,4,98,2,4,4),
(6,12,N'Costochondritis',N'sharp left-sided chest pain that is reproducible when pressing on the chest wall, ',N'Point tenderness over the costochondral junctions reproducing the pain exactly. ',N'Musculoskeletal costochondritis, with acute coronary syndrome excluded by serial troponins. ',N'Provide analgesia and reassurance, and discharge with clear return precautions. ',N'Pain was well controlled with simple analgesia and serial troponins remained negative. ',N'Follow up with primary care if the pain does not settle in two weeks.',36,78,18,124,22,74,14,14,4,98,2,5,4),
/* ---------- cond 7 : Syncope (R55) ---------- */
(7,1,N'Vasovagal syncope',N'a brief blackout after prolonged standing in a warm room with nausea beforehand, ',N'Well appearing with a normal cardiovascular and neurologic examination. ',N'Vasovagal syncope with a clear prodrome and rapid spontaneous recovery. ',N'Provide reassurance, teach counter-pressure maneuvers, and advise on trigger avoidance. ',N'No further episodes occurred during monitoring and counter-pressure maneuvers were taught before discharge. ',N'Follow up with primary care if episodes recur.',36,62,18,106,20,64,14,14,4,98,2,0,2),
(7,2,N'Complete heart block',N'a sudden loss of consciousness without warning while sitting quietly, ',N'A slow regular pulse with cannon waves visible in the neck. ',N'Cardiac syncope from complete heart block. ',N'Admit to telemetry, hold rate-limiting drugs, and refer urgently for pacing. ',N'A permanent pacemaker was implanted on the second day and no further episodes occurred afterwards. ',N'Arrange pacing clinic follow up in two weeks.',36,32,14,102,20,60,14,14,4,97,3,0,2),
(7,3,N'Orthostatic hypotension from medication',N'recurrent fainting when rising from a seated position since a medication change, ',N'A thirty-point systolic drop on standing that reproduces the symptoms. ',N'Orthostatic hypotension, medication related and compounded by volume depletion. ',N'Replete volume, withdraw the offending agent, and reassess standing pressures. ',N'Standing pressures normalized after volume repletion and withdrawal of the offending agent. ',N'Follow up with primary care in two weeks.',36,84,18,88,18,52,14,14,4,97,3,0,2),
(7,4,N'Exertional syncope from aortic stenosis',N'a loss of consciousness during exertion with slow recovery afterwards, ',N'A harsh ejection systolic murmur radiating to the carotids with a slow-rising pulse. ',N'Exertional syncope from severe aortic stenosis. ',N'Restrict activity, obtain urgent echocardiography, and refer for valve intervention. ',N'Echocardiography confirmed severe stenosis and the case was referred urgently for valve intervention. ',N'Arrange structural heart clinic follow up in one week.',36,72,18,102,20,62,14,16,4,96,4,1,3),
(7,5,N'Syncope of undetermined etiology',N'one witnessed fainting episode without warning and no recurrence since, ',N'Entirely normal cardiovascular and neurologic examination. ',N'Syncope of undetermined etiology after an unremarkable initial workup. ',N'Continue telemetry monitoring and arrange ambulatory rhythm recording on discharge. ',N'Telemetry captured no arrhythmia during the admission and an ambulatory recorder was fitted before discharge. ',N'Arrange cardiology follow up in four weeks.',36,70,18,116,22,70,14,14,4,97,3,0,2),
(7,6,N'Situational syncope',N'a blackout that occurred during a coughing fit with immediate recovery, ',N'Normal examination with a clear situational precipitant identified. ',N'Situational syncope with a clear precipitant and a reassuring workup. ',N'Reassure, treat the underlying cough, and advise on situational precautions. ',N'No further episodes occurred once the cough was treated and situational advice was given. ',N'Follow up with primary care in four weeks.',36,72,18,112,20,68,14,16,4,97,3,0,2),
(7,7,N'Syncope from ventricular tachycardia',N'a syncopal episode preceded by rapid palpitations and chest discomfort, ',N'Normal at rest, with a broad-complex tachycardia documented on the monitor. ',N'Cardiac syncope from monomorphic ventricular tachycardia. ',N'Admit to a monitored bed, start antiarrhythmic therapy, and refer for defibrillator assessment. ',N'Rhythm was controlled on antiarrhythmic therapy and the patient was accepted for defibrillator implantation. ',N'Arrange electrophysiology follow up in one week.',36,96,26,104,22,62,14,16,4,96,4,1,3),
(7,8,N'Syncope from gastrointestinal bleeding',N'a faint on standing with several days of black tarry stools beforehand, ',N'Pale with a postural drop and melena confirmed on rectal examination. ',N'Syncope secondary to anemia from an upper gastrointestinal bleed. ',N'Resuscitate, transfuse to target, start acid suppression, and arrange urgent endoscopy. ',N'Endoscopy identified and treated the bleeding point, and hemoglobin stabilized after transfusion. ',N'Arrange gastroenterology follow up in three weeks.',36,104,22,92,20,54,14,18,4,96,4,1,3),
(7,9,N'Carotid sinus hypersensitivity',N'blackouts when turning the head or fastening a tight collar, ',N'A marked pause reproduced on carotid sinus massage under monitoring. ',N'Carotid sinus hypersensitivity of the cardioinhibitory type. ',N'Avoid provoking maneuvers and refer for pacing assessment. ',N'Symptoms were reproduced under monitoring and the patient was referred for pacing assessment. ',N'Arrange cardiology follow up in three weeks.',36,58,16,112,20,68,14,14,4,97,3,0,2),
(7,10,N'Syncope from pulmonary embolism',N'a collapse with breathlessness that began suddenly this morning, ',N'Tachycardic and tachypneic with a raised jugular venous pressure and clear lungs. ',N'Syncope secondary to acute pulmonary embolism with right heart strain. ',N'Start therapeutic anticoagulation and assess for reperfusion therapy. ',N'Right heart strain improved on anticoagulation and reperfusion therapy was not required. ',N'Arrange anticoagulation clinic follow up in one week.',37,116,24,96,20,58,14,26,8,89,6,2,3),
(7,11,N'Convulsive syncope',N'a blackout with brief limb jerking witnessed by a bystander and rapid recovery, ',N'Alert with no tongue biting, no incontinence and a normal neurologic examination. ',N'Convulsive syncope rather than a primary seizure, given the rapid recovery. ',N'Avoid antiepileptic therapy, arrange cardiac rhythm assessment, and counsel on driving. ',N'Cardiac assessment identified the cause and antiepileptic therapy was correctly avoided. ',N'Arrange neurology follow up in six weeks.',36,68,18,108,20,66,14,14,4,98,2,0,2),
(7,12,N'Syncope from dehydration in an older adult',N'lightheadedness and one faint during a spell of hot weather with poor fluid intake, ',N'Dry mucous membranes with a postural drop and no focal neurology. ',N'Syncope from volume depletion in an older adult. ',N'Rehydrate, review diuretic dosing, and reassess orthostatic vitals before discharge. ',N'Standing pressures normalized with rehydration and the diuretic dose was reduced before discharge. ',N'Follow up with primary care in two weeks.',36,88,18,94,18,56,14,16,4,97,3,0,2),
/* ---------- cond 8 : Stroke (I63.9) ---------- */
(8,1,N'Ischemic stroke within the thrombolysis window',N'sudden right-sided weakness and slurred speech that began ninety minutes ago, ',N'Right facial droop with arm weakness and expressive dysphasia. ',N'Acute ischemic stroke presenting within the thrombolysis window. ',N'Activate the stroke team for immediate imaging and thrombolysis assessment. ',N'Thrombolysis was given within the window and the deficit improved substantially over the following day. ',N'Arrange stroke clinic follow up in two weeks.',36,84,20,158,28,88,18,16,4,96,4,0,2),
(8,2,N'Ischemic stroke outside the thrombolysis window',N'right-sided weakness and slurred speech noted on waking this morning, ',N'A dense right hemiparesis with dysarthria and no improvement since onset. ',N'Acute ischemic stroke outside the thrombolysis window. ',N'Admit to the stroke unit, obtain imaging, and start secondary prevention. ',N'Thrombolysis was not appropriate given the time of onset, and the patient began stroke-unit rehabilitation on day one. ',N'Arrange stroke clinic follow up in three weeks.',36,80,20,164,28,92,18,16,4,96,4,0,2),
(8,3,N'Transient ischemic attack',N'transient right-arm weakness that resolved completely within the hour, ',N'A normal neurologic examination at the time of assessment. ',N'Transient ischemic attack with complete resolution of the deficit. ',N'Start antiplatelet therapy and arrange expedited carotid imaging and risk-factor control. ',N'Carotid imaging was expedited, antiplatelet therapy was started, and no further events occurred. ',N'Arrange stroke clinic follow up within one week.',36,76,18,152,26,88,16,14,4,97,3,0,2),
(8,4,N'Subarachnoid hemorrhage',N'a sudden severe headache with neck stiffness and vomiting that peaked instantly, ',N'Neck stiffness and photophobia with no focal limb weakness. ',N'Subarachnoid hemorrhage confirmed on emergent imaging. ',N'Control blood pressure, start nimodipine, and refer emergently to neurosurgery. ',N'Neurosurgery secured the aneurysm and the patient was monitored for vasospasm on nimodipine. ',N'Arrange neurosurgery follow up in three weeks.',36,72,20,172,30,96,18,16,4,96,4,8,3),
(8,5,N'Posterior circulation stroke',N'acute vertigo, imbalance and double vision that began abruptly, ',N'Nystagmus with limb ataxia and an unsteady gait but preserved power. ',N'Posterior circulation stroke with brainstem and cerebellar signs. ',N'Admit to the stroke unit, obtain magnetic resonance imaging, and screen swallowing early. ',N'Imaging confirmed a cerebellar infarct, swallowing was safe on screening, and the patient improved with rehabilitation. ',N'Arrange stroke clinic follow up in three weeks.',36,78,18,154,26,88,16,16,4,96,4,1,3),
(8,6,N'Cardioembolic stroke from atrial fibrillation',N'sudden left-sided weakness with a known irregular heartbeat and missed anticoagulant doses, ',N'An irregularly irregular pulse with a left hemiparesis and facial weakness. ',N'Cardioembolic ischemic stroke in the setting of atrial fibrillation. ',N'Admit to the stroke unit and restart anticoagulation at the guideline-recommended interval. ',N'Anticoagulation was restarted at the recommended interval and the patient made steady rehabilitation progress. ',N'Arrange stroke clinic follow up in three weeks.',36,104,24,156,28,90,18,16,4,96,4,0,2),
(8,7,N'Large vessel occlusion for thrombectomy',N'sudden dense weakness with loss of speech that began two hours ago, ',N'A dense hemiparesis with global dysphasia and forced gaze deviation. ',N'Acute ischemic stroke from a proximal large vessel occlusion. ',N'Activate the thrombectomy pathway and transfer immediately to the neurointerventional center. ',N'Mechanical thrombectomy achieved reperfusion and the deficit improved markedly within twenty-four hours. ',N'Arrange stroke clinic follow up in two weeks.',36,88,20,166,28,92,18,18,4,95,4,0,2),
(8,8,N'Lacunar stroke',N'progressive left-sided numbness and mild weakness developing over hours, ',N'Pure motor weakness of the left limbs with no cortical signs. ',N'Lacunar infarct affecting the internal capsule. ',N'Start antiplatelet and statin therapy and control blood pressure carefully. ',N'The deficit was mild and improved with early physiotherapy on optimized secondary prevention. ',N'Arrange stroke clinic follow up in four weeks.',36,76,18,158,26,90,16,14,4,97,3,0,2),
(8,9,N'Stroke with symptomatic carotid stenosis',N'a stroke with speech disturbance and a bruit noted in the neck on examination, ',N'A carotid bruit with residual expressive dysphasia and mild arm weakness. ',N'Ischemic stroke with symptomatic severe carotid stenosis on imaging. ',N'Start secondary prevention and refer for carotid endarterectomy within two weeks. ',N'The patient was accepted for carotid endarterectomy within the recommended two-week window. ',N'Arrange vascular surgery follow up within one week.',36,78,18,160,26,90,16,14,4,97,3,0,2),
(8,10,N'Stroke mimic from hypoglycemia',N'sudden confusion with one-sided weakness that resolved after treatment in the ambulance, ',N'Neurologically intact on arrival with a documented low capillary glucose before treatment. ',N'Stroke mimic caused by hypoglycemia, with normal brain imaging. ',N'Correct and monitor glucose, review diabetes therapy, and avoid unnecessary stroke treatment. ',N'The deficit resolved completely with glucose correction and imaging showed no infarct. ',N'Follow up with the diabetes team in one week.',36,86,18,138,24,80,16,14,4,97,3,0,2),
(8,11,N'Intracerebral hemorrhage',N'sudden headache with weakness and rapidly declining alertness, ',N'Drowsy with a dense hemiparesis and a markedly elevated blood pressure. ',N'Intracerebral hemorrhage confirmed on computed tomography. ',N'Lower blood pressure to target, reverse any anticoagulation, and involve neurosurgery. ',N'Blood pressure was brought to target and repeat imaging showed no expansion of the hematoma. ',N'Arrange neurosurgery follow up in three weeks.',36,74,20,186,30,102,18,16,4,95,4,5,4),
(8,12,N'Cerebral venous sinus thrombosis',N'a persistent headache over days with blurred vision and one seizure, ',N'Papilledema with no focal limb weakness and a postictal state on arrival. ',N'Cerebral venous sinus thrombosis identified on venographic imaging. ',N'Start therapeutic anticoagulation despite the imaging appearance and screen for thrombophilia. ',N'Anticoagulation was started safely and the headache and visual symptoms improved over several days. ',N'Arrange neurology follow up in three weeks.',37,84,18,144,26,84,16,16,4,97,3,6,4),
/* ---------- cond 9 : COPD (J44.9) ---------- */
(9,1,N'Infective COPD exacerbation',N'increased breathlessness, wheeze and a change in sputum color and volume, ',N'Widespread expiratory wheeze with a prolonged expiratory phase. ',N'COPD exacerbation with an infective trigger. ',N'Give nebulized bronchodilators, systemic steroids and titrated controlled oxygen. ',N'Breathlessness and sputum purulence improved over four days on bronchodilators, steroids and antibiotics. ',N'Arrange respiratory follow up in three weeks.',37,102,22,126,24,74,16,24,6,87,6,2,4),
(9,2,N'Severe exacerbation with respiratory acidosis',N'severe breathlessness with accessory muscle use and difficulty speaking in sentences, ',N'Using accessory muscles with a silent chest in places and drowsiness. ',N'Severe COPD exacerbation with hypercapnic respiratory failure and acidosis. ',N'Start noninvasive ventilation with controlled oxygen targets in a monitored bed. ',N'The acidosis corrected over the first twelve hours of noninvasive ventilation, which was weaned by day three. ',N'Arrange respiratory follow up within two weeks.',37,116,24,138,26,80,18,30,8,82,7,3,4),
(9,3,N'Exacerbation with hypoxemia',N'worsening breathlessness and cough despite regular use of home inhalers, ',N'Reduced air entry with widespread wheeze and visible hypoxemia on room air. ',N'Acute COPD exacerbation with hypoxemia responding to nebulized therapy. ',N'Give nebulized therapy with controlled oxygen to a target saturation range. ',N'Saturations returned to the target range on controlled oxygen and nebulized therapy over two days. ',N'Arrange respiratory follow up in three weeks.',37,104,22,128,24,76,16,26,6,84,6,2,4),
(9,4,N'Viral-triggered exacerbation',N'progressive breathlessness after a recent upper respiratory infection with a dry cough, ',N'Diffuse wheeze with coryzal features and no focal consolidation. ',N'COPD exacerbation triggered by a viral infection. ',N'Provide supportive care with bronchodilators and steroids, and withhold antibiotics. ',N'Symptoms settled on supportive care and antibiotics were correctly withheld given the viral trigger. ',N'Arrange respiratory follow up in four weeks.',37,98,20,124,24,74,16,22,6,89,5,2,4),
(9,5,N'Exacerbation with marked bronchospasm',N'wheezing and chest tightness with markedly reduced exercise tolerance, ',N'Marked polyphonic wheeze throughout with a poor peak flow. ',N'COPD exacerbation with severe bronchospasm. ',N'Intensify bronchodilator therapy, add steroids, and reassess oxygenation regularly. ',N'Peak flow improved substantially on intensified bronchodilators and steroids over three days. ',N'Arrange respiratory follow up in three weeks.',37,108,22,130,24,76,16,26,6,88,6,3,4),
(9,6,N'Bacterial exacerbation',N'increasing cough with purulent sputum and a low-grade fever for four days, ',N'Coarse crackles with widespread wheeze and a low-grade fever. ',N'COPD exacerbation with a bacterial trigger. ',N'Start antibiotics, continue bronchodilators and steroids, and trend oxygenation. ',N'Sputum cleared and fever settled on antibiotics, with oxygenation improving in parallel. ',N'Arrange respiratory follow up in three weeks.',38,104,20,126,24,74,16,24,6,88,6,2,4),
(9,7,N'COPD with cor pulmonale',N'increasing breathlessness with marked ankle swelling and abdominal fullness, ',N'A raised jugular venous pressure with pitting edema and a loud pulmonary second sound. ',N'COPD complicated by cor pulmonale with right heart failure. ',N'Give diuretics with long-term oxygen assessment and continue bronchodilator therapy. ',N'Edema settled with careful diuresis and the patient was referred for long-term oxygen assessment. ',N'Arrange respiratory follow up in four weeks.',37,100,20,118,22,70,16,24,6,85,6,2,3),
(9,8,N'COPD with secondary pneumothorax',N'a sudden increase in breathlessness with one-sided chest pain on a background of emphysema, ',N'Reduced expansion with absent breath sounds on the left and hyperresonance. ',N'Secondary spontaneous pneumothorax complicating emphysema. ',N'Place an intercostal drain promptly given the underlying lung disease and repeat imaging. ',N'The lung reinflated after intercostal drainage and the drain was removed once the leak sealed. ',N'Arrange respiratory follow up in two weeks.',36,110,22,120,24,72,16,28,6,86,6,5,4),
(9,9,N'COPD and heart failure overlap',N'breathlessness with both wheeze and orthopnea alongside ankle swelling, ',N'Wheeze with bibasilar crackles, a raised venous pressure and pitting edema. ',N'COPD exacerbation with coexisting decompensated heart failure. ',N'Treat both processes with bronchodilators, steroids and cautious diuresis. ',N'Both processes responded to parallel treatment, with weight falling and wheeze reducing over four days. ',N'Arrange combined respiratory and cardiology follow up in three weeks.',37,100,20,124,24,74,16,24,6,86,6,2,3),
(9,10,N'End-stage COPD, palliative approach',N'severe breathlessness at rest with weight loss and repeated recent admissions, ',N'Cachectic and breathless at rest with widespread quiet breath sounds. ',N'End-stage COPD with a palliative rather than escalation-focused approach agreed. ',N'Focus on symptom control with opioids for breathlessness and engage the palliative care team. ',N'Breathlessness was controlled with low-dose opioids and a ceiling of treatment was agreed with the family. ',N'Arrange palliative care follow up within one week.',36,98,20,112,22,66,16,26,6,85,6,3,4),
(9,11,N'Exacerbation after smoking relapse',N'worsening cough and breathlessness since returning to smoking two months ago, ',N'Widespread wheeze with a productive cough and nicotine staining. ',N'COPD exacerbation following a return to smoking. ',N'Treat the exacerbation and refer to smoking cessation services before discharge. ',N'The exacerbation settled on standard therapy and a cessation plan with pharmacotherapy was agreed. ',N'Arrange smoking cessation follow up in two weeks.',37,100,20,126,24,74,16,24,6,88,6,2,4),
(9,12,N'Exacerbation from inhaler nonadherence',N'worsening breathlessness after running out of inhalers several weeks ago, ',N'Widespread wheeze with poor inhaler technique demonstrated on review. ',N'COPD exacerbation precipitated by interrupted inhaler therapy. ',N'Restart maintenance inhalers, correct technique, and resolve the supply problem. ',N'Symptoms improved once maintenance therapy was restarted and inhaler technique was corrected at the bedside. ',N'Arrange respiratory nurse follow up in two weeks.',37,98,20,124,24,74,16,22,6,89,5,2,4),
/* ---------------------------------------------------------------------------
   cond 10, 11 and 12 : PEDIATRIC bands, four stories each.

   Ward General has a Pediatrics department with a NICU and a PICU, and the
   patient roster runs from newborns upward, so children are admitted. The
   first 132 stories are all adult presentations, and #EncStory used to hand
   them out on EncounterId arithmetic alone -- which put an ST-elevation
   myocardial infarction on a one-year-old.

   The bands exist because the VITALS live on the story row. A healthy infant
   runs a heart rate of 140 and a respiratory rate of 40; a healthy adolescent
   does not. One pediatric band could not carry both without being wrong for
   one of them, so age selects the band and the band carries its own ranges.

   The same regex contract applies: the note prints "HR nnn" and "BP nnn/nn",
   so every range here stays inside two or three digits.
   --------------------------------------------------------------------------- */
/* ---------- cond 10 : Infant, under 2 ---------- */
(10,1,N'Bronchiolitis with respiratory distress',N'noisy breathing with poor feeding and a runny nose for three days, ',N'Nasal flaring with subcostal recession and widespread wheeze throughout. ',N'Acute bronchiolitis with increased work of breathing. ',N'Admit for nasal suction, supplemental oxygen as required and small frequent feeds. ',N'Work of breathing settled over three days with suction and oxygen, and feeding volumes returned to normal before discharge. ',N'Arrange pediatric follow up in one week.',37,140,30,78,18,42,16,46,18,88,6,0,2),
(10,2,N'Febrile urinary tract infection',N'fever with irritability and fewer wet diapers over two days, ',N'Febrile and irritable with a soft abdomen and no rash. ',N'Febrile urinary tract infection with no other source identified. ',N'Send a catheter urine culture and start intravenous antibiotics pending sensitivities. ',N'Fever settled within forty-eight hours of intravenous antibiotics and the culture guided the oral step-down. ',N'Arrange pediatric follow up in two weeks.',38,150,30,76,18,40,16,34,14,95,4,1,3),
(10,3,N'Viral gastroenteritis with dehydration',N'frequent watery stools with vomiting and reduced wet diapers, ',N'Dry mucous membranes with sunken eyes and a prolonged capillary refill. ',N'Viral gastroenteritis with moderate dehydration. ',N'Give oral rehydration by syringe and escalate to intravenous fluids if intake fails. ',N'Hydration was restored over twenty-four hours and stool frequency fell steadily before discharge. ',N'Arrange pediatric follow up in one week.',37,155,30,70,16,38,14,32,12,95,4,1,3),
(10,4,N'Neonatal jaundice requiring phototherapy',N'yellow discoloration of the skin and eyes noticed on the third day of life, ',N'Jaundiced to the chest with normal tone and an unremarkable abdomen. ',N'Unconjugated hyperbilirubinemia of the newborn above the phototherapy threshold. ',N'Start phototherapy, recheck bilirubin at intervals and support establishment of feeding. ',N'Bilirubin fell below the treatment line after thirty-six hours of phototherapy and feeding was established. ',N'Arrange newborn follow up in three days.',36,120,30,66,16,36,14,36,14,96,3,0,1),
/* ---------- cond 11 : Child, 2 to 12 ---------- */
(11,1,N'Community-acquired pneumonia',N'a productive cough with fever and fast breathing for four days, ',N'Focal crackles at the right base with mild subcostal recession. ',N'Community-acquired pneumonia with focal consolidation. ',N'Start oral antibiotics with antipyretics and review the oxygen requirement daily. ',N'Fever settled by the second day of antibiotics and the oxygen requirement resolved before discharge. ',N'Arrange pediatric follow up in two weeks.',38,110,30,88,20,48,16,26,12,90,6,2,4),
(11,2,N'Acute asthma exacerbation',N'wheeze and breathlessness that worsened after a cold, ',N'Widespread expiratory wheeze with intercostal recession and a prolonged expiratory phase. ',N'Acute asthma exacerbation with a partial response to initial bronchodilators. ',N'Give burst bronchodilators with oral steroids and space treatment as the response allows. ',N'Wheeze settled over two days as bronchodilators were spaced out and the steroid course was completed. ',N'Arrange asthma clinic follow up in three weeks.',36,120,30,92,20,50,16,28,14,89,6,1,3),
(11,3,N'Acute appendicitis in a child',N'central abdominal pain that moved to the right side with vomiting, ',N'Right lower quadrant tenderness with guarding and pain on percussion. ',N'Acute appendicitis without evidence of perforation. ',N'Keep nil by mouth, give fluids and analgesia, and refer for appendicectomy. ',N'Laparoscopic appendicectomy was performed the same day and recovery was uncomplicated. ',N'Arrange surgical follow up in two weeks.',37,105,30,92,20,52,16,22,10,96,3,5,4),
(11,4,N'Croup with stridor at rest',N'a barking cough with noisy breathing that is worse at night, ',N'A barking cough with stridor at rest and mild suprasternal recession. ',N'Moderate croup with stridor at rest. ',N'Give a single dose of oral steroid and observe for recurrence of stridor at rest. ',N'Stridor settled within hours of the steroid dose and the child was observed overnight without recurrence. ',N'Arrange pediatric follow up in one week.',37,115,30,90,20,50,16,26,12,92,6,1,3),
/* ---------- cond 12 : Adolescent, 13 to 17 ---------- */
(12,1,N'Acute appendicitis with localized peritonism',N'abdominal pain that began around the navel and settled in the right lower abdomen, ',N'Localized right lower quadrant tenderness with rebound and voluntary guarding. ',N'Acute appendicitis with localized peritonism. ',N'Keep nil by mouth, start fluids and analgesia, and refer for urgent appendicectomy. ',N'Laparoscopic appendicectomy was performed within twelve hours and the postoperative course was uncomplicated. ',N'Arrange surgical follow up in two weeks.',37,92,28,104,22,58,16,18,8,96,3,5,4),
(12,2,N'Diabetic ketoacidosis in new type 1 diabetes',N'thirst with weight loss and vomiting over a week before becoming drowsy, ',N'Dehydrated with deep sighing respirations and a ketotic smell on the breath. ',N'Diabetic ketoacidosis as the first presentation of type 1 diabetes. ',N'Rehydrate carefully, start a fixed rate insulin infusion and monitor for cerebral edema. ',N'The acidosis cleared over eighteen hours on an insulin infusion and the family completed structured diabetes education before discharge. ',N'Arrange pediatric diabetes follow up within one week.',36,110,30,96,22,54,16,26,12,96,3,2,4),
(12,3,N'Infectious mononucleosis',N'a severe sore throat with fever and profound tiredness for ten days, ',N'Enlarged tonsils with exudate, tender cervical nodes and a palpable spleen tip. ',N'Infectious mononucleosis with tonsillar enlargement and splenomegaly. ',N'Give supportive care with fluids and analgesia and advise avoiding contact sport. ',N'Oral intake improved with regular analgesia and the patient was discharged with advice to avoid contact sport while the spleen remained enlarged. ',N'Arrange pediatric follow up in four weeks.',38,88,28,102,22,58,16,16,8,96,3,4,4),
(12,4,N'Vasovagal syncope in an adolescent',N'a brief faint while standing in a warm hall with rapid full recovery, ',N'Alert with a normal cardiovascular and neurologic examination and no injury. ',N'Vasovagal syncope with a typical prodrome and rapid recovery. ',N'Record an electrocardiogram, advise hydration and counter-pressure manoeuvres, and review triggers. ',N'The electrocardiogram was normal and no further episodes occurred during a period of observation. ',N'Arrange pediatric follow up in six weeks.',36,58,40,96,24,54,16,14,8,97,2,0,2),
/* ---------- cond 13 : Psychiatric admission ----------
   Ward General has two psychiatry units, and until this condition existed the
   department had to borrow from the medical catalogue: an Adult Psych bed read
   "acute bacterial prostatitis" on the unit board. A psychiatric inpatient can
   certainly have a urinary infection, but the note never said why the patient
   was on a psychiatry ward, which is the one thing a psychiatry chart must say.

   Vital signs still carry clinical meaning here. Most psychiatric admissions are
   physiologically unremarkable, so these ranges sit near normal -- which is
   itself the point, because the four that are NOT (delirium tremens, serotonin
   syndrome, the bradycardia of anorexia, the tremor and slow pulse of lithium
   toxicity) are the ones a nurse is watching the monitor for. */
(13,1,N'Severe depression with active suicidal ideation',N'weeks of low mood with poor sleep and thoughts of ending their life, ',N'Flat affect with psychomotor slowing and no evidence of self-harm injury. ',N'Severe depressive episode with active suicidal ideation requiring inpatient safety. ',N'Admit for constant observation, start an antidepressant, and complete a full risk assessment. ',N'Suicidal ideation receded over several days of inpatient support and the antidepressant was tolerated without early side effects. ',N'Arrange psychiatry follow up within one week.',36,68,16,112,20,70,14,14,4,98,2,0,2),
(13,2,N'First-episode psychosis',N'several weeks of hearing voices with growing suspicion of neighbours, ',N'Guarded and distractible with disorganized speech and no focal neurologic signs. ',N'First episode of psychosis with organic causes excluded on initial workup. ',N'Start a second-generation antipsychotic at low dose and involve the early intervention team. ',N'Hallucinations became less intrusive over the first week of treatment and insight began to return before discharge. ',N'Arrange early intervention team follow up within one week.',36,84,18,124,20,76,14,16,4,98,2,0,2),
(13,3,N'Bipolar disorder with acute mania',N'five days of little sleep with rapid speech and heavy unplanned spending, ',N'Elated and pressured with flight of ideas and marked distractibility. ',N'Acute manic episode of bipolar affective disorder with impaired judgement. ',N'Admit for stabilization, start a mood stabilizer, and restrict access to finances during the episode. ',N'Sleep returned by the fourth day on a mood stabilizer and speech and spending normalized before discharge. ',N'Arrange psychiatry follow up in two weeks.',36,96,20,134,22,82,16,18,4,98,2,0,2),
(13,4,N'Alcohol withdrawal with delirium tremens',N'tremor and sweating with visual hallucinations two days after stopping alcohol, ',N'Tremulous and disoriented with profuse sweating and a coarse resting tremor. ',N'Delirium tremens complicating alcohol withdrawal. ',N'Give symptom-triggered benzodiazepines with thiamine replacement in a monitored bed. ',N'Withdrawal scores fell steadily on symptom-triggered dosing and the hallucinations resolved by the third day. ',N'Arrange addiction services follow up within one week.',38,116,24,168,28,96,18,24,6,95,4,2,3),
(13,5,N'Schizophrenia relapse after stopping medication',N'a return of voices and withdrawal from family since stopping medication two months ago, ',N'Preoccupied and responding to unseen stimuli with poor eye contact. ',N'Relapse of schizophrenia following discontinuation of antipsychotic therapy. ',N'Restart the previously effective agent and discuss a long-acting injectable before discharge. ',N'Symptoms settled on the reinstated agent and the patient agreed to a long-acting injectable at discharge. ',N'Arrange community mental health follow up within two weeks.',36,88,18,126,22,78,14,16,4,98,2,0,2),
(13,6,N'Panic disorder with recurrent attacks',N'repeated episodes of breathlessness and terror that peak within minutes, ',N'Anxious with rapid shallow breathing and an entirely normal cardiac examination. ',N'Panic disorder with recurrent attacks and no organic cause identified. ',N'Teach breathing control, start a serotonin reuptake inhibitor, and refer for cognitive therapy. ',N'Attack frequency fell during admission with breathing techniques and the first doses of therapy were tolerated. ',N'Arrange psychology follow up in three weeks.',36,104,22,138,22,84,16,22,6,98,2,2,3),
(13,7,N'Anorexia nervosa with medical instability',N'months of severe food restriction with dizziness and a marked fall in weight, ',N'Emaciated with a slow pulse, cool peripheries and lanugo hair over the back. ',N'Anorexia nervosa with medical instability requiring supervised refeeding. ',N'Begin cautious refeeding with daily electrolytes and cardiac monitoring for refeeding syndrome. ',N'Refeeding proceeded without electrolyte collapse and weight rose slowly under supervision. ',N'Arrange eating disorder service follow up within one week.',36,44,14,84,16,52,12,14,4,98,2,0,2),
(13,8,N'Opioid withdrawal on a supervised taper',N'muscle aches with sweating, yawning and abdominal cramps since the last dose, ',N'Restless with dilated pupils, gooseflesh and a fine tremor. ',N'Opioid withdrawal in the setting of opioid use disorder. ',N'Start opioid substitution with adjunctive symptomatic relief and monitor withdrawal scores. ',N'Withdrawal scores fell steadily once substitution therapy was established and cravings became manageable. ',N'Arrange addiction services follow up within one week.',37,104,20,142,22,86,16,20,4,97,3,4,4),
(13,9,N'Lithium toxicity',N'unsteadiness with coarse tremor and vomiting after a recent increase in dose, ',N'Ataxic with a coarse tremor and brisk reflexes but no focal weakness. ',N'Lithium toxicity with a level above the therapeutic range. ',N'Hold lithium, give intravenous fluids, and check levels and renal function every six hours. ',N'Levels fell into range with fluids and the tremor and unsteadiness resolved over two days. ',N'Arrange psychiatry follow up within one week.',36,58,16,106,20,64,14,16,4,97,3,0,2),
(13,10,N'Serotonin syndrome from a medication interaction',N'agitation with sweating and twitching that began after a second agent was added, ',N'Agitated and diaphoretic with inducible clonus and hyperreflexia in the legs. ',N'Serotonin syndrome precipitated by a serotonergic drug interaction. ',N'Stop all serotonergic agents, cool actively, and give benzodiazepines in a monitored bed. ',N'Clonus and rigidity resolved within thirty-six hours of stopping the offending agents. ',N'Arrange psychiatry follow up in two weeks.',38,118,24,156,26,92,18,24,6,95,4,2,3),
(13,11,N'Post-traumatic stress disorder in acute crisis',N'worsening nightmares and flashbacks with hypervigilance since an anniversary date, ',N'Startled easily during the interview with a guarded posture and intact orientation. ',N'Post-traumatic stress disorder in acute exacerbation without psychotic features. ',N'Provide a low-stimulus environment, begin trauma-focused therapy, and review sleep medication. ',N'Nightmares became less frequent with sleep support and the first trauma-focused sessions were completed. ',N'Arrange trauma therapy follow up in two weeks.',36,92,20,132,22,80,16,18,4,98,2,1,3),
(13,12,N'Delirium in an older adult on the psychiatry ward',N'sudden confusion with disturbed sleep and fluctuating alertness over two days, ',N'Inattentive and fluctuating with disorganized thinking and no new focal deficit. ',N'Delirium superimposed on an existing psychiatric illness rather than a primary relapse. ',N'Search for and treat the precipitant, minimize sedatives, and reorient frequently with family present. ',N'Attention improved once the underlying precipitant was treated and sedatives were reduced. ',N'Arrange old age psychiatry follow up in two weeks.',37,96,20,144,24,84,16,20,4,96,4,1,3);
GO

/* ----------------------------------------------------------------------------
   Two of the 144 stories are SEX-SPECIFIC; the other 142 are not. Story
   selection is pure EncounterId arithmetic and knows nothing about the
   patient, so without this an encounter can be handed the prostatitis story
   on a female patient or the ovarian-cyst story on a male one. Roughly 500
   notes, each with the patient's sex printed in the chart header immediately
   above it. Declared here rather than as a 22nd column on all 144 VALUES rows,
   because the requirement is the exception and reads better as one.
   ---------------------------------------------------------------------------- */
ALTER TABLE #Story ADD SexReq NVARCHAR(20) NULL;
GO
UPDATE #Story SET SexReq = N'Male'   WHERE cond = 4 AND sid = 11;  -- acute bacterial prostatitis
UPDATE #Story SET SexReq = N'Female' WHERE cond = 5 AND sid =  9;  -- ovarian cyst mimicking appendicitis
GO

/* ----------------------------------------------------------------------------
   The ICD-10-CM code each story is filed under.

   The code belongs to the STORY, not to the condition. Condition-level coding
   was the earlier design and it produced diagnoses that contradicted their own
   notes: three of the twelve hypertension stories are explicitly SECONDARY
   hypertension, so filing them under I10 ("essential hypertension") asserts
   the opposite of what the note says, and the ovarian-cyst story sat under an
   appendicitis code. Coding per story removes the contradiction — cond is now
   only a grouping for generation, never a clinical claim.

   These are ordinary codes for common presentations. The dataset is synthetic
   and is not a coding reference; nothing in the project depends on the codes being
   billable-accurate, only on them agreeing with the note beside them.
   ---------------------------------------------------------------------------- */
ALTER TABLE #Story ADD Icd VARCHAR(10) NULL;
GO
UPDATE s SET s.Icd = v.Icd
FROM #Story AS s
JOIN (VALUES
    /* hypertension */
    (0,1,'I16.1'),   (0,2,'I16.1'),   (0,3,'I67.4'),   (0,4,'I16.0'),
    (0,5,'I10'),     (0,6,'I10'),     (0,7,'R03.0'),   (0,8,'I15.0'),
    (0,9,'I15.2'),   (0,10,'I10'),    (0,11,'I95.2'),  (0,12,'I15.2'),
    /* type 2 diabetes */
    (1,1,'E11.10'),  (1,2,'E11.01'),  (1,3,'E11.65'),  (1,4,'E11.621'),
    (1,5,'E11.649'), (1,6,'E11.9'),   (1,7,'E11.43'),  (1,8,'E11.21'),
    (1,9,'E11.42'),  (1,10,'E09.65'), (1,11,'E11.319'),(1,12,'E11.65'),
    /* heart failure */
    (2,1,'I50.21'),  (2,2,'I50.1'),   (2,3,'I50.31'),  (2,4,'I50.811'),
    (2,5,'I13.0'),   (2,6,'I50.9'),   (2,7,'I50.9'),   (2,8,'I25.5'),
    (2,9,'I35.0'),   (2,10,'R57.0'),  (2,11,'I50.9'),  (2,12,'I42.7'),
    /* pneumonia */
    (3,1,'J18.9'),   (3,2,'J90'),     (3,3,'A41.9'),   (3,4,'J69.0'),
    (3,5,'J15.7'),   (3,6,'J15.9'),   (3,7,'J11.00'),  (3,8,'J86.9'),
    (3,9,'J18.8'),   (3,10,'J44.0'),  (3,11,'J85.2'),  (3,12,'J18.9'),
    /* urinary tract infection */
    (4,1,'N30.00'),  (4,2,'N10'),     (4,3,'A41.9'),   (4,4,'N39.0'),
    (4,5,'T83.511A'),(4,6,'N13.6'),   (4,7,'N39.0'),   (4,8,'N15.1'),
    (4,9,'N30.01'),  (4,10,'N39.0'),  (4,11,'N41.0'),  (4,12,'R82.71'),
    /* appendicitis */
    (5,1,'K35.80'),  (5,2,'K35.32'),  (5,3,'K35.20'),  (5,4,'K35.33'),
    (5,5,'Z48.815'), (5,6,'R10.31'),  (5,7,'K35.80'),  (5,8,'I88.0'),
    (5,9,'N83.20'),  (5,10,'K35.80'), (5,11,'T81.4XXA'),(5,12,'K56.7'),
    /* chest pain */
    (6,1,'I21.3'),   (6,2,'I21.4'),   (6,3,'I20.0'),   (6,4,'I20.9'),
    (6,5,'I30.9'),   (6,6,'I26.99'),  (6,7,'J93.11'),  (6,8,'F41.9'),
    (6,9,'I51.81'),  (6,10,'I71.00'), (6,11,'K21.9'),  (6,12,'M94.0'),
    /* syncope */
    (7,1,'R55'),     (7,2,'I44.2'),   (7,3,'I95.2'),   (7,4,'I35.0'),
    (7,5,'R55'),     (7,6,'R55'),     (7,7,'I47.2'),   (7,8,'K92.2'),
    (7,9,'G90.01'),  (7,10,'I26.99'), (7,11,'R55'),    (7,12,'E86.0'),
    /* stroke */
    (8,1,'I63.9'),   (8,2,'I63.9'),   (8,3,'G45.9'),   (8,4,'I60.9'),
    (8,5,'I63.9'),   (8,6,'I63.40'),  (8,7,'I63.50'),  (8,8,'I63.81'),
    (8,9,'I63.239'), (8,10,'E16.2'),  (8,11,'I61.9'),  (8,12,'I67.6'),
    /* COPD */
    (9,1,'J44.0'),   (9,2,'J96.02'),  (9,3,'J44.1'),   (9,4,'J44.0'),
    (9,5,'J44.1'),   (9,6,'J44.0'),   (9,7,'I27.81'),  (9,8,'J93.11'),
    (9,9,'J44.1'),   (9,10,'J44.9'),  (9,11,'J44.1'),  (9,12,'J44.1'),
    /* infant */
    (10,1,'J21.0'),  (10,2,'N39.0'),  (10,3,'A08.4'),  (10,4,'P59.9'),
    /* child */
    (11,1,'J18.9'),  (11,2,'J45.901'),(11,3,'K35.80'), (11,4,'J05.0'),
    /* adolescent */
    (12,1,'K35.80'), (12,2,'E10.10'), (12,3,'B27.90'), (12,4,'R55'),
    /* psychiatric admission */
    (13,1,'F32.2'),  (13,2,'F23'),    (13,3,'F31.13'), (13,4,'F10.231'),
    (13,5,'F20.9'),  (13,6,'F41.0'),  (13,7,'F50.01'), (13,8,'F11.23'),
    (13,9,'T43.591A'),(13,10,'T43.225A'),(13,11,'F43.12'),(13,12,'F05')
) AS v(cond, sid, Icd)
  ON v.cond = s.cond AND v.sid = s.sid;
GO

/* Every story must have been coded. A NULL here means a row was added to the
   VALUES list above without a matching code, and the diagnosis for that story
   would silently go missing. */
IF EXISTS (SELECT 1 FROM #Story WHERE Icd IS NULL)
    THROW 50001, N'#Story has uncoded rows - every (cond, sid) needs an ICD code.', 1;
GO

/* Every story label must be unique. Label becomes Diagnosis.Description and it
   is also the chief complaint written into IntakeJson, so two stories sharing a
   label are indistinguishable downstream -- the coherence checks count distinct
   descriptions, and a duplicate makes the count come up short with nothing to
   say why. Adding the pediatric bands produced exactly this: appendicitis was
   labelled identically in the child and adolescent bands, and the adolescent
   faint carried the same label as the adult one. */
DECLARE @Stories INT = (SELECT COUNT(*)          FROM #Story);
DECLARE @Labels  INT = (SELECT COUNT(DISTINCT Label) FROM #Story);
IF @Stories <> @Labels
    THROW 50002, N'#Story has duplicate labels - each story needs its own Label.', 1;
GO

/* ----------------------------------------------------------------------------
   #DeptCond - which conditions a department actually admits.

   Department and story used to be drawn from two independent arithmetic
   sequences off the same counter, which is worse than random. Twelve
   departments and eleven conditions share a factor, so each department saw a
   FIXED slice of the catalogue: Psychiatry held 330 lower-lobe pneumonias,
   while Neurology, Orthopedics and Radiology saw 15 distinct diagnoses each
   against Internal Medicine's 78. The Ward General App chart prints the department name in
   the header beside the admit time, so every one of those was on screen.

   Department, bed and attending are already mutually consistent -- the bed sits
   in a unit belonging to the encounter's department, and the attending is drawn
   from that department -- so the story bends to the department rather than the
   other way round. That keeps the repair inside this one table.

   Eleven adult conditions do not cover twelve departments. Seven map cleanly:
   Cardiology, Pulmonology, Neurology, Surgery, Internal Medicine, Emergency
   Medicine and Psychiatry. The rest get the closest defensible admission rather
   than an invented one -- Oncology admits intercurrent infection, an
   Orthopedics stay opens as a syncopal fall, and Obstetrics-Gynecology takes
   urinary infection in pregnancy. Radiology admits nobody and is excluded from
   the encounter round-robin in section 7.

   Psychiatry was the worst of the borrowed mappings and is the reason cond 13
   exists. It drew urinary infection and hypertension, so an Adult Psych chart
   opened on "acute bacterial prostatitis" with a note that never mentioned a
   psychiatric problem at all. It now admits only psychiatric presentations.
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('tempdb..#DeptCond') IS NOT NULL DROP TABLE #DeptCond;
CREATE TABLE #DeptCond
(
    DepartmentId INT     NOT NULL,
    ord          TINYINT NOT NULL,
    cond         TINYINT NOT NULL,
    CONSTRAINT PK_DeptCond PRIMARY KEY (DepartmentId, ord)
);

INSERT INTO #DeptCond (DepartmentId, ord, cond)
SELECT d.DepartmentId, m.ord, m.cond
FROM (VALUES
    /*  0 Hypertension   1 Type 2 diabetes   2 Heart failure   3 Pneumonia
        4 Urinary infection   5 Appendicitis   6 Chest pain   7 Syncope
        8 Stroke   9 COPD   10 Infant   11 Child   12 Adolescent
       13 Psychiatric admission                                              */
    (N'Cardiology',            1, 2), (N'Cardiology',            2, 6),
    (N'Pulmonology',           1, 3), (N'Pulmonology',           2, 9),
    (N'Neurology',             1, 8), (N'Neurology',             2, 7),
    (N'Surgery',               1, 5),
    (N'Internal Medicine',     1, 0), (N'Internal Medicine',     2, 1),
    (N'Internal Medicine',     3, 4), (N'Internal Medicine',     4, 3),
    (N'Emergency Medicine',    1, 6), (N'Emergency Medicine',    2, 7),
    (N'Emergency Medicine',    3, 3), (N'Emergency Medicine',    4, 5),
    (N'Oncology',              1, 3), (N'Oncology',              2, 4),
    (N'Psychiatry',            1, 13),
    (N'Orthopedics',           1, 7),
    (N'Obstetrics-Gynecology', 1, 4),
    /* Pediatrics is decided by age band below and never reads this row; it
       exists so the modulo has a non-zero divisor. */
    (N'Pediatrics',            1, 11)
) m(DeptName, ord, cond)
JOIN ops.Department d ON d.Name = m.DeptName;
GO

/* Every department that actually holds an encounter needs at least one
   condition, or the modulo divides by zero and the stay loses its story. */
IF EXISTS (SELECT 1 FROM clinical.Encounter AS e
           WHERE NOT EXISTS (SELECT 1 FROM #DeptCond AS dc
                             WHERE dc.DepartmentId = e.DepartmentId))
    THROW 50003, N'An admitting department has no #DeptCond mapping.', 1;
GO

/* ----------------------------------------------------------------------------
   #EncStory - ONE story per encounter, and the spine of everything below it.

   Sections 9 through 13 all read this table: the notes, the diagnoses, the
   medication orders, the lab panels and the 108M observations. That is the
   whole design. An admission is one clinical picture, so every table that
   describes it derives from a single row here and they cannot disagree.

   An earlier version derived the story per NOTE rather than per encounter.
   The two notes on one admission then described different presentations of
   the same condition, and — worse — there was no single answer to "what was
   this admission about" for the vitals, drugs and labs to agree with.

   For an adult, cond comes from the encounter's DEPARTMENT (#DeptCond) and sid
   from a second, independent hash of the EncounterId. Both draws are hashed
   rather than arithmetic, for the reason set out at the CROSS APPLY below.
   Check D1 is what proves the resulting coverage -- 144 distinct story
   diagnoses -- not the arithmetic.

   AGE OVERRIDES the department. A patient under 18 is routed to one of the
   three pediatric bands, and sid then wraps on 4 rather than 12. Without this
   the arithmetic handed a one-year-old an ST-elevation myocardial infarction,
   and every vital sign, drug, lab and symptom on the chart followed that adult
   story faithfully. The two rules never contend: children are only ever
   admitted to Pediatrics, and Pediatrics only ever holds children.
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('tempdb..#EncStory') IS NOT NULL DROP TABLE #EncStory;
CREATE TABLE #EncStory
(
    EncounterId INT     NOT NULL,
    cond        TINYINT NOT NULL,
    sid         TINYINT NOT NULL,
    CONSTRAINT PK_EncStory PRIMARY KEY (EncounterId)
);

INSERT INTO #EncStory (EncounterId, cond, sid)
SELECT
    e.EncounterId,
    cd.cond,
    /* If the drawn story demands the other sex, step to the next story within
       the same condition. Neither replacement (cond 4 sid 12, cond 5 sid 10)
       is itself sex-specific, so one step is always enough. The step wraps on
       the band's own story count, not a hard 12, or a pediatric encounter
       would step to a sid that does not exist and lose its story entirely. */
    CASE WHEN sx.Mismatch = 1
         THEN CONVERT(TINYINT, (k.sid0 % n.nsid) + 1)
         ELSE k.sid0
    END
FROM clinical.Encounter AS e
JOIN #PatAge            AS p ON p.PatientId = e.PatientId
/* #PatAge is measured against SYSUTCDATETIME(), deliberately, because that is
   the exact clock the encounter blocks used to build their admission pools --
   and it is the clock vPatientChart displays. Age at AdmitTime would be the
   more natural reading, but a discharged stay can sit up to a year in the past,
   so a patient who is 18 today may have been 17 on admission and would then
   draw a pediatric story while sitting in an adult department. Sharing one
   clock is what makes "every child is in Pediatrics" true rather than nearly
   true. */
/* Two independent draws per encounter, hashed rather than arithmetic.

   Modular arithmetic on EncounterId cannot do this job, because the department
   is itself a function of EncounterId: the two draws end up sharing factors
   with each other and with the department, and the result collapses. Measured
   on the previous generation -- Cardiology's two conditions split 3,322 to 25,
   Internal Medicine's four split 3,311 to 17, and each condition reached only
   10 or 11 of its 12 stories, which silently deletes stories from the corpus.
   CHECKSUM is no better: its salted variants are correlated, and swapping it in
   dropped story coverage to 3 of 12. SHA2_256 with a distinct salt per draw is
   independent of the department and of the other draw -- measured at a full 12
   of 12 stories for every condition, with the conditions inside a department
   splitting evenly. */
CROSS APPLY (SELECT hb1 = HASHBYTES('SHA2_256', CONVERT(VARCHAR(20), e.EncounterId) + 'cond'),
                    hb2 = HASHBYTES('SHA2_256', CONVERT(VARCHAR(20), e.EncounterId) + 'sid')) AS hb
CROSS APPLY (SELECT h1 = CONVERT(INT, SUBSTRING(hb.hb1, 1, 4)) & 0x7FFFFFFF,
                    h2 = CONVERT(INT, SUBSTRING(hb.hb2, 1, 4)) & 0x7FFFFFFF) AS hx
CROSS APPLY (SELECT ncond = (SELECT COUNT(*) FROM #DeptCond AS dc
                             WHERE dc.DepartmentId = e.DepartmentId)) AS m
CROSS APPLY (SELECT dcond = (SELECT dc.cond FROM #DeptCond AS dc
                             WHERE dc.DepartmentId = e.DepartmentId
                               AND dc.ord = (hx.h1 % m.ncond) + 1)) AS dm
CROSS APPLY (SELECT cond = CONVERT(TINYINT,
        CASE WHEN p.Age <  2 THEN 10
             WHEN p.Age < 13 THEN 11
             WHEN p.Age < 18 THEN 12
             ELSE dm.dcond
        END)) AS cd
CROSS APPLY (SELECT nsid = CASE WHEN cd.cond BETWEEN 10 AND 12 THEN 4 ELSE 12 END) AS n
CROSS APPLY (SELECT
        sid0 = CONVERT(TINYINT, (hx.h2 % n.nsid) + 1)) AS k
CROSS APPLY (SELECT Mismatch =
        CASE WHEN EXISTS (SELECT 1 FROM #Story AS st
                          WHERE st.cond   = cd.cond
                            AND st.sid    = k.sid0
                            AND st.SexReq IS NOT NULL
                            AND st.SexReq <> p.Sex)
             THEN 1 ELSE 0 END
    ) AS sx;
GO

/* ----------------------------------------------------------------------------
   The intake payload was written back in section 7, when the encounter row was
   inserted and no story existed yet, so its chief complaint and triage vitals
   were drawn from BedId arithmetic. Nothing in the Ward General App app renders IntakeJson
   today, but Performance builds a JSON index over it and a corpus is only as good as
   its weakest table, so it joins the same story as everything else.

   JSON functions behave identically over the native json type, so JSON_MODIFY
   reads and writes the column with no conversion: "JSON functions work the same
   whether the JSON document is stored in varchar, nvarchar, or the native json
   data type" (Microsoft Learn - JSON_MODIFY, Remarks; accessed 2026-08-15).

   painScore exists only on the active-encounter payload. Lax mode is the
   default, so the discharged payload gains the key rather than erroring, and
   both shapes end up the same.
   ---------------------------------------------------------------------------- */
PRINT N'--- clinical.Encounter.IntakeJson (aligned to the story) ---';

UPDATE e
SET IntakeJson = JSON_MODIFY(
                 JSON_MODIFY(
                 JSON_MODIFY(
                 JSON_MODIFY(
                 JSON_MODIFY(
                 JSON_MODIFY(
                 JSON_MODIFY(
                 JSON_MODIFY(e.IntakeJson,
                     '$.chiefComplaint',                       cc.Complaint),
                     '$.painScore',                            v.pain),
                     '$.triageVitals.heartRate',               v.hr),
                     '$.triageVitals.bloodPressure.systolic',  v.bpSys),
                     '$.triageVitals.bloodPressure.diastolic', v.bpDia),
                     '$.triageVitals.spO2',                    v.spo2),
                     '$.triageVitals.temperatureC',            v.tempC),
                     '$.triageVitals.respRate',                v.rr)
FROM clinical.Encounter AS e
JOIN #EncStory AS es ON es.EncounterId = e.EncounterId
JOIN #Story    AS s  ON s.cond = es.cond AND s.sid = es.sid
CROSS APPLY (SELECT
        r_hr = ABS(CHECKSUM(NEWID())), r_bs = ABS(CHECKSUM(NEWID())),
        r_bd = ABS(CHECKSUM(NEWID())), r_rr = ABS(CHECKSUM(NEWID())),
        r_sp = ABS(CHECKSUM(NEWID())), r_pn = ABS(CHECKSUM(NEWID())),
        r_t2 = ABS(CHECKSUM(NEWID()))
    ) AS r
CROSS APPLY (SELECT
        hr    = s.HrLo   + (r.r_hr % s.HrSp),
        bpSys = s.SysLo  + (r.r_bs % s.SysSp),
        bpDia = s.DiaLo  + (r.r_bd % s.DiaSp),
        rr    = s.RrLo   + (r.r_rr % s.RrSp),
        spo2  = s.SpLo   + (r.r_sp % s.SpSp),
        pain  = s.PainLo + (r.r_pn % s.PainSp),
        tempC = s.TempI  + ((r.r_t2 % 10) / 10.0)
    ) AS v
/* Subj is written as a sentence fragment for the note body, so it carries a
   trailing comma-space. LEN ignores trailing spaces, which makes trimming the
   comma a single LEFT. */
CROSS APPLY (SELECT Trimmed = LEFT(s.Subj, LEN(s.Subj) - 1)) AS j
CROSS APPLY (SELECT Complaint =
        UPPER(LEFT(j.Trimmed, 1)) + SUBSTRING(j.Trimmed, 2, 300)) AS cc
WHERE e.IntakeJson IS NOT NULL;
GO

/* ----------------------------------------------------------------------------
   GENERATE_SERIES(1,2) filtered by ((EncounterId + gs) % 4) <> 0 yields 1.5
   notes per encounter. For a DISCHARGED encounter the LAST surviving slot
   becomes the discharge summary, stamped at DischargeTime so it is the latest
   note by construction. It CONSUMES a slot rather than adding one, so the
   corpus size is unchanged and no second relabel pass is required.
   ---------------------------------------------------------------------------- */
INSERT INTO clinical.ClinicalNote
    (EncounterId, AuthorProviderId, NoteType, NoteText, CreatedAt)
SELECT
    e.EncounterId,
    e.AttendingProviderId,
    CASE WHEN x.isDischarge = 1 THEN N'Discharge'
         ELSE CHOOSE((x.r_type % 2) + 1, N'Progress', N'Consult') END,
    CASE WHEN x.isDischarge = 1 THEN
        /* ---- Discharge summary: four sections, same as the others ---- */
        CONCAT(
            N'Discharge summary: ', s.Course, t.Traj,
            N'Pain scored ', v.pain, N' out of 10 at discharge. ',
            CHAR(13), CHAR(10),
            N'Objective: T ', v.tempInt, N'.', v.tempTenth,
            N'C, HR ', v.hr, N', BP ', v.bpSys, N'/', v.bpDia,
            N', RR ', v.rr, N', SpO2 ', v.spo2, N'% on room air. ',
            s.Exam,
            CHAR(13), CHAR(10),
            N'Discharge diagnosis: ', s.Assess,
            CASE WHEN es.cond BETWEEN 10 AND 12 THEN
                CHOOSE((x.r_comorb % 4) + 1,
                    N'Comorbid asthma managed with as-needed inhalers. ',
                    N'Background of eczema and allergic rhinitis. ',
                    N'Born at term with an uncomplicated neonatal course. ',
                    N'No significant chronic comorbidities identified. ')
            ELSE
                CHOOSE((x.r_comorb % 4) + 1,
                    N'Comorbid hypertension, hyperlipidemia and type 2 diabetes, well controlled. ',
                    N'Comorbid chronic obstructive pulmonary disease and stage 3 chronic kidney disease. ',
                    N'History of atrial fibrillation maintained on anticoagulation. ',
                    N'No significant chronic comorbidities identified. ')
            END,
            CHAR(13), CHAR(10),
            N'Discharge instructions: ', s.PlanTxt,
            N'Medicines were reconciled and the changes were explained to the patient and family. ',
            s.FollowUp)
    ELSE
        /* ---- Progress / Consult: four sections ---- */
        CONCAT(
            N'Subjective: Patient reports ', s.Subj,
            CHOOSE((x.r_hpi % 4) + 1,
                N'with a gradual progression over several days. ',
                N'with an abrupt onset that peaked within hours. ',
                N'following an intermittent course that is worse in the evenings. ',
                N'with no clear precipitating factors and no prior similar episodes. '),
            N'Pain scored ', v.pain, N' out of 10. ',
            CASE WHEN es.cond BETWEEN 10 AND 12 THEN
                CHOOSE((x.r_pmh % 4) + 1,
                    N'Immunizations are up to date and no regular medicines are taken at home. ',
                    N'Parents report occasional missed doses of maintenance inhaler therapy. ',
                    N'Recently completed a course of antibiotics prescribed by the family doctor. ',
                    N'Receives only as-needed antipyretics at home. ')
            ELSE
                CHOOSE((x.r_pmh % 4) + 1,
                    N'Adherent to home medications with no new agents or supplements. ',
                    N'Reports occasional missed doses of maintenance therapy. ',
                    N'Recently started a new medication prescribed by an outside provider. ',
                    N'Takes only as-needed analgesics at home. ')
            END,
            CHOOSE((x.r_fh % 4) + 1,
                N'Family history significant for premature coronary artery disease. ',
                N'Family history notable for type 2 diabetes and stroke. ',
                N'No significant family history elicited. ',
                N'Family history of malignancy in a first-degree relative. '),
            CHAR(13), CHAR(10),
            N'Objective: T ', v.tempInt, N'.', v.tempTenth,
            N'C, HR ', v.hr, N', BP ', v.bpSys, N'/', v.bpDia,
            N', RR ', v.rr, N', SpO2 ', v.spo2, N'% on room air. ',
            CHOOSE((x.r_gen % 4) + 1,
                N'Patient appears comfortable, in no acute distress. ',
                N'Patient appears fatigued but interactive and cooperative. ',
                N'Patient is ill-appearing but hemodynamically stable. ',
                N'Patient is alert and in mild distress. '),
            s.Exam,
            CHAR(13), CHAR(10),
            N'Assessment: ', s.Assess,
            CASE WHEN es.cond BETWEEN 10 AND 12 THEN
                CHOOSE((x.r_comorb % 4) + 1,
                    N'Comorbid asthma managed with as-needed inhalers. ',
                    N'Background of eczema and allergic rhinitis. ',
                    N'Born at term with an uncomplicated neonatal course. ',
                    N'No significant chronic comorbidities identified. ')
            ELSE
                CHOOSE((x.r_comorb % 4) + 1,
                    N'Comorbid hypertension, hyperlipidemia and type 2 diabetes, well controlled. ',
                    N'Comorbid chronic obstructive pulmonary disease and stage 3 chronic kidney disease. ',
                    N'History of atrial fibrillation maintained on anticoagulation. ',
                    N'No significant chronic comorbidities identified. ')
            END,
            CHAR(13), CHAR(10),
            N'Plan: ', s.PlanTxt, t.Traj,
            CHOOSE((x.r_plan2 % 3) + 1,
                N'Repeat basic metabolic panel and complete blood count in the morning. ',
                N'Continue telemetry monitoring overnight. ',
                N'Case management engaged for discharge planning. '),
            s.FollowUp)
    END,
    CASE WHEN x.isDischarge = 1 THEN e.DischargeTime
         ELSE DATEADD(SECOND,
                ABS(CHECKSUM(NEWID())) % (ABS(DATEDIFF(SECOND, e.AdmitTime,
                    COALESCE(e.DischargeTime, SYSUTCDATETIME()))) + 1),
                e.AdmitTime)
    END
FROM clinical.Encounter AS e
CROSS JOIN GENERATE_SERIES(1, 2) AS gs
/* The story is looked up, not recomputed. #EncStory holds exactly one row per
   encounter, so both of an admission's notes draw the same clinical picture —
   and the same one the diagnoses, drugs, labs and vitals below are built from.

   It is also a JOIN KEY, which is why it must be DETERMINISTIC and why it is
   materialized once rather than derived here. Drawing a story with NEWID() —
   even hoisted into a CROSS APPLY — is re-evaluated per join candidate, so one
   encounter-slot matches SEVERAL #Story rows and the corpus inflates. Measured
   during development: 60,168 notes on one run and 60,410 on the next from
   identical input, with 40,003 discharge notes against only 39,660 discharged
   encounters. A nondeterministic value is safe when it only picks a STRING; it
   is never safe as a join key, because re-evaluation changes CARDINALITY and
   not just value. */
JOIN #EncStory AS es ON es.EncounterId = e.EncounterId
JOIN #Story    AS s  ON s.cond = es.cond AND s.sid = es.sid
/* Hoisting the random draws is a CORRECTNESS requirement, not tidiness.
   CHOOSE(idx, ...) compiles to a simple CASE, which re-evaluates its input
   once per WHEN comparison, so an inline ABS(CHECKSUM(NEWID())) draws a fresh
   number per branch and returns NULL when no draw matches its own branch
   (25% of rows for a two-arm CHOOSE, measured). Do not inline these. */
CROSS APPLY (SELECT
        isDischarge = CASE WHEN e.DischargeTime IS NOT NULL
                            AND gs.value = CASE WHEN (e.EncounterId + 2) % 4 = 0 THEN 1 ELSE 2 END
                           THEN 1 ELSE 0 END,
        r_traj      = ABS(CHECKSUM(NEWID())),
        r_type      = ABS(CHECKSUM(NEWID())),
        r_hpi       = ABS(CHECKSUM(NEWID())),
        r_pmh       = ABS(CHECKSUM(NEWID())),
        r_fh        = ABS(CHECKSUM(NEWID())),
        r_gen       = ABS(CHECKSUM(NEWID())),
        r_comorb    = ABS(CHECKSUM(NEWID())),
        r_plan2     = ABS(CHECKSUM(NEWID())),
        r_t2        = ABS(CHECKSUM(NEWID())),
        r_hr        = ABS(CHECKSUM(NEWID())),
        r_bs        = ABS(CHECKSUM(NEWID())),
        r_bd        = ABS(CHECKSUM(NEWID())),
        r_rr        = ABS(CHECKSUM(NEWID())),
        r_sp        = ABS(CHECKSUM(NEWID())),
        r_pn        = ABS(CHECKSUM(NEWID()))
    ) AS x
/* The trajectory axis. Drawn once per note and applied to BOTH the plan and
   the course, so it can never contradict the story it is attached to.
   144 stories x 5 trajectories = 720 meaning clusters. */
CROSS APPLY (SELECT Traj = CHOOSE((x.r_traj % 5) + 1,
        N'The patient is improving and is expected to step down shortly. ',
        N'Progress has been slower than expected and the plan was escalated. ',
        N'The patient remains clinically stable with no change in the plan. ',
        N'Care was transferred to the specialty team for ongoing management. ',
        N'The patient is for observation with a low threshold to escalate. ')) AS t
CROSS APPLY (SELECT
        tempInt   = s.TempI,
        tempTenth = x.r_t2 % 10,
        hr        = s.HrLo   + (x.r_hr % s.HrSp),
        bpSys     = s.SysLo  + (x.r_bs % s.SysSp),
        bpDia     = s.DiaLo  + (x.r_bd % s.DiaSp),
        rr        = s.RrLo   + (x.r_rr % s.RrSp),
        spo2      = s.SpLo   + (x.r_sp % s.SpSp),
        pain      = s.PainLo + (x.r_pn % s.PainSp)
    ) AS v
WHERE ((e.EncounterId + gs.value) % 4) <> 0;
GO

/* ============================================================================
   10. clinical.Diagnosis  (~80,000 — 2 per encounter)

       Deliberately placed AFTER the notes rather than before them. The coded
       diagnosis is read from the same #EncStory row the note was written from,
       so the code and the narrative are two views of ONE clinical picture
       instead of two independent draws that happen to share an encounter.

       Row 1 is the story's own diagnosis, carrying the story's own ICD code.
       Row 2 is a chronic comorbidity — something the patient brings INTO the
       admission, not a second acute problem. The earlier version derived row 2
       as cond + 1, which paired appendicitis with chest pain on every single
       appendicitis admission in the database.
   ============================================================================ */
PRINT N'--- clinical.Diagnosis ---';

INSERT INTO clinical.Diagnosis (EncounterId, IcdCode, Description, DiagnosedById)
SELECT e.EncounterId, s.Icd, s.Label, e.AttendingProviderId
FROM clinical.Encounter AS e
JOIN #EncStory AS es ON es.EncounterId = e.EncounterId
JOIN #Story    AS s  ON s.cond = es.cond AND s.sid = es.sid;

INSERT INTO clinical.Diagnosis (EncounterId, IcdCode, Description, DiagnosedById)
SELECT e.EncounterId, c.Icd, c.Descr, e.AttendingProviderId
FROM clinical.Encounter AS e
JOIN #EncStory AS es ON es.EncounterId = e.EncounterId
JOIN #Story    AS s  ON s.cond = es.cond AND s.sid = es.sid
CROSS APPLY (SELECT k = ((e.EncounterId * 11) % 5) + 1) AS p
/* The chronic condition a patient brings in with them has to be one they could
   plausibly have. Stage 3 chronic kidney disease on a two-year-old is the same
   class of error as the adult diagnoses the pediatric bands were added to fix,
   so the pediatric encounters draw from a childhood list instead. */
CROSS APPLY (SELECT IsPed = CASE WHEN es.cond BETWEEN 10 AND 12 THEN 1 ELSE 0 END) AS a
CROSS APPLY (SELECT cand = CASE WHEN a.IsPed = 1
        THEN CHOOSE(p.k, 'J45.909', 'L20.9', 'J30.9', 'F90.9', 'D57.1')
        ELSE CHOOSE(p.k, 'I10', 'E11.9', 'E78.5', 'N18.3', 'J44.9') END) AS c0
/* Step one place if the drawn comorbidity IS the admitting diagnosis. The five
   codes are distinct, so at most one can collide and one step always clears it. */
CROSS APPLY (SELECT k2 = CASE WHEN c0.cand = s.Icd
        THEN (p.k % 5) + 1 ELSE p.k END) AS p2
CROSS APPLY (SELECT
        Icd   = CASE WHEN a.IsPed = 1
                     THEN CHOOSE(p2.k2, 'J45.909', 'L20.9', 'J30.9', 'F90.9', 'D57.1')
                     ELSE CHOOSE(p2.k2, 'I10', 'E11.9', 'E78.5', 'N18.3', 'J44.9') END,
        Descr = CASE WHEN a.IsPed = 1
                THEN CHOOSE(p2.k2,
                    N'Unspecified asthma, uncomplicated',
                    N'Atopic dermatitis, unspecified',
                    N'Allergic rhinitis, unspecified',
                    N'Attention-deficit hyperactivity disorder, unspecified type',
                    N'Sickle-cell disease without crisis')
                ELSE CHOOSE(p2.k2,
                    N'Essential hypertension',
                    N'Type 2 diabetes mellitus without complications',
                    N'Hyperlipidemia, unspecified',
                    N'Chronic kidney disease, stage 3, unspecified',
                    N'Chronic obstructive pulmonary disease, unspecified') END) AS c;
GO

/* ============================================================================
   11. clinical.MedicationOrder  (~100,000 — 2.5 per encounter average)

       The drug list is keyed on the encounter's CONDITION. Previously it was
       keyed on EncounterId arithmetic alone, so an appendicitis admission
       could be ordered nothing but lisinopril and a stroke patient could be
       started on insulin. Three plausible orders per condition, selected by
       the same GENERATE_SERIES slot that already sets the order time — so the
       row count and the ~2.5-per-encounter average are unchanged.
   ============================================================================ */
PRINT N'--- clinical.MedicationOrder ---';
INSERT INTO clinical.MedicationOrder
    (EncounterId, PatientId, MedicationName, Dose, Route, OrderedById, OrderedAt)
SELECT
    e.EncounterId,
    e.PatientId,
    m.MedicationName,
    m.Dose,
    m.Route,
    e.AttendingProviderId,
    DATEADD(SECOND, gs.value * (DATEDIFF(SECOND, e.AdmitTime, COALESCE(e.DischargeTime, SYSUTCDATETIME())) / 4), e.AdmitTime)
FROM clinical.Encounter e
CROSS JOIN GENERATE_SERIES(1, 3) gs
JOIN #EncStory es ON es.EncounterId = e.EncounterId
CROSS APPLY (
    /* Dose + route travel WITH the drug on a single lookup row, so there are
       no combinations like "Insulin glargine 81 mg PO". Every (cond, slot)
       pair exists, so this always matches exactly one row and the cardinality
       is the same as the old EncounterId-keyed lookup. */
    SELECT d.MedicationName, d.Dose, d.Route
    FROM (VALUES
        (0, 1, N'Lisinopril',              N'10 mg',      N'PO'),
        (0, 2, N'Amlodipine',              N'5 mg',       N'PO'),
        (0, 3, N'Hydrochlorothiazide',     N'25 mg',      N'PO'),
        (1, 1, N'Insulin glargine',        N'20 units',   N'SC'),
        (1, 2, N'Insulin aspart',          N'6 units',    N'SC'),
        (1, 3, N'Metformin',               N'500 mg',     N'PO'),
        (2, 1, N'Furosemide',              N'40 mg',      N'IV'),
        (2, 2, N'Carvedilol',              N'6.25 mg',    N'PO'),
        (2, 3, N'Spironolactone',          N'25 mg',      N'PO'),
        (3, 1, N'Ceftriaxone',             N'1 g',        N'IV'),
        (3, 2, N'Azithromycin',            N'500 mg',     N'IV'),
        (3, 3, N'Acetaminophen',           N'650 mg',     N'PO'),
        (4, 1, N'Ceftriaxone',             N'1 g',        N'IV'),
        (4, 2, N'Nitrofurantoin',          N'100 mg',     N'PO'),
        (4, 3, N'Acetaminophen',           N'650 mg',     N'PO'),
        (5, 1, N'Piperacillin-tazobactam', N'3.375 g',    N'IV'),
        (5, 2, N'Ondansetron',             N'4 mg',       N'IV'),
        (5, 3, N'Morphine',                N'4 mg',       N'IV'),
        (6, 1, N'Aspirin',                 N'325 mg',     N'PO'),
        (6, 2, N'Atorvastatin',            N'80 mg',      N'PO'),
        (6, 3, N'Heparin',                 N'5000 units', N'SC'),
        (7, 1, N'Sodium chloride 0.9%',    N'1000 mL',    N'IV'),
        (7, 2, N'Ondansetron',             N'4 mg',       N'IV'),
        (7, 3, N'Acetaminophen',           N'650 mg',     N'PO'),
        (8, 1, N'Aspirin',                 N'300 mg',     N'PO'),
        (8, 2, N'Atorvastatin',            N'40 mg',      N'PO'),
        (8, 3, N'Enoxaparin',              N'40 mg',      N'SC'),
        (9, 1, N'Prednisone',              N'40 mg',      N'PO'),
        (9, 2, N'Ipratropium-albuterol',   N'3 mL',       N'NEB'),
        (9, 3, N'Azithromycin',            N'500 mg',     N'PO'),
        /* Pediatric bands. Doses are weight-appropriate rather than the adult
           figure above, and no band is given insulin: only cond 12 sid 2 is a
           diabetic story, and the drug list is keyed on cond, so an insulin
           row here would land on mononucleosis and appendicitis as well. */
        (10, 1, N'Ceftriaxone',            N'350 mg',     N'IV'),
        (10, 2, N'Paracetamol suspension', N'80 mg',      N'PO'),
        (10, 3, N'Oral rehydration solution', N'50 mL',   N'PO'),
        (11, 1, N'Amoxicillin suspension', N'500 mg',     N'PO'),
        (11, 2, N'Salbutamol',             N'2.5 mg',     N'NEB'),
        (11, 3, N'Dexamethasone',          N'6 mg',       N'PO'),
        (12, 1, N'Ceftriaxone',            N'1 g',        N'IV'),
        (12, 2, N'Ondansetron',            N'4 mg',       N'IV'),
        (12, 3, N'Ibuprofen',              N'400 mg',     N'PO'),
        /* Psychiatric admission. An antidepressant, an antipsychotic and a
           short-acting benzodiazepine cover the twelve stories between them
           without contradicting any one of them. */
        (13, 1, N'Sertraline',             N'50 mg',      N'PO'),
        (13, 2, N'Olanzapine',             N'5 mg',       N'PO'),
        (13, 3, N'Lorazepam',              N'1 mg',       N'PO')
    ) d(cond, slot, MedicationName, Dose, Route)
    WHERE d.cond = es.cond AND d.slot = gs.value
) m
WHERE ((e.EncounterId * 5 + gs.value) % 6) < 5;   -- ~2.5 per encounter
GO

/* ============================================================================
   12. clinical.LabResult  (~200,000 — 5 per encounter average)
   ============================================================================ */
PRINT N'--- clinical.LabResult ---';
INSERT INTO clinical.LabResult
    (EncounterId, PatientId, OrderedById, TestName, CollectedAt, ResultedAt, ResultJson, Status)
SELECT
    e.EncounterId,
    e.PatientId,
    e.AttendingProviderId,
    lab.TestName,
    DATEADD(SECOND, gs.value * (DATEDIFF(SECOND, e.AdmitTime, COALESCE(e.DischargeTime, SYSUTCDATETIME())) / 6), e.AdmitTime),
    LEAST(DATEADD(MINUTE, 45, DATEADD(SECOND, gs.value * (DATEDIFF(SECOND, e.AdmitTime, COALESCE(e.DischargeTime, SYSUTCDATETIME())) / 6), e.AdmitTime)), COALESCE(e.DischargeTime, SYSUTCDATETIME())),
    JSON_OBJECT(
        'panel'       : lab.TestName,
        'specimen'    : lab.Specimen,
        'instrument'  : lab.Instrument,
        'performedBy' : CONCAT(N'tech-', (gs.value * 7) % 999),
        'verifiedBy'  : CONCAT(N'MT-',  (gs.value * 11) % 99),
        /* Analytes match the ordered test: a Troponin carries a troponin, a    */
        /* TSH a TSH, a Lipid Panel a lipid profile — not a generic CBC.         */
        /* JSON_QUERY is required: CASE resolves to nvarchar across its branches. */
        'analytes'    : JSON_QUERY(
            CASE k.ti
                WHEN 1 THEN JSON_ARRAY(   -- CBC
                    JSON_OBJECT('name': N'WBC', 'value': 7.4 + (((e.EncounterId * 3  + gs.value) % 30) / 10.0), 'unit': N'K/uL', 'refLow': 4.5,  'refHigh': 11.0),
                    JSON_OBJECT('name': N'RBC', 'value': 4.6 + (((e.EncounterId * 5  + gs.value) % 15) / 10.0), 'unit': N'M/uL', 'refLow': 4.5,  'refHigh': 5.9),
                    JSON_OBJECT('name': N'HGB', 'value': 13  + (((e.EncounterId * 7  + gs.value) % 40) / 10.0), 'unit': N'g/dL', 'refLow': 12.0, 'refHigh': 17.0),
                    JSON_OBJECT('name': N'HCT', 'value': 40  + (((e.EncounterId * 11 + gs.value) % 80) / 10.0), 'unit': N'%',    'refLow': 36.0, 'refHigh': 51.0),
                    JSON_OBJECT('name': N'PLT', 'value': 200 + ((e.EncounterId * 13 + gs.value) % 150),         'unit': N'K/uL', 'refLow': 150,  'refHigh': 400))
                WHEN 2 THEN JSON_ARRAY(   -- BMP
                    JSON_OBJECT('name': N'Na',  'value': 136 + ((e.EncounterId * 3  + gs.value) % 8),          'unit': N'mmol/L', 'refLow': 135, 'refHigh': 145),
                    JSON_OBJECT('name': N'K',   'value': 3.6 + (((e.EncounterId * 5  + gs.value) % 14) / 10.0), 'unit': N'mmol/L', 'refLow': 3.5, 'refHigh': 5.1),
                    JSON_OBJECT('name': N'Cl',  'value': 99  + ((e.EncounterId * 7  + gs.value) % 8),          'unit': N'mmol/L', 'refLow': 98,  'refHigh': 107),
                    JSON_OBJECT('name': N'CO2', 'value': 23  + ((e.EncounterId * 11 + gs.value) % 6),          'unit': N'mmol/L', 'refLow': 22,  'refHigh': 29),
                    JSON_OBJECT('name': N'BUN', 'value': 10  + ((e.EncounterId * 13 + gs.value) % 12),         'unit': N'mg/dL',  'refLow': 7,   'refHigh': 20),
                    JSON_OBJECT('name': N'CR',  'value': 0.9 + (((e.EncounterId * 17 + gs.value) % 10) / 10.0), 'unit': N'mg/dL',  'refLow': 0.6, 'refHigh': 1.3),
                    JSON_OBJECT('name': N'GLU', 'value': 85  + ((e.EncounterId * 19 + gs.value) % 30),         'unit': N'mg/dL',  'refLow': 70,  'refHigh': 100),
                    JSON_OBJECT('name': N'CA',  'value': 8.8 + (((e.EncounterId * 23 + gs.value) % 14) / 10.0), 'unit': N'mg/dL',  'refLow': 8.5, 'refHigh': 10.2))
                WHEN 3 THEN JSON_ARRAY(   -- CMP (BMP + hepatic)
                    JSON_OBJECT('name': N'Na',  'value': 136 + ((e.EncounterId * 3  + gs.value) % 8),          'unit': N'mmol/L', 'refLow': 135, 'refHigh': 145),
                    JSON_OBJECT('name': N'K',   'value': 3.6 + (((e.EncounterId * 5  + gs.value) % 14) / 10.0), 'unit': N'mmol/L', 'refLow': 3.5, 'refHigh': 5.1),
                    JSON_OBJECT('name': N'BUN', 'value': 10  + ((e.EncounterId * 13 + gs.value) % 12),         'unit': N'mg/dL',  'refLow': 7,   'refHigh': 20),
                    JSON_OBJECT('name': N'CR',  'value': 0.9 + (((e.EncounterId * 17 + gs.value) % 10) / 10.0), 'unit': N'mg/dL',  'refLow': 0.6, 'refHigh': 1.3),
                    JSON_OBJECT('name': N'GLU', 'value': 85  + ((e.EncounterId * 19 + gs.value) % 30),         'unit': N'mg/dL',  'refLow': 70,  'refHigh': 100),
                    JSON_OBJECT('name': N'ALT', 'value': 12  + ((e.EncounterId * 3  + gs.value) % 40),         'unit': N'U/L',    'refLow': 7,   'refHigh': 56),
                    JSON_OBJECT('name': N'AST', 'value': 14  + ((e.EncounterId * 5  + gs.value) % 25),         'unit': N'U/L',    'refLow': 10,  'refHigh': 40),
                    JSON_OBJECT('name': N'ALP', 'value': 50  + ((e.EncounterId * 7  + gs.value) % 90),         'unit': N'U/L',    'refLow': 44,  'refHigh': 147),
                    JSON_OBJECT('name': N'TBIL','value': 0.3 + (((e.EncounterId * 11 + gs.value) % 9)  / 10.0), 'unit': N'mg/dL',  'refLow': 0.1, 'refHigh': 1.2),
                    JSON_OBJECT('name': N'ALB', 'value': 3.8 + (((e.EncounterId * 13 + gs.value) % 12) / 10.0), 'unit': N'g/dL',   'refLow': 3.5, 'refHigh': 5.0))
                WHEN 4 THEN JSON_ARRAY(   -- Troponin I: elevated only where the story is an infarct
                    JSON_OBJECT('name': N'Troponin I',
                        'value': CASE WHEN es.cond = 6 AND es.sid IN (1, 2, 9)
                                      THEN 2.5 + (((e.EncounterId * 7 + gs.value) % 180) / 10.0)
                                      ELSE ((e.EncounterId * 7 + gs.value) % 6) / 100.0 END,
                        'unit': N'ng/mL', 'refLow': 0.00, 'refHigh': 0.04))
                WHEN 5 THEN JSON_ARRAY(   -- Lipid Panel
                    JSON_OBJECT('name': N'Total Cholesterol', 'value': 150 + ((e.EncounterId * 3  + gs.value) % 90),  'unit': N'mg/dL', 'refLow': 0,  'refHigh': 200),
                    JSON_OBJECT('name': N'LDL',               'value': 80  + ((e.EncounterId * 5  + gs.value) % 80),  'unit': N'mg/dL', 'refLow': 0,  'refHigh': 100),
                    JSON_OBJECT('name': N'HDL',               'value': 40  + ((e.EncounterId * 7  + gs.value) % 30),  'unit': N'mg/dL', 'refLow': 40, 'refHigh': 90),
                    JSON_OBJECT('name': N'Triglycerides',     'value': 90  + ((e.EncounterId * 11 + gs.value) % 120), 'unit': N'mg/dL', 'refLow': 0,  'refHigh': 150))
                WHEN 6 THEN JSON_ARRAY(   -- TSH
                    JSON_OBJECT('name': N'TSH', 'value': 0.5 + (((e.EncounterId * 7 + gs.value) % 45) / 10.0), 'unit': N'mIU/L', 'refLow': 0.4, 'refHigh': 4.0))
            END)
    ),
    N'Resulted'
FROM clinical.Encounter e
CROSS JOIN GENERATE_SERIES(1, 5) gs
JOIN #EncStory es ON es.EncounterId = e.EncounterId
/* Which panels get drawn is a clinical decision, so it is keyed on the
   condition rather than on EncounterId arithmetic. A chest-pain admission gets
   serial troponins; a diabetic gets metabolic panels; nobody gets a random TSH.
   Five slots per condition, matching GENERATE_SERIES(1, 5) exactly, so the
   five-labs-per-encounter shape and the ~200,000 row count are unchanged. */
CROSS APPLY (
    SELECT p.ti
    FROM (VALUES
        (0,1,2), (0,2,3), (0,3,5), (0,4,1), (0,5,2),   -- hypertension
        (1,1,2), (1,2,3), (1,3,1), (1,4,5), (1,5,2),   -- type 2 diabetes
        (2,1,2), (2,2,1), (2,3,3), (2,4,4), (2,5,2),   -- heart failure
        (3,1,1), (3,2,2), (3,3,1), (3,4,3), (3,5,2),   -- pneumonia
        (4,1,1), (4,2,2), (4,3,1), (4,4,3), (4,5,2),   -- urinary tract infection
        (5,1,1), (5,2,2), (5,3,1), (5,4,3), (5,5,1),   -- appendicitis
        (6,1,4), (6,2,4), (6,3,1), (6,4,2), (6,5,5),   -- chest pain
        (7,1,2), (7,2,1), (7,3,4), (7,4,3), (7,5,6),   -- syncope
        (8,1,1), (8,2,2), (8,3,3), (8,4,5), (8,5,1),   -- stroke
        (9,1,1), (9,2,2), (9,3,1), (9,4,3), (9,5,2),   -- COPD
        /* Pediatric bands draw only CBC, BMP and CMP. Serial troponins, a
           lipid panel and a TSH are adult workups and would contradict the
           note beside them. */
        (10,1,1), (10,2,2), (10,3,1), (10,4,2), (10,5,1),  -- infant
        (11,1,1), (11,2,2), (11,3,1), (11,4,3), (11,5,1),  -- child
        (12,1,1), (12,2,2), (12,3,3), (12,4,1), (12,5,2),  -- adolescent
        /* Psychiatric admission: blood count, electrolytes and liver function,
           plus a thyroid test, which is a genuine part of a psychiatric
           workup. No troponin -- coherence check G1 flags a raised troponin
           outside a cardiac diagnosis, and it would be true here. */
        (13,1,1), (13,2,2), (13,3,3), (13,4,6), (13,5,2)   -- psychiatric
    ) p(cond, slot, ti)
    WHERE p.cond = es.cond AND p.slot = gs.value
) k
CROSS APPLY (VALUES (
    CHOOSE(k.ti, N'CBC', N'BMP', N'CMP', N'Troponin I', N'Lipid Panel', N'TSH'),
    CHOOSE(k.ti, N'Whole blood, EDTA', N'Serum', N'Serum', N'Serum', N'Serum (fasting)', N'Serum'),
    CHOOSE(k.ti, N'Sysmex XN-1000', N'Roche cobas c703', N'Roche cobas c703',
                 N'Abbott Architect i2000', N'Roche cobas c703', N'Roche cobas e601')
)) lab(TestName, Specimen, Instrument);
GO

/* ============================================================================
   13. clinical.Observation  (~108M — the size anchor)
       Generated in batches of @BatchEncounters encounters to keep log apply
       moving and stay within reasonable memory/log governance. This section
       dominates the run time quoted in the header — and because the load is
       log-rate gated rather than CPU gated, scaling the primary up does not
       shorten it (Performance §5).

       Values come from the encounter's OWN story, not from EncounterId
       arithmetic. This is what makes the Ward General App chart honest: the vitals panel
       and the note beside it are generated from one #Story row, so a septic
       pneumonia note can no longer sit next to a textbook-normal blood
       pressure. It also means abnormal readings actually occur — the old
       ranges were narrow enough that four of the six vital types could never
       cross the app's abnormal thresholds at all, so most charts rendered
       entirely green regardless of what the note said.
   ============================================================================ */
PRINT N'--- clinical.Observation (batched) ---';

DECLARE @Scale      FLOAT = 1.0;
DECLARE @ObsPerEnc  INT   = CAST(2700 * @Scale AS INT);  -- 6 types × 450 samples
DECLARE @BatchEncounters INT = 1000;
DECLARE @MinEnc INT, @MaxEnc INT, @CurEnc INT, @Batch INT = 0;
SELECT @MinEnc = MIN(EncounterId), @MaxEnc = MAX(EncounterId) FROM clinical.Encounter;
SET @CurEnc = @MinEnc;

WHILE @CurEnc <= @MaxEnc
BEGIN
    SET @Batch = @Batch + 1;

    INSERT INTO clinical.Observation
        (EncounterId, PatientId, RecordedAt, ObservationType, ValueNumeric, Unit)
    SELECT
        e.EncounterId,
        e.PatientId,
        DATEADD(SECOND, gs.value * (DATEDIFF(SECOND, e.AdmitTime, COALESCE(e.DischargeTime, SYSUTCDATETIME())) / (@ObsPerEnc / 6)), e.AdmitTime),
        t.ObservationType,
        CASE t.ObservationType
            WHEN N'HeartRate'   THEN s.HrLo  + ((gs.value + e.EncounterId * 3)  % s.HrSp)
            WHEN N'SystolicBP'  THEN s.SysLo + ((gs.value + e.EncounterId * 5)  % s.SysSp)
            WHEN N'DiastolicBP' THEN s.DiaLo + ((gs.value + e.EncounterId * 7)  % s.DiaSp)
            WHEN N'SpO2'        THEN s.SpLo  + ((gs.value + e.EncounterId * 11) % s.SpSp)
            WHEN N'Temperature' THEN s.TempI + (((gs.value + e.EncounterId * 13) % 10) / 10.0)
            WHEN N'RespRate'    THEN s.RrLo  + ((gs.value + e.EncounterId * 17) % s.RrSp)
        END,
        t.Unit
    FROM clinical.Encounter e
    JOIN #EncStory es ON es.EncounterId = e.EncounterId
    JOIN #Story    s  ON s.cond = es.cond AND s.sid = es.sid
    CROSS JOIN GENERATE_SERIES(1, @ObsPerEnc / 6) gs
    CROSS JOIN (VALUES
        (N'HeartRate',   N'bpm'),
        (N'SystolicBP',  N'mmHg'),
        (N'DiastolicBP', N'mmHg'),
        (N'SpO2',        N'%'),
        (N'Temperature', N'C'),
        (N'RespRate',    N'/min')
    ) t(ObservationType, Unit)
    WHERE e.EncounterId BETWEEN @CurEnc AND @CurEnc + @BatchEncounters - 1;

    PRINT CONCAT(N'    batch ', @Batch,
                 N' done at ', CONVERT(NVARCHAR(30), SYSUTCDATETIME(), 126));
    SET @CurEnc = @CurEnc + @BatchEncounters;
END;
GO

/* ============================================================================
   14. Bedside-chart extras — Symptoms, Care team, Imaging (active encounters).
       Clinical notes are already seeded above (clinical.ClinicalNote); the
       chart view just surfaces them. All synthetic.
   ============================================================================ */
PRINT N'--- clinical.Symptom / CareTeamMember / ImagingOrder (active encounters) ---';

/* Symptoms: 1-3 presenting complaints per active encounter, drawn from the
   encounter's own condition. A stroke admission presents with facial droop and
   slurred speech, not with a random pick from a twelve-item grab bag. */
;WITH activeEnc AS (SELECT EncounterId FROM clinical.Encounter WHERE Status = N'Active')
INSERT INTO clinical.Symptom (EncounterId, Description, Severity, NotedAt)
SELECT
    e.EncounterId, s.Description, s.Severity,
    DATEADD(HOUR, -(ABS(CHECKSUM(NEWID())) % 48), SYSUTCDATETIME())
FROM activeEnc AS e
JOIN #EncStory AS es ON es.EncounterId = e.EncounterId
CROSS APPLY
(
    SELECT TOP (1 + ABS(CHECKSUM(NEWID())) % 3) v.Description, v.Severity
    FROM (VALUES
        (0, N'Headache',                  N'Moderate'),
        (0, N'Blurred vision',            N'Mild'),
        (0, N'Dizziness',                 N'Mild'),
        (1, N'Excessive thirst',          N'Moderate'),
        (1, N'Frequent urination',        N'Mild'),
        (1, N'Fatigue',                   N'Mild'),
        (2, N'Shortness of breath',       N'Severe'),
        (2, N'Leg swelling',              N'Moderate'),
        (2, N'Breathlessness lying flat', N'Moderate'),
        (3, N'Productive cough',          N'Moderate'),
        (3, N'Fever',                     N'Moderate'),
        (3, N'Pleuritic chest pain',      N'Moderate'),
        (4, N'Burning with urination',    N'Moderate'),
        (4, N'Urinary frequency',         N'Mild'),
        (4, N'Flank pain',                N'Moderate'),
        (5, N'Right lower quadrant pain', N'Severe'),
        (5, N'Nausea',                    N'Moderate'),
        (5, N'Loss of appetite',          N'Mild'),
        (6, N'Chest pain',                N'Severe'),
        (6, N'Shortness of breath',       N'Moderate'),
        (6, N'Sweating',                  N'Moderate'),
        (7, N'Transient loss of consciousness', N'Severe'),
        (7, N'Lightheadedness',           N'Moderate'),
        (7, N'Palpitations',              N'Mild'),
        (8, N'One-sided weakness',        N'Severe'),
        (8, N'Slurred speech',            N'Severe'),
        (8, N'Facial droop',              N'Severe'),
        (9, N'Breathlessness on exertion', N'Severe'),
        (9, N'Chronic cough',             N'Moderate'),
        (9, N'Wheezing',                  N'Moderate'),
        (10, N'Poor feeding',             N'Moderate'),
        (10, N'Fever',                    N'Moderate'),
        (10, N'Irritability',             N'Mild'),
        (11, N'Cough',                    N'Moderate'),
        (11, N'Wheeze',                   N'Moderate'),
        (11, N'Fever',                    N'Moderate'),
        (12, N'Abdominal pain',           N'Severe'),
        (12, N'Sore throat',              N'Moderate'),
        (12, N'Fatigue',                  N'Mild'),
        (13, N'Low mood',                 N'Severe'),
        (13, N'Poor sleep',               N'Moderate'),
        (13, N'Agitation',                N'Moderate')
    ) AS v(cond, Description, Severity)
    WHERE v.cond = es.cond
    ORDER BY NEWID()
) AS s;
GO

/* Care team: attending (primary) + up to 3 others with distinct roles. */
INSERT INTO clinical.CareTeamMember (EncounterId, ProviderId, TeamRole, IsPrimary)
SELECT e.EncounterId, e.AttendingProviderId, N'Attending', 1
FROM clinical.Encounter AS e
WHERE e.Status = N'Active';
GO

;WITH activeEnc AS (SELECT EncounterId, AttendingProviderId FROM clinical.Encounter WHERE Status = N'Active'),
picks AS
(
    SELECT e.EncounterId, p.ProviderId,
        ROW_NUMBER() OVER (PARTITION BY e.EncounterId ORDER BY NEWID()) AS rn
    FROM activeEnc AS e
    JOIN ops.Provider AS p ON p.ProviderId <> e.AttendingProviderId
)
INSERT INTO clinical.CareTeamMember (EncounterId, ProviderId, TeamRole, IsPrimary)
SELECT EncounterId, ProviderId,
    CASE rn WHEN 1 THEN N'Resident' WHEN 2 THEN N'Intern' WHEN 3 THEN N'Consultant' END, 0
FROM picks
WHERE rn <= 3;
GO

/* Imaging: ~half of active encounters get 1-2 studies. */
;WITH activeEnc AS (
    SELECT EncounterId, PatientId, AttendingProviderId
    FROM clinical.Encounter WHERE Status = N'Active' AND EncounterId % 2 = 0
)
INSERT INTO clinical.ImagingOrder
    (EncounterId, PatientId, Modality, BodySite, Status, OrderedById, OrderedAt, ResultedAt)
SELECT
    e.EncounterId, e.PatientId, m.Modality, m.BodySite,
    /* m.r_status, not an inline NEWID(). A simple CASE re-evaluates its input
       expression once per WHEN comparison, so a nondeterministic input draws a
       fresh number for each branch and skews the distribution badly (measured
       33/26/41 instead of thirds). A column reference is evaluated once. */
    CASE m.r_status % 3 WHEN 0 THEN N'Completed' WHEN 1 THEN N'InProgress' ELSE N'Ordered' END,
    e.AttendingProviderId,
    DATEADD(HOUR, -(ABS(CHECKSUM(NEWID())) % 36), SYSUTCDATETIME()),
    NULL
FROM activeEnc AS e
JOIN #EncStory AS es ON es.EncounterId = e.EncounterId
/* Modality and body site follow the condition. A suspected stroke gets a head
   CT and an MRI brain; an appendicitis gets abdominal imaging. Nobody gets a
   brain MRI for a urinary tract infection. */
CROSS APPLY
(
    SELECT TOP (1 + ABS(CHECKSUM(NEWID())) % 2)
           v.Modality, v.BodySite,
           r_status = ABS(CHECKSUM(NEWID()))
    FROM (VALUES
        (0, N'CT',  N'Head'),            (0, N'XR',  N'Chest'),
        (1, N'XR',  N'Foot'),            (1, N'US',  N'Abdomen'),
        (2, N'XR',  N'Chest'),           (2, N'US',  N'Heart'),
        (3, N'XR',  N'Chest'),           (3, N'CT',  N'Chest'),
        (4, N'US',  N'Renal'),           (4, N'CT',  N'Abdomen/Pelvis'),
        (5, N'CT',  N'Abdomen/Pelvis'),  (5, N'US',  N'Abdomen'),
        (6, N'XR',  N'Chest'),           (6, N'CT',  N'Chest'),
        (7, N'CT',  N'Head'),            (7, N'XR',  N'Chest'),
        (8, N'CT',  N'Head'),            (8, N'MRI', N'Brain'),
        (9, N'XR',  N'Chest'),           (9, N'CT',  N'Chest'),
        (10, N'XR', N'Chest'),           (10, N'US', N'Abdomen'),
        (11, N'XR', N'Chest'),           (11, N'US', N'Abdomen'),
        (12, N'US', N'Abdomen'),         (12, N'XR', N'Chest'),
        (13, N'CT', N'Head'),            (13, N'XR', N'Chest')
    ) AS v(cond, Modality, BodySite)
    WHERE v.cond = es.cond
    ORDER BY NEWID()
) AS m;
GO

/* ----------------------------------------------------------------------------
   The story tables have done their job. They are dropped here rather than
   after the notes, because sections 9 through 14 all read them: the notes, the
   diagnoses, the drugs, the labs, the 108M observations, the intake payload,
   the symptoms and the imaging orders.
   ---------------------------------------------------------------------------- */
IF OBJECT_ID('tempdb..#EncStory') IS NOT NULL DROP TABLE #EncStory;
IF OBJECT_ID('tempdb..#Story')    IS NOT NULL DROP TABLE #Story;
GO

/* ============================================================================
   Final summary
   ============================================================================ */
PRINT N'--- Row counts ---';
SELECT N'ops.Department'            AS TableName, COUNT(*) AS [RowCount] FROM ops.Department
UNION ALL SELECT N'ops.Unit',                COUNT(*) FROM ops.Unit
UNION ALL SELECT N'ops.Bed',                 COUNT(*) FROM ops.Bed
UNION ALL SELECT N'ops.Provider',            COUNT(*) FROM ops.Provider
UNION ALL SELECT N'ops.Appointment',         COUNT(*) FROM ops.Appointment
UNION ALL SELECT N'clinical.Patient',        COUNT(*) FROM clinical.Patient
UNION ALL SELECT N'clinical.Allergy',        COUNT(*) FROM clinical.Allergy
UNION ALL SELECT N'clinical.Encounter',      COUNT(*) FROM clinical.Encounter
UNION ALL SELECT N'clinical.Diagnosis',      COUNT(*) FROM clinical.Diagnosis
UNION ALL SELECT N'clinical.ClinicalNote',   COUNT(*) FROM clinical.ClinicalNote
UNION ALL SELECT N'clinical.MedicationOrder',COUNT(*) FROM clinical.MedicationOrder
UNION ALL SELECT N'clinical.LabResult',      COUNT(*) FROM clinical.LabResult
UNION ALL SELECT N'clinical.Symptom',        COUNT(*) FROM clinical.Symptom
UNION ALL SELECT N'clinical.CareTeamMember', COUNT(*) FROM clinical.CareTeamMember
UNION ALL SELECT N'clinical.ImagingOrder',   COUNT(*) FROM clinical.ImagingOrder
UNION ALL SELECT N'clinical.Observation',    COUNT(*) FROM clinical.Observation;
GO

PRINT N'--- Approximate space used ---';
SELECT
    SUM(reserved_page_count) * 8.0 / 1024.0 / 1024.0 AS ReservedGB,
    SUM(used_page_count)     * 8.0 / 1024.0 / 1024.0 AS UsedGB
FROM sys.dm_db_partition_stats;
GO

PRINT N'Seed complete.';
GO
