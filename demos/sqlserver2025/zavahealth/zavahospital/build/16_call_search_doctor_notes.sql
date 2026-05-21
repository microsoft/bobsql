/* =======================================================================
   Demo: Call clinical.usp_search_doctor_notes
   ======================================================================= */
USE zavahospital;
GO

EXEC clinical.usp_search_doctor_notes
     @Prompt        = N'patient dehydrated with IV fluids and abnormal vitals',
     @TopN          = 50,
     @MinSimilarity = 0.3;
GO
