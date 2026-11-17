-- Run separately in each scheduling database, never with USE.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ARITHABORT ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() NOT IN (N'caldova-scheduling', N'northbrook-scheduling', N'ridgeview-scheduling')
    THROW 50000, 'Connect to one of the three Caldova scheduling databases.', 1;

IF OBJECT_ID(N'dbo.AppointmentSlot', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AppointmentSlot
    (
        SlotId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_AppointmentSlot PRIMARY KEY,
        ClinicId int NOT NULL,
        Clinician nvarchar(100) NOT NULL,
        Specialty nvarchar(80) NOT NULL,
        SlotStart datetime2(0) NOT NULL,
        DurationMinutes int NOT NULL CONSTRAINT CK_AppointmentSlot_Duration CHECK (DurationMinutes > 0),
        IsBooked bit NOT NULL CONSTRAINT DF_AppointmentSlot_IsBooked DEFAULT (0),
        CONSTRAINT UQ_AppointmentSlot UNIQUE (ClinicId, Specialty, SlotStart)
    );
    CREATE INDEX IX_AppointmentSlot_Search
        ON dbo.AppointmentSlot (Specialty, IsBooked, SlotStart)
        INCLUDE (ClinicId, Clinician, DurationMinutes);
END;

-- Written by network bookings from Caldova in the same transaction as the slot update.
IF OBJECT_ID(N'dbo.Appointment', N'U') IS NULL
    CREATE TABLE dbo.Appointment
    (
        AppointmentId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_Appointment PRIMARY KEY,
        SlotId bigint NOT NULL CONSTRAINT FK_Appointment_Slot REFERENCES dbo.AppointmentSlot (SlotId),
        BookedAtUtc datetime2(0) NOT NULL,
        BookedVia nvarchar(40) NOT NULL,
        CONSTRAINT UQ_Appointment_Slot UNIQUE (SlotId)
    );

DECLARE @schedule TABLE (Specialty nvarchar(80), LeadDays int, Clinician nvarchar(100));
IF DB_NAME() = N'caldova-scheduling'
    INSERT @schedule VALUES
        (N'Cardiology', 19, N'Dr. Amara Osei'), (N'Orthopedics', 16, N'Dr. Marco Ruiz'),
        (N'Dermatology', 24, N'Dr. Lena Fischer'), (N'Pediatrics', 9, N'Dr. Priya Raman'),
        (N'Primary Care', 7, N'Dr. Amara Osei');
ELSE IF DB_NAME() = N'northbrook-scheduling'
    INSERT @schedule VALUES
        (N'Pediatrics', 2, N'Dr. Hana Kim'), (N'Primary Care', 1, N'Dr. Samuel Okafor'),
        (N'Dermatology', 6, N'Dr. Elise Martin');
ELSE
    INSERT @schedule VALUES
        (N'Cardiology', 2, N'Dr. Tomas Varga'), (N'Orthopedics', 3, N'Dr. Nadia Petrov'),
        (N'Dermatology', 11, N'Dr. Owen Brennan');

DECLARE @today datetime2(0) = CONVERT(date, SYSUTCDATETIME());
INSERT dbo.AppointmentSlot (ClinicId, Clinician, Specialty, SlotStart, DurationMinutes)
SELECT 1, s.Clinician, s.Specialty, d.SlotStart, 30
FROM @schedule AS s
CROSS JOIN (VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9)) AS n(OffsetDays)
CROSS APPLY (SELECT DATEADD(hour, 9, DATEADD(day, s.LeadDays + n.OffsetDays, @today)) AS SlotStart) AS d
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.AppointmentSlot AS existing
    WHERE existing.ClinicId = 1 AND existing.Specialty = s.Specialty AND existing.SlotStart = d.SlotStart
);

IF DB_NAME() = N'caldova-scheduling'
BEGIN
    IF SCHEMA_ID(N'network') IS NULL EXEC(N'CREATE SCHEMA network AUTHORIZATION dbo;');
    IF OBJECT_ID(N'network.ProviderClinic', N'U') IS NULL
        EXEC(N'CREATE TABLE network.ProviderClinic (
            ProviderKey nvarchar(20) NOT NULL,
            ClinicId int NOT NULL,
            ProviderName nvarchar(100) NOT NULL,
            Location nvarchar(100) NOT NULL,
            IsNetworkMember bit NOT NULL,
            CONSTRAINT PK_ProviderClinic PRIMARY KEY (ProviderKey, ClinicId)
        );');

    EXEC(N'INSERT network.ProviderClinic (ProviderKey, ClinicId, ProviderName, Location, IsNetworkMember)
        SELECT v.ProviderKey, 1, v.ProviderName, v.Location, 1
        FROM (VALUES
            (N''caldova'', N''Caldova Health'', N''Caldova Main Campus''),
            (N''northbrook'', N''Northbrook Family Clinics'', N''Northbrook Elm Street Clinic''),
            (N''ridgeview'', N''Ridgeview Specialty Care'', N''Ridgeview Heart and Vascular'')
        ) AS v(ProviderKey, ProviderName, Location)
        WHERE NOT EXISTS (SELECT 1 FROM network.ProviderClinic AS p WHERE p.ProviderKey = v.ProviderKey AND p.ClinicId = 1);');
END;
GO
