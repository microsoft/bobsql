/* =======================================================================
   Zava Hospital – Doctor Notes Vector Index
   SQL Server 2025 + NVIDIA NIM on AKS

   Creates a DiskANN cosine vector index on DoctorNotesEmbeddings
   so that VECTOR_SEARCH can be used in usp_search_doctor_notes.
   Must run AFTER 13_embeddingtable.sql and BEFORE 14_search_doctor_notes.sql.
   ======================================================================= */
CREATE VECTOR INDEX doctornotes_vector_index
ON clinical.DoctorNotesEmbeddings (Embedding)
WITH (METRIC = 'cosine', TYPE = 'diskann', MAXDOP = 8);
GO
