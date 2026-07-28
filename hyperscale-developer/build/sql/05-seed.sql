/* ============================================================================
   Ward General Hospital — Hyperscale developer demo
   05-seed.sql      : reproducible synthetic seed for Ward General Hospital.
   Run order        : 5 of 5  (after 04-procedures.sql)

   What this script populates:

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
       clinical.Observation ~108M            (the size anchor; ~10 GB w/ indexes)

   Anchor target: a database a little over 10 GB after this seed completes.
   A separate grow script can push clinical.Observation to ~1 TB for the
   scale demo — the seed itself stays at the volumes below.

   ----------------------------------------------------------------------------
   DISCLAIMER — PURELY FICTIONAL, FULLY SYNTHETIC DATA
   ----------------------------------------------------------------------------
   This is the demo dataset. Every value it produces is
   PURELY FICTIONAL and FULLY SYNTHETIC. It contains NO real protected health
   information (PHI) and does NOT represent any real person, patient, provider,
   event, place, diagnosis, medication, lab result, insurer, or organization.
   Any resemblance to a real individual or institution is coincidental.
   Recognisable names are *Seinfeld* supporting cast, used purely as memorable
   flavour to make the data easier to follow. Jerry does not appear.

   This data was GENERATED WITH AI ASSISTANCE. Although plausible in shape, it
   DOES NOT accurately represent real medical, clinical, laboratory,
   pharmacological, or billing data IN ANY WAY. It exists SOLELY to illustrate
   Azure SQL Hyperscale features in this demo.

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
   gated (~105 MiB/s), so a larger vCore size does NOT shorten it.

   Idempotence: re-runnable. The script TRUNCATEs the synthesised tables
   and reseeds Patient / Provider / Department / Unit / Bed. Identity
   counters are reset.
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
   Default volumes target ~10 GB after this script completes.
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
TRUNCATE TABLE clinical.Observation;
TRUNCATE TABLE clinical.LabResult;
TRUNCATE TABLE clinical.MedicationOrder;
TRUNCATE TABLE clinical.ClinicalNote;
TRUNCATE TABLE clinical.Diagnosis;
TRUNCATE TABLE clinical.Allergy;
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
    DATEFROMPARTS(
        1930 + (ABS(CHECKSUM(NEWID())) % 96),
        1   + (ABS(CHECKSUM(NEWID())) %  12),
        1   + (ABS(CHECKSUM(NEWID())) %  28)),
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

DECLARE @BedCount   INT = (SELECT COUNT(*) FROM ops.Bed);
DECLARE @ProvCount  INT = (SELECT COUNT(*) FROM ops.Provider);
DECLARE @DeptCount  INT = (SELECT COUNT(*) FROM ops.Department);
DECLARE @PatCount   INT = (SELECT COUNT(*) FROM clinical.Patient);

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
   - The patient fits the unit (#6): Peds units get children, OB units get
     reproductive-age women, everything else gets adults. The three pools are
     DISJOINT and matched to beds by row-number, so no patient occupies two beds. */
