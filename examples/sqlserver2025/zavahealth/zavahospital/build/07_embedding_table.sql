-- One row per encounter vector; no narrative text stored
DROP TABLE IF EXISTS clinical.EncounterVectors;
GO
CREATE TABLE clinical.EncounterVectors
(
    EncounterID        INT          NOT NULL PRIMARY KEY,
    PatientID          INT          NOT NULL,
    NarrativeEmbedding VECTOR(1024) NOT NULL   -- 1024 for mxbai-embed-large
);
