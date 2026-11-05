CREATE OR ALTER PROCEDURE clinical.usp_GetCurrentPatientVitals
    @PatientID  INT          = NULL,     -- optional: filter by PatientID
    @MRN        NVARCHAR(50) = NULL,     -- optional: filter by MRN
    @BedID      INT          = NULL,     -- optional: filter by current BedID
    @MaxRows    INT          = 1000      -- safety cap when no patient filter is provided
AS
BEGIN
    SET NOCOUNT ON;

    /*
        Returns the latest vitals snapshot per patient (one row per patient),
        restricted to OPEN encounters only.

        Filters:
          - @PatientID : specific patient
          - @MRN       : specific MRN
          - @BedID     : whoever is currently in this bed
          - @MaxRows   : cap when broad querying

        RLS is enforced automatically by your security policy.
    */

    -- Decide how many rows to return
    DECLARE @RowsToReturn INT =
        CASE WHEN @PatientID IS NULL AND @MRN IS NULL AND @BedID IS NULL
             THEN @MaxRows ELSE 2147483647 END; -- unlimited if filtered

    -- Base patients with open encounters and optional filters
    ;WITH Base AS
    (
        SELECT DISTINCT
               p.PatientID,
               p.MRN,
               p.FirstName,
               p.LastName,
               e.EncounterID
        FROM core.Patients   AS p
        JOIN core.Encounters AS e
          ON e.PatientID = p.PatientID
         AND e.DischargeDate IS NULL
        LEFT JOIN core.BedAssignments AS ba
          ON ba.PatientID = p.PatientID
         AND ba.DischargeDate IS NULL
        WHERE
            (@PatientID IS NULL OR p.PatientID = @PatientID)
            AND (@MRN      IS NULL OR p.MRN = @MRN)
            AND (@BedID    IS NULL OR ba.BedID = @BedID)
    )
    SELECT TOP (@RowsToReturn)
           b.PatientID,
           b.MRN,
           b.FirstName,
           b.LastName,
           b.EncounterID,
           -- latest vitals
           v.RecordedAt,
           v.HeartRate,
           v.BloodPressure,
           v.SpO2,
           v.TemperatureC,
           v.RespiratoryRate,
           v.Source,
           -- current location (if any)
           bldg.Name     AS Building,
           rm.Ward       AS Ward,
           rm.RoomNumber AS RoomNumber,
           bed.BedNumber AS BedNumber
    FROM Base AS b
    -- latest vitals for that patient/encounter (allow null EncounterID in vitals)
    OUTER APPLY
    (
        SELECT TOP (1)
               vs.SnapshotID,
               vs.RecordedAt,
               vs.HeartRate,
               vs.BloodPressure,
               vs.SpO2,
               vs.TemperatureC,
               vs.RespiratoryRate,
               vs.Source
        FROM clinical.VitalsSnapshots AS vs
        WHERE vs.PatientID = b.PatientID
          AND (vs.EncounterID = b.EncounterID OR vs.EncounterID IS NULL)
        ORDER BY vs.RecordedAt DESC, vs.SnapshotID DESC
    ) AS v
    -- current bed (open assignment)
    OUTER APPLY
    (
        SELECT TOP (1) ba.BedID
        FROM core.BedAssignments AS ba
        WHERE ba.PatientID = b.PatientID
          AND ba.DischargeDate IS NULL
        ORDER BY ba.AdmitDate DESC, ba.AssignmentID DESC
    ) AS cur
    LEFT JOIN ref.Beds      AS bed  ON bed.BedID = cur.BedID
    LEFT JOIN ref.Rooms     AS rm   ON rm.RoomID = bed.RoomID
    LEFT JOIN ref.Buildings AS bldg ON bldg.BuildingID = rm.BuildingID
    WHERE v.SnapshotID IS NOT NULL   -- require at least one vitals snapshot
    ORDER BY v.RecordedAt DESC, b.PatientID
    OPTION (RECOMPILE);  -- keeps plans optimal for varying filter shapes
END;
GO
CREATE OR ALTER PROCEDURE clinical.usp_GetPatientSymptoms
    @PatientID   INT           = NULL,   -- optional: filter by PatientID
    @MRN         NVARCHAR(50)  = NULL,   -- optional: filter by MRN
    @EncounterID BIGINT        = NULL,   -- optional: filter by EncounterID
    @Since       DATETIME2(3)  = NULL,   -- optional: only symptoms recorded at/after this time (UTC)
    @MaxRows     INT           = 1000    -- safety cap when broad querying