;WITH BedBucket AS (
    SELECT b.BedId, un.DepartmentId,
           CASE dept.Name WHEN N'Pediatrics'            THEN 1
                          WHEN N'Obstetrics-Gynecology' THEN 2
                          ELSE 3 END AS bucket,
           ROW_NUMBER() OVER (
             PARTITION BY CASE dept.Name WHEN N'Pediatrics'            THEN 1
                                         WHEN N'Obstetrics-Gynecology' THEN 2
                                         ELSE 3 END
             ORDER BY b.BedId) AS brn
    FROM ops.Bed b
    JOIN ops.Unit un         ON un.UnitId       = b.UnitId
    JOIN ops.Department dept ON dept.DepartmentId = un.DepartmentId
),
PoolPeds AS (
    SELECT PatientId, ROW_NUMBER() OVER (ORDER BY PatientId) AS prn
    FROM clinical.Patient
    WHERE DATEDIFF(YEAR, DateOfBirth, SYSUTCDATETIME()) <= 17
),
PoolOB AS (
    SELECT PatientId, ROW_NUMBER() OVER (ORDER BY PatientId) AS prn
    FROM clinical.Patient
    WHERE Sex = N'Female'
      AND DATEDIFF(YEAR, DateOfBirth, SYSUTCDATETIME()) BETWEEN 18 AND 50
),
PoolAdult AS (
    SELECT PatientId, ROW_NUMBER() OVER (ORDER BY PatientId) AS prn
    FROM clinical.Patient
    WHERE DATEDIFF(YEAR, DateOfBirth, SYSUTCDATETIME()) >= 18
      AND NOT (Sex = N'Female'
               AND DATEDIFF(YEAR, DateOfBirth, SYSUTCDATETIME()) BETWEEN 18 AND 50)
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
        'allergiesAtIntake' : CHOOSE(((b.BedId * 3) % 4) + 1,
                                  JSON_ARRAY(N'Penicillin', N'Latex'),
                                  JSON_ARRAY(N'NKDA'),
                                  JSON_ARRAY(N'Sulfa'),
                                  JSON_ARRAY(N'Shellfish', N'Iodine contrast')),
        'currentMedications': CHOOSE(((b.BedId * 5) % 4) + 1,
                                  JSON_ARRAY(N'Lisinopril 10mg daily', N'Atorvastatin 40mg nightly', N'Aspirin 81mg daily'),
                                  JSON_ARRAY(N'Metformin 1000mg twice daily', N'Insulin glargine 20 units nightly'),
                                  JSON_ARRAY(N'Metoprolol 25mg twice daily', N'Apixaban 5mg twice daily'),
                                  JSON_ARRAY(N'Albuterol inhaler as needed', N'Furosemide 40mg daily')),
        'pastMedicalHistory': CHOOSE(((b.BedId * 7) % 4) + 1,
                                  JSON_ARRAY(N'Hypertension', N'Hyperlipidemia', N'Type 2 Diabetes'),
                                  JSON_ARRAY(N'COPD', N'Chronic kidney disease'),
                                  JSON_ARRAY(N'Atrial fibrillation', N'Prior stroke'),
                                  JSON_ARRAY(N'Coronary artery disease', N'Heart failure')),
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
    SELECT PatientId FROM PoolPeds
        WHERE b.bucket = 1 AND prn = ((b.brn - 1) % (SELECT COUNT(*) FROM PoolPeds)) + 1
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

PRINT N'--- clinical.Encounter (discharged) ---';

/* Local scale knob — keep in sync with the other two @Scale declarations
   in this file (Appointment and Observation batches). */
DECLARE @Scale          FLOAT = 1.0;
DECLARE @EncounterCount INT   = CAST(40000 * @Scale AS INT);

/* Discharged encounters — backfill to @EncounterCount total. */
DECLARE @Active INT = (SELECT COUNT(*) FROM clinical.Encounter);
DECLARE @Discharged INT = @EncounterCount - @Active;
PRINT CONCAT(N'    active = ', @Active, N', discharged to add = ', @Discharged);

;WITH P AS (SELECT PatientId,    ROW_NUMBER() OVER (ORDER BY PatientId)    - 1 AS rn FROM clinical.Patient),
      D AS (SELECT DepartmentId, ROW_NUMBER() OVER (ORDER BY DepartmentId) - 1 AS rn FROM ops.Department)
INSERT INTO clinical.Encounter
    (PatientId, DepartmentId, AttendingProviderId, BedId,
     EncounterType, AdmitTime, DischargeTime, Status, IntakeJson)
SELECT
    P.PatientId,
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
JOIN P ON P.rn = (gs.value * 4001) % @PatCount
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
   9.  clinical.Diagnosis  (~80,000 — 2 per encounter average)
   ============================================================================ */
PRINT N'--- clinical.Diagnosis ---';
INSERT INTO clinical.Diagnosis (EncounterId, IcdCode, Description, DiagnosedById)
SELECT
    e.EncounterId,
    CHOOSE(((e.EncounterId * 7 + gs.value) % 10) + 1,
           N'I10',   N'E11.9', N'I50.9', N'J18.9', N'N39.0',
           N'K35.80',N'R07.9', N'R55',   N'I63.9', N'J44.9'),
    CHOOSE(((e.EncounterId * 7 + gs.value) % 10) + 1,
           N'Essential hypertension',
           N'Type 2 diabetes mellitus without complications',
           N'Heart failure, unspecified',
           N'Pneumonia, unspecified organism',
           N'Urinary tract infection, site not specified',
           N'Acute appendicitis without rupture',
           N'Chest pain, unspecified',
           N'Syncope and collapse',
           N'Cerebral infarction, unspecified',
           N'Chronic obstructive pulmonary disease, unspecified'),
    e.AttendingProviderId
FROM clinical.Encounter e
CROSS JOIN GENERATE_SERIES(1, 2) gs;
GO

/* ============================================================================
   10. clinical.ClinicalNote  (~60,000 — 2 per encounter; ~1-2 KB NoteText)
   ============================================================================ */
PRINT N'--- clinical.ClinicalNote ---';
/* ----------------------------------------------------------------------------
   Notes are anchored to the encounter's PRIMARY diagnosis (the same 10 ICD
   conditions seeded above; primary = the gs.value = 1 diagnosis), so each note
   is clinically COHERENT and clusters by condition for vector search. Every
   surface fragment is then chosen with INDEPENDENT per-row randomness
   (ABS(CHECKSUM(NEWID()))), so within-condition variation is high and near-
   duplicate collisions are rare. The vitals / "Pain scored N out of 10" /
   "Follow up ..." tokens are preserved verbatim because 03-views.sql mines them
   with REGEXP_*. CreatedAt is randomized within each encounter's stay window.

     cond: 0 HTN · 1 T2DM · 2 HF · 3 Pneumonia · 4 UTI ·
           5 Appendicitis · 6 Chest pain · 7 Syncope · 8 Stroke · 9 COPD
   ---------------------------------------------------------------------------- */
INSERT INTO clinical.ClinicalNote
    (EncounterId, AuthorProviderId, NoteType, NoteText, CreatedAt)
SELECT
    e.EncounterId,
    e.AttendingProviderId,
    CHOOSE((x.r_type % 3) + 1, N'Progress', N'Consult', N'Discharge'),
    CONCAT(
        N'Subjective: Patient reports ',
        CHOOSE(x.cond + 1,
            CHOOSE((x.r_sub % 6) + 1, N'an incidental severely elevated blood-pressure reading found at a routine visit, ', N'a throbbing headache with home readings persistently above goal, ', N'blurred vision and epistaxis with a markedly elevated pressure at triage, ', N'chest discomfort and dyspnea in the setting of very high blood pressure, ', N'symptoms after running out of antihypertensive medications weeks ago, ', N'dizziness and palpitations with labile home blood-pressure readings, '),
            CHOOSE((x.r_sub % 6) + 1, N'increased thirst, polyuria, and fatigue with very high home glucose readings, ', N'nausea, vomiting, and abdominal pain with deep rapid breathing, ', N'confusion and lethargy with profoundly elevated blood glucose, ', N'a painful, slow-healing foot ulcer with surrounding redness, ', N'recurrent hypoglycemic episodes after a recent insulin adjustment, ', N'an incidentally elevated glucose found on routine screening, '),
            CHOOSE((x.r_sub % 6) + 1, N'progressive dyspnea on exertion, orthopnea, and bilateral leg swelling, ', N'acute severe breathlessness with pink frothy sputum at rest, ', N'a three-kilogram weight gain over the week with worsening edema, ', N'fatigue and early satiety with increasing abdominal distension, ', N'paroxysmal nocturnal dyspnea requiring several pillows to sleep, ', N'worsening swelling after dietary indiscretion and missed diuretic doses, '),
            CHOOSE((x.r_sub % 6) + 1, N'fevers, chills, and a productive cough with green sputum, ', N'pleuritic chest pain with shortness of breath and subjective fevers, ', N'worsening cough and breathlessness with new confusion, ', N'cough and fever shortly after a recent hospitalization, ', N'sudden high fever and rigors with rapid breathing, ', N'a gradual cough and malaise with reduced appetite over a week, '),
            CHOOSE((x.r_sub % 6) + 1, N'dysuria, urinary frequency, and suprapubic discomfort, ', N'flank pain, fever, and rigors with nausea, ', N'burning with urination and new urinary urgency with malaise, ', N'foul-smelling urine and new confusion at home, ', N'urinary symptoms in the setting of a chronic indwelling catheter, ', N'lower abdominal pain and blood in the urine with frequency, '),
            CHOOSE((x.r_sub % 6) + 1, N'periumbilical pain migrating to the right lower quadrant with nausea, ', N'sharp right lower quadrant abdominal pain with anorexia and low-grade fever, ', N'diffuse abdominal pain with high fever and rigidity, ', N'right lower quadrant pain with repeated vomiting over the past day, ', N'worsening abdominal pain now on the first post-operative day, ', N'intermittent right-sided abdominal pain over several days, '),
            CHOOSE((x.r_sub % 6) + 1, N'crushing substernal chest pressure radiating to the left arm and jaw with diaphoresis, ', N'exertional chest tightness relieved by rest, consistent with stable angina, ', N'pleuritic, positional chest pain that improves when leaning forward, ', N'sharp left-sided chest pain reproducible on palpation of the chest wall, ', N'burning retrosternal discomfort worse after meals and when lying flat, ', N'sudden tearing chest pain radiating to the back between the shoulder blades, '),
            CHOOSE((x.r_sub % 6) + 1, N'a transient loss of consciousness while standing, with rapid full recovery, ', N'a syncopal episode preceded by palpitations and chest discomfort, ', N'lightheadedness and one witnessed fainting episode without warning, ', N'a loss of consciousness during exertion with slow recovery, ', N'recurrent fainting when rising from a seated position, ', N'a brief blackout after prolonged standing in a warm room, '),
            CHOOSE((x.r_sub % 6) + 1, N'sudden right-sided weakness and slurred speech noted on waking, ', N'acute facial droop and difficulty finding words witnessed by family, ', N'transient right-arm weakness that resolved within the hour, ', N'a sudden severe headache with neck stiffness and vomiting, ', N'acute vertigo, imbalance, and double vision, ', N'progressive left-sided numbness and confusion over hours, '),
            CHOOSE((x.r_sub % 6) + 1, N'increased dyspnea, wheeze, and a change in sputum color and volume, ', N'severe breathlessness with accessory muscle use and difficulty speaking, ', N'worsening breathlessness and cough despite home inhaler use, ', N'progressive dyspnea after a recent upper respiratory infection, ', N'wheezing and chest tightness with reduced exercise tolerance, ', N'increasing cough and sputum with a low-grade fever, ')),
        CHOOSE((x.r_hpi % 4) + 1,
            N'with a gradual progression over several days. ',
            N'with an abrupt onset that peaked within hours. ',
            N'following an intermittent course that is worse in the evenings. ',
            N'with no clear precipitating factors and no prior similar episodes. '),
        N'Pain scored ', v.pain, N' out of 10. ',
        CHOOSE((x.r_pmh % 4) + 1,
            N'Adherent to home medications with no new agents or supplements. ',
            N'Reports occasional missed doses of maintenance therapy. ',
            N'Recently started a new medication prescribed by an outside provider. ',
            N'Takes only as-needed analgesics at home. '),
        CHOOSE((x.r_fh % 4) + 1,
            N'Family history significant for premature coronary artery disease. ',
            N'Family history notable for type 2 diabetes and stroke. ',
            N'No significant family history elicited. ',
            N'Family history of malignancy in a first-degree relative. '),
        CHAR(13), CHAR(10),
        N'Objective: T ', v.tempInt, N'.', v.tempTenth,
        N'C, HR ', v.hr,
        N', BP ', v.bpSys, N'/', v.bpDia,
        N', RR ', v.rr,
        N', SpO2 ', v.spo2,
        N'% on room air. ',
        CHOOSE((x.r_gen % 4) + 1,
            N'Patient appears comfortable, in no acute distress. ',
            N'Patient appears fatigued but interactive and cooperative. ',
            N'Patient is ill-appearing but hemodynamically stable. ',
            N'Patient is alert and in mild distress. '),
        N'HEENT atraumatic and normocephalic, mucous membranes moist; neck supple without JVD. ',
        CHOOSE((x.r_card % 4) + 1,
            N'Cardiac exam regular rate and rhythm without murmurs, rubs, or gallops. ',
            N'Cardiac exam with a soft II/VI systolic ejection murmur at the base. ',
            N'Cardiac rhythm irregularly irregular, consistent with atrial fibrillation. ',
            N'Tachycardic but regular, with no appreciable murmur. '),
        CHOOSE((x.r_lung % 4) + 1,
            N'Lungs clear to auscultation bilaterally without rales or wheezing. ',
            N'Bibasilar crackles noted, worse on the right. ',
            N'Scattered expiratory wheezes throughout both lung fields. ',
            N'Decreased breath sounds at the right base. '),
        CHOOSE((x.r_abd % 3) + 1,
            N'Abdomen soft, non-tender, with normoactive bowel sounds. ',
            N'Abdomen with right lower quadrant tenderness and voluntary guarding. ',
            N'Abdomen mildly distended, non-tender, without rebound. '),
        CHOOSE((x.r_ext % 3) + 1,
            N'Extremities warm and well perfused with 2+ pulses and no edema. ',
            N'Bilateral lower extremity pitting edema to the knees. ',
            N'Unilateral calf swelling and tenderness noted. '),
        CASE WHEN x.cond = 8
             THEN N'Neurologic exam notable for right-sided facial droop, pronator drift, and dysarthria. '
             ELSE N'Neurologic exam grossly intact, alert and oriented to person, place, time, and situation. '
        END,
        CHAR(13), CHAR(10),
        N'Assessment: ',
        CHOOSE(x.cond + 1,
            CHOOSE((x.r_assess % 6) + 1, N'Hypertensive emergency with acute end-organ involvement; admitted for IV therapy. ', N'Hypertensive urgency without end-organ damage; oral agents up-titrated. ', N'Newly diagnosed stage 2 essential hypertension; combination therapy started. ', N'Uncontrolled hypertension from medication nonadherence; regimen restarted. ', N'White-coat hypertension; ambulatory monitoring arranged without acute treatment. ', N'Secondary hypertension suspected; workup for renal and endocrine causes begun. '),
            CHOOSE((x.r_assess % 6) + 1, N'Diabetic ketoacidosis; started on an insulin infusion and fluid resuscitation. ', N'Hyperosmolar hyperglycemic state; aggressive rehydration and insulin begun. ', N'Type 2 diabetes, markedly uncontrolled, without acute metabolic decompensation. ', N'Diabetic foot ulcer with local infection; antibiotics and wound care started. ', N'Recurrent hypoglycemia from insulin excess; regimen reduced and education given. ', N'Newly diagnosed type 2 diabetes; lifestyle counseling and metformin initiated. '),
            CHOOSE((x.r_assess % 6) + 1, N'Acute decompensated heart failure with reduced ejection fraction, volume overloaded. ', N'Flash pulmonary edema requiring noninvasive positive-pressure ventilation. ', N'Heart failure with preserved ejection fraction, congested on examination. ', N'Right-sided heart failure with hepatic congestion and peripheral edema. ', N'Acute on chronic systolic heart failure exacerbation, diuresing appropriately. ', N'Heart failure exacerbation precipitated by nonadherence and dietary sodium. '),
            CHOOSE((x.r_assess % 6) + 1, N'Community-acquired pneumonia, lower lobe, responding to empiric antibiotics. ', N'Community-acquired pneumonia with a parapneumonic effusion on imaging. ', N'Severe community-acquired pneumonia with sepsis and hypoxemia. ', N'Healthcare-associated pneumonia; broadened antibiotic coverage started. ', N'Community-acquired pneumonia with mild hypoxemia requiring supplemental oxygen. ', N'Atypical pneumonia suspected; macrolide therapy initiated. '),
            CHOOSE((x.r_assess % 6) + 1, N'Uncomplicated cystitis; urinalysis consistent with a lower urinary tract infection. ', N'Acute pyelonephritis with systemic signs; intravenous antibiotics started. ', N'Urinary tract infection with early urosepsis; hemodynamically monitored. ', N'Complicated urinary tract infection with delirium in an older adult. ', N'Catheter-associated urinary tract infection; the catheter was exchanged. ', N'Hemorrhagic cystitis; infection treated and hematuria monitored. '),
            CHOOSE((x.r_assess % 6) + 1, N'Acute appendicitis without perforation; surgical evaluation obtained. ', N'Perforated appendicitis with localized peritonitis; urgent surgery planned. ', N'Appendicitis with generalized peritonitis and sepsis. ', N'Uncomplicated appendicitis confirmed on imaging; appendectomy scheduled. ', N'Acute appendicitis, post-operative day one, recovering after laparoscopic appendectomy. ', N'Suspected appendicitis; serial examinations and imaging in progress. '),
            CHOOSE((x.r_assess % 6) + 1, N'ST-elevation myocardial infarction; activated the cardiac catheterization laboratory. ', N'Non-ST-elevation myocardial infarction with a rising troponin; dual antiplatelet therapy started. ', N'Unstable angina; admitted for serial troponins and inpatient risk stratification. ', N'Acute pericarditis with diffuse ST changes; anti-inflammatory therapy started. ', N'Non-cardiac chest pain, likely gastroesophageal reflux; cardiac workup reassuring. ', N'Musculoskeletal costochondritis; acute coronary syndrome excluded by serial troponins. '),
            CHOOSE((x.r_assess % 6) + 1, N'Vasovagal syncope; orthostatic and cardiac causes considered and unlikely. ', N'Cardiac syncope from a suspected arrhythmia; telemetry monitoring initiated. ', N'Orthostatic hypotension, likely medication-related and volume-depleted. ', N'Exertional syncope concerning for structural heart disease; echocardiogram ordered. ', N'Syncope of undetermined etiology; telemetry monitoring in place. ', N'Situational syncope with a clear precipitant and reassuring workup. '),
            CHOOSE((x.r_assess % 6) + 1, N'Acute ischemic stroke within the thrombolysis window; stroke team activated. ', N'Acute ischemic stroke outside the thrombolysis window; admitted for workup. ', N'Transient ischemic attack with resolved deficit; urgent secondary prevention. ', N'Subarachnoid hemorrhage suspected; emergent imaging and neurosurgery consulted. ', N'Posterior circulation stroke with brainstem signs. ', N'Cerebral infarction with residual deficit; stroke protocol initiated. '),
            CHOOSE((x.r_assess % 6) + 1, N'COPD exacerbation, likely infective trigger, on bronchodilators and steroids. ', N'Severe COPD exacerbation with respiratory acidosis requiring noninvasive ventilation. ', N'Acute COPD exacerbation with hypoxemia; responding to nebulized therapy. ', N'COPD exacerbation triggered by a viral infection; supportive care started. ', N'COPD exacerbation with bronchospasm; intensified bronchodilator therapy. ', N'COPD exacerbation with a bacterial trigger; antibiotics initiated. ')),
        CHOOSE((x.r_comorb % 4) + 1,
            N'Comorbid hypertension, hyperlipidemia, and type 2 diabetes, well controlled. ',
            N'Comorbid COPD and stage 3 chronic kidney disease. ',
            N'History of atrial fibrillation maintained on anticoagulation. ',
            N'No significant chronic comorbidities identified. '),
        CHAR(13), CHAR(10),
        N'Plan: ',
        CHOOSE(x.cond + 1,
            CHOOSE((x.r_plan % 6) + 1, N'Admit to a monitored bed for IV antihypertensive titration and end-organ surveillance. ', N'Up-titrate oral agents, observe for several hours, and arrange close follow-up. ', N'Start a thiazide plus an ACE inhibitor and counsel on sodium restriction. ', N'Reconcile medications, address adherence barriers, and resume the prior regimen. ', N'Reassure, initiate home blood-pressure logging, and follow up in clinic. ', N'Order renal ultrasound and aldosterone-renin testing for secondary causes. '),
            CHOOSE((x.r_plan % 6) + 1, N'Start an insulin drip with hourly glucose and electrolyte monitoring. ', N'Give aggressive isotonic fluids, correct electrolytes, and transition to subcutaneous insulin. ', N'Adjust the insulin regimen and engage diabetes education for glycemic control. ', N'Offload the ulcer, provide wound care, and start empiric antibiotics. ', N'Reduce insulin dosing, review carbohydrate intake, and reinforce glucose monitoring. ', N'Start metformin, provide dietary counseling, and arrange endocrinology follow-up. '),
            CHOOSE((x.r_plan % 6) + 1, N'Diurese with IV furosemide and monitor daily weights and electrolytes. ', N'Provide noninvasive ventilation, nitrates, and aggressive diuresis in a monitored bed. ', N'Diurese, optimize afterload reduction, and evaluate diastolic function. ', N'Diurese cautiously, evaluate for pulmonary hypertension, and monitor renal function. ', N'Optimize guideline-directed medical therapy and restrict fluid and sodium. ', N'Reinforce adherence, provide dietary education, and arrange close follow-up. '),
            CHOOSE((x.r_plan % 6) + 1, N'Start empiric antibiotics and supplemental oxygen after obtaining blood cultures. ', N'Continue antibiotics, evaluate the effusion with ultrasound, and consider drainage. ', N'Initiate the sepsis bundle with fluids, broad antibiotics, and monitored admission. ', N'Broaden antibiotic coverage per exposure history and de-escalate on cultures. ', N'Continue antibiotics, trend oxygenation, and encourage incentive spirometry. ', N'Start a macrolide, treat as an outpatient if stable, and follow up closely. '),
            CHOOSE((x.r_plan % 6) + 1, N'Start oral antibiotics, encourage hydration, and follow up if symptoms persist. ', N'Give intravenous antibiotics, obtain cultures, and monitor renal function. ', N'Provide fluids, broad antibiotics, and monitored observation for sepsis. ', N'Treat the infection, address the delirium, and review for reversible causes. ', N'Exchange the catheter, obtain cultures, and start targeted antibiotics. ', N'Treat the infection, ensure hydration, and monitor the hematuria. '),
            CHOOSE((x.r_plan % 6) + 1, N'Keep NPO with IV fluids and analgesia; surgery consulted for operative planning. ', N'Proceed to urgent appendectomy with broad antibiotics and fluid resuscitation. ', N'Arrange emergent surgery, sepsis management, and monitored-bed admission. ', N'Proceed to laparoscopic appendectomy with perioperative antibiotics. ', N'Continue post-operative pain control, advance diet, and watch for infection. ', N'Perform serial abdominal exams, repeat imaging, and surgical reassessment. '),
            CHOOSE((x.r_plan % 6) + 1, N'Proceed to emergent percutaneous coronary intervention with interventional cardiology. ', N'Admit to telemetry, load antiplatelets and anticoagulation, and trend high-sensitivity troponin. ', N'Obtain serial electrocardiograms and troponins with cardiology consultation for possible catheterization. ', N'Start high-dose NSAIDs and colchicine with outpatient cardiology follow-up. ', N'Trial proton-pump inhibitor therapy and discharge with gastroenterology follow-up. ', N'Provide reassurance and analgesia, and discharge with return precautions and primary-care follow-up. '),
            CHOOSE((x.r_plan % 6) + 1, N'Hydrate, review medications, and counsel on trigger avoidance. ', N'Arrange telemetry monitoring, cardiology consultation, and an echocardiogram. ', N'Replete volume, review medications, and reassess orthostatic vitals. ', N'Obtain urgent echocardiography, restrict activity, and arrange cardiology evaluation. ', N'Continue telemetry monitoring, orthostatic vitals, and an echocardiogram. ', N'Reassure, hydrate, and arrange outpatient follow-up. '),
            CHOOSE((x.r_plan % 6) + 1, N'Pursue emergent thrombolysis evaluation, imaging, and stroke-unit admission. ', N'Admit to the stroke unit, obtain MRI, and start secondary-prevention therapy. ', N'Arrange expedited carotid imaging, antiplatelets, and risk-factor management. ', N'Obtain emergent CT and neurosurgical consultation with blood-pressure control. ', N'Obtain neurology consultation, dysphagia screening, and close neurologic monitoring. ', N'Provide stroke-unit care, dysphagia screening, and early rehabilitation. '),
            CHOOSE((x.r_plan % 6) + 1, N'Give nebulized bronchodilators, systemic steroids, and titrated oxygen. ', N'Provide noninvasive ventilation, steroids, and monitored-bed admission. ', N'Admit for respiratory support and continue bronchodilator therapy. ', N'Provide supportive care, bronchodilators, and monitor for bacterial superinfection. ', N'Intensify bronchodilators, add steroids, and reassess oxygenation. ', N'Start antibiotics, continue bronchodilators and steroids, and trend oxygenation. ')),
        CHOOSE((x.r_plan2 % 3) + 1,
            N'Repeat basic metabolic panel and complete blood count in the morning. ',
            N'Continue telemetry monitoring overnight. ',
            N'Case management engaged for discharge planning. '),
        N'Patient and family educated on medication reconciliation and dietary modification. ',
        CHOOSE((x.r_fu % 3) + 1,
            N'Follow up with primary care within seven days. ',
            N'Follow up in the appropriate specialty clinic in two weeks. ',
            N'Return precautions reviewed; follow up as needed. ')
    ),
    /* CreatedAt: a random instant inside this encounter's stay window */
    DATEADD(SECOND,
        ABS(CHECKSUM(NEWID())) % (ABS(DATEDIFF(SECOND, e.AdmitTime, COALESCE(e.DischargeTime, SYSUTCDATETIME()))) + 1),
        e.AdmitTime)
FROM clinical.Encounter e
CROSS JOIN GENERATE_SERIES(1, 2) gs
CROSS APPLY (SELECT
        cond     = (e.EncounterId * 7 + 1) % 10,   -- aligns with the primary (gs=1) diagnosis
        r_type   = ABS(CHECKSUM(NEWID())),
        r_sub    = ABS(CHECKSUM(NEWID())),
        r_hpi    = ABS(CHECKSUM(NEWID())),
        r_pmh    = ABS(CHECKSUM(NEWID())),
        r_fh     = ABS(CHECKSUM(NEWID())),
        r_gen    = ABS(CHECKSUM(NEWID())),
        r_card   = ABS(CHECKSUM(NEWID())),
        r_lung   = ABS(CHECKSUM(NEWID())),
        r_abd    = ABS(CHECKSUM(NEWID())),
        r_ext    = ABS(CHECKSUM(NEWID())),
        r_assess = ABS(CHECKSUM(NEWID())),
        r_comorb = ABS(CHECKSUM(NEWID())),
        r_plan   = ABS(CHECKSUM(NEWID())),
        r_plan2  = ABS(CHECKSUM(NEWID())),
        r_fu     = ABS(CHECKSUM(NEWID())),
        r_t      = ABS(CHECKSUM(NEWID())),
        r_t2     = ABS(CHECKSUM(NEWID())),
        r_hr     = ABS(CHECKSUM(NEWID())),
        r_bs     = ABS(CHECKSUM(NEWID())),
        r_bd     = ABS(CHECKSUM(NEWID())),
        r_rr     = ABS(CHECKSUM(NEWID())),
        r_sp     = ABS(CHECKSUM(NEWID())),
        r_pn     = ABS(CHECKSUM(NEWID()))
    ) x
CROSS APPLY (SELECT
        /* condition-appropriate vitals with per-row jitter (formats match the REGEXP views) */
        tempInt   = CASE WHEN x.cond IN (3, 4, 5) THEN 38 WHEN x.cond IN (2, 9) THEN 37 ELSE 36 + (x.r_t % 2) END,
        tempTenth = x.r_t2 % 10,
        hr        = CASE WHEN x.cond = 7 THEN 50 + (x.r_hr % 60)
                         WHEN x.cond IN (2, 3, 6, 9) THEN 90 + (x.r_hr % 35)
                         ELSE 62 + (x.r_hr % 40) END,
        bpSys     = CASE WHEN x.cond = 0 THEN 150 + (x.r_bs % 35)
                         WHEN x.cond = 7 THEN 88 + (x.r_bs % 22)
                         ELSE 108 + (x.r_bs % 40) END,
        bpDia     = CASE WHEN x.cond = 0 THEN 92 + (x.r_bd % 18)
                         WHEN x.cond = 7 THEN 52 + (x.r_bd % 16)
                         ELSE 62 + (x.r_bd % 26) END,
        rr        = CASE WHEN x.cond IN (3, 9) THEN 20 + (x.r_rr % 8) ELSE 12 + (x.r_rr % 8) END,
        spo2      = CASE WHEN x.cond IN (2, 3, 9) THEN 86 + (x.r_sp % 8) ELSE 95 + (x.r_sp % 5) END,
        pain      = CASE WHEN x.cond IN (5, 6) THEN 5 + (x.r_pn % 5)
                         WHEN x.cond IN (0, 1, 8) THEN (x.r_pn % 3)
                         ELSE 2 + (x.r_pn % 5) END
    ) v
WHERE ((e.EncounterId + gs.value) % 4) <> 0;   -- ~1.25 notes per encounter
GO

/* ============================================================================
   11. clinical.MedicationOrder  (~100,000 — 2.5 per encounter average)
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
CROSS APPLY (
    /* Dose + route are matched to the drug (a single lookup row) so there are
       no nonsensical combinations like "Insulin glargine 81 mg PO". */
    SELECT d.MedicationName, d.Dose, d.Route
    FROM (VALUES
        ( 1, N'Lisinopril',       N'10 mg',      N'PO'),
        ( 2, N'Atorvastatin',     N'40 mg',      N'PO'),
        ( 3, N'Aspirin',          N'81 mg',      N'PO'),
        ( 4, N'Metoprolol',       N'25 mg',      N'PO'),
        ( 5, N'Furosemide',       N'40 mg',      N'IV'),
        ( 6, N'Insulin glargine', N'20 units',   N'SC'),
        ( 7, N'Ceftriaxone',      N'1 g',        N'IV'),
        ( 8, N'Azithromycin',     N'500 mg',     N'IV'),
        ( 9, N'Ondansetron',      N'4 mg',       N'IV'),
        (10, N'Acetaminophen',    N'650 mg',     N'PO'),
        (11, N'Heparin',          N'5000 units', N'SC'),
        (12, N'Pantoprazole',     N'40 mg',      N'IV')
    ) d(idx, MedicationName, Dose, Route)
    WHERE d.idx = ((e.EncounterId * 7 + gs.value) % 12) + 1
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
        'analytes'    :
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
                WHEN 4 THEN JSON_ARRAY(   -- Troponin I (mostly normal, occasionally elevated)
                    JSON_OBJECT('name': N'Troponin I', 'value': ((e.EncounterId * 7 + gs.value) % 6) / 100.0, 'unit': N'ng/mL', 'refLow': 0.00, 'refHigh': 0.04))
                WHEN 5 THEN JSON_ARRAY(   -- Lipid Panel
                    JSON_OBJECT('name': N'Total Cholesterol', 'value': 150 + ((e.EncounterId * 3  + gs.value) % 90),  'unit': N'mg/dL', 'refLow': 0,  'refHigh': 200),
                    JSON_OBJECT('name': N'LDL',               'value': 80  + ((e.EncounterId * 5  + gs.value) % 80),  'unit': N'mg/dL', 'refLow': 0,  'refHigh': 100),
                    JSON_OBJECT('name': N'HDL',               'value': 40  + ((e.EncounterId * 7  + gs.value) % 30),  'unit': N'mg/dL', 'refLow': 40, 'refHigh': 90),
                    JSON_OBJECT('name': N'Triglycerides',     'value': 90  + ((e.EncounterId * 11 + gs.value) % 120), 'unit': N'mg/dL', 'refLow': 0,  'refHigh': 150))
                WHEN 6 THEN JSON_ARRAY(   -- TSH
                    JSON_OBJECT('name': N'TSH', 'value': 0.5 + (((e.EncounterId * 7 + gs.value) % 45) / 10.0), 'unit': N'mIU/L', 'refLow': 0.4, 'refHigh': 4.0))
            END
    ),
    N'Resulted'
