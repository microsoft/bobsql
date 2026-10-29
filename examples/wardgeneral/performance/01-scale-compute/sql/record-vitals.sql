SET NOCOUNT ON;

DECLARE @MaxEncounterId INT;
DECLARE @EncounterId INT;
DECLARE @CandidateEncounterId INT;
DECLARE @Vital INT = ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % 3;
DECLARE @ObservationType NVARCHAR(20);
DECLARE @ValueNumeric DECIMAL(9, 3);
DECLARE @Unit NVARCHAR(20);

SELECT @MaxEncounterId = MAX(EncounterId)
FROM clinical.Encounter;

SET @CandidateEncounterId = 1 + (ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % @MaxEncounterId);

SELECT TOP (1) @EncounterId = EncounterId
FROM clinical.Encounter
WHERE EncounterId >= @CandidateEncounterId
ORDER BY EncounterId;
SET @ObservationType = CASE @Vital
    WHEN 0 THEN N'HeartRate'
    WHEN 1 THEN N'SpO2'
    ELSE N'RespRate'
END;
SET @ValueNumeric = CASE @Vital
    WHEN 0 THEN 60 + (ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % 60)
    WHEN 1 THEN 92 + (ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % 8)
    ELSE 12 + (ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % 12)
END;
SET @Unit = CASE @Vital
    WHEN 0 THEN N'WG-PERF-SCALE:bpm'
    WHEN 1 THEN N'WG-PERF-SCALE:%'
    ELSE N'WG-PERF-SCALE:/min'
END;

EXEC clinical.RecordVitals
    @EncounterId = @EncounterId,
    @ObservationType = @ObservationType,
    @ValueNumeric = @ValueNumeric,
    @Unit = @Unit;