AS
BEGIN
    SET NOCOUNT ON;

    /*
        Returns symptoms for patients that currently have an OPEN encounter.
        Filters (all optional):
          - @PatientID   : specific patient
          - @MRN         : specific MRN
          - @EncounterID : specific encounter (else uses the patient's open encounter)
          - @Since       : time window lower bound for RecordedAt (UTC)
          - @MaxRows     : cap when broad querying
        Notes:
          - RLS is enforced automatically by your security policy.
          - Clinical table: clinical.Symptoms (SymptomID, Code, Description, RecordedAt, [PatientID, EncounterID])
          - Open encounters only (core.Encounters.DischargeDate IS NULL).
    */

    -- Decide how many rows to return if the query is broad
    DECLARE @RowsToReturn INT =
        CASE WHEN @PatientID IS NULL AND @MRN IS NULL AND @EncounterID IS NULL AND @Since IS NULL
             THEN @MaxRows ELSE 2147483647 END;  -- effectively “unlimited” when narrowly filtered

    ;WITH Base AS
    (
        SELECT DISTINCT
               p.PatientID,
               p.MRN,
               p.FirstName,
               p.LastName,
               e.EncounterID
        FROM core.Patients   AS p
        JOIN core.Encounters AS e
          ON e.PatientID = p.PatientID
         AND e.DischargeDate IS NULL
        LEFT JOIN core.BedAssignments AS ba
          ON ba.PatientID = p.PatientID
         AND ba.DischargeDate IS NULL
        WHERE
            (@PatientID IS NULL OR p.PatientID = @PatientID)
        AND (@MRN      IS NULL OR p.MRN       = @MRN)
        -- If @BedID were desired, we’d filter via ba.BedID here (kept out for this proc on purpose)
    )
    SELECT TOP (@RowsToReturn)
           b.PatientID,
           b.MRN,
           b.FirstName,
           b.LastName,
           COALESCE(@EncounterID, b.EncounterID) AS EncounterID,
           s.SymptomID,
           s.Code,
           s.Description,
           s.RecordedAt
    FROM Base AS b
    JOIN clinical.Symptoms AS s
      ON s.PatientID = b.PatientID
     AND (
            -- If an explicit @EncounterID was provided, match only that
            (@EncounterID IS NOT NULL AND s.EncounterID = @EncounterID)
            -- Otherwise, match the patient's *open* encounter, and also allow NULL EncounterID symptoms
         OR (@EncounterID IS NULL AND (s.EncounterID = b.EncounterID OR s.EncounterID IS NULL))
         )
    WHERE
        (@Since IS NULL OR s.RecordedAt >= @Since)
    ORDER BY s.RecordedAt DESC, s.SymptomID DESC
    OPTION (RECOMPILE);
END;
GO
CREATE OR ALTER PROCEDURE clinical.usp_GetDoctorNotes
    @PatientID    INT            = NULL,   -- optional: filter by patient
    @MRN          NVARCHAR(50)   = NULL,   -- optional: filter by MRN
    @EncounterID  BIGINT         = NULL,   -- optional: filter by encounter
    @ProviderID   INT            = NULL,   -- optional: filter by authoring provider
    @Since        DATETIME2(3)   = NULL,   -- optional: notes created at/after this UTC time
    @TextLike     NVARCHAR(200)  = NULL,   -- optional: NoteText contains (LIKE)
    @MaxRows      INT            = 1000    -- cap when broad querying
