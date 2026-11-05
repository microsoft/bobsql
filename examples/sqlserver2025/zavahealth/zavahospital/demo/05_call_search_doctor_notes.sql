/* =======================================================================
   ZavaHospital Demo – Call Doctor Notes Search
   SQL Server 2025 + NVIDIA NIM on AKS

   Searches doctor notes for entries similar to a natural-language prompt
   using vector similarity via NIM embeddings + DiskANN index.

   ** EXECUTE THIS SCRIPT LIVE **
   ======================================================================= */
USE zavahospital;
GO

EXEC clinical.usp_search_doctor_notes
     @Prompt        = N'patient dehydrated with IV fluids and abnormal vitals',
     @TopN          = 50,
     @MinSimilarity = 0.3;
GO
