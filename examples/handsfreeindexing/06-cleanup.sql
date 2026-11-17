/* Remove the demo workload and restore database-level settings. */

ALTER DATABASE CURRENT SET AUTOMATIC_INDEX_COMPACTION = OFF;
ALTER DATABASE CURRENT SET AUTOMATIC_TUNING
(
	FORCE_LAST_GOOD_PLAN = DEFAULT,
	CREATE_INDEX = DEFAULT,
	DROP_INDEX = DEFAULT
);
GO

DROP PROCEDURE IF EXISTS demo.usp_ShowIndexHealth;
DROP PROCEDURE IF EXISTS demo.usp_PatientAccessDashboard;
DROP PROCEDURE IF EXISTS demo.usp_CaptureIndexHealth;
DROP PROCEDURE IF EXISTS demo.usp_GetIndexHealthTimeline;
DROP PROCEDURE IF EXISTS demo.usp_RecordDashboardMeasurement;
DROP PROCEDURE IF EXISTS demo.usp_SetDemoPhase;
DROP TABLE IF EXISTS demo.IndexHealthTelemetry;
DROP TABLE IF EXISTS demo.DashboardMeasurement;
DROP TABLE IF EXISTS demo.DemoState;
DROP TABLE IF EXISTS demo.PatientAccessActivity;
GO

PRINT 'Caldova hands-free indexing demo cleanup complete.';
GO