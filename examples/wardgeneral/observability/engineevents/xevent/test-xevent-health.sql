/*=============================================================================
  Observability — Generate one controlled system error for wardgeneral_health

  The invalid object reference raises system error 208, severity 16. It changes
  no data or schema. The nonzero client exit is the expected test result.
=============================================================================*/
SET NOCOUNT ON;

SELECT *
FROM clinical.CH07_ThisTableDoesNotExist;