AS
BEGIN
    SET NOCOUNT ON;

    /*
        Returns doctor notes (append-only ledger) for patients who have an OPEN encounter.

        Filters:
          - @PatientID, @MRN, @EncounterID, @ProviderID, @Since, @TextLike
          - @MaxRows caps result size when no specific filters are supplied

        Notes:
          - RLS is enforced automatically by your security policy.
          - Location is based on the current open bed assignment (if any).
    */

    DECLARE @RowsToReturn INT =
        CASE WHEN @PatientID   IS NULL
              AND @MRN         IS NULL
              AND @EncounterID IS NULL
              AND @ProviderID  IS NULL
              AND @Since       IS NULL
              AND @TextLike    IS NULL
             THEN @MaxRows ELSE 2147483647 END;

    ;WITH Base AS
    (
        SELECT DISTINCT
               p.PatientID,
               p.MRN,
               p.FirstName,
               p.LastName,
               e.EncounterID
        FROM core.Patients AS p
        INNER JOIN core.Encounters AS e
            ON e.PatientID     = p.PatientID
           AND e.DischargeDate IS NULL                         -- open encounter
        -- (Left join to BedAssignments only needed if you later add BedID filter)
        WHERE (@PatientID IS NULL OR p.PatientID = @PatientID)
          AND (@MRN       IS NULL OR p.MRN       = @MRN)
    )
    SELECT TOP (@RowsToReturn)
           b.PatientID,
           b.MRN,
           b.FirstName,
           b.LastName,
           -- encounter context for this result row:
           COALESCE(@EncounterID, b.EncounterID) AS EncounterID,
           -- note
           dn.NoteID,
           dn.CreatedAt,
           dn.NoteText,
           -- author
           pr.ProviderID,
           pr.FullName              AS Provider,
           prr.RoleName             AS ProviderRole,
           -- current location (if any)
           bldg.Name                AS Building,
           rooms.Ward               AS Ward,
           rooms.RoomNumber         AS RoomNumber,
           beds.BedNumber           AS BedNumber
    FROM Base AS b
    INNER JOIN clinical.DoctorNotes AS dn
        ON dn.PatientID = b.PatientID
       AND (
                (@EncounterID IS NOT NULL AND dn.EncounterID = @EncounterID)
             OR (@EncounterID IS NULL    AND (dn.EncounterID = b.EncounterID OR dn.EncounterID IS NULL))
           )
    LEFT JOIN core.Providers     AS pr   ON pr.ProviderID = dn.ProviderID
    LEFT JOIN ref.ProviderRoles  AS prr  ON prr.RoleID    = pr.RoleID
    -- current open bed (if any)
    OUTER APPLY
    (
        SELECT TOP (1) ba2.BedID
        FROM core.BedAssignments AS ba2
        WHERE ba2.PatientID = b.PatientID
          AND ba2.DischargeDate IS NULL
        ORDER BY ba2.AdmitDate DESC, ba2.AssignmentID DESC
    ) AS curBed
    LEFT JOIN ref.Beds      AS beds  ON beds.BedID      = curBed.BedID
    LEFT JOIN ref.Rooms     AS rooms ON rooms.RoomID    = beds.RoomID
    LEFT JOIN ref.Buildings AS bldg  ON bldg.BuildingID = rooms.BuildingID
    WHERE (@ProviderID IS NULL OR dn.ProviderID = @ProviderID)
      AND (@Since     IS NULL OR dn.CreatedAt  >= @Since)
      AND (@TextLike  IS NULL OR dn.NoteText   LIKE N'%' + @TextLike + N'%')
    ORDER BY dn.CreatedAt DESC, dn.NoteID DESC;