FROM clinical.Encounter e
CROSS JOIN GENERATE_SERIES(1, 5) gs
CROSS APPLY (VALUES ( ((e.EncounterId * 7 + gs.value) % 6) + 1 )) k(ti)
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
       moving and stay within reasonable memory/log governance. On a 4 vCore
       HS_Gen5 primary expect ~5-15 min total at @Scale = 1.0.
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
            WHEN N'HeartRate'   THEN  60 + ((gs.value + e.EncounterId * 3)  % 60)
            WHEN N'SystolicBP'  THEN 110 + ((gs.value + e.EncounterId * 5)  % 50)
            WHEN N'DiastolicBP' THEN  65 + ((gs.value + e.EncounterId * 7)  % 30)
            WHEN N'SpO2'        THEN  90 + ((gs.value + e.EncounterId * 11) % 10)
            WHEN N'Temperature' THEN  36.5 + (((gs.value + e.EncounterId * 13) % 25) / 10.0)
            WHEN N'RespRate'    THEN  12 + ((gs.value + e.EncounterId * 17) % 12)
        END,
        t.Unit
    FROM clinical.Encounter e
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

/* Symptoms: 1-3 presenting complaints per active encounter. */
;WITH activeEnc AS (SELECT EncounterId FROM clinical.Encounter WHERE Status = N'Active')
INSERT INTO clinical.Symptom (EncounterId, Description, Severity, NotedAt)
SELECT
    e.EncounterId, s.Description, s.Severity,
    DATEADD(HOUR, -(ABS(CHECKSUM(NEWID())) % 48), SYSUTCDATETIME())
