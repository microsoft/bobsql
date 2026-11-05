SET NOCOUNT ON;

DECLARE @MaxEncounterId INT;
DECLARE @EncounterId INT;
DECLARE @CandidateEncounterId INT;
DECLARE @AuthorProviderId INT;

SELECT @MaxEncounterId = MAX(EncounterId)
FROM clinical.Encounter;

SET @CandidateEncounterId = 1 + (ABS(CONVERT(BIGINT, CHECKSUM(NEWID()))) % @MaxEncounterId);

SELECT TOP (1) @EncounterId = EncounterId
FROM clinical.Encounter
WHERE EncounterId >= @CandidateEncounterId
ORDER BY EncounterId;

SELECT @AuthorProviderId = AttendingProviderId
FROM clinical.Encounter
WHERE EncounterId = @EncounterId;

EXEC clinical.AddClinicalNote
    @EncounterId = @EncounterId,
    @AuthorProviderId = @AuthorProviderId,
    @NoteType = N'Progress',
    @NoteText = N'WG-PERF-SCALE: Patient remains stable. Continue the current plan and reassess on rounds.';
