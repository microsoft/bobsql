-- Create a new table to store embeddings
--
DROP TABLE IF EXISTS clinical.DoctorNotesEmbeddings;
GO
CREATE TABLE clinical.DoctorNotesEmbeddings
( 
  Embedding vector(1024),
  NoteId INT NOT NULL PRIMARY KEY CLUSTERED,
);
GO

-- Populate rows with embeddings from NIM
INSERT INTO clinical.DoctorNotesEmbeddings
SELECT AI_GENERATE_EMBEDDINGS(dn.NoteText USE MODEL NIMEmbeddingModel), 
dn.NoteID
FROM clinical.DoctorNotes dn
GO