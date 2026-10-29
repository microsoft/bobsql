SET NOCOUNT ON;

DECLARE @BedId INT;

SELECT TOP (1) @BedId = BedId
FROM clinical.Encounter
WHERE Status = N'Active'
  AND BedId IS NOT NULL
ORDER BY NEWID();

IF @BedId IS NULL
    THROW 51000, 'The workload requires at least one active bed.', 1;

EXEC clinical.GetPatientChartByBed @BedId = @BedId;
