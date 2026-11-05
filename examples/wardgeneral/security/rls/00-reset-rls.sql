SET NOCOUNT ON;

DROP SECURITY POLICY IF EXISTS security.EncounterAccessPolicy;
DROP PROCEDURE IF EXISTS clinical.GetPatientChartRlsApi;
DROP PROCEDURE IF EXISTS clinical.GetPatientChartByBedRlsApi;
DROP FUNCTION IF EXISTS security.fn_encounterAccess;
GO
