SET NOCOUNT ON;

SELECT
    RemainingArea8Objects = COUNT_BIG(*)
FROM sys.objects
WHERE object_id IN
(
    OBJECT_ID(N'security.EncounterAccessPolicy'),
    OBJECT_ID(N'security.fn_encounterAccess'),
    OBJECT_ID(N'clinical.GetPatientChartRlsApi'),
    OBJECT_ID(N'clinical.GetPatientChartByBedRlsApi')
);
GO