END;
GO
CREATE OR ALTER PROCEDURE clinical.usp_CreateOrder
    @PatientID        INT,                       -- required
    @ProviderID       INT,                       -- required (authoring provider)
    @OrderTypeCode    NVARCHAR(40),              -- required (must exist in ref.OrderTypes or auto-create if enabled)
    @Details          NVARCHAR(MAX) = NULL,      -- optional free text (defaults to "Order: <OrderTypeCode>")
    @EncounterID      BIGINT        = NULL,      -- optional; if NULL, uses the patient's most recent OPEN encounter
    @Status           NVARCHAR(30)  = N'Pending',-- one of: Pending | InProgress | Completed | Cancelled
    @OrderedAtUtc     DATETIME2(3)  = NULL,      -- optional; defaults to SYSUTCDATETIME()
    @DedupWindowMin   INT           = 480,       -- minutes for duplicate suppression (default 8 hours)
    @ReturnExistingIfDuplicate BIT  = 1,         -- if a duplicate is found, return it instead of inserting
    @CreateOrderTypeIfMissing BIT   = 1          -- create OrderType in lower envs if missing
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        -------------------------------------------------
        -- 0) Validate required inputs
        -------------------------------------------------
        IF @PatientID IS NULL OR @ProviderID IS NULL OR @OrderTypeCode IS NULL
        BEGIN
            THROW 50001, '(@PatientID, @ProviderID, @OrderTypeCode) are required.', 1;
        END;

        IF @Status NOT IN (N'Pending', N'InProgress', N'Completed', N'Cancelled')
        BEGIN
            THROW 50002, '@Status must be one of: Pending | InProgress | Completed | Cancelled.', 1;
        END;

        IF @OrderedAtUtc IS NULL
            SET @OrderedAtUtc = SYSUTCDATETIME();

        IF @Details IS NULL OR LTRIM(RTRIM(@Details)) = N''
            SET @Details = N'Order: ' + @OrderTypeCode;

        -------------------------------------------------
        -- 1) Validate patient & provider
        -------------------------------------------------
        IF NOT EXISTS (SELECT 1 FROM core.Patients WITH (READCOMMITTEDLOCK) WHERE PatientID = @PatientID)
            THROW 50003, 'Patient not found.', 1;

        IF NOT EXISTS (SELECT 1 FROM core.Providers WITH (READCOMMITTEDLOCK) WHERE ProviderID = @ProviderID AND IsActive = 1)
            THROW 50004, 'Provider not found or inactive.', 1;

        -------------------------------------------------
        -- 2) Resolve or validate encounter
        --    If multiple open encounters exist (should be rare),
        --    we pick the most recent by AdmitDate.
        -------------------------------------------------
        IF @EncounterID IS NULL
        BEGIN
            SELECT TOP (1) @EncounterID = e.EncounterID
            FROM core.Encounters e WITH (READCOMMITTEDLOCK)
            WHERE e.PatientID = @PatientID
              AND e.DischargeDate IS NULL
            ORDER BY e.AdmitDate DESC, e.EncounterID DESC;

            IF @EncounterID IS NULL
                THROW 50005, 'No open encounter found for patient; provide @EncounterID.', 1;
        END
        ELSE
        BEGIN
            IF NOT EXISTS (
                SELECT 1
                FROM core.Encounters e WITH (READCOMMITTEDLOCK)
                WHERE e.EncounterID = @EncounterID
                  AND e.PatientID   = @PatientID
            )
                THROW 50006, 'The provided @EncounterID does not belong to @PatientID.', 1;
        END;

        -------------------------------------------------
        -- 3) Ensure OrderType exists (and is active)
        -------------------------------------------------
        IF NOT EXISTS (
            SELECT 1
            FROM ref.OrderTypes WITH (READCOMMITTEDLOCK)
            WHERE OrderTypeCode = @OrderTypeCode
              AND IsActive = 1
        )
        BEGIN
            IF @CreateOrderTypeIfMissing = 1
            BEGIN
                INSERT INTO ref.OrderTypes(OrderTypeCode, DisplayName, IsActive)
                VALUES (@OrderTypeCode, @OrderTypeCode, 1);
            END
            ELSE
            BEGIN
                THROW 50007, 'OrderTypeCode is missing or inactive in ref.OrderTypes.', 1;
            END
        END;

        -------------------------------------------------
        -- 4) Duplicate suppression (optional)
        --    Duplicate = same Patient, Encounter, Provider, OrderTypeCode
        --    and SAME normalized Details within @DedupWindowMin.
        -------------------------------------------------
        DECLARE @ExistingOrderID BIGINT;

        IF @DedupWindowMin IS NOT NULL AND @ReturnExistingIfDuplicate = 1
        BEGIN
            DECLARE @NormDetails NVARCHAR(MAX) = UPPER(LTRIM(RTRIM(@Details)));

            SELECT TOP (1) @ExistingOrderID = o.OrderID
            FROM clinical.Orders o WITH (READCOMMITTEDLOCK)
            WHERE o.PatientID     = @PatientID
              AND o.EncounterID   = @EncounterID
              AND o.ProviderID    = @ProviderID
              AND o.OrderTypeCode = @OrderTypeCode
              AND UPPER(LTRIM(RTRIM(o.Details))) = @NormDetails
              AND o.OrderedAt >= DATEADD(MINUTE, -@DedupWindowMin, @OrderedAtUtc)
            ORDER BY o.OrderedAt DESC;

            IF @ExistingOrderID IS NOT NULL
            BEGIN
                SELECT o.OrderID, o.PatientID, o.EncounterID, o.OrderTypeCode,
                       o.Details, o.ProviderID, o.OrderedAt, o.Status
                FROM clinical.Orders o
                WHERE o.OrderID = @ExistingOrderID;

                COMMIT TRAN;
                RETURN;
            END
        END;

        -------------------------------------------------
        -- 5) Insert new order
        -------------------------------------------------
        INSERT INTO clinical.Orders
        (
            PatientID,
            EncounterID,
            OrderTypeCode,
            Details,
            ProviderID,
            OrderedAt,
            Status
        )
        VALUES
        (
            @PatientID,
            @EncounterID,
            @OrderTypeCode,
            @Details,
            @ProviderID,
            @OrderedAtUtc,
            @Status
        );

        DECLARE @NewOrderID BIGINT = SCOPE_IDENTITY();

        -------------------------------------------------
        -- 6) Return the created row
        -------------------------------------------------
        SELECT o.OrderID, o.PatientID, o.EncounterID, o.OrderTypeCode,
               o.Details, o.ProviderID, o.OrderedAt, o.Status
        FROM clinical.Orders o
        WHERE o.OrderID = @NewOrderID;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        -- Re-throw original error with original message & state:
        THROW;
    END CATCH
END;


