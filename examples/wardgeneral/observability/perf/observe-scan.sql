/*=============================================================================
  Observability — Observability, Monitoring, and Troubleshooting
  A bounded anti-pattern: scan 108 million observations without a supporting
  ValueNumeric index, return four aggregate rows, and expose the work through
  STATISTICS IO and STATISTICS TIME.

  Read-only. This script creates, changes, and deletes nothing.
=============================================================================*/
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT
    /* CH07_OBSERVABILITY_SCAN */
    ObservationType,
    ObservationCount = COUNT_BIG(*),
    AverageValue = AVG(ValueNumeric)
FROM clinical.Observation
WHERE ValueNumeric BETWEEN 90 AND 110
GROUP BY ObservationType
OPTION (RECOMPILE);
