-- Ward General — READ-ONLY load: the worklist.
-- Mirrors the app's encounter search (clinical.SearchEncounters), active only.
-- All filters are optional (OPPO). No writes.
SET NOCOUNT ON;
EXEC clinical.SearchEncounters @Status = N'Active';
