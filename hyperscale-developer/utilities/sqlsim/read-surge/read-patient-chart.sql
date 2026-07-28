-- Ward General — READ-ONLY load: open a patient chart.
-- Mirrors the app bedside chart (clinical.GetPatientChart) for a random active
-- encounter. The heaviest read in the app (all chart sections). No writes.
SET NOCOUNT ON;
DECLARE @EncounterId INT =
    (SELECT TOP 1 EncounterId FROM clinical.Encounter WHERE Status = N'Active' ORDER BY NEWID());
IF @EncounterId IS NOT NULL
    EXEC clinical.GetPatientChart @EncounterId = @EncounterId;