FROM activeEnc AS e
CROSS APPLY
(
    SELECT TOP (1 + ABS(CHECKSUM(NEWID())) % 3) v.Description, v.Severity
    FROM (VALUES
        (N'Chest pain', N'Moderate'), (N'Shortness of breath', N'Moderate'),
        (N'Fever', N'Mild'), (N'Nausea', N'Mild'), (N'Abdominal pain', N'Moderate'),
        (N'Headache', N'Mild'), (N'Dizziness', N'Mild'), (N'Cough', N'Mild'),
        (N'Fatigue', N'Mild'), (N'Confusion', N'Severe'), (N'Palpitations', N'Moderate'),
        (N'Weakness', N'Mild')
    ) AS v(Description, Severity)
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
    CASE ABS(CHECKSUM(NEWID())) % 3 WHEN 0 THEN N'Completed' WHEN 1 THEN N'InProgress' ELSE N'Ordered' END,
    e.AttendingProviderId,
    DATEADD(HOUR, -(ABS(CHECKSUM(NEWID())) % 36), SYSUTCDATETIME()),
    NULL
FROM activeEnc AS e
CROSS APPLY
(
    SELECT TOP (1 + ABS(CHECKSUM(NEWID())) % 2) v.Modality, v.BodySite
    FROM (VALUES
        (N'XR', N'Chest'), (N'CT', N'Head'), (N'CT', N'Abdomen/Pelvis'),
        (N'MRI', N'Brain'), (N'US', N'Abdomen'), (N'XR', N'Pelvis'), (N'CT', N'Chest')
    ) AS v(Modality, BodySite)
    ORDER BY NEWID()
) AS m;
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
