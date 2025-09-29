CREATE OR ALTER PROCEDURE edge.kiosk_session_start
    @store_code     VARCHAR(16),
    @terminal_code  VARCHAR(32),
    @customer_id    UNIQUEIDENTIFIER = NULL,
    @session_id     UNIQUEIDENTIFIER OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @store_id INT, @terminal_id INT;

    SELECT @store_id = s.store_id
    FROM edge.store s
    WHERE s.store_code = @store_code AND s.is_active = 1;

    IF @store_id IS NULL
        THROW 51000, 'Invalid store_code or store inactive.', 1;

    SELECT @terminal_id = t.terminal_id
    FROM edge.pos_terminal t
    WHERE t.store_id = @store_id
      AND t.terminal_code = @terminal_code
      AND t.is_active = 1;

    IF @terminal_id IS NULL
        THROW 51001, 'Invalid terminal_code or terminal inactive.', 1;

    SET @session_id = NEWSEQUENTIALID();

    INSERT INTO edge.kiosk_session (session_id, store_id, terminal_id, customer_id, started_at_utc, status)
    VALUES (@session_id, @store_id, @terminal_id, @customer_id, SYSUTCDATETIME(), 'ACTIVE');

    -- Optional telemetry
    INSERT INTO edge.kiosk_event (session_id, event_type, payload_json)
    VALUES (@session_id, 'SESSION_STARTED', NULL);

    SELECT @session_id AS session_id;
END
GO