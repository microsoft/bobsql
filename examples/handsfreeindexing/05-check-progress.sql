/* Beat 5 - Capture current physical state paired with the latest app refresh. */

SET NOCOUNT ON;
GO

EXEC demo.usp_CaptureIndexHealth;
GO

EXEC demo.usp_ShowIndexHealth;
GO

