/*
    Ward General — Observability
    Generate one controlled engine error for the AzureSQLErrors demonstration.

    This changes no data or schema. THROW returns error 50001 to the caller so
    the configured diagnostic pipeline has a recognizable event to retain.
*/

SET NOCOUNT ON;

THROW 50001, 'CH07_ENGINEEVENTS_AZURESQLERRORS_TEST', 1;