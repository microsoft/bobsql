CREATE VECTOR INDEX encounter_vector_index
ON clinical.EncounterVectors (NarrativeEmbedding)
WITH (METRIC = 'cosine', TYPE = 'diskann', MAXDOP = 8);
GO