/* ===========================================================================
   Zava Health – Sample Data Seeder (Variety + Volume Edition)
   - Azure SQL compatible
   - High variety in Symptoms, Orders, Notes
   - Parameterized volume
   =========================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRAN;

-- ---------------------------------------------------------------------------
-- Parameters (adjust as needed)
-- ---------------------------------------------------------------------------
DECLARE @PatientCount             INT = 5000;  -- total patients
DECLARE @MaxRoomsPerBuilding      INT = 160;   -- rooms per building
DECLARE @VitalsPerPatientMax      INT = 10;    -- max vitals per patient (>=3)
DECLARE @MaxNotesPerPatient       INT = 4;     -- max notes per patient (>=1)
DECLARE @MaxOrdersPerPatient      INT = 4;     -- max orders per patient (>=0)

-- ---------------------------------------------------------------------------
-- Quick exit if seeded already
-- ---------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM ref.Beds) OR EXISTS (SELECT 1 FROM core.Patients)
BEGIN
    PRINT 'Seed skipped: tables already contain data.';
    ROLLBACK TRAN;
    RETURN;
END;

-- ---------------------------------------------------------------------------
-- Utility: #N numbers table (1..20000)
-- ---------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#N') IS NOT NULL DROP TABLE #N;
CREATE TABLE #N (n INT NOT NULL PRIMARY KEY);
;WITH N AS (
    SELECT TOP (20000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO #N(n) SELECT n FROM N;

-- ---------------------------------------------------------------------------
-- 1) Reference data: Buildings, Rooms, Beds, Lookups
-- ---------------------------------------------------------------------------
INSERT INTO ref.Buildings(Name, AddressLine1, City, StateProvince, PostalCode) VALUES
(N'Building A', N'1000 Serenity Ln',   N'North Richland Hills', N'TX', N'76180'),
(N'Building B', N'1100 Festivus Blvd', N'North Richland Hills', N'TX', N'76180'),
(N'Building C', N'1200 Soup Nazi Dr',  N'North Richland Hills', N'TX', N'76180'),
(N'Building D', N'1300 Vandelay Ave',  N'North Richland Hills', N'TX', N'76180'),
(N'Building E', N'1400 Newman Way',    N'North Richland Hills', N'TX', N'76180');

;WITH R AS (
    SELECT TOP (@MaxRoomsPerBuilding) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS r
    FROM sys.all_objects
),
Rooms AS (
    SELECT 
        b.BuildingID,
        RIGHT(CONCAT('00', R.r), 3) AS RoomNumber,
        CHOOSE(1 + ((CHECKSUM(NEWID()) & 0x7FFFFFFF) % 7),
               N'ICU-1',N'ICU-2',N'Cardio',N'Oncology',N'Pediatrics',N'Med-Surg',N'Ortho') AS Ward
    FROM ref.Buildings b
    CROSS JOIN R
)
INSERT INTO ref.Rooms(BuildingID, RoomNumber, Ward)
SELECT BuildingID, RoomNumber, Ward FROM Rooms;

INSERT INTO ref.Beds(RoomID, BedNumber)
SELECT r.RoomID, s.BedLetter
FROM ref.Rooms r
CROSS APPLY (VALUES (N'A'), (N'B'), (N'C')) AS s(BedLetter);

IF NOT EXISTS (SELECT 1 FROM ref.OrderTypes)
    INSERT INTO ref.OrderTypes(OrderTypeCode, DisplayName)
    VALUES (N'Medication',N'Medication'),(N'Lab',N'Laboratory'),(N'Imaging',N'Imaging'),(N'Procedure',N'Procedure');

IF NOT EXISTS (SELECT 1 FROM ref.AlertSeverities)
    INSERT INTO ref.AlertSeverities(SeverityCode, Rank, DisplayName)
    VALUES (N'Critical',10,N'Critical'),(N'High',7,N'High'),(N'Medium',5,N'Medium'),(N'Low',2,N'Low');

IF NOT EXISTS (SELECT 1 FROM ref.ProviderRoles)
    INSERT INTO ref.ProviderRoles(RoleName)
    VALUES (N'Intern'),(N'Resident'),(N'Associate'),(N'Attending'),(N'Consultant');

-- Cache Role IDs
DECLARE @RoleIntern     INT = (SELECT RoleID FROM ref.ProviderRoles WHERE RoleName = N'Intern');
DECLARE @RoleResident   INT = (SELECT RoleID FROM ref.ProviderRoles WHERE RoleName = N'Resident');
DECLARE @RoleAssociate  INT = (SELECT RoleID FROM ref.ProviderRoles WHERE RoleName = N'Associate');
DECLARE @RoleAttending  INT = (SELECT RoleID FROM ref.ProviderRoles WHERE RoleName = N'Attending');
DECLARE @RoleConsultant INT = (SELECT RoleID FROM ref.ProviderRoles WHERE RoleName = N'Consultant');

-- ---------------------------------------------------------------------------
-- 2) Providers & supervision chain
-- ---------------------------------------------------------------------------
INSERT INTO core.Providers(FullName, RoleID, SupervisorProviderID, ContactInfo)
VALUES (N'Dr. Art Vandelay', @RoleAssociate, NULL, N'art.vandelay@hospital.example');
DECLARE @ProvArt INT = SCOPE_IDENTITY();

INSERT INTO core.Providers(FullName, RoleID, SupervisorProviderID, ContactInfo)
VALUES (N'Dr. Newman', @RoleResident, @ProvArt, N'dr.newman@hospital.example');
DECLARE @ProvNewman INT = SCOPE_IDENTITY();

INSERT INTO core.Providers(FullName, RoleID, SupervisorProviderID, ContactInfo)
VALUES (N'Dr. Kramer', @RoleIntern, @ProvNewman, N'dr.kramer@hospital.example');
DECLARE @ProvKramer INT = SCOPE_IDENTITY();

INSERT INTO core.Providers(FullName, RoleID, SupervisorProviderID, ContactInfo)
VALUES 
(N'Dr. Tim Whatley', @RoleAttending, NULL, N'tim.whatley@hospital.example'),
(N'Dr. Reston', @RoleConsultant, NULL, N'reston@hospital.example'),
(N'Dr. Siegel', @RoleAttending, NULL, N'siegel@hospital.example'),
(N'Dr. Martin Van Nostrand', @RoleAssociate, NULL, N'mvn@hospital.example'),
(N'Dr. Cooperman', @RoleAttending, NULL, N'cooperman@hospital.example'),
(N'Dr. Sitarides', @RoleAssociate, NULL, N'sitarides@hospital.example'),
(N'Dr. Akiva', @RoleResident, @ProvArt, N'akiva@hospital.example'),
(N'Dr. Wexler', @RoleResident, @ProvArt, N'wexler@hospital.example'),
(N'Dr. Alvarez', @RoleAttending, NULL, N'alvarez@hospital.example'),
(N'Dr. Bison', @RoleConsultant, NULL, N'bison@hospital.example');

DECLARE @ProviderIds TABLE (ProviderID INT PRIMARY KEY);
INSERT INTO @ProviderIds SELECT ProviderID FROM core.Providers WHERE IsActive = 1;

-- ---------------------------------------------------------------------------
-- 3) Patients, Encounters, Bed Assignments
-- ---------------------------------------------------------------------------

-- Name pools (Seinfeld-themed core + diverse names for realistic demo)
DECLARE @Fn TABLE (ix INT IDENTITY(1,1) PRIMARY KEY, v NVARCHAR(100));
INSERT INTO @Fn(v) VALUES
(N'Jerry'),(N'George'),(N'Elaine'),(N'Cosmo'),(N'Susan'),(N'Frank'),(N'Estelle'),(N'Helen'),(N'Jackie'),(N'Kenny'),
(N'Leo'),(N'Mickey'),(N'Bob'),(N'Gina'),(N'Carol'),(N'Rachel'),(N'Jane'),(N'Jimmy'),(N'David'),(N'Donna'),
(N'Maria'),(N'James'),(N'Patricia'),(N'Robert'),(N'Jennifer'),(N'Michael'),(N'Linda'),(N'William'),(N'Elizabeth'),(N'Richard'),
(N'Barbara'),(N'Thomas'),(N'Sarah'),(N'Daniel'),(N'Lisa'),(N'Matthew'),(N'Karen'),(N'Anthony'),(N'Nancy'),(N'Mark'),
(N'Sandra'),(N'Paul'),(N'Betty'),(N'Andrew'),(N'Dorothy'),(N'Joshua'),(N'Kimberly'),(N'Kevin'),(N'Brian'),(N'Angela');
DECLARE @FnCount INT = (SELECT COUNT(*) FROM @Fn);

DECLARE @Ln TABLE (ix INT IDENTITY(1,1) PRIMARY KEY, v NVARCHAR(100));
INSERT INTO @Ln(v) VALUES
(N'Seinfeld'),(N'Costanza'),(N'Benes'),(N'Kramer'),(N'Ross'),(N'Puddy'),(N'Chiles'),(N'Bhatt'),(N'Bania'),(N'Abbott'),
(N'Lane'),(N'Cohen'),(N'Lippman'),(N'Mandelbaum'),(N'Hernandez'),(N'Chang'),(N'Holland'),(N'Kruger'),(N'Steinbrenner'),(N'Davola'),
(N'Smith'),(N'Johnson'),(N'Williams'),(N'Brown'),(N'Jones'),(N'Garcia'),(N'Miller'),(N'Davis'),(N'Rodriguez'),(N'Martinez'),
(N'Anderson'),(N'Taylor'),(N'Thomas'),(N'Jackson'),(N'White'),(N'Harris'),(N'Martin'),(N'Thompson'),(N'Lee'),(N'Clark'),
(N'Walker'),(N'Hall'),(N'Allen'),(N'Young'),(N'King'),(N'Wright'),(N'Lopez'),(N'Hill'),(N'Scott'),(N'Green');
DECLARE @LnCount INT = (SELECT COUNT(*) FROM @Ln);

;WITH Tally AS (
    SELECT TOP (@PatientCount) n AS rn
    FROM #N
)
INSERT INTO core.Patients (MRN, FirstName, LastName, DOB, Gender, ContactInfo, Allergies)
SELECT
    CONCAT(N'MRN-', RIGHT(CONCAT('0000000', t.rn), 7))                                        AS MRN,
    fn.v                                                                                      AS FirstName,
    ln.v                                                                                      AS LastName,
    DATEADD(DAY, -1 * (18*365 + ABS(CHECKSUM(t.rn, 17)) % (70*365)), CAST(SYSUTCDATETIME() AS DATE)) AS DOB,
    CHOOSE(1 + ABS(CHECKSUM(t.rn, 23)) % 3, N'Male', N'Female', N'Other')                     AS Gender,
    CONCAT(N'555-', RIGHT(CONCAT('0000', ABS(CHECKSUM(t.rn, 29)) % 10000), 4))                AS ContactInfo,
    CASE
      WHEN ABS(CHECKSUM(t.rn, 31)) % 100 < 12 THEN N'Penicillin'
      WHEN ABS(CHECKSUM(t.rn, 37)) % 100 < 20 THEN N'Latex'
      WHEN ABS(CHECKSUM(t.rn, 41)) % 100 < 26 THEN N'Peanuts'
      WHEN ABS(CHECKSUM(t.rn, 43)) % 100 < 31 THEN N'Sulfa'
      ELSE NULL
    END                                                                                       AS Allergies
FROM Tally AS t
CROSS APPLY (
    SELECT v FROM @Fn
    WHERE ix = 1 + (CHECKSUM(CONCAT(t.rn, N'fn')) & 0x7FFFFFFF) % @FnCount
) AS fn(v)
CROSS APPLY (
    SELECT v FROM @Ln
    WHERE ix = 1 + (CHECKSUM(CONCAT(t.rn, N'ln')) & 0x7FFFFFFF) % @LnCount
) AS ln(v);

INSERT INTO core.Encounters(PatientID, AdmitDate, DischargeDate, Reason)
SELECT 
    p.PatientID,
    DATEADD(HOUR, -1 * ((CHECKSUM(NEWID()) & 0x7FFFFFFF) % 96), SYSUTCDATETIME()),
    NULL,
    CHOOSE(1 + (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 8,
           N'Respiratory', N'Cardiac', N'Infection', N'Elective surgery', N'Trauma', N'Observation', N'GI', N'Neurology')
FROM core.Patients p;

;WITH P AS (
    SELECT PatientID, ROW_NUMBER() OVER (ORDER BY PatientID) AS rn FROM core.Patients
),
B AS (
    SELECT BedID, ROW_NUMBER() OVER (ORDER BY BedID) AS rn FROM ref.Beds
),
E AS (
    SELECT PatientID, EncounterID, AdmitDate FROM core.Encounters WHERE DischargeDate IS NULL
)
INSERT INTO core.BedAssignments(BedID, PatientID, EncounterID, AdmitDate)
SELECT b.BedID, p.PatientID, e.EncounterID, e.AdmitDate
FROM P
JOIN B ON B.rn = P.rn
JOIN E ON E.PatientID = P.PatientID
WHERE P.rn <= (SELECT COUNT(*) FROM ref.Beds);

-- ---------------------------------------------------------------------------
-- 4) Clinical: Symptoms (0–5 unique per patient) – Expanded & varied
-- ---------------------------------------------------------------------------
DECLARE @SymptomsMaster TABLE (Code NVARCHAR(50), Description NVARCHAR(500), Weight TINYINT);
INSERT INTO @SymptomsMaster VALUES
(N'Fever',N'Fever',20),(N'Cough',N'Cough',25),(N'Dyspnea',N'Shortness of breath',18),(N'ChestPain',N'Chest pain',12),
(N'Nausea',N'Nausea',10),(N'Headache',N'Headache',18),(N'Fatigue',N'Fatigue',22),(N'Dizziness',N'Dizziness',14),
(N'SoreThroat',N'Sore throat',15),(N'Edema',N'Peripheral edema',8),
(N'AbdominalPain',N'Abdominal pain',16),(N'Vomiting',N'Vomiting',9),(N'Diarrhea',N'Diarrhea',8),
(N'BackPain',N'Back pain',12),(N'Myalgia',N'Muscle aches',10),(N'Rash',N'Skin rash',6),
(N'Confusion',N'Acute confusion',5),(N'Syncope',N'Fainting',4),(N'Palpitations',N'Palpitations',7),
(N'Anxiety',N'Anxiety',6),(N'Insomnia',N'Insomnia',5),(N'Anorexia',N'Loss of appetite',6),
(N'Constipation',N'Constipation',5),(N'Hematuria',N'Blood in urine',3),(N'Melena',N'Black stools',2),
(N'Arthralgia',N'Joint pain',8),(N'Photophobia',N'Sensitivity to light',3),(N'Otalgia',N'Ear pain',2),
(N'Odynophagia',N'Painful swallowing',2),(N'Paresthesia',N'Numbness or tingling',4);

;WITH E1 AS (
    SELECT e.EncounterID, e.PatientID
    FROM core.Encounters e
    WHERE e.DischargeDate IS NULL
),
K1 AS (
    SELECT PatientID, EncounterID,
           (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 6 AS k  -- 0..5
    FROM E1
),
Pool1 AS (
    SELECT 
       e.PatientID, e.EncounterID,
       sm.Code, sm.Description,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 100 AS rScore,
       sm.Weight
    FROM E1 e
    CROSS JOIN @SymptomsMaster sm
)
INSERT INTO clinical.Symptoms (PatientID, EncounterID, Code, Description, RecordedAt)
SELECT x.PatientID, x.EncounterID, x.Code, x.Description,
       DATEADD(HOUR, -1 * ((CHECKSUM(NEWID()) & 0x7FFFFFFF) % 36), SYSUTCDATETIME())
FROM (
    SELECT p.PatientID, p.EncounterID, p.Code, p.Description,
           ROW_NUMBER() OVER (PARTITION BY p.PatientID, p.EncounterID ORDER BY (p.rScore - (100 - p.Weight)) DESC) AS rn,
           k.k
    FROM Pool1 p
    JOIN K1 k ON k.PatientID = p.PatientID AND k.EncounterID = p.EncounterID
) x
WHERE x.rn <= x.k;

-- ---------------------------------------------------------------------------
-- 5) Clinical: Orders (with non-null Status)
-- ---------------------------------------------------------------------------
DECLARE @OrderDetails TABLE (Detail NVARCHAR(200));
INSERT INTO @OrderDetails VALUES
(N'CBC panel'),(N'BMP panel'),(N'LFT panel'),(N'Troponin I'),(N'D-dimer'),
(N'Chest X-ray PA/LAT'),(N'CT Abdomen/Pelvis'),(N'CT Head (non-contrast)'),(N'MRI Brain'),
(N'IV ceftriaxone 1g q24h'),(N'IV piperacillin-tazobactam 3.375g q6h'),(N'PO azithromycin 500mg daily'),
(N'Ultrasound RUQ'),(N'Echocardiogram'),(N'Urinalysis with culture');

;WITH E2 AS (
    SELECT e.EncounterID, e.PatientID
    FROM core.Encounters e
    WHERE e.DischargeDate IS NULL
),
K2 AS (
    SELECT PatientID, EncounterID,
           (CHECKSUM(NEWID()) & 0x7FFFFFFF) % (@MaxOrdersPerPatient + 1) AS k
    FROM E2
),
Pool2 AS (
    SELECT e.PatientID, e.EncounterID,
           (SELECT TOP 1 OrderTypeCode FROM ref.OrderTypes WHERE IsActive = 1 ORDER BY NEWID()) AS OrderTypeCode,
           (SELECT TOP 1 Detail FROM @OrderDetails ORDER BY NEWID()) AS Details,
           (SELECT TOP 1 ProviderID FROM @ProviderIds ORDER BY NEWID()) AS ProviderID,
           (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 100 AS r
    FROM E2 e
)
INSERT INTO clinical.Orders (PatientID, EncounterID, OrderTypeCode, Details, ProviderID, OrderedAt, Status)
SELECT x.PatientID, x.EncounterID, x.OrderTypeCode, x.Details, x.ProviderID,
       DATEADD(HOUR, -1 * ((CHECKSUM(NEWID()) & 0x7FFFFFFF) % 48), SYSUTCDATETIME()),
       ISNULL(CHOOSE(1 + (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 4,
                     N'Pending', N'InProgress', N'Completed', N'Cancelled'), N'Pending')
FROM (
    SELECT p.*, ROW_NUMBER() OVER (PARTITION BY p.PatientID, p.EncounterID ORDER BY p.r DESC) AS rn, k.k
    FROM Pool2 p
    JOIN K2 k ON k.PatientID = p.PatientID AND k.EncounterID = p.EncounterID
) x
WHERE x.rn <= x.k;

-- ---------------------------------------------------------------------------
-- 6) Clinical: Vitals (3–@VitalsPerPatientMax snapshots per patient)
-- ---------------------------------------------------------------------------
;WITH E3 AS (
    SELECT e.EncounterID, e.PatientID, e.AdmitDate
    FROM core.Encounters e
    WHERE e.DischargeDate IS NULL
),
K3 AS (
    SELECT PatientID, EncounterID,
           3 + ((CHECKSUM(NEWID()) & 0x7FFFFFFF) % (@VitalsPerPatientMax - 2)) AS k
    FROM E3
)
INSERT INTO clinical.VitalsSnapshots (
    PatientID, EncounterID, HeartRate, BloodPressure, SpO2, TemperatureC, RespiratoryRate, RecordedAt, Source
)
SELECT e.PatientID, e.EncounterID,
       55 + ((CHECKSUM(NEWID()) & 0x7FFFFFFF) % 75),
       CONCAT(95 + ((CHECKSUM(NEWID()) & 0x7FFFFFFF) % 60), N'/', 55 + ((CHECKSUM(NEWID()) & 0x7FFFFFFF) % 40)),
       CAST( (8700 + ((CHECKSUM(NEWID()) & 0x7FFFFFFF) % 1301)) / 100.0 AS DECIMAL(5,2)),
       CAST(35.8 + ((CHECKSUM(NEWID()) & 0x7FFFFFFF) % 35) / 10.0 AS DECIMAL(4,1)),
       10 + ((CHECKSUM(NEWID()) & 0x7FFFFFFF) % 18),
       DATEADD(MINUTE, -1 * (#N.n * (1 + ABS(CHECKSUM(e.PatientID)) % 3)), SYSUTCDATETIME()),
       CHOOSE(1 + (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 2, N'Nurse', N'Monitor')
FROM E3 e
JOIN K3 k ON k.PatientID = e.PatientID AND k.EncounterID = e.EncounterID
JOIN #N ON #N.n <= k.k;

-- ---------------------------------------------------------------------------
-- 7) Clinical: Doctor Notes – unique per encounter using actual clinical data
-- ---------------------------------------------------------------------------

-- Build encounter-specific context for realistic note generation
;WITH EncContext AS (
    SELECT
        e.EncounterID,
        e.PatientID,
        e.Reason,
        p.FirstName,
        p.LastName,
        p.Gender,
        p.Allergies,
        DATEDIFF(YEAR, p.DOB, SYSUTCDATETIME()) AS Age
    FROM core.Encounters e
    JOIN core.Patients p ON p.PatientID = e.PatientID
    WHERE e.DischargeDate IS NULL
),
EncVitals AS (
    SELECT
        vs.EncounterID,
        vs.HeartRate,
        vs.BloodPressure,
        vs.SpO2,
        vs.TemperatureC,
        vs.RespiratoryRate,
        ROW_NUMBER() OVER (PARTITION BY vs.EncounterID ORDER BY vs.RecordedAt DESC) AS rn
    FROM clinical.VitalsSnapshots vs
),
EncSymptoms AS (
    SELECT
        s.EncounterID,
        STRING_AGG(s.Description, N', ') WITHIN GROUP (ORDER BY s.Code) AS SymList
    FROM clinical.Symptoms s
    GROUP BY s.EncounterID
),
EncOrders AS (
    SELECT
        o.EncounterID,
        STRING_AGG(o.Details, N'; ') AS OrdList
    FROM clinical.Orders o
    GROUP BY o.EncounterID
)
-- Note 1: Initial assessment (every encounter gets one)
INSERT INTO clinical.DoctorNotes (PatientID, EncounterID, ProviderID, NoteText, CreatedAt)
SELECT
    c.PatientID,
    c.EncounterID,
    (SELECT TOP 1 ProviderID FROM @ProviderIds ORDER BY NEWID()),
    CONCAT(
        N'Initial assessment for ', c.FirstName, N' ', c.LastName,
        N' (', c.Age, N'y ', ISNULL(c.Gender, N''), N'). ',
        N'Chief complaint: ', ISNULL(c.Reason, N'not documented'), N'. ',
        N'Presenting symptoms: ', ISNULL(sy.SymList, N'none reported'), N'. ',
        CASE WHEN c.Allergies IS NOT NULL
             THEN CONCAT(N'Known allergies: ', c.Allergies, N'. ')
             ELSE N'No known drug allergies. ' END,
        N'Vitals on admission: HR ', ISNULL(CONVERT(NVARCHAR(10), v.HeartRate), N'--'),
        N', BP ', ISNULL(v.BloodPressure, N'--'),
        N', SpO2 ', ISNULL(CONVERT(NVARCHAR(10), v.SpO2), N'--'),
        N'%, Temp ', ISNULL(CONVERT(NVARCHAR(10), v.TemperatureC), N'--'),
        N'C, RR ', ISNULL(CONVERT(NVARCHAR(10), v.RespiratoryRate), N'--'), N'. ',
        CHOOSE(1 + ABS(CHECKSUM(c.EncounterID)) % 6,
            N'Plan: admit for observation and serial exams.',
            N'Plan: IV access established, labs drawn, awaiting results.',
            N'Plan: start empiric therapy pending cultures.',
            N'Plan: imaging ordered, monitoring vitals q4h.',
            N'Plan: consult specialty service, continue supportive care.',
            N'Plan: begin treatment protocol, reassess in 4 hours.'
        )
    ),
    DATEADD(HOUR, -1 * (24 + ABS(CHECKSUM(c.EncounterID)) % 24), SYSUTCDATETIME())
FROM EncContext c
LEFT JOIN (SELECT * FROM EncVitals WHERE rn = 1) v ON v.EncounterID = c.EncounterID
LEFT JOIN EncSymptoms sy ON sy.EncounterID = c.EncounterID;

-- Note 2: Progress note (every encounter, different provider, 6-12h later)
;WITH EncContext AS (
    SELECT e.EncounterID, e.PatientID, e.Reason,
           p.FirstName, p.LastName
    FROM core.Encounters e
    JOIN core.Patients p ON p.PatientID = e.PatientID
    WHERE e.DischargeDate IS NULL
),
EncVitals AS (
    SELECT vs.EncounterID, vs.HeartRate, vs.BloodPressure, vs.SpO2,
           vs.TemperatureC, vs.RespiratoryRate,
           ROW_NUMBER() OVER (PARTITION BY vs.EncounterID ORDER BY vs.RecordedAt DESC) AS rn
    FROM clinical.VitalsSnapshots vs
),
EncOrders AS (
    SELECT o.EncounterID,
           STRING_AGG(CONCAT(o.OrderTypeCode, N': ', LEFT(o.Details, 100)), N'; ') AS OrdList
    FROM clinical.Orders o
    GROUP BY o.EncounterID
)
INSERT INTO clinical.DoctorNotes (PatientID, EncounterID, ProviderID, NoteText, CreatedAt)
SELECT
    c.PatientID,
    c.EncounterID,
    (SELECT TOP 1 ProviderID FROM @ProviderIds ORDER BY NEWID()),
    CONCAT(
        CHOOSE(1 + rng.r1,
            N'Progress note. ', N'Follow-up evaluation. ',
            N'Interval update. ', N'Reassessment note. '),
        N'Patient ', c.FirstName, N' ', c.LastName,
        CHOOSE(1 + rng.r2,
            N' is resting comfortably. ',
            N' reports mild improvement. ',
            N' remains stable. ',
            N' is alert and cooperative. ',
            N' appears fatigued but oriented. '),
        N'Current vitals: HR ', ISNULL(CONVERT(NVARCHAR(10), v.HeartRate), N'--'),
        N', BP ', ISNULL(v.BloodPressure, N'--'),
        N', SpO2 ', ISNULL(CONVERT(NVARCHAR(10), v.SpO2), N'--'),
        N'%, Temp ', ISNULL(CONVERT(NVARCHAR(10), v.TemperatureC), N'--'), N'C. ',
        CASE WHEN v.HeartRate > 100 THEN N'Tachycardia noted; monitoring closely. '
             WHEN v.HeartRate < 60  THEN N'Bradycardia noted; cardiac consult considered. '
             ELSE N'Heart rate within normal limits. ' END,
        CASE WHEN v.SpO2 < 94.0 THEN N'Hypoxia — supplemental O2 titrated. '
             ELSE N'' END,
        CASE WHEN v.TemperatureC > 38.0 THEN N'Febrile; blood cultures sent, antipyretics administered. '
             ELSE N'' END,
        N'Active orders: ', ISNULL(LEFT(o.OrdList, 300), N'none pending'), N'. ',
        CHOOSE(1 + rng.r3,
            N'Continue current plan.',
            N'Adjusting medications per response.',
            N'Will reassess on next rounding.',
            N'Discussed plan with patient and family.'
        )
    ),
    DATEADD(HOUR, -1 * (12 + rng.r4), SYSUTCDATETIME())
FROM EncContext c
LEFT JOIN (SELECT * FROM EncVitals WHERE rn = 1) v ON v.EncounterID = c.EncounterID
LEFT JOIN EncOrders o ON o.EncounterID = c.EncounterID
CROSS APPLY (
    SELECT (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 4  AS r1,
           (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 5  AS r2,
           (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 4  AS r3,
           (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 12 AS r4
) AS rng;

-- Note 3: Specialty/procedure notes (random 60% of encounters)
;WITH EncContext AS (
    SELECT e.EncounterID, e.PatientID, e.Reason,
           p.FirstName, p.LastName, p.Allergies,
           DATEDIFF(YEAR, p.DOB, SYSUTCDATETIME()) AS Age
    FROM core.Encounters e
    JOIN core.Patients p ON p.PatientID = e.PatientID
    WHERE e.DischargeDate IS NULL
),
EncSymptoms AS (
    SELECT s.EncounterID,
           STRING_AGG(s.Description, N', ') WITHIN GROUP (ORDER BY s.Code) AS SymList
    FROM clinical.Symptoms s
    GROUP BY s.EncounterID
)
INSERT INTO clinical.DoctorNotes (PatientID, EncounterID, ProviderID, NoteText, CreatedAt)
SELECT
    c.PatientID,
    c.EncounterID,
    (SELECT TOP 1 ProviderID FROM @ProviderIds ORDER BY NEWID()),
    CONCAT(
        CHOOSE(1 + rng.r1,
            N'Cardiology consult: Reviewed ECG — ',
            N'Pulmonology note: Chest X-ray reviewed — ',
            N'Nephrology consult: Renal panel reviewed — ',
            N'Infectious disease note: Culture results reviewed — ',
            N'Surgical consult: Abdominal imaging reviewed — ',
            N'Neurology consult: Neuro exam performed — ',
            N'GI consult: Endoscopy report reviewed — ',
            N'Orthopedic consult: Imaging reviewed — '),
        CHOOSE(1 + rng.r2,
            N'no acute findings. ',
            N'mild abnormalities noted. ',
            N'findings consistent with clinical presentation. ',
            N'results pending further workup. ',
            N'improvement compared to prior study. ',
            N'new finding requires monitoring. ',
            N'stable compared to baseline. ',
            N'concerning changes — closer follow-up recommended. '),
        N'Patient ', c.FirstName, N' ', c.LastName, N' (',  c.Age, N'y). ',
        N'Admitted for: ', ISNULL(c.Reason, N'evaluation'), N'. ',
        N'Symptoms: ', ISNULL(sy.SymList, N'as noted in chart'), N'. ',
        CASE WHEN c.Allergies IS NOT NULL
             THEN CONCAT(N'Allergy alert: ', c.Allergies, N'. ')
             ELSE N'' END,
        CHOOSE(1 + rng.r3,
            N'Recommend: continue current management, recheck labs in 12h.',
            N'Recommend: adjust medication dosing, monitor renal function.',
            N'Recommend: serial imaging in 24-48h to track progression.',
            N'Recommend: initiate targeted therapy, reassess response in 24h.',
            N'Recommend: physical therapy evaluation, mobilize as tolerated.',
            N'Recommend: dietary modification, follow up with nutrition team.'
        )
    ),
    DATEADD(HOUR, -1 * (6 + rng.r4), SYSUTCDATETIME())
FROM EncContext c
LEFT JOIN EncSymptoms sy ON sy.EncounterID = c.EncounterID
CROSS APPLY (
    SELECT (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 8  AS r1,
           (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 8  AS r2,
           (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 6  AS r3,
           (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 18 AS r4,
           (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 100 AS r5
) AS rng
WHERE rng.r5 < 60;

-- Note 4: Nursing/supervision chain notes (smaller batch, still unique)
INSERT INTO clinical.DoctorNotes (PatientID, EncounterID, ProviderID, NoteText, CreatedAt)
SELECT TOP (400) e.PatientID, e.EncounterID, @ProvKramer,
    CONCAT(
        N'Intern update: Patient ', p.FirstName, N' ', p.LastName,
        N' seen and examined. ',
        CHOOSE(1 + rng.r1,
            N'No acute changes. Vital signs stable. ',
            N'Patient reports improved pain control. ',
            N'Mild agitation noted, redirected. ',
            N'Tolerating oral intake. Bowel sounds active. ',
            N'Wound site clean, no signs of infection. ',
            N'Patient requesting update on discharge timeline. '),
        N'Supervising resident notified. ',
        N'Admitted for: ', ISNULL(e.Reason, N'observation'), N'.'
    ),
    DATEADD(HOUR, -2 - rng.r2, SYSUTCDATETIME())
FROM core.Encounters e
JOIN core.Patients p ON p.PatientID = e.PatientID
CROSS APPLY (
    SELECT (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 6 AS r1,
           (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 6 AS r2
) AS rng
WHERE e.DischargeDate IS NULL
ORDER BY NEWID();

INSERT INTO clinical.DoctorNotes (PatientID, EncounterID, ProviderID, NoteText, CreatedAt)
SELECT TOP (300) e.PatientID, e.EncounterID, @ProvNewman,
    CONCAT(
        N'Resident addendum for ', p.FirstName, N' ', p.LastName, N'. ',
        N'Agrees with intern assessment. ',
        CHOOSE(1 + rng.r1,
            N'Continue IV antibiotics per protocol. ',
            N'Step-down to oral medications if tolerating PO. ',
            N'Hold diuretics pending AM labs. ',
            N'Increase monitoring frequency to q2h. ',
            N'Pain regimen adjusted — added scheduled acetaminophen. ',
            N'Clear liquid diet advanced to regular. '),
        N'Plan discussed with attending. ',
        N'Primary diagnosis: ', ISNULL(e.Reason, N'under evaluation'), N'.'
    ),
    DATEADD(HOUR, -1 - rng.r2, SYSUTCDATETIME())
FROM core.Encounters e
JOIN core.Patients p ON p.PatientID = e.PatientID
CROSS APPLY (
    SELECT (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 6 AS r1,
           (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 4 AS r2
) AS rng
WHERE e.DischargeDate IS NULL
ORDER BY NEWID();

INSERT INTO clinical.DoctorNotes (PatientID, EncounterID, ProviderID, NoteText, CreatedAt)
SELECT TOP (200) e.PatientID, e.EncounterID, @ProvArt,
    CONCAT(
        N'Attending review: ', p.FirstName, N' ', p.LastName, N'. ',
        CHOOSE(1 + rng.r1,
            N'Care plan appropriate. Continue current course. ',
            N'Discussed case with team — agree to broaden coverage. ',
            N'Patient improving. Target discharge within 24-48h. ',
            N'Escalation criteria reviewed with nursing staff. ',
            N'Family meeting held; goals of care discussed. ',
            N'Complex case — multidisciplinary conference scheduled. '),
        N'Maintain current therapy; escalate if vitals decline. ',
        N'Encounter reason: ', ISNULL(e.Reason, N'multifactorial'), N'.'
    ),
    SYSUTCDATETIME()
FROM core.Encounters e
JOIN core.Patients p ON p.PatientID = e.PatientID
CROSS APPLY (
    SELECT (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 6 AS r1
) AS rng
WHERE e.DischargeDate IS NULL
ORDER BY NEWID();

-- ---------------------------------------------------------------------------
-- 8) Clinical: Alerts (robust version using CROSS APPLY; no multi-CTE)
-- ---------------------------------------------------------------------------

-- Build latest vitals per patient from VitalsSnapshots
IF OBJECT_ID('tempdb..#Lv1') IS NOT NULL DROP TABLE #Lv1;

SELECT
    e.PatientID,
    v.EncounterID,
    v.HeartRate,
    v.SpO2,
    v.TemperatureC
INTO #Lv1
FROM core.Encounters AS e
CROSS APPLY (
    SELECT TOP (1)
           vs.EncounterID,
           vs.HeartRate,
           vs.SpO2,
           vs.TemperatureC
    FROM clinical.VitalsSnapshots AS vs
    WHERE vs.PatientID = e.PatientID
    ORDER BY vs.RecordedAt DESC
) AS v
WHERE e.DischargeDate IS NULL;

-- Insert active alerts based on latest vitals
INSERT INTO clinical.Alerts
(
    PatientID,
    EncounterID,
    AlertType,
    SeverityCode,
    Message,
    CreatedAt,
    Resolved,
    ResolvedAt,
    ResolvedBy
)
SELECT
    l.PatientID,
    l.EncounterID,
    CASE 
        WHEN l.SpO2 < 88 THEN N'Critical Low SpO2'
        WHEN l.SpO2 < 92 THEN N'Low SpO2'
        WHEN l.TemperatureC >= 39.5 THEN N'High Fever'
        WHEN l.TemperatureC >= 38.5 THEN N'Fever'
        WHEN l.HeartRate >= 140 THEN N'Tachycardia Severe'
        WHEN l.HeartRate >= 120 THEN N'Tachycardia'
    END AS AlertType,
    CASE 
        WHEN l.SpO2 < 88 OR l.HeartRate >= 140 OR l.TemperatureC >= 39.5 THEN N'High'
        ELSE N'Medium'
    END AS SeverityCode,
    CONCAT(N'Latest vitals — HR:', l.HeartRate, N', SpO2:', l.SpO2, N', Temp:', l.TemperatureC) AS Message,
    SYSUTCDATETIME() AS CreatedAt,
    0 AS Resolved,
    NULL AS ResolvedAt,
    NULL AS ResolvedBy
FROM #Lv1 AS l
WHERE (l.SpO2 < 92) OR (l.TemperatureC >= 38.5) OR (l.HeartRate >= 120);

-- ~12% resolved informational alerts
INSERT INTO clinical.Alerts
(
    PatientID,
    EncounterID,
    AlertType,
    SeverityCode,
    Message,
    CreatedAt,
    Resolved,
    ResolvedAt,
    ResolvedBy
)
SELECT
    e.PatientID,
    e.EncounterID,
    N'Order Follow-up',
    N'Low',
    N'Lab result reviewed; no further action.',
    DATEADD(HOUR, -4, SYSUTCDATETIME()),
    1,
    SYSUTCDATETIME(),
    N'Auto-Resolver'
FROM core.Encounters AS e
WHERE e.DischargeDate IS NULL
  AND ((CHECKSUM(NEWID()) & 0x7FFFFFFF) % 100) < 12;

COMMIT TRAN;

-- Optional sanity probes
-- SELECT COUNT(*) AS Buildings    FROM ref.Buildings;
-- SELECT COUNT(*) AS Rooms        FROM ref.Rooms;
-- SELECT COUNT(*) AS Beds         FROM ref.Beds;
-- SELECT COUNT(*) AS Patients     FROM core.Patients;
-- SELECT COUNT(*) AS EncOpen      FROM core.Encounters WHERE DischargeDate IS NULL;
-- SELECT COUNT(*) AS AssignOpen   FROM core.BedAssignments WHERE DischargeDate IS NULL;
-- SELECT COUNT(*) AS Vitals       FROM clinical.VitalsSnapshots;
-- SELECT COUNT(*) AS Notes        FROM clinical.DoctorNotes;
-- SELECT COUNT(*) AS Symptoms     FROM clinical.Symptoms;
-- SELECT COUNT(*) AS Orders       FROM clinical.Orders;
